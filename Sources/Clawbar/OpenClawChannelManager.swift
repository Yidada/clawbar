import Foundation

struct OpenClawChannelCommandResult: Equatable, Sendable {
    let output: String
    let exitStatus: Int32
    let timedOut: Bool
}

enum WeChatFlowKind: String, Sendable {
    case install
    case bind

    var command: String {
        switch self {
        case .install:
            "npx -y @tencent-weixin/openclaw-weixin-cli@latest install"
        case .bind:
            "openclaw channels login --channel openclaw-weixin"
        }
    }
}

struct WeChatRuntimeSnapshot: Equatable, Sendable {
    var qrCodeURL: String?
    var pluginInstallStarted = false
    var pluginInstalled = false
    var pluginReadyForLogin = false
    var waitingForConnection = false
    var scanned = false
    var connected = false
    var restartingGateway = false
    var qrExpired = false
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
    @Published private(set) var pendingInstallCompletion = false
    @Published private(set) var pendingBindingCompletion = false
    @Published private(set) var lastActionSummary = "等待绑定"
    @Published private(set) var lastActionDetail = "Clawbar 会内置微信能力安装和绑定流程，用户只需要点击绑定并扫码。"
    @Published private(set) var lastCommandOutput = ""
    @Published private(set) var lastRefreshDate: Date?
    @Published private(set) var runtimeSnapshot = WeChatRuntimeSnapshot()

    private let environmentProvider: EnvironmentProvider
    private let runCommand: CommandRunner
    private var activeFlowProcess: Process?
    private var activeFlowKind: WeChatFlowKind?
    private var didRequestFlowCancellation = false

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

    var isBusy: Bool {
        isRefreshing || isInstalling || isLaunchingBinding
    }

    func refreshWeChatStatus() {
        guard !isRefreshing else { return }

        let environment = OpenClawInstaller.installationEnvironment(base: environmentProvider())
        let commandRunner = runCommand
        isRefreshing = true

        Task.detached(priority: .utility) {
            let openClawBinaryPath = Self.detectBinaryPath(
                named: "openclaw",
                environment: environment,
                runCommand: commandRunner
            )
            let npxBinaryPath = Self.detectBinaryPath(
                named: "npx",
                environment: environment,
                runCommand: commandRunner
            )
            let pluginInstalled = openClawBinaryPath.map {
                Self.queryPluginInstalled(
                    openClawBinaryPath: $0,
                    environment: environment,
                    runCommand: commandRunner
                )
            } ?? false
            let bindingDetected = openClawBinaryPath.map {
                Self.queryBindingDetected(
                    openClawBinaryPath: $0,
                    environment: environment,
                    runCommand: commandRunner
                )
            } ?? false

            await MainActor.run {
                self.isRefreshing = false
                self.lastRefreshDate = Date()
                self.openClawBinaryPath = openClawBinaryPath.map(OpenClawInstaller.displayBinaryPath(_:))
                self.npxBinaryPath = npxBinaryPath.map(OpenClawInstaller.displayBinaryPath(_:))
                self.pluginInstalled = pluginInstalled
                self.bindingDetected = bindingDetected
                self.pendingInstallCompletion = self.pendingInstallCompletion && !pluginInstalled
                self.pendingBindingCompletion = self.pendingBindingCompletion && !bindingDetected
                if bindingDetected || (!self.isInstalling && !self.isLaunchingBinding) {
                    self.runtimeSnapshot = WeChatRuntimeSnapshot()
                }

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
        let commandRunner = runCommand
        guard Self.detectBinaryPath(named: "openclaw", environment: environment, runCommand: commandRunner) != nil else {
            lastActionSummary = "未检测到 OpenClaw"
            lastActionDetail = "请先安装 OpenClaw，再安装微信能力。"
            return
        }
        guard Self.detectBinaryPath(named: "npx", environment: environment, runCommand: commandRunner) != nil else {
            lastActionSummary = "未检测到 npx"
            lastActionDetail = "当前环境里没有可用的 npx，无法执行官方微信安装器。"
            return
        }

        isInstalling = true
        pendingInstallCompletion = false
        pendingBindingCompletion = false
        runtimeSnapshot = WeChatRuntimeSnapshot()
        lastActionSummary = "正在后台安装微信能力..."
        lastActionDetail = "Clawbar 会在后台执行官方安装器，并把二维码显示在这里。"
        lastCommandOutput = "$ \(WeChatFlowKind.install.command)\n\n"

        startBackgroundFlow(kind: .install, environment: environment)
    }

    func startWeChatBinding() {
        guard !isLaunchingBinding else { return }

        let environment = OpenClawInstaller.installationEnvironment(base: environmentProvider())
        let commandRunner = runCommand
        guard Self.detectBinaryPath(named: "openclaw", environment: environment, runCommand: commandRunner) != nil else {
            lastActionSummary = "未检测到 OpenClaw"
            lastActionDetail = "请先安装 OpenClaw，再开始微信绑定。"
            return
        }
        guard pluginInstalled else {
            lastActionSummary = "请先安装微信能力"
            lastActionDetail = "微信插件还没有安装完成，暂时不能开始绑定。"
            return
        }

        isLaunchingBinding = true
        pendingInstallCompletion = false
        pendingBindingCompletion = false
        runtimeSnapshot = WeChatRuntimeSnapshot()
        lastActionSummary = "正在后台发起扫码连接..."
        lastActionDetail = "Clawbar 会在后台执行登录命令，并把二维码显示在这里。"
        lastCommandOutput = "$ \(WeChatFlowKind.bind.command)\n\n"

        startBackgroundFlow(kind: .bind, environment: environment)
    }

    func cancelActiveWeChatFlow() {
        didRequestFlowCancellation = true
        activeFlowProcess?.terminate()
        activeFlowProcess = nil
        activeFlowKind = nil
        isInstalling = false
        isLaunchingBinding = false
        pendingInstallCompletion = false
        pendingBindingCompletion = false
        runtimeSnapshot = WeChatRuntimeSnapshot()
        lastActionSummary = "已取消微信流程"
        lastActionDetail = "后台安装或扫码流程已停止。"
    }

    private func startBackgroundFlow(kind: WeChatFlowKind, environment: [String: String]) {
        didRequestFlowCancellation = false
        activeFlowKind = kind

        do {
            let process = try Self.makeStreamingProcess(
                command: kind.command,
                environment: environment,
                outputHandler: { [weak self] chunk in
                    Task { @MainActor [weak self] in
                        self?.handleBackgroundFlowOutput(chunk, kind: kind)
                    }
                },
                terminationHandler: { [weak self] status in
                    Task { @MainActor [weak self] in
                        self?.finishBackgroundFlow(kind: kind, status: status)
                    }
                }
            )

            activeFlowProcess = process
            try process.run()
        } catch {
            isInstalling = false
            isLaunchingBinding = false
            activeFlowProcess = nil
            activeFlowKind = nil
            lastActionSummary = "无法启动微信流程"
            lastActionDetail = error.localizedDescription
        }
    }

    private func handleBackgroundFlowOutput(_ chunk: String, kind: WeChatFlowKind) {
        guard activeFlowKind == kind else { return }

        lastCommandOutput.append(chunk)
        if lastCommandOutput.count > 60_000 {
            lastCommandOutput.removeFirst(lastCommandOutput.count - 60_000)
        }

        runtimeSnapshot = Self.parseRuntimeSnapshot(from: lastCommandOutput)

        if runtimeSnapshot.connected {
            pendingInstallCompletion = false
            pendingBindingCompletion = false
            lastActionSummary = "微信连接成功"
            lastActionDetail = kind == .install
                ? "插件已安装并完成扫码，正在重启 OpenClaw Gateway。"
                : "扫码已确认，正在等待连接完成。"
        } else if runtimeSnapshot.restartingGateway {
            pendingInstallCompletion = kind == .install
            pendingBindingCompletion = false
            lastActionSummary = "正在重启 OpenClaw Gateway"
            lastActionDetail = "微信账号已经确认，Clawbar 正在等待 Gateway 重启完成。"
        } else if runtimeSnapshot.scanned {
            pendingInstallCompletion = kind == .install
            pendingBindingCompletion = kind == .bind
            lastActionSummary = "已扫码，等待微信确认"
            lastActionDetail = "请在手机微信里确认登录。"
        } else if runtimeSnapshot.qrCodeURL != nil {
            pendingInstallCompletion = kind == .install
            pendingBindingCompletion = kind == .bind
            lastActionSummary = kind == .install ? "请扫码安装并连接" : "请扫码连接微信"
            lastActionDetail = "二维码已准备好。请直接用微信扫一扫。"
        } else if runtimeSnapshot.pluginReadyForLogin {
            lastActionSummary = "插件已就绪"
            lastActionDetail = "正在准备微信扫码登录。"
        } else if runtimeSnapshot.pluginInstalled {
            lastActionSummary = "微信插件已安装"
            lastActionDetail = "安装已完成，正在进入扫码连接。"
        } else if runtimeSnapshot.pluginInstallStarted {
            lastActionSummary = "正在安装微信插件"
            lastActionDetail = "Clawbar 正在后台执行官方安装器。"
        }
    }

    private func finishBackgroundFlow(kind: WeChatFlowKind, status: Int32) {
        let didCancel = didRequestFlowCancellation
        didRequestFlowCancellation = false
        activeFlowProcess = nil
        activeFlowKind = nil
        isInstalling = false
        isLaunchingBinding = false

        if didCancel {
            return
        }

        if status == 0 {
            pendingInstallCompletion = false
            pendingBindingCompletion = false

            if runtimeSnapshot.connected {
                lastActionSummary = "微信连接成功"
                lastActionDetail = "后台流程已完成，正在刷新当前状态。"
            } else {
                lastActionSummary = kind == .install ? "微信能力安装完成" : "微信扫码流程结束"
                lastActionDetail = "后台流程已结束，正在刷新当前状态。"
            }

            refreshWeChatStatus()
            return
        }

        pendingInstallCompletion = false
        pendingBindingCompletion = false
        lastActionSummary = kind == .install ? "微信安装流程失败" : "微信扫码流程失败"
        lastActionDetail = Self.extractFailureDetail(from: lastCommandOutput)
            ?? "后台命令异常退出，详情见最近输出。"
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

    nonisolated static func parseRuntimeSnapshot(from output: String) -> WeChatRuntimeSnapshot {
        let latestQRCodeURL = latestMatch(
            pattern: #"https://liteapp\.weixin\.qq\.com/q/\S+"#,
            in: output
        )

        return WeChatRuntimeSnapshot(
            qrCodeURL: latestQRCodeURL,
            pluginInstallStarted: output.contains("正在安装插件"),
            pluginInstalled: output.contains("Installed plugin: openclaw-weixin"),
            pluginReadyForLogin: output.contains("插件就绪，开始首次连接"),
            waitingForConnection: output.contains("等待连接结果"),
            scanned: output.contains("已扫码，在微信继续操作"),
            connected: output.contains("✅ 与微信连接成功"),
            restartingGateway: output.contains("正在重启 OpenClaw Gateway"),
            qrExpired: output.contains("二维码已过期")
        )
    }

    private nonisolated static func latestMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        guard let result = matches.last, let matchRange = Range(result.range, in: text) else { return nil }
        return String(text[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func extractFailureDetail(from output: String) -> String? {
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

    private nonisolated static func makeStreamingProcess(
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
            outputHandler(sanitizeChannelOutput(data))
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

private func sanitizeChannelOutput(_ data: Data) -> String {
    let raw = String(decoding: data, as: UTF8.self)
    let pattern = #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#

    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return raw
    }

    let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
    return regex.stringByReplacingMatches(in: raw, options: [], range: range, withTemplate: "")
}
