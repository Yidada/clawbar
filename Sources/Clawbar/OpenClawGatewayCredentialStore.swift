import Foundation

enum OpenClawGatewayCredentialStoreError: LocalizedError {
    case missingBinary
    case configReadFailed(path: String, detail: String)
    case configWriteFailed(command: String, detail: String)
    case storageWriteFailed(path: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .missingBinary:
            "未检测到 openclaw，无法准备本地 Gateway token。"
        case let .configReadFailed(path, detail):
            "读取 OpenClaw 配置 \(path) 失败：\(detail)"
        case let .configWriteFailed(command, detail):
            "写入 OpenClaw 配置失败：\(command)\n\(detail)"
        case let .storageWriteFailed(path, underlying):
            "写入本地 token 文件失败：\(path)\n\(underlying.localizedDescription)"
        }
    }
}

final class OpenClawGatewayCredentialStore: @unchecked Sendable {
    static let shared = OpenClawGatewayCredentialStore()

    typealias EnvironmentProvider = @Sendable () -> [String: String]
    typealias CommandRunner = @Sendable (
        _ command: String,
        _ environment: [String: String],
        _ timeout: TimeInterval
    ) -> OpenClawGatewayCommandResult
    typealias TokenGenerator = @Sendable () -> String

    private let environmentProvider: EnvironmentProvider
    private let runCommand: CommandRunner
    private let tokenGenerator: TokenGenerator
    private let storageDirectoryURL: URL
    private let fileManager: FileManager

    init(
        environmentProvider: @escaping EnvironmentProvider = { ProcessInfo.processInfo.environment },
        runCommand: @escaping CommandRunner = OpenClawGatewayCredentialStore.runCommand,
        tokenGenerator: @escaping TokenGenerator = OpenClawGatewayCredentialStore.makeRandomToken,
        storageDirectoryURL: URL = OpenClawGatewayCredentialStore.defaultStorageDirectoryURL(),
        fileManager: FileManager = .default
    ) {
        self.environmentProvider = environmentProvider
        self.runCommand = runCommand
        self.tokenGenerator = tokenGenerator
        self.storageDirectoryURL = storageDirectoryURL
        self.fileManager = fileManager
    }

    func ensureGatewayTokenConfigured() throws -> String {
        let environment = OpenClawInstaller.installationEnvironment(base: environmentProvider())
        guard detectInstalledBinaryPath(environment: environment) != nil else {
            throw OpenClawGatewayCredentialStoreError.missingBinary
        }

        let token = try loadOrCreateToken(environment: environment)
        try syncGatewayConfiguration(token: token, environment: environment)
        return token
    }

    func storedToken() -> String? {
        guard let data = try? Data(contentsOf: tokenFileURL),
              let token = String(data: data, encoding: .utf8)?.trimmedNonEmpty else {
            return nil
        }

        return token
    }

    nonisolated static func defaultStorageDirectoryURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".clawbar")
    }

    nonisolated static func requiredConfigCommands(token: String) -> [String] {
        [
            "openclaw config set gateway.mode local",
            "openclaw config set gateway.auth.mode token",
            "openclaw config set gateway.auth.token \(shellQuote(token))",
            "openclaw config set gateway.remote.token \(shellQuote(token))",
        ]
    }

    private var tokenFileURL: URL {
        storageDirectoryURL.appending(path: "openclaw-gateway-token")
    }

    private func loadOrCreateToken(environment: [String: String]) throws -> String {
        if let token = storedToken() {
            return token
        }

        if let configuredToken = try readConfigValue(at: "gateway.auth.token", environment: environment) {
            try persistToken(configuredToken)
            return configuredToken
        }

        if let configuredToken = try readConfigValue(at: "gateway.remote.token", environment: environment) {
            try persistToken(configuredToken)
            return configuredToken
        }

        let token = tokenGenerator()
        try persistToken(token)
        return token
    }

    private func syncGatewayConfiguration(token: String, environment: [String: String]) throws {
        for command in Self.requiredConfigCommands(token: token) {
            let result = runCommand(command, environment, 10)
            guard !result.timedOut, result.exitStatus == 0 else {
                let detail = result.timedOut ? "命令超时。" : result.output.nonEmptyOr("命令返回了非零退出码 \(result.exitStatus)。")
                throw OpenClawGatewayCredentialStoreError.configWriteFailed(command: command, detail: detail)
            }
        }
    }

    private func persistToken(_ token: String) throws {
        do {
            try fileManager.createDirectory(at: storageDirectoryURL, withIntermediateDirectories: true)
            try token.write(to: tokenFileURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenFileURL.path)
        } catch {
            throw OpenClawGatewayCredentialStoreError.storageWriteFailed(path: tokenFileURL.path, underlying: error)
        }
    }

    private func readConfigValue(at path: String, environment: [String: String]) throws -> String? {
        let result = runCommand("openclaw config get \(path)", environment, 5)
        if result.timedOut {
            throw OpenClawGatewayCredentialStoreError.configReadFailed(path: path, detail: "命令超时。")
        }

        if result.exitStatus != 0 {
            return nil
        }

        return result.output.trimmedNonEmpty
    }

    private func detectInstalledBinaryPath(environment: [String: String]) -> String? {
        let result = runCommand("command -v openclaw", environment, 3)
        guard !result.timedOut, result.exitStatus == 0 else { return nil }
        return OpenClawInstaller.parseDetectedBinaryPath(result.output)
    }

    private nonisolated static func makeRandomToken() -> String {
        let left = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let right = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return "clawbar_\(left)\(right)"
    }

    private nonisolated static func shellQuote(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "'", with: #"'\"'\"'"#)
        return "'\(escaped)'"
    }

    private nonisolated static func runCommand(
        _ command: String,
        _ environment: [String: String],
        _ timeout: TimeInterval
    ) -> OpenClawGatewayCommandResult {
        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", command]
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            return OpenClawGatewayCommandResult(
                output: error.localizedDescription,
                exitStatus: 1,
                timedOut: false
            )
        }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false

        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            timedOut = true
            process.terminate()
            process.waitUntilExit()
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return OpenClawGatewayCommandResult(
            output: sanitizeCommandOutput(data),
            exitStatus: process.terminationStatus,
            timedOut: timedOut
        )
    }

    private nonisolated static func sanitizeCommandOutput(_ data: Data) -> String {
        let raw = String(decoding: data, as: UTF8.self)
        let pattern = #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return raw
        }

        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        return regex.stringByReplacingMatches(in: raw, options: [], range: range, withTemplate: "")
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func nonEmptyOr(_ fallback: String) -> String {
        trimmedNonEmpty ?? fallback
    }
}
