import Foundation

enum OpenClawTUICredentialKind: String, Equatable, Sendable {
    case token = "OPENCLAW_GATEWAY_TOKEN"
    case password = "OPENCLAW_GATEWAY_PASSWORD"
}

struct OpenClawTUILaunchCredential: Equatable, Sendable {
    let kind: OpenClawTUICredentialKind
    let value: String
}

@MainActor
final class OpenClawTUIManager: ObservableObject {
    static let shared = OpenClawTUIManager()

    typealias EnvironmentProvider = @Sendable () -> [String: String]
    typealias LaunchdEnvironmentLookup = @Sendable (_ name: String) -> String?
    typealias ShellEnvironmentLookup = @Sendable (
        _ shellPath: String,
        _ name: String,
        _ environment: [String: String]
    ) -> String?
    typealias CommandRunner = @Sendable (
        _ executablePath: String,
        _ arguments: [String],
        _ environment: [String: String],
        _ timeout: TimeInterval
    ) -> OpenClawChannelCommandResult

    @Published private(set) var isLaunching = false

    private let environmentProvider: EnvironmentProvider
    private let launchdEnvironmentLookup: LaunchdEnvironmentLookup
    private let shellEnvironmentLookup: ShellEnvironmentLookup
    private let credentialStore: OpenClawGatewayCredentialStore
    private let runCommand: CommandRunner

    init(
        environmentProvider: @escaping EnvironmentProvider = { ProcessInfo.processInfo.environment },
        launchdEnvironmentLookup: @escaping LaunchdEnvironmentLookup = OpenClawTUIManager.readLaunchdEnvironment,
        shellEnvironmentLookup: @escaping ShellEnvironmentLookup = OpenClawTUIManager.readLoginShellEnvironment,
        credentialStore: OpenClawGatewayCredentialStore = .shared,
        runCommand: @escaping CommandRunner = OpenClawTUIManager.runCommand
    ) {
        self.environmentProvider = environmentProvider
        self.launchdEnvironmentLookup = launchdEnvironmentLookup
        self.shellEnvironmentLookup = shellEnvironmentLookup
        self.credentialStore = credentialStore
        self.runCommand = runCommand
    }

    func launchTUI() {
        guard !isLaunching else { return }

        let environment = OpenClawInstaller.installationEnvironment(base: environmentProvider())
        let openClawBinaryPath = OpenClawChannelManager.detectBinaryPath(
            named: "openclaw",
            environment: environment,
            runCommand: runCommand
        )
        let credential: OpenClawTUILaunchCredential?

        if openClawBinaryPath != nil, let token = try? credentialStore.ensureGatewayTokenConfigured() {
            credential = OpenClawTUILaunchCredential(kind: .token, value: token)
        } else {
            credential = Self.resolveLaunchCredential(
                environment: environment,
                launchdEnvironmentLookup: launchdEnvironmentLookup,
                shellPath: environment["SHELL"]?.trimmedNonEmpty ?? "/bin/zsh",
                shellEnvironmentLookup: shellEnvironmentLookup
            )
        }
        let shellCommand = Self.makeLaunchShellCommand(
            openClawBinaryAvailable: openClawBinaryPath != nil,
            credential: credential,
            path: environment["PATH"] ?? ""
        )
        let appleScriptArguments = OpenClawChannelManager.makeTerminalLaunchArguments(shellCommand: shellCommand)

        isLaunching = true

        Task.detached(priority: .userInitiated) {
            _ = self.runCommand("/usr/bin/osascript", appleScriptArguments, environment, 8)

            await MainActor.run {
                self.isLaunching = false
            }
        }
    }

    nonisolated static func resolveLaunchCredential(
        environment: [String: String],
        launchdEnvironmentLookup: LaunchdEnvironmentLookup,
        shellPath: String,
        shellEnvironmentLookup: ShellEnvironmentLookup
    ) -> OpenClawTUILaunchCredential? {
        for kind in [OpenClawTUICredentialKind.token, .password] {
            if let value = environment[kind.rawValue]?.trimmedNonEmpty {
                return OpenClawTUILaunchCredential(kind: kind, value: value)
            }
        }

        for kind in [OpenClawTUICredentialKind.token, .password] {
            if let value = launchdEnvironmentLookup(kind.rawValue)?.trimmedNonEmpty {
                return OpenClawTUILaunchCredential(kind: kind, value: value)
            }
        }

        for kind in [OpenClawTUICredentialKind.token, .password] {
            if let value = shellEnvironmentLookup(shellPath, kind.rawValue, environment)?.trimmedNonEmpty {
                return OpenClawTUILaunchCredential(kind: kind, value: value)
            }
        }

        return nil
    }

    nonisolated static func makeLaunchShellCommand(
        openClawBinaryAvailable: Bool,
        credential: OpenClawTUILaunchCredential?,
        path: String
    ) -> String {
        var commands = ["export PATH=\(shellQuote(path))"]

        guard openClawBinaryAvailable else {
            commands.append(#"printf '%s\n' 'Clawbar 没有在当前 PATH 里找到 openclaw；请先确认 CLI 已安装。'"#)
            commands.append("exec $SHELL -l")
            return commands.joined(separator: "; ")
        }

        if let credential {
            switch credential.kind {
            case .token:
                commands.append(#"printf '%s\n' 'Clawbar 已准备本地 Gateway token，正在启动 openclaw tui。'"#)
                commands.append("openclaw tui --token \(shellQuote(credential.value))")
            case .password:
                commands.append(#"printf '%s\n' 'Clawbar 已准备 Gateway password，正在启动 openclaw tui。'"#)
                commands.append("openclaw tui --password \(shellQuote(credential.value))")
            }
            commands.append("STATUS=$?")
            commands.append(#"if [ "$STATUS" -ne 0 ]; then printf '\n%s\n' "openclaw tui exited with status $STATUS."; fi"#)
            commands.append("exec $SHELL -l")
            return commands.joined(separator: "; ")
        }

        commands.append(#"printf '%s\n' 'Clawbar 没有找到 OPENCLAW_GATEWAY_TOKEN / OPENCLAW_GATEWAY_PASSWORD；将直接启动 openclaw tui 方便排查。'"#)
        commands.append("openclaw tui")
        commands.append("STATUS=$?")
        commands.append(#"if [ "$STATUS" -ne 0 ]; then printf '\n%s\n' '可先在当前 shell export OPENCLAW_GATEWAY_TOKEN=... 再重试。'; fi"#)
        commands.append("exec $SHELL -l")
        return commands.joined(separator: "; ")
    }

    private nonisolated static func readLaunchdEnvironment(named name: String) -> String? {
        let result = runCommand("/bin/launchctl", ["getenv", name], ProcessInfo.processInfo.environment, 3)
        guard !result.timedOut, result.exitStatus == 0 else { return nil }
        return result.output.trimmedNonEmpty
    }

    private nonisolated static func readLoginShellEnvironment(
        shellPath: String,
        named name: String,
        environment: [String: String]
    ) -> String? {
        let sentinel = "__CLAWBAR_ENV__"
        let command = #"printf '%s%s' "\#(sentinel)" "${\#(name)-}""#
        let result = runCommand(shellPath, ["-ilc", command], environment, 5)
        guard !result.timedOut, result.exitStatus == 0 else { return nil }
        guard let suffix = result.output.components(separatedBy: sentinel).last else { return nil }
        return suffix.trimmedNonEmpty
    }

    private nonisolated static func shellQuote(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "'", with: #"'\"'\"'"#)
        return "'\(escaped)'"
    }

    private nonisolated static func runCommand(
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
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            return OpenClawChannelCommandResult(
                output: String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                exitStatus: process.terminationStatus,
                timedOut: true
            )
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return OpenClawChannelCommandResult(
            output: output,
            exitStatus: process.terminationStatus,
            timedOut: false
        )
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
