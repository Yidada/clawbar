import Foundation

struct OpenClawChannelCommandResult: Equatable, Sendable {
    let output: String
    let exitStatus: Int32
    let timedOut: Bool
}

func trimmedNonEmpty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

enum ChannelCommandSupport {
    typealias CommandRunner = @Sendable (
        _ executablePath: String,
        _ arguments: [String],
        _ environment: [String: String],
        _ timeout: TimeInterval
    ) -> OpenClawChannelCommandResult

    static func commandEnvironment(base: [String: String]) -> [String: String] {
        OpenClawInstaller.installationEnvironment(base: base)
    }

    static func detectBinaryPath(
        named command: String,
        environment: [String: String],
        runCommand: CommandRunner
    ) -> String? {
        let result = runCommand("/bin/zsh", ["-lc", "command -v \(command)"], environment, 3)
        if !result.timedOut,
           result.exitStatus == 0,
           let path = OpenClawInstaller.parseDetectedBinaryPath(result.output) {
            return path
        }

        return nil
    }

    static func runShellCommand(
        _ command: String,
        environment: [String: String],
        timeout: TimeInterval
    ) -> OpenClawChannelCommandResult {
        runCommand("/bin/bash", ["-lc", command], environment, timeout)
    }

    static func runShellCommand(
        _ command: String,
        environment: [String: String],
        timeout: TimeInterval,
        runCommand: CommandRunner
    ) -> OpenClawChannelCommandResult {
        runCommand("/bin/bash", ["-lc", command], environment, timeout)
    }

    static func runCommand(
        _ executablePath: String,
        _ arguments: [String],
        _ environment: [String: String],
        _ timeout: TimeInterval
    ) -> OpenClawChannelCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = environment

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            return OpenClawChannelCommandResult(
                output: error.localizedDescription,
                exitStatus: 1,
                timedOut: false
            )
        }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false

        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            timedOut = true
            process.terminate()
            process.waitUntilExit()
        }

        let output = sanitizeOutput(outputPipe.fileHandleForReading.readDataToEndOfFile())
        return OpenClawChannelCommandResult(
            output: output,
            exitStatus: process.terminationStatus,
            timedOut: timedOut
        )
    }

    static func makeStreamingProcess(
        command: String,
        environment: [String: String],
        outputHandler: @escaping @Sendable (String) -> Void,
        terminationHandler: @escaping @Sendable (Int32) -> Void
    ) throws -> Process {
        let process = Process()
        let outputPipe = Pipe()

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            outputHandler(sanitizeOutput(data))
        }

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", command]
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.terminationHandler = { process in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            terminationHandler(process.terminationStatus)
        }

        return process
    }

    static func parseJSONObject(from output: String) -> [String: Any]? {
        guard let data = output.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func extractFailureDetail(from output: String) -> String? {
        let candidates = output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reversed()

        for line in candidates {
            if line.contains("失败") || line.contains("Error") || line.contains("error") || line.contains("未完成") {
                return line
            }
        }

        return candidates.first
    }

    static func latestMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        guard let result = matches.last, let matchRange = Range(result.range, in: text) else { return nil }
        return String(text[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractURLs(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"https?://\S+"#) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)

        var seen = Set<String>()
        var urls: [String] = []
        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let value = String(text[matchRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'()[]{}<>"))
            guard seen.insert(value).inserted else { continue }
            urls.append(value)
        }
        return urls
    }

    static func sanitizeOutput(_ data: Data) -> String {
        let raw = String(decoding: data, as: UTF8.self)
        let pattern = #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return raw
        }

        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        return regex.stringByReplacingMatches(in: raw, options: [], range: range, withTemplate: "")
    }
}
