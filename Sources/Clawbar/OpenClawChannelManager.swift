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

struct OpenClawWeixinStatusPayload: Equatable, Sendable {
    struct GatewaySnapshot: Equatable, Sendable {
        let reachable: Bool?
        let error: String?
        let url: String?
    }

    struct GatewayServiceSnapshot: Equatable, Sendable {
        let installed: Bool?
        let loaded: Bool?
        let runtimeShort: String?
    }

    let runtimeVersion: String?
    let channelSummary: [String]
    let gateway: GatewaySnapshot
    let gatewayService: GatewayServiceSnapshot
}

enum OpenClawWeixinDerivedState: Equatable, Sendable {
    case pluginMissing
    case pluginPresentButNotConfigured
    case pluginConfiguredGatewayReachable(accountLabel: String?)
    case pluginConfiguredGatewayUnreachable(accountLabel: String?, gatewayDetail: String?)
}

enum OpenClawWeixinCardState: Equatable, Sendable {
    case missingCLI
    case refreshing(lastKnown: OpenClawWeixinDerivedState?)
    case statusCommandFailed(detail: String)
    case jsonParseFailed(detail: String)
    case pluginMissing
    case pluginPresentButNotConfigured
    case pluginConfiguredGatewayReachable(accountLabel: String?)
    case pluginConfiguredGatewayUnreachable(accountLabel: String?, gatewayDetail: String?)

    var stableDerivedState: OpenClawWeixinDerivedState? {
        switch self {
        case .refreshing(let lastKnown):
            return lastKnown
        case .pluginMissing:
            return .pluginMissing
        case .pluginPresentButNotConfigured:
            return .pluginPresentButNotConfigured
        case .pluginConfiguredGatewayReachable(let accountLabel):
            return .pluginConfiguredGatewayReachable(accountLabel: accountLabel)
        case .pluginConfiguredGatewayUnreachable(let accountLabel, let gatewayDetail):
            return .pluginConfiguredGatewayUnreachable(
                accountLabel: accountLabel,
                gatewayDetail: gatewayDetail
            )
        case .missingCLI, .statusCommandFailed, .jsonParseFailed:
            return nil
        }
    }
}

private enum OpenClawWeixinRefreshOutcome: Equatable, Sendable {
    case missingCLI
    case statusCommandFailed(detail: String)
    case jsonParseFailed(detail: String)
    case success(payload: OpenClawWeixinStatusPayload, derivedState: OpenClawWeixinDerivedState)
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
    nonisolated static let statusArguments = ["status", "--json"]

    @Published private(set) var isRefreshing = false
    @Published private(set) var isInstalling = false
    @Published private(set) var isLaunchingBinding = false
    @Published private(set) var openClawBinaryPath: String?
    @Published private(set) var npxBinaryPath: String?
    @Published private(set) var statusPayload: OpenClawWeixinStatusPayload?
    @Published private(set) var cardState: OpenClawWeixinCardState = .refreshing(lastKnown: nil)
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
        switch cardState {
        case .refreshing(let lastKnown):
            if let lastKnown {
                return Self.statusLabel(for: lastKnown)
            }
            return "正在检查状态"
        case .missingCLI:
            return "未检测到 OpenClaw"
        case .statusCommandFailed:
            return "状态检查失败"
        case .jsonParseFailed:
            return "状态输出不可解析"
        case .pluginMissing:
            return "待安装微信能力"
        case .pluginPresentButNotConfigured:
            return "待绑定扫码"
        case .pluginConfiguredGatewayReachable:
            return "微信可用"
        case .pluginConfiguredGatewayUnreachable:
            return "微信已配置"
        }
    }

    var steadyStatusHeadline: String {
        switch cardState {
        case .refreshing:
            return "正在检查状态"
        case .missingCLI:
            return "未检测到 OpenClaw"
        case .statusCommandFailed:
            return "状态检查失败"
        case .jsonParseFailed:
            return "状态输出不可解析"
        case .pluginMissing:
            return "待安装微信能力"
        case .pluginPresentButNotConfigured:
            return "待绑定扫码"
        case .pluginConfiguredGatewayReachable:
            return "微信已可用"
        case .pluginConfiguredGatewayUnreachable:
            return "Gateway 当前不可达"
        }
    }

    var steadyStatusDetail: String {
        switch cardState {
        case .refreshing:
            return "正在读取 openclaw status --json。"
        case .missingCLI:
            return "请先安装 OpenClaw，再继续微信能力安装和绑定。"
        case .statusCommandFailed(let detail):
            return detail
        case .jsonParseFailed(let detail):
            return detail
        case .pluginMissing:
            return "当前 status 结果里没有发现 openclaw-weixin；可以直接开始安装微信能力。"
        case .pluginPresentButNotConfigured:
            return "当前 status 结果显示微信能力已存在，但还没有完成扫码绑定。"
        case .pluginConfiguredGatewayReachable(let accountLabel):
            if let accountLabel = accountLabel?.trimmedNonEmpty {
                return "已检测到 \(accountLabel)，并且 Gateway 当前可达。"
            }
            return "微信能力已配置，并且 Gateway 当前可达。"
        case .pluginConfiguredGatewayUnreachable(let accountLabel, let gatewayDetail):
            var segments: [String] = []
            if let accountLabel = accountLabel?.trimmedNonEmpty {
                segments.append("已检测到 \(accountLabel)。")
            } else {
                segments.append("微信能力已配置。")
            }

            if let gatewayDetail = gatewayDetail?.trimmedNonEmpty {
                segments.append("Gateway 状态：\(gatewayDetail)")
            } else {
                segments.append("Gateway 当前不可达。")
            }

            return segments.joined(separator: " ")
        }
    }

    var isBusy: Bool {
        isRefreshing || isInstalling || isLaunchingBinding
    }

    var isFlowActive: Bool {
        isInstalling || isLaunchingBinding
    }

    var shouldOfferInstall: Bool {
        guard openClawBinaryPath != nil else { return false }
        guard let derivedState = cardState.stableDerivedState else { return false }
        if case .pluginMissing = derivedState {
            return true
        }
        return false
    }

    var shouldOfferBind: Bool {
        guard openClawBinaryPath != nil else { return false }
        guard let derivedState = cardState.stableDerivedState else { return false }
        if case .pluginPresentButNotConfigured = derivedState {
            return true
        }
        return false
    }

    var usesWarningTone: Bool {
        switch cardState {
        case .missingCLI, .statusCommandFailed, .jsonParseFailed, .pluginConfiguredGatewayUnreachable:
            return true
        case .refreshing(let lastKnown):
            if case .pluginConfiguredGatewayUnreachable = lastKnown {
                return true
            }
            return false
        case .pluginMissing, .pluginPresentButNotConfigured, .pluginConfiguredGatewayReachable:
            return false
        }
    }

    var usesSuccessTone: Bool {
        switch cardState {
        case .pluginConfiguredGatewayReachable:
            return true
        case .refreshing(let lastKnown):
            if case .pluginConfiguredGatewayReachable = lastKnown {
                return true
            }
            return false
        case .missingCLI,
             .statusCommandFailed,
             .jsonParseFailed,
             .pluginMissing,
             .pluginPresentButNotConfigured,
             .pluginConfiguredGatewayUnreachable:
            return false
        }
    }

    func refreshWeChatStatus() {
        guard !isRefreshing else { return }

        let environment = OpenClawInstaller.installationEnvironment(base: environmentProvider())
        let commandRunner = runCommand
        let lastKnownState = cardState.stableDerivedState

        isRefreshing = true
        cardState = .refreshing(lastKnown: lastKnownState)

        Task.detached(priority: .utility) {
            let openClawBinaryPath = Self.detectBinaryPath(
                named: "openclaw",
                environment: environment,
                runCommand: commandRunner
            )
            let outcome = Self.queryWeixinStatus(
                openClawBinaryPath: openClawBinaryPath,
                environment: environment,
                runCommand: commandRunner
            )

            await MainActor.run {
                self.isRefreshing = false
                self.lastRefreshDate = Date()
                self.openClawBinaryPath = openClawBinaryPath.map(OpenClawInstaller.displayBinaryPath(_:))
                self.applyRefreshOutcome(outcome)
            }
        }
    }

    func installWeChatCapability() {
        guard !isInstalling else { return }

        let environment = OpenClawInstaller.installationEnvironment(base: environmentProvider())
        let commandRunner = runCommand
        guard let openClawBinaryPath = Self.detectBinaryPath(
            named: "openclaw",
            environment: environment,
            runCommand: commandRunner
        ) else {
            self.openClawBinaryPath = nil
            cardState = .missingCLI
            lastActionSummary = "未检测到 OpenClaw"
            lastActionDetail = "请先安装 OpenClaw，再安装微信能力。"
            return
        }

        self.openClawBinaryPath = OpenClawInstaller.displayBinaryPath(openClawBinaryPath)

        guard let npxBinaryPath = Self.detectBinaryPath(
            named: "npx",
            environment: environment,
            runCommand: commandRunner
        ) else {
            self.npxBinaryPath = nil
            lastActionSummary = "未检测到 npx"
            lastActionDetail = "当前环境里没有可用的 npx，无法执行官方微信安装器。"
            return
        }

        self.npxBinaryPath = OpenClawInstaller.displayBinaryPath(npxBinaryPath)
        runtimeSnapshot = WeChatRuntimeSnapshot()
        lastActionSummary = "正在后台安装微信能力..."
        lastActionDetail = "Clawbar 会在后台执行官方安装器，并把二维码显示在这里。"
        lastCommandOutput = "$ \(WeChatFlowKind.install.command)\n\n"
        isInstalling = true

        startBackgroundFlow(kind: .install, environment: environment)
    }

    func startWeChatBinding() {
        guard !isLaunchingBinding else { return }

        let environment = OpenClawInstaller.installationEnvironment(base: environmentProvider())
        let commandRunner = runCommand
        guard let openClawBinaryPath = Self.detectBinaryPath(
            named: "openclaw",
            environment: environment,
            runCommand: commandRunner
        ) else {
            self.openClawBinaryPath = nil
            cardState = .missingCLI
            lastActionSummary = "未检测到 OpenClaw"
            lastActionDetail = "请先安装 OpenClaw，再开始微信绑定。"
            return
        }

        self.openClawBinaryPath = OpenClawInstaller.displayBinaryPath(openClawBinaryPath)

        guard shouldOfferBind else {
            lastActionSummary = "当前无需重新扫码"
            lastActionDetail = "只有在微信能力已安装但尚未绑定时，才需要重新发起扫码。"
            return
        }

        isLaunchingBinding = true
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
            lastActionSummary = "微信连接成功"
            lastActionDetail = kind == .install
                ? "插件已安装并完成扫码，正在重启 OpenClaw Gateway。"
                : "扫码已确认，正在等待连接完成。"
        } else if runtimeSnapshot.restartingGateway {
            lastActionSummary = "正在重启 OpenClaw Gateway"
            lastActionDetail = "微信账号已经确认，Clawbar 正在等待 Gateway 重启完成。"
        } else if runtimeSnapshot.scanned {
            lastActionSummary = "已扫码，等待微信确认"
            lastActionDetail = "请在手机微信里确认登录。"
        } else if runtimeSnapshot.qrCodeURL != nil {
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

        lastActionSummary = kind == .install ? "微信安装流程失败" : "微信扫码流程失败"
        lastActionDetail = Self.extractFailureDetail(from: lastCommandOutput)
            ?? "后台命令异常退出，详情见最近输出。"
    }

    private func applyRefreshOutcome(_ outcome: OpenClawWeixinRefreshOutcome) {
        switch outcome {
        case .missingCLI:
            statusPayload = nil
            cardState = .missingCLI
            lastActionSummary = "未检测到 OpenClaw"
            lastActionDetail = "请先安装 OpenClaw，再继续微信能力安装和绑定。"
        case .statusCommandFailed(let detail):
            statusPayload = nil
            cardState = .statusCommandFailed(detail: detail)
            lastActionSummary = "状态检查失败"
            lastActionDetail = detail
        case .jsonParseFailed(let detail):
            statusPayload = nil
            cardState = .jsonParseFailed(detail: detail)
            lastActionSummary = "状态输出不可解析"
            lastActionDetail = detail
        case .success(let payload, let derivedState):
            statusPayload = payload
            cardState = Self.cardState(for: derivedState)
            switch derivedState {
            case .pluginMissing:
                lastActionSummary = "微信能力未安装"
                lastActionDetail = "当前 status 结果里没有发现 openclaw-weixin。"
            case .pluginPresentButNotConfigured:
                lastActionSummary = "等待微信绑定"
                lastActionDetail = "当前 status 结果显示微信能力已存在，但还没有完成扫码绑定。"
            case .pluginConfiguredGatewayReachable(let accountLabel):
                lastActionSummary = "微信已可用"
                if let accountLabel = accountLabel?.trimmedNonEmpty {
                    lastActionDetail = "已检测到 \(accountLabel)，并且 Gateway 当前可达。"
                } else {
                    lastActionDetail = "微信能力已配置，并且 Gateway 当前可达。"
                }
            case .pluginConfiguredGatewayUnreachable(let accountLabel, let gatewayDetail):
                lastActionSummary = "Gateway 当前不可达"
                if let accountLabel = accountLabel?.trimmedNonEmpty,
                   let gatewayDetail = gatewayDetail?.trimmedNonEmpty {
                    lastActionDetail = "已检测到 \(accountLabel)。Gateway 状态：\(gatewayDetail)"
                } else if let accountLabel = accountLabel?.trimmedNonEmpty {
                    lastActionDetail = "已检测到 \(accountLabel)，但 Gateway 当前不可达。"
                } else if let gatewayDetail = gatewayDetail?.trimmedNonEmpty {
                    lastActionDetail = "微信能力已配置。Gateway 状态：\(gatewayDetail)"
                } else {
                    lastActionDetail = "微信能力已配置，但 Gateway 当前不可达。"
                }
            }
        }
    }

    private nonisolated static func statusLabel(for state: OpenClawWeixinDerivedState) -> String {
        switch state {
        case .pluginMissing:
            return "待安装微信能力"
        case .pluginPresentButNotConfigured:
            return "待绑定扫码"
        case .pluginConfiguredGatewayReachable:
            return "微信可用"
        case .pluginConfiguredGatewayUnreachable:
            return "微信已配置"
        }
    }

    private nonisolated static func cardState(for state: OpenClawWeixinDerivedState) -> OpenClawWeixinCardState {
        switch state {
        case .pluginMissing:
            return .pluginMissing
        case .pluginPresentButNotConfigured:
            return .pluginPresentButNotConfigured
        case .pluginConfiguredGatewayReachable(let accountLabel):
            return .pluginConfiguredGatewayReachable(accountLabel: accountLabel)
        case .pluginConfiguredGatewayUnreachable(let accountLabel, let gatewayDetail):
            return .pluginConfiguredGatewayUnreachable(
                accountLabel: accountLabel,
                gatewayDetail: gatewayDetail
            )
        }
    }

    nonisolated static func detectBinaryPath(
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

    private nonisolated static func queryWeixinStatus(
        openClawBinaryPath: String?,
        environment: [String: String],
        runCommand: CommandRunner
    ) -> OpenClawWeixinRefreshOutcome {
        guard let openClawBinaryPath else {
            return .missingCLI
        }

        let result = runCommand(openClawBinaryPath, statusArguments, environment, 10)
        if result.timedOut {
            return .statusCommandFailed(detail: "openclaw status --json 未在 10 秒内完成。")
        }

        guard result.exitStatus == 0 else {
            let detail = extractFailureDetail(from: result.output)
                ?? "openclaw status --json 退出码 \(result.exitStatus)。"
            return .statusCommandFailed(detail: detail)
        }

        guard let payload = parseStatusPayload(from: result.output) else {
            let detail = makeJSONParseFailureDetail(from: result.output)
            return .jsonParseFailed(detail: detail)
        }

        let derivedState = deriveState(from: payload)
        return .success(payload: payload, derivedState: derivedState)
    }

    nonisolated static func parseStatusPayload(from output: String) -> OpenClawWeixinStatusPayload? {
        guard let jsonString = extractTrailingJSONObjectString(from: output),
              let payload = parseJSONObject(from: jsonString) else {
            return nil
        }

        let gateway = (payload["gateway"] as? [String: Any]).flatMap { gateway -> OpenClawWeixinStatusPayload.GatewaySnapshot? in
            OpenClawWeixinStatusPayload.GatewaySnapshot(
                reachable: gateway["reachable"] as? Bool,
                error: (gateway["error"] as? String)?.trimmedNonEmpty,
                url: (gateway["url"] as? String)?.trimmedNonEmpty
            )
        } ?? OpenClawWeixinStatusPayload.GatewaySnapshot(
            reachable: nil,
            error: nil,
            url: nil
        )

        let gatewayService = (payload["gatewayService"] as? [String: Any]).flatMap { gatewayService -> OpenClawWeixinStatusPayload.GatewayServiceSnapshot? in
            OpenClawWeixinStatusPayload.GatewayServiceSnapshot(
                installed: gatewayService["installed"] as? Bool,
                loaded: gatewayService["loaded"] as? Bool,
                runtimeShort: (gatewayService["runtimeShort"] as? String)?.trimmedNonEmpty
            )
        } ?? OpenClawWeixinStatusPayload.GatewayServiceSnapshot(
            installed: nil,
            loaded: nil,
            runtimeShort: nil
        )

        return OpenClawWeixinStatusPayload(
            runtimeVersion: (payload["runtimeVersion"] as? String)?.trimmedNonEmpty,
            channelSummary: payload["channelSummary"] as? [String] ?? [],
            gateway: gateway,
            gatewayService: gatewayService
        )
    }

    nonisolated static func deriveState(from payload: OpenClawWeixinStatusPayload) -> OpenClawWeixinDerivedState {
        guard let channelStatus = parseChannelSummary(payload.channelSummary) else {
            return .pluginMissing
        }

        if channelStatus.status == "configured" {
            if payload.gateway.reachable == true {
                return .pluginConfiguredGatewayReachable(accountLabel: channelStatus.accountLabel)
            }

            return .pluginConfiguredGatewayUnreachable(
                accountLabel: channelStatus.accountLabel,
                gatewayDetail: payload.gateway.error ?? payload.gatewayService.runtimeShort
            )
        }

        return .pluginPresentButNotConfigured
    }

    nonisolated static func extractTrailingJSONObjectString(from output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidateIndices = trimmed.indices.filter { trimmed[$0] == "{" }
        for index in candidateIndices.reversed() {
            let candidate = String(trimmed[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else { continue }
            if parseJSONObject(from: candidate) != nil {
                return candidate
            }
        }

        return nil
    }

    nonisolated static func parseChannelSummary(_ lines: [String]) -> (status: String, accountLabel: String?)? {
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.lowercased().hasPrefix("\(wechatChannelID):") else { continue }

            let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
            let status = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() : ""

            var accountLabel: String?
            var nextIndex = index + 1
            while nextIndex < lines.count {
                let nextLine = lines[nextIndex]
                let nextTrimmed = nextLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if nextTrimmed.isEmpty {
                    nextIndex += 1
                    continue
                }
                guard nextLine.first?.isWhitespace == true else { break }

                if accountLabel == nil {
                    let normalized = nextTrimmed.hasPrefix("-")
                        ? String(nextTrimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                        : nextTrimmed
                    accountLabel = normalized.trimmedNonEmpty
                }
                nextIndex += 1
            }

            return (status: status, accountLabel: accountLabel)
        }

        return nil
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

    private nonisolated static func makeJSONParseFailureDetail(from output: String) -> String {
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "openclaw status --json 没有返回任何可解析内容。"
        }

        return "未能从 openclaw status --json 的输出中提取有效 JSON。"
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

    nonisolated static func makeTerminalLaunchArguments(shellCommand: String) -> [String] {
        let escapedCommand = appleScriptStringLiteral(shellCommand)
        return [
            "-e", #"tell application "Terminal""#,
            "-e", "activate",
            "-e", "do script \(escapedCommand)",
            "-e", "end tell",
        ]
    }

    private nonisolated static func parseJSONObject(from output: String) -> [String: Any]? {
        guard let data = output.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private nonisolated static func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
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
        var timedOut = false

        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            timedOut = true
            process.terminate()
            process.waitUntilExit()
        }

        let output = sanitizeChannelOutput(outputPipe.fileHandleForReading.readDataToEndOfFile())
        return OpenClawChannelCommandResult(
            output: output,
            exitStatus: process.terminationStatus,
            timedOut: timedOut
        )
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
