import Foundation

struct OpenClawChannelCommandResult: Equatable, Sendable {
    let output: String
    let exitStatus: Int32
    let timedOut: Bool
}

@MainActor
final class OpenClawChannelManager: ObservableObject {
    static let shared = OpenClawChannelManager()

    typealias EnvironmentProvider = @Sendable () -> [String: String]
    typealias CommandRunner = @Sendable (
        _ executablePath: String,
        _ arguments: [String],
        _ environment: [String: String],
        _ timeout: TimeInterval
    ) -> OpenClawChannelCommandResult

    nonisolated static let wechatChannelID = "openclaw-weixin"
    nonisolated static let wechatPluginSpec = "@tencent-weixin/openclaw-weixin-cli@latest"
    nonisolated static let installArguments = ["-y", wechatPluginSpec, "install"]
    nonisolated static let bindArguments = ["channels", "login", "--channel", wechatChannelID]

    @Published private(set) var isRefreshing = false
    @Published private(set) var isInstalling = false
    @Published private(set) var isLaunchingBinding = false
    @Published private(set) var openClawBinaryPath: String?
    @Published private(set) var npxBinaryPath: String?
    @Published private(set) var pluginInstalled = false
    @Published private(set) var bindingDetected = false
    @Published private(set) var lastActionSummary = "等待绑定"
    @Published private(set) var lastActionDetail = "Clawbar 会内置微信能力安装和绑定流程，用户只需要点击绑定并扫码。"
    @Published private(set) var lastCommandOutput = ""
    @Published private(set) var lastRefreshDate: Date?

    private let environmentProvider: EnvironmentProvider
    private let runCommand: CommandRunner

    init(
        environmentProvider: @escaping EnvironmentProvider = { ProcessInfo.processInfo.environment },
        runCommand: @escaping CommandRunner = OpenClawChannelManager.runCommand
    ) {
        self.environmentProvider = environmentProvider
        self.runCommand = runCommand
    }

    var statusLabel: String {
        guard openClawBinaryPath != nil else { return "未检测到 OpenClaw" }
        if pluginInstalled == false { return "待安装微信能力" }
        if bindingDetected == false { return "待绑定扫码" }
        return "已连接微信"
    }

    func refreshWeChatStatus() {
        guard !isRefreshing else { return }

        let environment = OpenClawInstaller.installationEnvironment(base: environmentProvider())
        isRefreshing = true

        Task.detached(priority: .utility) {
            let openClawBinaryPath = Self.detectBinaryPath(
                named: "openclaw",
                environment: environment,
                runCommand: self.runCommand
            )
            let npxBinaryPath = Self.detectBinaryPath(
                named: "npx",
                environment: environment,
                runCommand: self.runCommand
            )
            let pluginInstalled = openClawBinaryPath.map {
                Self.queryPluginInstalled(
                    openClawBinaryPath: $0,
                    environment: environment,
                    runCommand: self.runCommand
                )
            } ?? false
            let bindingDetected = openClawBinaryPath.map {
                Self.queryBindingDetected(
                    openClawBinaryPath: $0,
                    environment: environment,
                    runCommand: self.runCommand
                )
            } ?? false

            await MainActor.run {
                self.isRefreshing = false
                self.lastRefreshDate = Date()
                self.openClawBinaryPath = openClawBinaryPath.map(OpenClawInstaller.displayBinaryPath(_:))
                self.npxBinaryPath = npxBinaryPath.map(OpenClawInstaller.displayBinaryPath(_:))
                self.pluginInstalled = pluginInstalled
                self.bindingDetected = bindingDetected

                if openClawBinaryPath == nil {
                    self.lastActionSummary = "未检测到 OpenClaw"
                    self.lastActionDetail = "请先安装 OpenClaw，再内置微信 Channel 能力。"
                } else if pluginInstalled == false {
                    self.lastActionSummary = "微信能力未安装"
                    self.lastActionDetail = "点击“安装微信能力”后，Clawbar 会执行官方 WeixinClawBot 安装流程。"
                } else if bindingDetected == false {
                    self.lastActionSummary = "等待微信绑定"
                    self.lastActionDetail = "点击“开始绑定”后，Clawbar 会自动拉起终端执行扫码登录。"
                } else {
                    self.lastActionSummary = "微信 Channel 已连接"
                    self.lastActionDetail = "已检测到微信 Channel 可用；用户后续只需要重新绑定时再扫码。"
                }
            }
        }
    }

    func installWeChatCapability() {
        guard !isInstalling else { return }

        let environment = OpenClawInstaller.installationEnvironment(base: environmentProvider())
        guard Self.detectBinaryPath(named: "openclaw", environment: environment, runCommand: runCommand) != nil else {
            lastActionSummary = "未检测到 OpenClaw"
            lastActionDetail = "请先安装 OpenClaw，再安装微信能力。"
            return
        }
        guard let npxPath = Self.detectBinaryPath(named: "npx", environment: environment, runCommand: runCommand) else {
            lastActionSummary = "未检测到 npx"
            lastActionDetail = "当前环境里没有可用的 npx，无法执行官方微信安装器。"
            return
        }

        isInstalling = true
        lastActionSummary = "正在安装微信能力..."
        lastActionDetail = "Clawbar 正在执行官方 WeixinClawBot 安装命令。"
        lastCommandOutput = "$ npx \(Self.installArguments.joined(separator: " "))\n\n"

        Task.detached(priority: .userInitiated) {
            let result = self.runCommand(npxPath, Self.installArguments, environment, 300)

            await MainActor.run {
                self.isInstalling = false
                self.lastCommandOutput = "$ npx \(Self.installArguments.joined(separator: " "))\n\n" + result.output.nonEmptyOr("(no output)")

                if result.timedOut {
                    self.lastActionSummary = "微信能力安装超时"
                    self.lastActionDetail = "官方安装命令在 300 秒内没有完成。"
                } else if result.exitStatus != 0 {
                    self.lastActionSummary = "微信能力安装失败"
                    self.lastActionDetail = "官方安装命令退出码为 \(result.exitStatus)。"
                } else {
                    self.lastActionSummary = "微信能力安装完成"
                    self.lastActionDetail = "官方安装器已执行完成，正在刷新当前微信 Channel 状态。"
                }

                self.refreshWeChatStatus()
            }
        }
    }

    func startWeChatBinding() {
        guard !isLaunchingBinding else { return }

        let environment = OpenClawInstaller.installationEnvironment(base: environmentProvider())
        guard Self.detectBinaryPath(named: "openclaw", environment: environment, runCommand: runCommand) != nil else {
            lastActionSummary = "未检测到 OpenClaw"
            lastActionDetail = "请先安装 OpenClaw，再开始微信绑定。"
            return
        }
        guard pluginInstalled else {
            lastActionSummary = "请先安装微信能力"
            lastActionDetail = "微信插件还没有安装完成，暂时不能开始绑定。"
            return
        }

        let terminalCommand = Self.makeTerminalShellCommand(
            command: "openclaw " + Self.bindArguments.joined(separator: " "),
            path: environment["PATH"] ?? ""
        )
        let appleScriptArguments = Self.makeTerminalLaunchArguments(shellCommand: terminalCommand)

        isLaunchingBinding = true
        lastActionSummary = "正在打开绑定终端..."
        lastActionDetail = "Clawbar 会拉起 Terminal，并自动运行微信扫码登录命令。"
        lastCommandOutput = "$ openclaw \(Self.bindArguments.joined(separator: " "))\n\n"

        Task.detached(priority: .userInitiated) {
            let result = self.runCommand("/usr/bin/osascript", appleScriptArguments, environment, 8)

            await MainActor.run {
                self.isLaunchingBinding = false
                self.lastCommandOutput = "$ openclaw \(Self.bindArguments.joined(separator: " "))\n\n" + result.output.nonEmptyOr("(Terminal launch requested)")

                if result.timedOut {
                    self.lastActionSummary = "绑定终端启动超时"
                    self.lastActionDetail = "Terminal 没有在预期时间内响应 AppleScript。"
                } else if result.exitStatus != 0 {
                    self.lastActionSummary = "无法启动绑定终端"
                    self.lastActionDetail = "请检查 Terminal 自动化权限，或手动重试。"
                } else {
                    self.lastActionSummary = "已打开绑定终端"
                    self.lastActionDetail = "请在弹出的 Terminal 中完成扫码；扫码成功后回到 Clawbar 点“刷新状态”。"
                }
            }
        }
    }

    nonisolated static func detectBinaryPath(
        named command: String,
        environment: [String: String],
        runCommand: CommandRunner
    ) -> String? {
        let result = runCommand("/bin/zsh", ["-lc", "command -v \(command)"], environment, 3)
        guard !result.timedOut, result.exitStatus == 0 else { return nil }
        return OpenClawInstaller.parseDetectedBinaryPath(result.output)
    }

    nonisolated static func queryPluginInstalled(
        openClawBinaryPath: String,
        environment: [String: String],
        runCommand: CommandRunner
    ) -> Bool {
        let result = runCommand(openClawBinaryPath, ["plugins", "list", "--json"], environment, 12)
        guard !result.timedOut, result.exitStatus == 0 else { return false }
        return parsePluginInstalled(result.output)
    }

    nonisolated static func queryBindingDetected(
        openClawBinaryPath: String,
        environment: [String: String],
        runCommand: CommandRunner
    ) -> Bool {
        let result = runCommand(openClawBinaryPath, ["channels", "status", "--probe", "--json"], environment, 12)
        let credentialEntries = listCredentialEntryNames()
        return parseBindingDetected(statusOutput: result.output, credentialEntries: credentialEntries)
    }

    nonisolated static func parsePluginInstalled(_ output: String) -> Bool {
        if let payload = parseJSONObject(from: output),
           let plugins = payload["plugins"] as? [[String: Any]] {
            for plugin in plugins {
                let candidates = [
                    plugin["id"] as? String,
                    plugin["name"] as? String,
                    plugin["packageName"] as? String,
                    plugin["source"] as? String,
                ]
                .compactMap { $0?.lowercased() }

                if candidates.contains(where: { $0.contains("openclaw-weixin") || $0.contains("weixin") }) {
                    return true
                }
            }
        }

        let normalized = output.lowercased()
        return normalized.contains("openclaw-weixin") || normalized.contains("@tencent-weixin/openclaw-weixin")
    }

    nonisolated static func parseBindingDetected(
        statusOutput: String,
        credentialEntries: [String]
    ) -> Bool {
        if credentialEntries.contains(where: { $0.lowercased().hasPrefix(wechatChannelID) }) {
            return true
        }

        let normalized = statusOutput.lowercased()
        let mentionsWeChat = normalized.contains(wechatChannelID) || normalized.contains("weixin")
        let positiveSignal = normalized.contains("ready") || normalized.contains("connected") || normalized.contains("online")
        let negativeSignal = normalized.contains("not configured") || normalized.contains("disconnected") || normalized.contains("error")
        return mentionsWeChat && positiveSignal && !negativeSignal
    }

    nonisolated static func makeTerminalShellCommand(command: String, path: String) -> String {
        "export PATH=\(shellQuote(path)); \(command)"
    }

    nonisolated static func makeTerminalLaunchArguments(shellCommand: String) -> [String] {
        [
            "-e", #"tell application "Terminal""#,
            "-e", "activate",
            "-e", #"do script "\#(appleScriptQuoted(shellCommand))""#,
            "-e", "end tell",
        ]
    }

    nonisolated static func listCredentialEntryNames(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String] {
        let credentialsDirectory = homeDirectory
            .appending(path: ".openclaw")
            .appending(path: "credentials")

        guard let entries = try? fileManager.contentsOfDirectory(
            at: credentialsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return entries.map(\.lastPathComponent)
    }

    private nonisolated static func parseJSONObject(from output: String) -> [String: Any]? {
        guard let data = output.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private nonisolated static func shellQuote(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "'", with: #"'\"'\"'"#)
        return "'\(escaped)'"
    }

    private nonisolated static func appleScriptQuoted(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
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
    func nonEmptyOr(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
