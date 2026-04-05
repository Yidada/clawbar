import Foundation

struct FeishuAppCredentials: Equatable, Sendable {
    let appID: String
    let appSecret: String

    var isComplete: Bool {
        trimmedNonEmpty(appID) != nil && trimmedNonEmpty(appSecret) != nil
    }

    var cliValue: String? {
        guard let appID = trimmedNonEmpty(appID),
              let appSecret = trimmedNonEmpty(appSecret) else {
            return nil
        }

        return "\(appID):\(appSecret)"
    }
}

enum FeishuChannelStage: String, Equatable, Sendable {
    case preflight
    case install
    case configure
    case verify
    case diagnose
    case ready
}

enum FeishuChannelAction: String, Equatable, Sendable {
    case enable
    case disable
    case retry
    case diagnose
    case fix
    case refresh
}

struct FeishuChannelStatusSnapshot: Equatable, Sendable {
    let stage: FeishuChannelStage
    let pluginInstalled: Bool
    let channelEnabled: Bool
    let gatewayReachable: Bool
    let doctorHealthy: Bool?
    let openClawBinaryPath: String?
    let npxBinaryPath: String?
    let openClawVersion: String?
    let pluginVersion: String?
    let summary: String
    let detail: String
    let continueURL: String?
    let logSummary: String?

    static let idle = FeishuChannelStatusSnapshot(
        stage: .preflight,
        pluginInstalled: false,
        channelEnabled: false,
        gatewayReachable: false,
        doctorHealthy: nil,
        openClawBinaryPath: nil,
        npxBinaryPath: nil,
        openClawVersion: nil,
        pluginVersion: nil,
        summary: "等待检查 Feishu 状态",
        detail: "Clawbar 会读取官方插件安装状态、Feishu channel 配置和 Gateway 状态。",
        continueURL: nil,
        logSummary: nil
    )
}

private struct FeishuPluginInfo: Equatable, Sendable {
    let cliVersion: String?
    let openClawVersion: String?
    let pluginVersion: String?

    var pluginInstalled: Bool {
        pluginVersion != nil
    }
}

private struct FeishuDoctorStatus: Equatable, Sendable {
    let healthy: Bool
    let detail: String
}

private struct FeishuInstallProgress: Equatable, Sendable {
    let stage: FeishuChannelStage
    let summary: String
    let detail: String
    let continueURL: String?
}

private struct FeishuVersion: Comparable, Equatable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init?(string: String) {
        let parts = string.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.year = parts[0]
        self.month = parts[1]
        self.day = parts[2]
    }

    static func < (lhs: FeishuVersion, rhs: FeishuVersion) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

@MainActor
final class OpenClawFeishuChannelManager: ObservableObject {
    static let shared = OpenClawFeishuChannelManager()

    typealias EnvironmentProvider = @Sendable () -> [String: String]
    typealias CommandRunner = ChannelCommandSupport.CommandRunner
    typealias StreamingProcessFactory = @Sendable (
        _ command: String,
        _ environment: [String: String],
        _ outputHandler: @escaping @Sendable (String) -> Void,
        _ terminationHandler: @escaping @Sendable (Int32) -> Void
    ) throws -> Process

    fileprivate nonisolated static let minimumOpenClawVersion = FeishuVersion(string: "2026.2.26")!

    @Published private(set) var snapshot: FeishuChannelStatusSnapshot = .idle
    @Published private(set) var isRefreshing = false
    @Published private(set) var activeAction: FeishuChannelAction?
    @Published private(set) var lastCommandOutput = ""
    @Published private(set) var lastRefreshDate: Date?
    @Published private(set) var toggleIntent = false

    private let environmentProvider: EnvironmentProvider
    private let runCommand: CommandRunner
    private let makeStreamingProcess: StreamingProcessFactory
    private var activeProcess: Process?

    init(
        environmentProvider: @escaping EnvironmentProvider = { ProcessInfo.processInfo.environment },
        runCommand: @escaping CommandRunner = ChannelCommandSupport.runCommand,
        makeStreamingProcess: @escaping StreamingProcessFactory = ChannelCommandSupport.makeStreamingProcess
    ) {
        self.environmentProvider = environmentProvider
        self.runCommand = runCommand
        self.makeStreamingProcess = makeStreamingProcess
    }

    var isBusy: Bool {
        isRefreshing || activeAction != nil
    }

    var isEnabled: Bool {
        toggleIntent || snapshot.channelEnabled
    }

    var canStartEnableFlow: Bool {
        primaryAction == .enable
    }

    var statusLabel: String {
        switch snapshot.stage {
        case .preflight:
            return "环境待检查"
        case .install:
            return "未安装"
        case .configure:
            return "配置中"
        case .verify:
            return "待验证"
        case .diagnose:
            return "待修复"
        case .ready:
            return "可用"
        }
    }

    var primaryAction: FeishuChannelAction {
        switch snapshot.stage {
        case .preflight:
            return .retry
        case .install:
            return .enable
        case .configure:
            return .retry
        case .verify:
            return snapshot.channelEnabled ? .retry : .enable
        case .diagnose:
            return .fix
        case .ready:
            return .retry
        }
    }

    var primaryActionTitle: String {
        switch primaryAction {
        case .enable:
            return snapshot.pluginInstalled ? "重新启用" : "开始安装并启用"
        case .disable:
            return "停用"
        case .retry:
            switch snapshot.stage {
            case .configure:
                return "继续配置"
            case .ready:
                return "重新验证"
            default:
                return "重新检查"
            }
        case .diagnose:
            return "运行诊断"
        case .fix:
            return "运行修复"
        case .refresh:
            return "刷新状态"
        }
    }

    func refreshStatus() {
        guard !isRefreshing else { return }

        let environment = ChannelCommandSupport.commandEnvironment(base: environmentProvider())
        let runCommand = runCommand

        isRefreshing = true

        Task.detached(priority: .utility) {
            let openClawBinaryPath = ChannelCommandSupport.detectBinaryPath(
                named: "openclaw",
                environment: environment,
                runCommand: runCommand
            )
            let npxBinaryPath = ChannelCommandSupport.detectBinaryPath(
                named: "npx",
                environment: environment,
                runCommand: runCommand
            )
            let snapshot = Self.makeStatusSnapshot(
                openClawBinaryPath: openClawBinaryPath,
                npxBinaryPath: npxBinaryPath,
                environment: environment,
                runCommand: runCommand
            )

            await MainActor.run {
                self.isRefreshing = false
                self.lastRefreshDate = Date()
                self.snapshot = snapshot
                if self.activeAction == nil {
                    self.toggleIntent = snapshot.channelEnabled
                }
            }
        }
    }

    func runPrimaryAction(existingAppCredentials: FeishuAppCredentials?) {
        switch primaryAction {
        case .enable:
            enable(using: existingAppCredentials)
        case .disable:
            disable()
        case .retry, .refresh:
            refreshStatus()
        case .diagnose:
            runDoctor()
        case .fix:
            runDoctorFix()
        }
    }

    func enable(using existingAppCredentials: FeishuAppCredentials? = nil) {
        guard activeAction == nil else { return }
        guard canStartEnableFlow else { return }
        toggleIntent = true

        if snapshot.pluginInstalled {
            setChannelEnabled(true, summary: "正在重新启用 Feishu Channel...")
            return
        }

        let environment = ChannelCommandSupport.commandEnvironment(base: environmentProvider())
        guard let npxBinaryPath = ChannelCommandSupport.detectBinaryPath(
            named: "npx",
            environment: environment,
            runCommand: runCommand
        ) else {
            snapshot = FeishuChannelStatusSnapshot(
                stage: .preflight,
                pluginInstalled: false,
                channelEnabled: false,
                gatewayReachable: false,
                doctorHealthy: nil,
                openClawBinaryPath: snapshot.openClawBinaryPath,
                npxBinaryPath: nil,
                openClawVersion: snapshot.openClawVersion,
                pluginVersion: snapshot.pluginVersion,
                summary: "未检测到 npx",
                detail: "Feishu 官方插件通过 npx 分发，请先确保当前环境可执行 npx。",
                continueURL: nil,
                logSummary: nil
            )
            toggleIntent = false
            return
        }

        snapshot = FeishuChannelStatusSnapshot(
            stage: .install,
            pluginInstalled: false,
            channelEnabled: false,
            gatewayReachable: snapshot.gatewayReachable,
            doctorHealthy: nil,
            openClawBinaryPath: snapshot.openClawBinaryPath,
            npxBinaryPath: OpenClawInstaller.displayBinaryPath(npxBinaryPath),
            openClawVersion: snapshot.openClawVersion,
            pluginVersion: snapshot.pluginVersion,
            summary: "正在安装并启用 Feishu 官方插件...",
            detail: "Clawbar 会在后台执行官方 CLI，并把下一步浏览器链接展示在这里。",
            continueURL: nil,
            logSummary: nil
        )
        lastCommandOutput = "$ \(Self.installLogCommand(credentials: existingAppCredentials))\n\n"
        activeAction = .enable

        startStreamingCommand(
            command: Self.installCommand(credentials: existingAppCredentials),
            environment: environment,
            activeAction: .enable
        )
    }

    func disable() {
        guard activeAction == nil else { return }
        toggleIntent = false
        setChannelEnabled(false, summary: "正在停用 Feishu Channel...")
    }

    func runDoctor() {
        guard activeAction == nil else { return }
        runOneShotCommand(
            action: .diagnose,
            summary: "正在运行 Feishu 诊断...",
            detail: "Clawbar 正在调用官方 doctor 命令检查当前安装。",
            command: Self.doctorCommand(fix: false)
        )
    }

    func runDoctorFix() {
        guard activeAction == nil else { return }
        runOneShotCommand(
            action: .fix,
            summary: "正在修复 Feishu 插件配置...",
            detail: "Clawbar 正在调用官方 doctor --fix 自动修复常见问题。",
            command: Self.doctorCommand(fix: true)
        )
    }

    private func setChannelEnabled(_ enabled: Bool, summary: String) {
        let environment = ChannelCommandSupport.commandEnvironment(base: environmentProvider())
        let runCommand = runCommand
        activeAction = enabled ? .enable : .disable
        lastCommandOutput = "$ openclaw config set channels.feishu.enabled \(enabled ? "true" : "false") --strict-json\n\n"

        Task.detached(priority: .userInitiated) {
            let openClawBinaryPath = ChannelCommandSupport.detectBinaryPath(
                named: "openclaw",
                environment: environment,
                runCommand: runCommand
            )

            guard let openClawBinaryPath else {
                await MainActor.run {
                    self.activeAction = nil
                    self.toggleIntent = false
                    self.snapshot = FeishuChannelStatusSnapshot(
                        stage: .preflight,
                        pluginInstalled: self.snapshot.pluginInstalled,
                        channelEnabled: false,
                        gatewayReachable: false,
                        doctorHealthy: nil,
                        openClawBinaryPath: nil,
                        npxBinaryPath: self.snapshot.npxBinaryPath,
                        openClawVersion: self.snapshot.openClawVersion,
                        pluginVersion: self.snapshot.pluginVersion,
                        summary: "未检测到 OpenClaw",
                        detail: "请先安装 OpenClaw，再管理 Feishu Channel。",
                        continueURL: nil,
                        logSummary: nil
                    )
                }
                return
            }

            let setResult = runCommand(
                openClawBinaryPath,
                ["config", "set", "channels.feishu.enabled", enabled ? "true" : "false", "--strict-json"],
                environment,
                12
            )

            await MainActor.run {
                self.lastCommandOutput += setResult.output
            }

            if setResult.timedOut || setResult.exitStatus != 0 {
                let detail = ChannelCommandSupport.extractFailureDetail(from: setResult.output)
                    ?? "Feishu Channel 配置写入失败。"
                await MainActor.run {
                    self.activeAction = nil
                    if enabled {
                        self.toggleIntent = self.snapshot.channelEnabled
                    }
                    self.snapshot = FeishuChannelStatusSnapshot(
                        stage: .diagnose,
                        pluginInstalled: self.snapshot.pluginInstalled,
                        channelEnabled: self.snapshot.channelEnabled,
                        gatewayReachable: self.snapshot.gatewayReachable,
                        doctorHealthy: false,
                        openClawBinaryPath: self.snapshot.openClawBinaryPath,
                        npxBinaryPath: self.snapshot.npxBinaryPath,
                        openClawVersion: self.snapshot.openClawVersion,
                        pluginVersion: self.snapshot.pluginVersion,
                        summary: enabled ? "Feishu Channel 启用失败" : "Feishu Channel 停用失败",
                        detail: detail,
                        continueURL: nil,
                        logSummary: detail
                    )
                }
                return
            }

            let restartResult = runCommand(
                openClawBinaryPath,
                ["gateway", "restart", "--json"],
                environment,
                20
            )

            await MainActor.run {
                if !self.lastCommandOutput.hasSuffix("\n") { self.lastCommandOutput += "\n" }
                self.lastCommandOutput += "\n$ openclaw gateway restart --json\n\n"
                self.lastCommandOutput += restartResult.output
            }

            await MainActor.run {
                self.snapshot = FeishuChannelStatusSnapshot(
                    stage: .verify,
                    pluginInstalled: self.snapshot.pluginInstalled,
                    channelEnabled: enabled,
                    gatewayReachable: self.snapshot.gatewayReachable,
                    doctorHealthy: nil,
                    openClawBinaryPath: OpenClawInstaller.displayBinaryPath(openClawBinaryPath),
                    npxBinaryPath: self.snapshot.npxBinaryPath,
                    openClawVersion: self.snapshot.openClawVersion,
                    pluginVersion: self.snapshot.pluginVersion,
                    summary: summary,
                    detail: "配置已写入，Clawbar 正在重新验证插件和 Gateway 状态。",
                    continueURL: nil,
                    logSummary: trimmedNonEmpty(restartResult.output)
                )
                self.activeAction = nil
                self.refreshStatus()
            }
        }
    }

    private func runOneShotCommand(
        action: FeishuChannelAction,
        summary: String,
        detail: String,
        command: String
    ) {
        let environment = ChannelCommandSupport.commandEnvironment(base: environmentProvider())
        let runCommand = runCommand
        activeAction = action
        lastCommandOutput = "$ \(command)\n\n"
        snapshot = FeishuChannelStatusSnapshot(
            stage: action == .fix ? .diagnose : snapshot.stage,
            pluginInstalled: snapshot.pluginInstalled,
            channelEnabled: snapshot.channelEnabled,
            gatewayReachable: snapshot.gatewayReachable,
            doctorHealthy: snapshot.doctorHealthy,
            openClawBinaryPath: snapshot.openClawBinaryPath,
            npxBinaryPath: snapshot.npxBinaryPath,
            openClawVersion: snapshot.openClawVersion,
            pluginVersion: snapshot.pluginVersion,
            summary: summary,
            detail: detail,
            continueURL: nil,
            logSummary: nil
        )

        Task.detached(priority: .userInitiated) {
            let result = ChannelCommandSupport.runShellCommand(
                command,
                environment: environment,
                timeout: action == .fix ? 30 : 15,
                runCommand: runCommand
            )

            await MainActor.run {
                self.lastCommandOutput += result.output
                self.activeAction = nil
                if result.exitStatus == 0 {
                    self.refreshStatus()
                } else {
                    let failureDetail = ChannelCommandSupport.extractFailureDetail(from: result.output)
                        ?? "命令执行失败。"
                    self.snapshot = FeishuChannelStatusSnapshot(
                        stage: .diagnose,
                        pluginInstalled: self.snapshot.pluginInstalled,
                        channelEnabled: self.snapshot.channelEnabled,
                        gatewayReachable: self.snapshot.gatewayReachable,
                        doctorHealthy: false,
                        openClawBinaryPath: self.snapshot.openClawBinaryPath,
                        npxBinaryPath: self.snapshot.npxBinaryPath,
                        openClawVersion: self.snapshot.openClawVersion,
                        pluginVersion: self.snapshot.pluginVersion,
                        summary: action == .fix ? "自动修复失败" : "诊断发现异常",
                        detail: failureDetail,
                        continueURL: nil,
                        logSummary: failureDetail
                    )
                }
            }
        }
    }

    private func startStreamingCommand(
        command: String,
        environment: [String: String],
        activeAction: FeishuChannelAction
    ) {
        do {
            let process = try makeStreamingProcess(
                command,
                environment,
                { [weak self] chunk in
                    Task { @MainActor [weak self] in
                        self?.handleStreamingOutput(chunk)
                    }
                },
                { [weak self] status in
                    Task { @MainActor [weak self] in
                        self?.finishStreamingCommand(status: status, action: activeAction)
                    }
                }
            )

            activeProcess = process
            try process.run()
        } catch {
            self.activeAction = nil
            self.snapshot = FeishuChannelStatusSnapshot(
                stage: .diagnose,
                pluginInstalled: false,
                channelEnabled: false,
                gatewayReachable: false,
                doctorHealthy: false,
                openClawBinaryPath: snapshot.openClawBinaryPath,
                npxBinaryPath: snapshot.npxBinaryPath,
                openClawVersion: snapshot.openClawVersion,
                pluginVersion: snapshot.pluginVersion,
                summary: "无法启动 Feishu 安装流程",
                detail: error.localizedDescription,
                continueURL: nil,
                logSummary: error.localizedDescription
            )
        }
    }

    private func handleStreamingOutput(_ chunk: String) {
        lastCommandOutput.append(chunk)
        if lastCommandOutput.count > 60_000 {
            lastCommandOutput.removeFirst(lastCommandOutput.count - 60_000)
        }

        let progress = Self.parseInstallProgress(from: lastCommandOutput)
        snapshot = FeishuChannelStatusSnapshot(
            stage: progress.stage,
            pluginInstalled: progress.stage == .verify || progress.stage == .ready,
            channelEnabled: snapshot.channelEnabled,
            gatewayReachable: snapshot.gatewayReachable,
            doctorHealthy: snapshot.doctorHealthy,
            openClawBinaryPath: snapshot.openClawBinaryPath,
            npxBinaryPath: snapshot.npxBinaryPath,
            openClawVersion: snapshot.openClawVersion,
            pluginVersion: snapshot.pluginVersion,
            summary: progress.summary,
            detail: progress.detail,
            continueURL: progress.continueURL,
            logSummary: Self.logSummary(from: lastCommandOutput)
        )
    }

    private func finishStreamingCommand(status: Int32, action: FeishuChannelAction) {
        activeProcess = nil
        activeAction = nil

        if status == 0 {
            if action == .enable {
                setChannelEnabled(true, summary: "Feishu 插件安装完成，正在启用 Channel...")
                return
            }

            refreshStatus()
            return
        }

        let detail = ChannelCommandSupport.extractFailureDetail(from: lastCommandOutput)
            ?? "官方安装器执行失败，详情见日志。"
        if action == .enable {
            toggleIntent = false
        }
        snapshot = FeishuChannelStatusSnapshot(
            stage: .diagnose,
            pluginInstalled: snapshot.pluginInstalled,
            channelEnabled: false,
            gatewayReachable: snapshot.gatewayReachable,
            doctorHealthy: false,
            openClawBinaryPath: snapshot.openClawBinaryPath,
            npxBinaryPath: snapshot.npxBinaryPath,
            openClawVersion: snapshot.openClawVersion,
            pluginVersion: snapshot.pluginVersion,
            summary: "Feishu 安装或配置失败",
            detail: detail,
            continueURL: Self.parseInstallProgress(from: lastCommandOutput).continueURL,
            logSummary: detail
        )
    }

    private nonisolated static func installCommand(credentials: FeishuAppCredentials?) -> String {
        if let cliValue = credentials?.cliValue {
            return "npx -y @larksuite/openclaw-lark install --use-existing --app '\(cliValue)'"
        }

        return "npx -y @larksuite/openclaw-lark install"
    }

    private nonisolated static func installLogCommand(credentials: FeishuAppCredentials?) -> String {
        if let appID = trimmedNonEmpty(credentials?.appID) {
            return "npx -y @larksuite/openclaw-lark install --use-existing --app '\(appID):<redacted>'"
        }

        return installCommand(credentials: nil)
    }

    private nonisolated static func doctorCommand(fix: Bool) -> String {
        fix ? "npx -y @larksuite/openclaw-lark doctor --fix" : "npx -y @larksuite/openclaw-lark doctor"
    }

    private nonisolated static func makeStatusSnapshot(
        openClawBinaryPath: String?,
        npxBinaryPath: String?,
        environment: [String: String],
        runCommand: CommandRunner
    ) -> FeishuChannelStatusSnapshot {
        let displayOpenClawPath = openClawBinaryPath.map(OpenClawInstaller.displayBinaryPath(_:))
        let displayNpxPath = npxBinaryPath.map(OpenClawInstaller.displayBinaryPath(_:))

        guard openClawBinaryPath != nil else {
            return FeishuChannelStatusSnapshot(
                stage: .preflight,
                pluginInstalled: false,
                channelEnabled: false,
                gatewayReachable: false,
                doctorHealthy: nil,
                openClawBinaryPath: nil,
                npxBinaryPath: displayNpxPath,
                openClawVersion: nil,
                pluginVersion: nil,
                summary: "未检测到 OpenClaw",
                detail: "Feishu 官方插件依赖本机 OpenClaw。请先完成 OpenClaw 安装，再回来启用飞书 Channel。",
                continueURL: nil,
                logSummary: nil
            )
        }

        guard npxBinaryPath != nil else {
            return FeishuChannelStatusSnapshot(
                stage: .preflight,
                pluginInstalled: false,
                channelEnabled: false,
                gatewayReachable: false,
                doctorHealthy: nil,
                openClawBinaryPath: displayOpenClawPath,
                npxBinaryPath: nil,
                openClawVersion: nil,
                pluginVersion: nil,
                summary: "未检测到 npx",
                detail: "Feishu 官方插件通过 npx 分发。请先修复 Node.js / npx 环境。",
                continueURL: nil,
                logSummary: nil
            )
        }

        let infoResult = ChannelCommandSupport.runShellCommand(
            "npx -y @larksuite/openclaw-lark info",
            environment: environment,
            timeout: 12,
            runCommand: runCommand
        )
        let pluginInfo = parsePluginInfo(from: infoResult.output)
        let openClawVersion = pluginInfo?.openClawVersion

        if let versionString = openClawVersion,
           let parsedVersion = FeishuVersion(string: versionString),
           parsedVersion < minimumOpenClawVersion {
            return FeishuChannelStatusSnapshot(
                stage: .preflight,
                pluginInstalled: false,
                channelEnabled: false,
                gatewayReachable: false,
                doctorHealthy: nil,
                openClawBinaryPath: displayOpenClawPath,
                npxBinaryPath: displayNpxPath,
                openClawVersion: versionString,
                pluginVersion: pluginInfo?.pluginVersion,
                summary: "OpenClaw 版本过低",
                detail: "Feishu 官方插件要求 OpenClaw 至少为 2026.2.26；当前检测到 \(versionString)。",
                continueURL: nil,
                logSummary: nil
            )
        }

        guard let pluginInfo else {
            return FeishuChannelStatusSnapshot(
                stage: .preflight,
                pluginInstalled: false,
                channelEnabled: false,
                gatewayReachable: false,
                doctorHealthy: nil,
                openClawBinaryPath: displayOpenClawPath,
                npxBinaryPath: displayNpxPath,
                openClawVersion: nil,
                pluginVersion: nil,
                summary: "无法读取 Feishu 插件信息",
                detail: ChannelCommandSupport.extractFailureDetail(from: infoResult.output)
                    ?? "官方 info 命令没有返回可识别结果。",
                continueURL: nil,
                logSummary: logSummary(from: infoResult.output)
            )
        }

        if !pluginInfo.pluginInstalled {
            return FeishuChannelStatusSnapshot(
                stage: .install,
                pluginInstalled: false,
                channelEnabled: false,
                gatewayReachable: false,
                doctorHealthy: nil,
                openClawBinaryPath: displayOpenClawPath,
                npxBinaryPath: displayNpxPath,
                openClawVersion: pluginInfo.openClawVersion,
                pluginVersion: nil,
                summary: "Feishu 官方插件未安装",
                detail: "打开开关后，Clawbar 会直接调用官方 CLI 完成安装、配置和启用。",
                continueURL: nil,
                logSummary: logSummary(from: infoResult.output)
            )
        }

        guard let openClawBinaryPath else {
            return .idle
        }

        let channelEnabled = readBooleanConfig(
            openClawBinaryPath: openClawBinaryPath,
            environment: environment,
            runCommand: runCommand,
            path: "channels.feishu.enabled"
        ) ?? false
        let gatewayReachable = queryGatewayReachable(
            openClawBinaryPath: openClawBinaryPath,
            environment: environment,
            runCommand: runCommand
        )

        if !channelEnabled {
            return FeishuChannelStatusSnapshot(
                stage: .verify,
                pluginInstalled: true,
                channelEnabled: false,
                gatewayReachable: gatewayReachable,
                doctorHealthy: nil,
                openClawBinaryPath: displayOpenClawPath,
                npxBinaryPath: displayNpxPath,
                openClawVersion: pluginInfo.openClawVersion,
                pluginVersion: pluginInfo.pluginVersion,
                summary: "Feishu 插件已安装，Channel 未启用",
                detail: "点击“重新启用”后，Clawbar 会写入 `channels.feishu.enabled=true` 并重启 Gateway。",
                continueURL: nil,
                logSummary: logSummary(from: infoResult.output)
            )
        }

        let doctorStatus = queryDoctorStatus(environment: environment, runCommand: runCommand)
        if doctorStatus.healthy == false {
            return FeishuChannelStatusSnapshot(
                stage: .diagnose,
                pluginInstalled: true,
                channelEnabled: true,
                gatewayReachable: gatewayReachable,
                doctorHealthy: false,
                openClawBinaryPath: displayOpenClawPath,
                npxBinaryPath: displayNpxPath,
                openClawVersion: pluginInfo.openClawVersion,
                pluginVersion: pluginInfo.pluginVersion,
                summary: "Feishu 插件需要诊断修复",
                detail: doctorStatus.detail,
                continueURL: nil,
                logSummary: doctorStatus.detail
            )
        }

        if !gatewayReachable {
            return FeishuChannelStatusSnapshot(
                stage: .verify,
                pluginInstalled: true,
                channelEnabled: true,
                gatewayReachable: false,
                doctorHealthy: true,
                openClawBinaryPath: displayOpenClawPath,
                npxBinaryPath: displayNpxPath,
                openClawVersion: pluginInfo.openClawVersion,
                pluginVersion: pluginInfo.pluginVersion,
                summary: "Feishu 已启用，等待 Gateway 恢复",
                detail: "当前 Gateway 未运行或未加载，建议先处理 Gateway 再重新验证。",
                continueURL: nil,
                logSummary: nil
            )
        }

        return FeishuChannelStatusSnapshot(
            stage: .ready,
            pluginInstalled: true,
            channelEnabled: true,
            gatewayReachable: true,
            doctorHealthy: true,
            openClawBinaryPath: displayOpenClawPath,
            npxBinaryPath: displayNpxPath,
            openClawVersion: pluginInfo.openClawVersion,
            pluginVersion: pluginInfo.pluginVersion,
            summary: "Feishu 已启用并可用",
            detail: "官方插件已安装，Feishu Channel 已启用，Gateway 当前运行正常。",
            continueURL: nil,
            logSummary: logSummary(from: infoResult.output)
        )
    }

    private nonisolated static func parsePluginInfo(from output: String) -> FeishuPluginInfo? {
        let lines = output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return nil }

        var cliVersion: String?
        var openClawVersion: String?
        var pluginVersion: String?

        for line in lines {
            if let value = value(after: "feishu-plugin-onboard:", in: line) {
                cliVersion = trimmedNonEmpty(value)
            } else if let value = value(after: "openclaw:", in: line) {
                openClawVersion = extractVersionToken(from: value)
            } else if let value = value(after: "openclaw-lark:", in: line) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.caseInsensitiveCompare("Not Installed") != .orderedSame {
                    pluginVersion = trimmed
                }
            }
        }

        return FeishuPluginInfo(
            cliVersion: cliVersion,
            openClawVersion: openClawVersion,
            pluginVersion: pluginVersion
        )
    }

    private nonisolated static func parseInstallProgress(from output: String) -> FeishuInstallProgress {
        let urls = ChannelCommandSupport.extractURLs(from: output)
        let continueURL = urls.last

        if output.contains("OK: 登录成功") || output.contains("OK: 安装成功") {
            return FeishuInstallProgress(
                stage: .verify,
                summary: "Feishu 安装完成，正在验证",
                detail: "官方 CLI 已完成主要流程，Clawbar 即将继续启用并验证 Channel。",
                continueURL: continueURL
            )
        }

        if output.contains("等待配置应用")
            || output.contains("打开以下链接配置应用")
            || output.contains("等待用户授权")
            || output.contains("verification_url")
            || output.contains("authorization URL") {
            return FeishuInstallProgress(
                stage: .configure,
                summary: "请继续在浏览器完成配置",
                detail: "Clawbar 已拿到官方 CLI 给出的浏览器链接；打开链接继续完成应用配置或授权。",
                continueURL: continueURL
            )
        }

        return FeishuInstallProgress(
            stage: .install,
            summary: "正在安装 Feishu 官方插件",
            detail: "Clawbar 正在后台执行官方安装与配置命令。",
            continueURL: continueURL
        )
    }

    private nonisolated static func queryDoctorStatus(
        environment: [String: String],
        runCommand: CommandRunner
    ) -> FeishuDoctorStatus {
        let result = ChannelCommandSupport.runShellCommand(
            doctorCommand(fix: false),
            environment: environment,
            timeout: 15,
            runCommand: runCommand
        )

        if result.exitStatus == 0 {
            return FeishuDoctorStatus(healthy: true, detail: "官方 doctor 检查通过。")
        }

        return FeishuDoctorStatus(
            healthy: false,
            detail: ChannelCommandSupport.extractFailureDetail(from: result.output)
                ?? trimmedNonEmpty(result.output)
                ?? "doctor 检查失败。"
        )
    }

    private nonisolated static func queryGatewayReachable(
        openClawBinaryPath: String,
        environment: [String: String],
        runCommand: CommandRunner
    ) -> Bool {
        let result = runCommand(
            openClawBinaryPath,
            ["gateway", "status", "--json", "--no-probe"],
            environment,
            12
        )

        guard result.exitStatus == 0,
              let payload = ChannelCommandSupport.parseJSONObject(from: result.output),
              let service = payload["service"] as? [String: Any],
              let loaded = service["loaded"] as? Bool,
              let runtime = service["runtime"] as? [String: Any],
              let status = (runtime["status"] as? String)?.lowercased() else {
            return false
        }

        return loaded && status == "running"
    }

    private nonisolated static func readBooleanConfig(
        openClawBinaryPath: String,
        environment: [String: String],
        runCommand: CommandRunner,
        path: String
    ) -> Bool? {
        let result = runCommand(
            openClawBinaryPath,
            ["config", "get", path, "--json"],
            environment,
            8
        )

        guard result.exitStatus == 0 else { return nil }

        let trimmed = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "true" {
            return true
        }
        if trimmed == "false" {
            return false
        }
        return nil
    }

    private nonisolated static func value(after prefix: String, in line: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        return trimmedNonEmpty(String(line.dropFirst(prefix.count)))
    }

    private nonisolated static func extractVersionToken(from line: String) -> String? {
        let pattern = #"\d{4}\.\d{1,2}\.\d{1,2}"#
        return ChannelCommandSupport.latestMatch(pattern: pattern, in: line)
    }

    private nonisolated static func logSummary(from output: String) -> String? {
        if let detail = ChannelCommandSupport.extractFailureDetail(from: output) {
            return detail
        }

        let lastLine = output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .last(where: { !$0.isEmpty })
        return trimmedNonEmpty(lastLine)
    }
}
