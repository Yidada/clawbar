#!/usr/bin/env swift

import CryptoKit
import Darwin
import Dispatch
import Foundation

struct DevLoop {
    let rootDirectory: URL
    let artifactDirectory: URL
    let appLogURL: URL
    let pidFileURL: URL
    let pollInterval: TimeInterval
    let watchTargets: [URL]

    private var appProcess: Process?
    private var shouldExit = false
    private var signalSources: [DispatchSourceSignal] = []
    private var lastFingerprint = ""
    private var hasSuccessfulBuild = false

    init(rootDirectory: URL, pollInterval: TimeInterval) {
        self.rootDirectory = rootDirectory
        artifactDirectory = rootDirectory.appending(path: "Artifacts/DevRunner", directoryHint: .isDirectory)
        appLogURL = artifactDirectory.appending(path: "clawbar-dev.log")
        pidFileURL = artifactDirectory.appending(path: "clawbar-dev.pid")
        self.pollInterval = pollInterval
        watchTargets = [
            rootDirectory.appending(path: "Package.swift"),
            rootDirectory.appending(path: "Sources", directoryHint: .isDirectory),
            rootDirectory.appending(path: "Tests", directoryHint: .isDirectory),
        ]
    }

    mutating func run() throws {
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
        installSignalHandlers()
        try stopTrackedAppIfNeeded()

        print("Watching for changes every \(formattedPollInterval())s")
        print("App log: \(appLogURL.path)")

        while !shouldExit {
            shouldExit = SignalBox.shared.requestStop
            if shouldExit {
                break
            }

            let fingerprint = try computeFingerprint()
            if fingerprint != lastFingerprint {
                print("[\(timestamp())] change detected, building...")

                if try buildApp() {
                    hasSuccessfulBuild = true
                    try restartApp()
                } else {
                    print("[\(timestamp())] build failed, waiting for next change")
                }

                lastFingerprint = fingerprint
            } else if hasSuccessfulBuild && !isAppRunning() {
                print("[\(timestamp())] app missing, relaunching...")
                try launchApp()
                print("[\(timestamp())] app restarted")
            }

            Thread.sleep(forTimeInterval: pollInterval)
        }

        stopApp()
    }

    mutating func requestStop() {
        shouldExit = true
    }

    private mutating func installSignalHandlers() {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        for signalValue in [SIGINT, SIGTERM] {
            let source = DispatchSource.makeSignalSource(signal: signalValue, queue: DispatchQueue.global(qos: .userInitiated))
            source.setEventHandler { [weak box = SignalBox.shared] in
                box?.requestStop = true
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private func formattedPollInterval() -> String {
        if pollInterval.rounded(.towardZero) == pollInterval {
            return String(Int(pollInterval))
        }
        return String(format: "%.2f", pollInterval)
    }

    private func computeFingerprint() throws -> String {
        var entries: [String] = []
        let fileManager = FileManager.default

        for target in watchTargets {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: target.path, isDirectory: &isDirectory) else { continue }

            if !isDirectory.boolValue {
                let values = try target.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let relativePath = target.path.replacingOccurrences(of: rootDirectory.path + "/", with: "")
                entries.append("\(relativePath):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0):\(values.fileSize ?? 0)")
                continue
            }

            guard let enumerator = fileManager.enumerator(
                at: target,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            var directoryEntries: [String] = []
            for case let fileURL as URL in enumerator {
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey])
                guard values.isRegularFile == true else { continue }
                let relativePath = fileURL.path.replacingOccurrences(of: rootDirectory.path + "/", with: "")
                directoryEntries.append(
                    "\(relativePath):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0):\(values.fileSize ?? 0)"
                )
            }
            entries.append(contentsOf: directoryEntries.sorted())
        }

        let payload = entries.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func buildApp() throws -> Bool {
        try runProcess(
            executablePath: "/usr/bin/env",
            arguments: ["swift", "build"],
            captureOutput: false
        ).status == 0
    }

    private mutating func restartApp() throws {
        stopApp()
        try launchApp()
        print("[\(timestamp())] app restarted")
    }

    private mutating func launchApp() throws {
        let binaryURL = try resolvedExecutableURL()

        FileManager.default.createFile(atPath: appLogURL.path, contents: Data())
        let logHandle = try FileHandle(forWritingTo: appLogURL)

        let process = Process()
        process.executableURL = binaryURL
        process.currentDirectoryURL = rootDirectory
        process.standardOutput = logHandle
        process.standardError = logHandle
        process.terminationHandler = { [pidFileURL] _ in
            try? FileManager.default.removeItem(at: pidFileURL)
            try? logHandle.close()
        }

        try process.run()
        appProcess = process
        try String(process.processIdentifier).write(to: pidFileURL, atomically: true, encoding: .utf8)
    }

    private mutating func stopApp() {
        if let process = appProcess, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        appProcess = nil

        if let pid = trackedPID(), pid > 0, kill(pid, 0) == 0 {
            kill(pid, SIGTERM)
            usleep(300_000)
            if kill(pid, 0) == 0 {
                kill(pid, SIGKILL)
            }
        }

        if let binaryURL = try? resolvedExecutableURL() {
            for pid in matchingProcessIDs(for: binaryURL.path) {
                guard pid != getpid() else { continue }
                kill(pid, SIGTERM)
            }
            usleep(300_000)
            for pid in matchingProcessIDs(for: binaryURL.path) {
                guard pid != getpid() else { continue }
                if kill(pid, 0) == 0 {
                    kill(pid, SIGKILL)
                }
            }
        }

        try? FileManager.default.removeItem(at: pidFileURL)
    }

    private mutating func stopTrackedAppIfNeeded() throws {
        guard let pid = trackedPID(), pid > 0, kill(pid, 0) == 0 else {
            try? FileManager.default.removeItem(at: pidFileURL)
            return
        }
        stopApp()
    }

    private func isAppRunning() -> Bool {
        if let process = appProcess, process.isRunning {
            return true
        }

        if let pid = trackedPID(), pid > 0, kill(pid, 0) == 0 {
            return true
        }

        guard let binaryURL = try? resolvedExecutableURL() else {
            return false
        }

        return !matchingProcessIDs(for: binaryURL.path).isEmpty
    }

    private func trackedPID() -> pid_t? {
        guard let text = try? String(contentsOf: pidFileURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(text) else {
            return nil
        }
        return pid
    }

    private func resolvedBinaryPath() throws -> String {
        let result = try runProcess(
            executablePath: "/usr/bin/env",
            arguments: ["swift", "build", "--show-bin-path"],
            captureOutput: true
        )

        guard result.status == 0 else {
            throw NSError(domain: "ClawbarDevLoop", code: Int(result.status), userInfo: [
                NSLocalizedDescriptionKey: result.output.nonEmptyOr("Unable to resolve SwiftPM binary path.")
            ])
        }

        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolvedExecutableURL() throws -> URL {
        URL(fileURLWithPath: try resolvedBinaryPath()).appending(path: "Clawbar")
    }

    private func runProcess(
        executablePath: String,
        arguments: [String],
        captureOutput: Bool
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = rootDirectory

        if captureOutput {
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }

        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        return (process.terminationStatus, "")
    }

    private func matchingProcessIDs(for executablePath: String) -> [pid_t] {
        guard let result = try? runProcess(
            executablePath: "/usr/bin/pgrep",
            arguments: ["-f", executablePath],
            captureOutput: true
        ), result.status == 0 else {
            return []
        }

        return result.output
            .split(separator: "\n")
            .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}

private final class SignalBox {
    static let shared = SignalBox()
    var requestStop = false
}

private extension String {
    func nonEmptyOr(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}

private func resolveRepositoryRoot(from scriptPath: String) -> URL? {
    var currentURL = URL(fileURLWithPath: scriptPath).deletingLastPathComponent()
    let fileManager = FileManager.default

    while currentURL.path != "/" {
        let packagePath = currentURL.appending(path: "Package.swift").path
        let sourcesPath = currentURL.appending(path: "Sources", directoryHint: .isDirectory).path

        if fileManager.fileExists(atPath: packagePath), fileManager.fileExists(atPath: sourcesPath) {
            return currentURL
        }

        currentURL.deleteLastPathComponent()
    }

    return nil
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    Usage: ./.agents/skills/clawbar-dev-loop/scripts/run-dev-loop.swift

    Environment:
      CLAWBAR_DEV_POLL_INTERVAL   Poll interval in seconds. Default: 1
    """)
    exit(0)
}

guard let repositoryRoot = resolveRepositoryRoot(from: CommandLine.arguments[0]) else {
    fputs("Unable to locate repository root from \(CommandLine.arguments[0])\n", stderr)
    exit(1)
}

let interval = TimeInterval(ProcessInfo.processInfo.environment["CLAWBAR_DEV_POLL_INTERVAL"] ?? "") ?? 1
var loop = DevLoop(rootDirectory: repositoryRoot, pollInterval: max(interval, 0.2))

while !SignalBox.shared.requestStop {
    do {
        try loop.run()
        break
    } catch {
        fputs("Clawbar dev loop failed: \(error.localizedDescription)\n", stderr)
        break
    }
}
