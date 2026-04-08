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

enum FeishuTenantBrand: String, CaseIterable, Codable, Equatable, Sendable {
    case feishu
    case lark

    var registrationBaseURL: URL {
        switch self {
        case .feishu:
            return URL(string: "https://accounts.feishu.cn")!
        case .lark:
            return URL(string: "https://accounts.larksuite.com")!
        }
    }

    var configValue: String {
        rawValue
    }
}

enum FeishuSetupMode: String, CaseIterable, Identifiable, Equatable, Sendable {
    case reuseConfiguredBot
    case useProvidedCredentials
    case createOrConfigureNewBot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reuseConfiguredBot:
            return "继续使用当前已配置机器人"
        case .useProvidedCredentials:
            return "手动输入 App ID / Secret"
        case .createOrConfigureNewBot:
            return "扫码创建/配置新机器人"
        }
    }

    var detail: String {
        switch self {
        case .reuseConfiguredBot:
            return "复用 OpenClaw 当前配置里的 Feishu 机器人。"
        case .useProvidedCredentials:
            return "直接输入已有机器人的 App ID 和 App Secret。"
        case .createOrConfigureNewBot:
            return "按飞书官方流程扫码创建并配置 Personal Agent。"
        }
    }
}

enum FeishuOnboardingState: String, Equatable, Sendable {
    case idle
    case selectingMode
    case waitingForScan
    case pollingRegistration
    case installingPlugin
    case enablingChannel
    case diagnosing
    case ready
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

enum FeishuPermissionMode: String, CaseIterable, Identifiable, Equatable, Sendable {
    case onlyMe
    case selected
    case open

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onlyMe:
            return "仅自己"
        case .selected:
            return "指定 UID"
        case .open:
            return "全开放"
        }
    }
}

struct FeishuAdvancedPolicySnapshot: Equatable, Sendable {
    let dmMode: FeishuPermissionMode
    let dmUIDs: [String]
    let groupMode: FeishuPermissionMode
    let groupUIDs: [String]
    let ownerOpenID: String?

    static let `default` = FeishuAdvancedPolicySnapshot(
        dmMode: .open,
        dmUIDs: [],
        groupMode: .open,
        groupUIDs: [],
        ownerOpenID: nil
    )
}

struct FeishuAdvancedPolicyDraft: Equatable, Sendable {
    var dmMode: FeishuPermissionMode
    var dmUIDs: [String]
    var groupMode: FeishuPermissionMode
    var groupUIDs: [String]
    var ownerOpenID: String?
}

struct FeishuChannelStatusSnapshot: Equatable, Sendable {
    let stage: FeishuChannelStage
    let onboardingState: FeishuOnboardingState
    let pluginInstalled: Bool
    let channelEnabled: Bool
    let channelBound: Bool
    let gatewayReachable: Bool
    let doctorHealthy: Bool?
    let openClawBinaryPath: String?
    let npxBinaryPath: String?
    let openClawVersion: String?
    let pluginVersion: String?
    let reusableConfiguredBotAvailable: Bool
    let setupMode: FeishuSetupMode
    let qrCodeURL: String?
    let browserURL: String?
    let scannedOwnerOpenID: String?
    let tenantBrand: FeishuTenantBrand?
    let summary: String
    let detail: String
    let continueURL: String?
    let logSummary: String?

    static let idle = FeishuChannelStatusSnapshot(
        stage: .preflight,
        onboardingState: .idle,
        pluginInstalled: false,
        channelEnabled: false,
        channelBound: false,
        gatewayReachable: false,
        doctorHealthy: nil,
        openClawBinaryPath: nil,
        npxBinaryPath: nil,
        openClawVersion: nil,
        pluginVersion: nil,
        reusableConfiguredBotAvailable: false,
        setupMode: .createOrConfigureNewBot,
        qrCodeURL: nil,
        browserURL: nil,
        scannedOwnerOpenID: nil,
        tenantBrand: nil,
        summary: "等待检查 Feishu 状态",
        detail: "Clawbar 会读取官方插件安装状态、Feishu channel 配置和 Gateway 状态。",
        continueURL: nil,
        logSummary: nil
    )

    func updating(
        stage: FeishuChannelStage? = nil,
        onboardingState: FeishuOnboardingState? = nil,
        pluginInstalled: Bool? = nil,
        channelEnabled: Bool? = nil,
        channelBound: Bool? = nil,
        gatewayReachable: Bool? = nil,
        doctorHealthy: Bool?? = nil,
        openClawBinaryPath: String?? = nil,
        npxBinaryPath: String?? = nil,
        openClawVersion: String?? = nil,
        pluginVersion: String?? = nil,
        reusableConfiguredBotAvailable: Bool? = nil,
        setupMode: FeishuSetupMode? = nil,
        qrCodeURL: String?? = nil,
        browserURL: String?? = nil,
        scannedOwnerOpenID: String?? = nil,
        tenantBrand: FeishuTenantBrand?? = nil,
        summary: String? = nil,
        detail: String? = nil,
        continueURL: String?? = nil,
        logSummary: String?? = nil
    ) -> Self {
        Self(
            stage: stage ?? self.stage,
            onboardingState: onboardingState ?? self.onboardingState,
            pluginInstalled: pluginInstalled ?? self.pluginInstalled,
            channelEnabled: channelEnabled ?? self.channelEnabled,
            channelBound: channelBound ?? self.channelBound,
            gatewayReachable: gatewayReachable ?? self.gatewayReachable,
            doctorHealthy: doctorHealthy ?? self.doctorHealthy,
            openClawBinaryPath: openClawBinaryPath ?? self.openClawBinaryPath,
            npxBinaryPath: npxBinaryPath ?? self.npxBinaryPath,
            openClawVersion: openClawVersion ?? self.openClawVersion,
            pluginVersion: pluginVersion ?? self.pluginVersion,
            reusableConfiguredBotAvailable: reusableConfiguredBotAvailable ?? self.reusableConfiguredBotAvailable,
            setupMode: setupMode ?? self.setupMode,
            qrCodeURL: qrCodeURL ?? self.qrCodeURL,
            browserURL: browserURL ?? self.browserURL,
            scannedOwnerOpenID: scannedOwnerOpenID ?? self.scannedOwnerOpenID,
            tenantBrand: tenantBrand ?? self.tenantBrand,
            summary: summary ?? self.summary,
            detail: detail ?? self.detail,
            continueURL: continueURL ?? self.continueURL,
            logSummary: logSummary ?? self.logSummary
        )
    }
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

private struct FeishuOnboardingDefaultsContext: Equatable, Sendable {
    let ownerOpenID: String?
    let tenantBrand: FeishuTenantBrand?
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
    typealias SleepHandler = @Sendable (_ nanoseconds: UInt64) async throws -> Void

    fileprivate nonisolated static let minimumOpenClawVersion = FeishuVersion(string: "2026.2.26")!

    @Published private(set) var snapshot: FeishuChannelStatusSnapshot = .idle
    @Published private(set) var isRefreshing = false
    @Published private(set) var activeAction: FeishuChannelAction?
    @Published private(set) var lastCommandOutput = ""
    @Published private(set) var lastRefreshDate: Date?
    @Published private(set) var toggleIntent = false
    @Published private(set) var advancedPolicySnapshot: FeishuAdvancedPolicySnapshot = .default
    @Published private(set) var advancedPolicyBusy = false
    @Published private(set) var advancedPolicyError: String?

    private let environmentProvider: EnvironmentProvider
    private let runCommand: CommandRunner
    private let makeStreamingProcess: StreamingProcessFactory
    private let registrationClient: FeishuRegistrationClient
    private let sleep: SleepHandler

    private var activeProcess: Process?
    private var onboardingTask: Task<Void, Never>?
    private var pendingOnboardingDefaults: FeishuOnboardingDefaultsContext?

    init(
        environmentProvider: @escaping EnvironmentProvider = { ProcessInfo.processInfo.environment },
        runCommand: @escaping CommandRunner = ChannelCommandSupport.runCommand,
        makeStreamingProcess: @escaping StreamingProcessFactory = ChannelCommandSupport.makeStreamingProcess,
        registrationClient: FeishuRegistrationClient = .live,
        sleep: @escaping SleepHandler = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.environmentProvider = environmentProvider
        self.runCommand = runCommand
        self.makeStreamingProcess = makeStreamingProcess
        self.registrationClient = registrationClient
        self.sleep = sleep
    }

    var isBusy: Bool {
        isRefreshing || activeAction != nil || onboardingTask != nil || advancedPolicyBusy
    }

    var isEnabled: Bool {
        toggleIntent || snapshot.channelEnabled
    }

    var canToggleChannelEnabled: Bool {
        snapshot.pluginInstalled && snapshot.channelBound
    }

    var isOnboardingActive: Bool {
        switch snapshot.onboardingState {
        case .waitingForScan, .pollingRegistration, .installingPlugin, .enablingChannel:
            return true
        case .idle, .selectingMode, .diagnosing, .ready:
            return false
        }
    }

    var canStartEnableFlow: Bool {
        primaryAction == .enable && canToggleChannelEnabled
    }

    var canStartSetupFlow: Bool {
        if snapshot.setupMode == .reuseConfiguredBot {
            return snapshot.reusableConfiguredBotAvailable
        }
        return true
    }

    var bindingActionTitle: String {
        snapshot.channelBound ? "重新绑定" : "扫码配置/创建机器人"
    }

    var displaySummary: String {
        if let liveProgress = liveProgressStatus {
            return liveProgress.summary
        }
        return snapshot.summary
    }

    var displayDetail: String {
        if let liveProgress = liveProgressStatus {
            return liveProgress.detail
        }
        return snapshot.detail
    }

    var statusLabel: String {
        switch snapshot.stage {
        case .preflight:
            return "环境待检查"
        case .install:
            return "待安装"
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
        switch snapshot.stage {
        case .install:
            switch snapshot.setupMode {
            case .reuseConfiguredBot:
                return "继续使用当前已配置机器人"
            case .useProvidedCredentials:
                return "使用输入凭证继续"
            case .createOrConfigureNewBot:
                return "开始扫码创建/配置"
            }
        case .configure:
            if snapshot.browserURL != nil {
                return "在浏览器打开"
            }
            return "继续配置"
        case .verify:
            return snapshot.channelEnabled ? "重新验证" : "重新启用"
        case .diagnose:
            return "运行修复"
        case .ready:
            return "重新验证"
        case .preflight:
            return "重新检查"
        }
    }

    func selectSetupMode(_ mode: FeishuSetupMode) {
        snapshot = snapshot.updating(
            setupMode: Self.resolvedSetupMode(
                preferred: mode,
                reusableConfiguredBotAvailable: snapshot.reusableConfiguredBotAvailable
            )
        )
    }

    func refreshStatus() {
        guard !isRefreshing else { return }

        let environment = ChannelCommandSupport.commandEnvironment(base: environmentProvider())
        let runCommand = runCommand
        let currentSetupMode = snapshot.setupMode

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
                runCommand: runCommand,
                currentSetupMode: currentSetupMode
            )

            await MainActor.run {
                self.isRefreshing = false
                self.lastRefreshDate = Date()
                self.snapshot = snapshot
                if !self.isOnboardingActive && self.activeAction == nil {
                    self.toggleIntent = snapshot.channelEnabled
                }
            }
        }
    }

    func runPrimaryAction(existingAppCredentials: FeishuAppCredentials? = nil) {
        switch primaryAction {
        case .enable:
            if canToggleChannelEnabled {
                enable()
            } else {
                startSetup(using: existingAppCredentials)
            }
        case .disable:
            disable()
        case .retry, .refresh:
            if snapshot.stage == .configure,
               let browserURL = snapshot.browserURL,
               !browserURL.isEmpty {
                return
            }
            refreshStatus()
        case .diagnose:
            runDoctor()
        case .fix:
            runDoctorFix()
        }
    }

    func enable(using manualCredentials: FeishuAppCredentials? = nil) {
        guard activeAction == nil, onboardingTask == nil else { return }
        guard canToggleChannelEnabled else { return }
        toggleIntent = true
        setChannelEnabled(true, summary: "正在启用 Feishu Channel...")
    }

    func startSetup(using manualCredentials: FeishuAppCredentials? = nil) {
        guard activeAction == nil, onboardingTask == nil else { return }
        guard canStartSetupFlow else { return }

        switch snapshot.setupMode {
        case .reuseConfiguredBot:
            startInstallFlow(
                mode: .reuseConfiguredBot,
                credentials: nil,
                defaultsContext: nil
            )
        case .useProvidedCredentials:
            guard let manualCredentials, manualCredentials.isComplete else {
                return
            }
            startInstallFlow(
                mode: .useProvidedCredentials,
                credentials: manualCredentials,
                defaultsContext: nil
            )
        case .createOrConfigureNewBot:
            startRegistrationFlow()
        }
    }

    func startQRCodeBinding() {
        if onboardingTask != nil {
            onboardingTask?.cancel()
            onboardingTask = nil
        }
        if activeProcess != nil {
            activeProcess?.terminate()
            activeProcess = nil
        }
        activeAction = nil
        pendingOnboardingDefaults = nil
        snapshot = snapshot.updating(setupMode: .createOrConfigureNewBot)
        startRegistrationFlow()
    }

    func disable() {
        guard activeAction == nil, onboardingTask == nil else { return }
        toggleIntent = false
        setChannelEnabled(false, summary: "正在停用 Feishu Channel...")
    }

    func loadAdvancedPolicy() {
        guard !advancedPolicyBusy else { return }
        advancedPolicyBusy = true
        advancedPolicyError = nil

        let environment = ChannelCommandSupport.commandEnvironment(base: environmentProvider())
        let runCommand = runCommand
        let scannedOwnerOpenID = snapshot.scannedOwnerOpenID

        Task.detached(priority: .utility) {
            guard let openClawBinaryPath = ChannelCommandSupport.detectBinaryPath(
                named: "openclaw",
                environment: environment,
                runCommand: runCommand
            ) else {
                await MainActor.run {
                    self.advancedPolicyBusy = false
                    self.advancedPolicyError = "没有找到 openclaw CLI，无法读取高级设置。"
                }
                return
            }

            let dmPolicy = Self.readStringConfig(
                openClawBinaryPath: openClawBinaryPath,
                environment: environment,
                runCommand: runCommand,
                path: "channels.feishu.dmPolicy"
            ) ?? "open"
            let allowFrom = Self.readStringArrayConfig(
                openClawBinaryPath: openClawBinaryPath,
                environment: environment,
                runCommand: runCommand,
                path: "channels.feishu.allowFrom"
            )
            let groupPolicy = Self.readStringConfig(
                openClawBinaryPath: openClawBinaryPath,
                environment: environment,
                runCommand: runCommand,
                path: "channels.feishu.groupPolicy"
            ) ?? "open"
            let groups = Self.readJSONObjectConfig(
                openClawBinaryPath: openClawBinaryPath,
                environment: environment,
                runCommand: runCommand,
                path: "channels.feishu.groups"
            ) ?? [:]

            let wildcard = groups["*"] as? [String: Any]
            let groupAllowFrom = (wildcard?["allowFrom"] as? [Any])?.compactMap { $0 as? String } ?? []
            let resolved = Self.resolveAdvancedPolicySnapshot(
                dmPolicy: dmPolicy,
                allowFrom: allowFrom,
                groupPolicy: groupPolicy,
                groupAllowFrom: groupAllowFrom,
                ownerOpenID: scannedOwnerOpenID
            )

            await MainActor.run {
                self.advancedPolicyBusy = false
                self.advancedPolicySnapshot = resolved
            }
        }
    }

    func saveAdvancedPolicy(_ draft: FeishuAdvancedPolicyDraft) {
        guard !advancedPolicyBusy else { return }
        guard activeAction == nil, onboardingTask == nil else { return }

        let normalized = Self.normalizeAdvancedPolicyDraft(draft)
        if normalized.dmMode == .selected, normalized.dmUIDs.isEmpty {
            advancedPolicyError = "DM 选择“指定 UID”时不能为空。"
            return
        }
        if normalized.groupMode == .selected, normalized.groupUIDs.isEmpty {
            advancedPolicyError = "Group 选择“指定 UID”时不能为空。"
            return
        }
        if normalized.dmMode == .onlyMe || normalized.groupMode == .onlyMe {
            guard trimmedNonEmpty(normalized.ownerOpenID) != nil else {
                advancedPolicyError = "“仅自己”模式需要 owner Open ID。"
                return
            }
        }

        advancedPolicyBusy = true
        advancedPolicyError = nil
        let environment = ChannelCommandSupport.commandEnvironment(base: environmentProvider())
        let runCommand = runCommand

        Task.detached(priority: .userInitiated) {
            guard let openClawBinaryPath = ChannelCommandSupport.detectBinaryPath(
                named: "openclaw",
                environment: environment,
                runCommand: runCommand
            ) else {
                await MainActor.run {
                    self.advancedPolicyBusy = false
                    self.advancedPolicyError = "没有找到 openclaw CLI，无法保存高级设置。"
                }
                return
            }

            do {
                switch normalized.dmMode {
                case .open:
                    try Self.writeJSONStringConfig(
                        openClawBinaryPath: openClawBinaryPath,
                        environment: environment,
                        runCommand: runCommand,
                        path: "channels.feishu.dmPolicy",
                        value: "open",
                        log: { line in await MainActor.run { self.appendLogLine(line) } }
                    )
                    try Self.writeJSONConfig(
                        openClawBinaryPath: openClawBinaryPath,
                        environment: environment,
                        runCommand: runCommand,
                        path: "channels.feishu.allowFrom",
                        value: ["*"],
                        log: { line in await MainActor.run { self.appendLogLine(line) } }
                    )
                case .onlyMe:
                    let owner = trimmedNonEmpty(normalized.ownerOpenID) ?? ""
                    try Self.writeJSONStringConfig(
                        openClawBinaryPath: openClawBinaryPath,
                        environment: environment,
                        runCommand: runCommand,
                        path: "channels.feishu.dmPolicy",
                        value: "allowlist",
                        log: { line in await MainActor.run { self.appendLogLine(line) } }
                    )
                    try Self.writeJSONConfig(
                        openClawBinaryPath: openClawBinaryPath,
                        environment: environment,
                        runCommand: runCommand,
                        path: "channels.feishu.allowFrom",
                        value: [owner],
                        log: { line in await MainActor.run { self.appendLogLine(line) } }
                    )
                case .selected:
                    try Self.writeJSONStringConfig(
                        openClawBinaryPath: openClawBinaryPath,
                        environment: environment,
                        runCommand: runCommand,
                        path: "channels.feishu.dmPolicy",
                        value: "allowlist",
                        log: { line in await MainActor.run { self.appendLogLine(line) } }
                    )
                    try Self.writeJSONConfig(
                        openClawBinaryPath: openClawBinaryPath,
                        environment: environment,
                        runCommand: runCommand,
                        path: "channels.feishu.allowFrom",
                        value: normalized.dmUIDs,
                        log: { line in await MainActor.run { self.appendLogLine(line) } }
                    )
                }

                var groups = Self.readJSONObjectConfig(
                    openClawBinaryPath: openClawBinaryPath,
                    environment: environment,
                    runCommand: runCommand,
                    path: "channels.feishu.groups"
                ) ?? [:]
                var wildcard = groups["*"] as? [String: Any] ?? [:]
                wildcard["enabled"] = true
                switch normalized.groupMode {
                case .open:
                    wildcard.removeValue(forKey: "allowFrom")
                case .onlyMe:
                    let owner = trimmedNonEmpty(normalized.ownerOpenID) ?? ""
                    wildcard["allowFrom"] = [owner]
                case .selected:
                    wildcard["allowFrom"] = normalized.groupUIDs
                }
                groups["*"] = wildcard

                try Self.writeJSONStringConfig(
                    openClawBinaryPath: openClawBinaryPath,
                    environment: environment,
                    runCommand: runCommand,
                    path: "channels.feishu.groupPolicy",
                    value: "open",
                    log: { line in await MainActor.run { self.appendLogLine(line) } }
                )
                try Self.writeJSONConfig(
                    openClawBinaryPath: openClawBinaryPath,
                    environment: environment,
                    runCommand: runCommand,
                    path: "channels.feishu.groups",
                    value: groups,
                    log: { line in await MainActor.run { self.appendLogLine(line) } }
                )

                await MainActor.run {
                    self.advancedPolicyBusy = false
                    self.advancedPolicySnapshot = FeishuAdvancedPolicySnapshot(
                        dmMode: normalized.dmMode,
                        dmUIDs: normalized.dmUIDs,
                        groupMode: normalized.groupMode,
                        groupUIDs: normalized.groupUIDs,
                        ownerOpenID: normalized.ownerOpenID
                    )
                    self.refreshStatus()
                }
            } catch {
                await MainActor.run {
                    self.advancedPolicyBusy = false
                    self.advancedPolicyError = error.localizedDescription
                }
            }
        }
    }

    func runDoctor() {
        guard activeAction == nil, onboardingTask == nil else { return }
        runOneShotCommand(
            action: .diagnose,
            summary: "正在运行 Feishu 诊断...",
            detail: "Clawbar 正在调用官方 doctor 命令检查当前安装。",
            command: Self.doctorCommand(fix: false)
        )
    }

    func runDoctorFix() {
        guard activeAction == nil, onboardingTask == nil else { return }
        runOneShotCommand(
            action: .fix,
            summary: "正在修复 Feishu 插件配置...",
            detail: "Clawbar 正在调用官方 doctor --fix 自动修复常见问题。",
            command: Self.doctorCommand(fix: true)
        )
    }

    func cancelActiveSetupFlow() {
        onboardingTask?.cancel()
        onboardingTask = nil
        activeProcess?.terminate()
        activeProcess = nil
        pendingOnboardingDefaults = nil
        activeAction = nil
        toggleIntent = snapshot.channelEnabled
        snapshot = snapshot.updating(
            stage: snapshot.pluginInstalled ? (snapshot.channelEnabled ? .ready : .verify) : .install,
            onboardingState: snapshot.pluginInstalled ? (snapshot.channelEnabled ? .ready : .idle) : .selectingMode,
            qrCodeURL: nil,
            browserURL: nil,
            scannedOwnerOpenID: nil,
            tenantBrand: nil,
            summary: snapshot.pluginInstalled ? "已取消 Feishu 流程" : "已取消 Feishu 引导",
            detail: snapshot.pluginInstalled ? "当前插件状态未变；如需继续可重新发起操作。" : "当前没有继续中的安装；可以重新选择模式后继续。",
            continueURL: nil,
            logSummary: "用户取消了当前 Feishu 流程。"
        )
    }

    private func startRegistrationFlow() {
        guard onboardingTask == nil else { return }

        lastCommandOutput = "$ feishu registration init\n$ feishu registration begin\n\n"
        snapshot = snapshot.updating(
            stage: .configure,
            onboardingState: .waitingForScan,
            qrCodeURL: nil,
            browserURL: nil,
            scannedOwnerOpenID: nil,
            tenantBrand: .feishu,
            summary: "正在准备飞书扫码配置",
            detail: "Clawbar 正在向飞书官方注册接口申请当前设备的扫码会话。",
            continueURL: nil,
            logSummary: nil
        )

        let registrationClient = registrationClient
        let sleep = self.sleep

        onboardingTask = Task.detached(priority: .userInitiated) {
            do {
                _ = try await registrationClient.initialize()
                let beginResponse = try await registrationClient.begin(brand: .feishu)
                await MainActor.run {
                    self.appendLogLine(beginResponse.verificationURL)
                    self.snapshot = self.snapshot.updating(
                        stage: .configure,
                        onboardingState: .waitingForScan,
                        qrCodeURL: beginResponse.verificationURL,
                        browserURL: beginResponse.verificationURL,
                        summary: "请使用飞书扫码配置机器人",
                        detail: "二维码已提取到当前页面，无需查看 Terminal；扫码后 Clawbar 会继续轮询配置结果。",
                        continueURL: beginResponse.verificationURL
                    )
                }

                let expiry = Date().addingTimeInterval(TimeInterval(beginResponse.expiresIn ?? 600))
                var pollBrand: FeishuTenantBrand = .feishu
                var intervalSeconds = max(beginResponse.interval ?? 5, 1)

                while Date() < expiry {
                    try Task.checkCancellation()

                    await MainActor.run {
                        self.snapshot = self.snapshot.updating(
                            stage: .configure,
                            onboardingState: .pollingRegistration,
                            tenantBrand: pollBrand,
                            summary: "等待扫码完成并返回机器人配置",
                            detail: "如果已在手机中完成扫码或授权，Clawbar 会自动继续安装插件。"
                        )
                    }

                    let pollResponse = try await registrationClient.poll(
                        deviceCode: beginResponse.deviceCode,
                        brand: pollBrand
                    )

                    if let tenantBrand = pollResponse.userInfo?.tenantBrand,
                       tenantBrand != pollBrand {
                        pollBrand = tenantBrand
                        await MainActor.run {
                            self.appendLogLine("Detected tenant brand: \(tenantBrand.rawValue)")
                            self.snapshot = self.snapshot.updating(tenantBrand: tenantBrand)
                        }
                    }

                    if let clientID = trimmedNonEmpty(pollResponse.clientID),
                       let clientSecret = trimmedNonEmpty(pollResponse.clientSecret) {
                        let credentials = FeishuAppCredentials(appID: clientID, appSecret: clientSecret)
                        let defaultsContext = FeishuOnboardingDefaultsContext(
                            ownerOpenID: trimmedNonEmpty(pollResponse.userInfo?.openID),
                            tenantBrand: pollResponse.userInfo?.tenantBrand ?? pollBrand
                        )
                        await MainActor.run {
                            self.onboardingTask = nil
                            self.snapshot = self.snapshot.updating(
                                stage: .install,
                                onboardingState: .installingPlugin,
                                scannedOwnerOpenID: defaultsContext.ownerOpenID,
                                tenantBrand: defaultsContext.tenantBrand,
                                summary: "扫码成功，正在安装 Feishu 插件",
                                detail: "Clawbar 已拿到机器人凭证，接下来会调用官方 CLI 写入配置并安装插件。"
                            )
                            self.startInstallFlow(
                                mode: .createOrConfigureNewBot,
                                credentials: credentials,
                                defaultsContext: defaultsContext
                            )
                        }
                        return
                    }

                    if let error = trimmedNonEmpty(pollResponse.error) {
                        switch error {
                        case "authorization_pending":
                            break
                        case "slow_down":
                            intervalSeconds += 5
                            await MainActor.run {
                                self.appendLogLine("registration poll requested slow_down")
                                self.snapshot = self.snapshot.updating(
                                    detail: "飞书要求放慢轮询速度，Clawbar 会继续等待扫码结果。"
                                )
                            }
                        case "access_denied":
                            await MainActor.run {
                                self.onboardingTask = nil
                                self.toggleIntent = false
                                self.snapshot = self.snapshot.updating(
                                    stage: .diagnose,
                                    onboardingState: .diagnosing,
                                    summary: "用户取消了飞书扫码授权",
                                    detail: pollResponse.errorDescription ?? "飞书返回 access_denied，可重新扫码发起新会话。",
                                    logSummary: pollResponse.errorDescription ?? error
                                )
                            }
                            return
                        case "expired_token":
                            await MainActor.run {
                                self.onboardingTask = nil
                                self.toggleIntent = false
                                self.snapshot = self.snapshot.updating(
                                    stage: .diagnose,
                                    onboardingState: .diagnosing,
                                    summary: "飞书扫码会话已过期",
                                    detail: "请重新发起扫码；当前二维码已经失效。",
                                    logSummary: pollResponse.errorDescription ?? error
                                )
                            }
                            return
                        default:
                            await MainActor.run {
                                self.onboardingTask = nil
                                self.toggleIntent = false
                                self.snapshot = self.snapshot.updating(
                                    stage: .diagnose,
                                    onboardingState: .diagnosing,
                                    summary: "飞书扫码流程失败",
                                    detail: pollResponse.errorDescription ?? error,
                                    logSummary: pollResponse.errorDescription ?? error
                                )
                            }
                            return
                        }
                    }

                    try await sleep(UInt64(intervalSeconds) * 1_000_000_000)
                }

                await MainActor.run {
                    self.onboardingTask = nil
                    self.toggleIntent = false
                    self.snapshot = self.snapshot.updating(
                        stage: .diagnose,
                        onboardingState: .diagnosing,
                        summary: "飞书扫码会话超时",
                        detail: "在有效期内没有拿到机器人配置结果，请重新发起扫码。",
                        logSummary: "Feishu registration timed out."
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.onboardingTask = nil
                }
            } catch {
                await MainActor.run {
                    self.onboardingTask = nil
                    self.toggleIntent = false
                    self.snapshot = self.snapshot.updating(
                        stage: .diagnose,
                        onboardingState: .diagnosing,
                        summary: "无法完成飞书扫码引导",
                        detail: error.localizedDescription,
                        logSummary: error.localizedDescription
                    )
                }
            }
        }
    }

    private func startInstallFlow(
        mode: FeishuSetupMode,
        credentials: FeishuAppCredentials?,
        defaultsContext: FeishuOnboardingDefaultsContext?
    ) {
        guard activeAction == nil else { return }

        let environment = ChannelCommandSupport.commandEnvironment(base: environmentProvider())
        guard let npxBinaryPath = ChannelCommandSupport.detectBinaryPath(
            named: "npx",
            environment: environment,
            runCommand: runCommand
        ) else {
            snapshot = snapshot.updating(
                stage: .preflight,
                onboardingState: .idle,
                npxBinaryPath: .some(nil),
                summary: "未检测到 npx",
                detail: "Feishu 官方插件通过 npx 分发，请先确保当前环境可执行 npx。",
                logSummary: nil
            )
            toggleIntent = false
            return
        }

        let command = Self.installCommand(mode: mode, credentials: credentials)
        let logCommand = Self.installLogCommand(mode: mode, credentials: credentials)
        pendingOnboardingDefaults = defaultsContext
        activeAction = .enable
        lastCommandOutput = lastCommandOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !lastCommandOutput.isEmpty {
            lastCommandOutput += "\n\n"
        }
        lastCommandOutput += "$ \(logCommand)\n\n"

        snapshot = snapshot.updating(
            stage: .install,
            onboardingState: .installingPlugin,
            npxBinaryPath: .some(OpenClawInstaller.displayBinaryPath(npxBinaryPath)),
            summary: Self.installSummary(for: mode),
            detail: Self.installDetail(for: mode)
        )

        startStreamingCommand(
            command: command,
            environment: environment,
            activeAction: .enable
        )
    }

    private func setChannelEnabled(_ enabled: Bool, summary: String) {
        let environment = ChannelCommandSupport.commandEnvironment(base: environmentProvider())
        let runCommand = runCommand
        activeAction = enabled ? .enable : .disable
        if !lastCommandOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !lastCommandOutput.hasSuffix("\n") {
                lastCommandOutput += "\n"
            }
            lastCommandOutput += "\n"
        }
        lastCommandOutput += "$ openclaw config set channels.feishu.enabled \(enabled ? "true" : "false") --strict-json\n\n"
        snapshot = snapshot.updating(
            stage: .verify,
            onboardingState: enabled ? .enablingChannel : .idle,
            summary: summary,
            detail: enabled ? "Clawbar 正在写入 `channels.feishu.enabled=true` 并重启 Gateway。" : "Clawbar 正在停用当前 Feishu channel。"
        )

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
                    self.snapshot = self.snapshot.updating(
                        stage: .preflight,
                        onboardingState: .idle,
                        channelEnabled: false,
                        channelBound: false,
                        gatewayReachable: false,
                        openClawBinaryPath: .some(nil),
                        summary: "未检测到 OpenClaw",
                        detail: "请先安装 OpenClaw，再管理 Feishu Channel。",
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
                    self.snapshot = self.snapshot.updating(
                        stage: .diagnose,
                        onboardingState: .diagnosing,
                        doctorHealthy: .some(false),
                        summary: enabled ? "Feishu Channel 启用失败" : "Feishu Channel 停用失败",
                        detail: detail,
                        logSummary: .some(detail)
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
                if !self.lastCommandOutput.hasSuffix("\n") {
                    self.lastCommandOutput += "\n"
                }
                self.lastCommandOutput += "\n$ openclaw gateway restart --json\n\n"
                self.lastCommandOutput += restartResult.output
                self.snapshot = self.snapshot.updating(
                    stage: .verify,
                    onboardingState: enabled ? .enablingChannel : .idle,
                    channelEnabled: enabled,
                    openClawBinaryPath: .some(OpenClawInstaller.displayBinaryPath(openClawBinaryPath)),
                    summary: summary,
                    detail: "配置已写入，Clawbar 正在重新验证插件和 Gateway 状态。",
                    logSummary: .some(trimmedNonEmpty(restartResult.output))
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
        snapshot = snapshot.updating(
            stage: action == .fix ? .diagnose : snapshot.stage,
            onboardingState: .diagnosing,
            qrCodeURL: .some(nil),
            browserURL: .some(nil),
            summary: summary,
            detail: detail,
            continueURL: .some(nil),
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
                    self.snapshot = self.snapshot.updating(
                        stage: .diagnose,
                        onboardingState: .diagnosing,
                        doctorHealthy: .some(false),
                        summary: action == .fix ? "自动修复失败" : "诊断发现异常",
                        detail: failureDetail,
                        logSummary: .some(failureDetail)
                    )
                }
            }
        }
    }

    private func applyPostInstallDefaultsAndEnable(_ context: FeishuOnboardingDefaultsContext?) {
        let environment = ChannelCommandSupport.commandEnvironment(base: environmentProvider())
        let runCommand = runCommand

        activeAction = .enable
        snapshot = snapshot.updating(
            stage: .verify,
            onboardingState: .enablingChannel,
            summary: "正在补齐飞书默认权限配置",
            detail: "Clawbar 会把飞书默认群聊权限和 OpenClaw 工具权限写回配置，再继续启用 Channel。"
        )

        Task.detached(priority: .userInitiated) {
            guard let openClawBinaryPath = ChannelCommandSupport.detectBinaryPath(
                named: "openclaw",
                environment: environment,
                runCommand: runCommand
            ) else {
                await MainActor.run {
                    self.activeAction = nil
                    self.toggleIntent = false
                    self.snapshot = self.snapshot.updating(
                        stage: .diagnose,
                        onboardingState: .diagnosing,
                        summary: "无法补齐飞书默认配置",
                        detail: "没有找到 openclaw CLI，无法继续写入扫码得到的配置。",
                        logSummary: .some("openclaw CLI not found")
                    )
                }
                return
            }

            do {
                if context?.tenantBrand == .lark {
                    try Self.writeJSONStringConfig(
                        openClawBinaryPath: openClawBinaryPath,
                        environment: environment,
                        runCommand: runCommand,
                        path: "channels.feishu.domain",
                        value: context?.tenantBrand?.configValue,
                        log: { line in await MainActor.run { self.appendLogLine(line) } }
                    )
                }

                let dmAllowFrom = Self.mergeUniqueString(
                    "*",
                    into: Self.readStringArrayConfig(
                        openClawBinaryPath: openClawBinaryPath,
                        environment: environment,
                        runCommand: runCommand,
                        path: "channels.feishu.allowFrom"
                    )
                )

                if let ownerOpenID = trimmedNonEmpty(context?.ownerOpenID) {
                    try Self.writeJSONStringConfig(
                        openClawBinaryPath: openClawBinaryPath,
                        environment: environment,
                        runCommand: runCommand,
                        path: "channels.feishu.dmPolicy",
                        value: "open",
                        log: { line in await MainActor.run { self.appendLogLine(line) } }
                    )

                    let allowFrom = Self.mergeUniqueString(ownerOpenID, into: dmAllowFrom)
                    try Self.writeJSONConfig(
                        openClawBinaryPath: openClawBinaryPath,
                        environment: environment,
                        runCommand: runCommand,
                        path: "channels.feishu.allowFrom",
                        value: allowFrom,
                        log: { line in await MainActor.run { self.appendLogLine(line) } }
                    )
                } else {
                    try Self.writeJSONStringConfig(
                        openClawBinaryPath: openClawBinaryPath,
                        environment: environment,
                        runCommand: runCommand,
                        path: "channels.feishu.dmPolicy",
                        value: "open",
                        log: { line in await MainActor.run { self.appendLogLine(line) } }
                    )
                    try Self.writeJSONConfig(
                        openClawBinaryPath: openClawBinaryPath,
                        environment: environment,
                        runCommand: runCommand,
                        path: "channels.feishu.allowFrom",
                        value: dmAllowFrom,
                        log: { line in await MainActor.run { self.appendLogLine(line) } }
                    )
                }

                try Self.writeJSONStringConfig(
                    openClawBinaryPath: openClawBinaryPath,
                    environment: environment,
                    runCommand: runCommand,
                    path: "channels.feishu.groupPolicy",
                    value: "open",
                    log: { line in await MainActor.run { self.appendLogLine(line) } }
                )

                var groups = Self.readJSONObjectConfig(
                    openClawBinaryPath: openClawBinaryPath,
                    environment: environment,
                    runCommand: runCommand,
                    path: "channels.feishu.groups"
                ) ?? [:]
                var wildcard = groups["*"] as? [String: Any] ?? [:]
                wildcard["enabled"] = true
                wildcard["requireMention"] = false
                groups["*"] = wildcard

                try Self.writeJSONConfig(
                    openClawBinaryPath: openClawBinaryPath,
                    environment: environment,
                    runCommand: runCommand,
                    path: "channels.feishu.groups",
                    value: groups,
                    log: { line in await MainActor.run { self.appendLogLine(line) } }
                )

                try Self.writeJSONStringConfig(
                    openClawBinaryPath: openClawBinaryPath,
                    environment: environment,
                    runCommand: runCommand,
                    path: "tools.profile",
                    value: "full",
                    log: { line in await MainActor.run { self.appendLogLine(line) } }
                )

                try Self.writeJSONStringConfig(
                    openClawBinaryPath: openClawBinaryPath,
                    environment: environment,
                    runCommand: runCommand,
                    path: "tools.sessions.visibility",
                    value: "all",
                    log: { line in await MainActor.run { self.appendLogLine(line) } }
                )

                await MainActor.run {
                    self.appendLogLine("Next step: open the Feishu bot chat and send /feishu auth to complete full user authorization.")
                }

                await MainActor.run {
                    self.pendingOnboardingDefaults = nil
                    self.activeAction = nil
                    self.setChannelEnabled(true, summary: "Feishu 插件安装完成，正在启用 Channel...")
                }
            } catch {
                await MainActor.run {
                    self.pendingOnboardingDefaults = nil
                    self.activeAction = nil
                    self.toggleIntent = false
                    self.snapshot = self.snapshot.updating(
                        stage: .diagnose,
                        onboardingState: .diagnosing,
                        summary: "写入飞书默认配置失败",
                        detail: error.localizedDescription,
                        logSummary: .some(error.localizedDescription)
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
            self.pendingOnboardingDefaults = nil
            self.toggleIntent = false
            self.snapshot = self.snapshot.updating(
                stage: .diagnose,
                onboardingState: .diagnosing,
                doctorHealthy: .some(false),
                summary: "无法启动 Feishu 安装流程",
                detail: error.localizedDescription,
                logSummary: .some(error.localizedDescription)
            )
        }
    }

    private func handleStreamingOutput(_ chunk: String) {
        lastCommandOutput.append(chunk)
        if lastCommandOutput.count > 60_000 {
            lastCommandOutput.removeFirst(lastCommandOutput.count - 60_000)
        }

        let progress = Self.parseInstallProgress(from: lastCommandOutput)
        var nextSnapshot = snapshot.updating(
            logSummary: .some(Self.logSummary(from: lastCommandOutput))
        )

        if nextSnapshot.browserURL == nil,
           let continueURL = progress.continueURL {
            nextSnapshot = nextSnapshot.updating(
                browserURL: .some(continueURL),
                continueURL: .some(continueURL)
            )
        }

        if snapshot.setupMode != .createOrConfigureNewBot,
           snapshot.onboardingState == .installingPlugin,
           progress.stage == .configure,
           let continueURL = progress.continueURL {
            nextSnapshot = nextSnapshot.updating(
                stage: .configure,
                onboardingState: .pollingRegistration,
                browserURL: .some(continueURL),
                summary: progress.summary,
                detail: progress.detail,
                continueURL: .some(continueURL)
            )
        }

        snapshot = nextSnapshot
    }

    private func finishStreamingCommand(status: Int32, action: FeishuChannelAction) {
        activeProcess = nil
        activeAction = nil

        if status == 0 {
            if action == .enable {
                applyPostInstallDefaultsAndEnable(pendingOnboardingDefaults)
                return
            }

            refreshStatus()
            return
        }

        let detail = ChannelCommandSupport.extractFailureDetail(from: lastCommandOutput)
            ?? "官方安装器执行失败，详情见日志。"
        pendingOnboardingDefaults = nil
        if action == .enable {
            toggleIntent = false
        }
        snapshot = snapshot.updating(
            stage: .diagnose,
            onboardingState: .diagnosing,
            channelEnabled: false,
            doctorHealthy: .some(false),
            summary: "Feishu 安装或配置失败",
            detail: detail,
            logSummary: .some(detail)
        )
    }

    private func appendLogLine(_ text: String) {
        if !lastCommandOutput.hasSuffix("\n"), !lastCommandOutput.isEmpty {
            lastCommandOutput += "\n"
        }
        lastCommandOutput += text
        if !lastCommandOutput.hasSuffix("\n") {
            lastCommandOutput += "\n"
        }
    }

    private var liveProgressStatus: (summary: String, detail: String)? {
        guard !lastCommandOutput.isEmpty else { return nil }

        switch snapshot.onboardingState {
        case .waitingForScan, .pollingRegistration:
            return nil
        case .installingPlugin, .enablingChannel:
            return Self.parseLiveProgressStatus(from: lastCommandOutput)
        case .idle, .selectingMode, .diagnosing, .ready:
            guard isBusy else { return nil }
            return Self.parseLiveProgressStatus(from: lastCommandOutput)
        }
    }

    private nonisolated static func makeStatusSnapshot(
        openClawBinaryPath: String?,
        npxBinaryPath: String?,
        environment: [String: String],
        runCommand: CommandRunner,
        currentSetupMode: FeishuSetupMode
    ) -> FeishuChannelStatusSnapshot {
        let displayOpenClawPath = openClawBinaryPath.map(OpenClawInstaller.displayBinaryPath(_:))
        let displayNpxPath = npxBinaryPath.map(OpenClawInstaller.displayBinaryPath(_:))

        guard let openClawBinaryPath else {
            return FeishuChannelStatusSnapshot.idle.updating(
                stage: .preflight,
                onboardingState: .idle,
                openClawBinaryPath: .some(nil),
                npxBinaryPath: .some(displayNpxPath),
                reusableConfiguredBotAvailable: false,
                setupMode: resolvedSetupMode(
                    preferred: currentSetupMode,
                    reusableConfiguredBotAvailable: false
                ),
                summary: "未检测到 OpenClaw",
                detail: "Feishu 官方插件依赖本机 OpenClaw。请先完成 OpenClaw 安装，再回来启用飞书 Channel。"
            )
        }

        guard npxBinaryPath != nil else {
            return FeishuChannelStatusSnapshot.idle.updating(
                stage: .preflight,
                onboardingState: .idle,
                openClawBinaryPath: .some(displayOpenClawPath),
                npxBinaryPath: .some(nil),
                reusableConfiguredBotAvailable: false,
                setupMode: resolvedSetupMode(
                    preferred: currentSetupMode,
                    reusableConfiguredBotAvailable: false
                ),
                summary: "未检测到 npx",
                detail: "Feishu 官方插件通过 npx 分发。请先修复 Node.js / npx 环境。"
            )
        }

        let reusableConfiguredBotAvailable = hasReusableConfiguredBot(
            openClawBinaryPath: openClawBinaryPath,
            environment: environment,
            runCommand: runCommand
        )

        let infoResult = ChannelCommandSupport.runShellCommand(
            "npx -y @larksuite/openclaw-lark info",
            environment: environment,
            timeout: 12,
            runCommand: runCommand
        )
        let pluginInfo = parsePluginInfo(from: infoResult.output)
        let channelRuntimeSnapshot = OpenClawChannelsSnapshotSupport.fetchSnapshot(
            openClawBinaryPath: openClawBinaryPath,
            environment: environment,
            runCommand: runCommand,
            pluginIDs: ["openclaw-lark"]
        )
        let feishuChannel = channelRuntimeSnapshot.channel(id: "feishu")
        let pluginInspection = channelRuntimeSnapshot.pluginInspection(id: "openclaw-lark")
        let openClawVersion = pluginInfo?.openClawVersion
        let resolvedSetupMode = resolvedSetupMode(
            preferred: currentSetupMode,
            reusableConfiguredBotAvailable: reusableConfiguredBotAvailable
        )

        if let versionString = openClawVersion,
           let parsedVersion = FeishuVersion(string: versionString),
           parsedVersion < minimumOpenClawVersion {
            return FeishuChannelStatusSnapshot.idle.updating(
                stage: .preflight,
                onboardingState: .idle,
                openClawBinaryPath: .some(displayOpenClawPath),
                npxBinaryPath: .some(displayNpxPath),
                openClawVersion: .some(versionString),
                pluginVersion: .some(pluginInfo?.pluginVersion),
                reusableConfiguredBotAvailable: reusableConfiguredBotAvailable,
                setupMode: resolvedSetupMode,
                summary: "OpenClaw 版本过低",
                detail: "Feishu 官方插件要求 OpenClaw 至少为 2026.2.26；当前检测到 \(versionString)。"
            )
        }

        guard let pluginInfo else {
            return FeishuChannelStatusSnapshot.idle.updating(
                stage: .preflight,
                onboardingState: .idle,
                openClawBinaryPath: .some(displayOpenClawPath),
                npxBinaryPath: .some(displayNpxPath),
                reusableConfiguredBotAvailable: reusableConfiguredBotAvailable,
                setupMode: resolvedSetupMode,
                summary: "无法读取 Feishu 插件信息",
                detail: ChannelCommandSupport.extractFailureDetail(from: infoResult.output)
                    ?? "官方 info 命令没有返回可识别结果。",
                logSummary: .some(logSummary(from: infoResult.output))
            )
        }

        let pluginInstalled = feishuChannel != nil || pluginInspection?.isActive == true || pluginInfo.pluginInstalled
        let channelEnabled = readBooleanConfig(
            openClawBinaryPath: openClawBinaryPath,
            environment: environment,
            runCommand: runCommand,
            path: "channels.feishu.enabled"
        ) ?? (feishuChannel?.configured ?? false)
        let channelBound = (feishuChannel?.configured ?? false) || reusableConfiguredBotAvailable
        let gatewayReachable = feishuChannel?.running ?? false

        if !pluginInstalled {
            return FeishuChannelStatusSnapshot.idle.updating(
                stage: .install,
                onboardingState: .selectingMode,
                pluginInstalled: false,
                channelEnabled: false,
                channelBound: reusableConfiguredBotAvailable,
                gatewayReachable: false,
                openClawBinaryPath: .some(displayOpenClawPath),
                npxBinaryPath: .some(displayNpxPath),
                openClawVersion: .some(pluginInfo.openClawVersion),
                pluginVersion: .some(nil),
                reusableConfiguredBotAvailable: reusableConfiguredBotAvailable,
                setupMode: resolvedSetupMode,
                summary: reusableConfiguredBotAvailable
                    ? "Feishu 插件未安装，可直接复用当前机器人或重新扫码"
                    : "Feishu 插件未安装，请选择安装方式",
                detail: "Clawbar 会按官方流程引导你复用当前机器人、手动输入凭证，或扫码创建新机器人。",
                logSummary: .some(logSummary(from: infoResult.output))
            )
        }

        if !channelBound {
            return FeishuChannelStatusSnapshot.idle.updating(
                stage: .install,
                onboardingState: .idle,
                pluginInstalled: true,
                channelEnabled: channelEnabled,
                channelBound: false,
                gatewayReachable: gatewayReachable,
                openClawBinaryPath: .some(displayOpenClawPath),
                npxBinaryPath: .some(displayNpxPath),
                openClawVersion: .some(pluginInfo.openClawVersion),
                pluginVersion: .some(pluginInfo.pluginVersion),
                reusableConfiguredBotAvailable: reusableConfiguredBotAvailable,
                setupMode: resolvedSetupMode,
                summary: "Feishu 插件已安装，等待绑定机器人",
                detail: "请通过下方二维码绑定新飞书机器人，或复用已有机器人配置。顶部开关只负责启用/停用 channel。",
                logSummary: .some(logSummary(from: infoResult.output))
            )
        }

        if !channelEnabled {
            return FeishuChannelStatusSnapshot.idle.updating(
                stage: .verify,
                onboardingState: .idle,
                pluginInstalled: true,
                channelEnabled: false,
                channelBound: true,
                gatewayReachable: gatewayReachable,
                openClawBinaryPath: .some(displayOpenClawPath),
                npxBinaryPath: .some(displayNpxPath),
                openClawVersion: .some(pluginInfo.openClawVersion),
                pluginVersion: .some(pluginInfo.pluginVersion),
                reusableConfiguredBotAvailable: reusableConfiguredBotAvailable,
                setupMode: resolvedSetupMode,
                summary: "Feishu 已绑定，Channel 已停用",
                detail: "打开开关后，Clawbar 只会写入 `channels.feishu.enabled=true` 并重启 Gateway；如需更换机器人，请使用下方绑定流程。",
                logSummary: .some(logSummary(from: infoResult.output))
            )
        }

        if gatewayReachable {
            return FeishuChannelStatusSnapshot.idle.updating(
                stage: .ready,
                onboardingState: .ready,
                pluginInstalled: true,
                channelEnabled: true,
                channelBound: true,
                gatewayReachable: true,
                openClawBinaryPath: .some(displayOpenClawPath),
                npxBinaryPath: .some(displayNpxPath),
                openClawVersion: .some(pluginInfo.openClawVersion),
                pluginVersion: .some(pluginInfo.pluginVersion),
                reusableConfiguredBotAvailable: reusableConfiguredBotAvailable,
                setupMode: resolvedSetupMode,
                summary: "Feishu 已启用并可用",
                detail: "Feishu Channel 已在 runtime 中运行，Clawbar 也已写入 `dmPolicy=open`、`tools.profile=full` 与 `tools.sessions.visibility=all`。若要打开文档、日历、群消息等完整用户态能力，请回到飞书机器人对话里发送 `/feishu auth` 完成授权。",
                logSummary: .some(logSummary(from: infoResult.output))
            )
        }

        let doctorStatus = queryDoctorStatus(environment: environment, runCommand: runCommand)
        if doctorStatus.healthy == false {
            return FeishuChannelStatusSnapshot.idle.updating(
                stage: .diagnose,
                onboardingState: .diagnosing,
                pluginInstalled: true,
                channelEnabled: true,
                channelBound: true,
                gatewayReachable: false,
                doctorHealthy: .some(false),
                openClawBinaryPath: .some(displayOpenClawPath),
                npxBinaryPath: .some(displayNpxPath),
                openClawVersion: .some(pluginInfo.openClawVersion),
                pluginVersion: .some(pluginInfo.pluginVersion),
                reusableConfiguredBotAvailable: reusableConfiguredBotAvailable,
                setupMode: resolvedSetupMode,
                summary: "Feishu 插件需要诊断修复",
                detail: doctorStatus.detail,
                logSummary: .some(doctorStatus.detail)
            )
        }

        return FeishuChannelStatusSnapshot.idle.updating(
            stage: .verify,
            onboardingState: .idle,
            pluginInstalled: true,
            channelEnabled: true,
            channelBound: true,
            gatewayReachable: false,
            doctorHealthy: .some(true),
            openClawBinaryPath: .some(displayOpenClawPath),
            npxBinaryPath: .some(displayNpxPath),
            openClawVersion: .some(pluginInfo.openClawVersion),
            pluginVersion: .some(pluginInfo.pluginVersion),
            reusableConfiguredBotAvailable: reusableConfiguredBotAvailable,
            setupMode: resolvedSetupMode,
            summary: "Feishu 已配置，等待 runtime 恢复",
            detail: trimmedNonEmpty(feishuChannel?.lastError) ?? "Feishu Channel 已配置，但当前还没有 running runtime。",
            logSummary: .some(logSummary(from: infoResult.output))
        )
    }

    private nonisolated static func hasReusableConfiguredBot(
        openClawBinaryPath: String,
        environment: [String: String],
        runCommand: CommandRunner
    ) -> Bool {
        let appID = readStringConfig(
            openClawBinaryPath: openClawBinaryPath,
            environment: environment,
            runCommand: runCommand,
            path: "channels.feishu.appId"
        )
        let appSecret = readConfigValue(
            openClawBinaryPath: openClawBinaryPath,
            environment: environment,
            runCommand: runCommand,
            path: "channels.feishu.appSecret"
        )
        return trimmedNonEmpty(appID) != nil && appSecret != nil
    }

    private nonisolated static func installCommand(
        mode: FeishuSetupMode,
        credentials: FeishuAppCredentials?
    ) -> String {
        switch mode {
        case .reuseConfiguredBot:
            return "npx -y @larksuite/openclaw-lark install --use-existing"
        case .useProvidedCredentials, .createOrConfigureNewBot:
            if let cliValue = credentials?.cliValue {
                return "npx -y @larksuite/openclaw-lark install --app '\(cliValue)'"
            }
            return "npx -y @larksuite/openclaw-lark install"
        }
    }

    private nonisolated static func installLogCommand(
        mode: FeishuSetupMode,
        credentials: FeishuAppCredentials?
    ) -> String {
        switch mode {
        case .reuseConfiguredBot:
            return installCommand(mode: mode, credentials: nil)
        case .useProvidedCredentials, .createOrConfigureNewBot:
            if let appID = trimmedNonEmpty(credentials?.appID) {
                return "npx -y @larksuite/openclaw-lark install --app '\(appID):<redacted>'"
            }
            return installCommand(mode: mode, credentials: nil)
        }
    }

    private nonisolated static func installSummary(for mode: FeishuSetupMode) -> String {
        switch mode {
        case .reuseConfiguredBot:
            return "正在复用当前已配置机器人安装 Feishu 插件"
        case .useProvidedCredentials:
            return "正在使用输入凭证安装 Feishu 插件"
        case .createOrConfigureNewBot:
            return "已完成扫码，正在安装 Feishu 插件"
        }
    }

    private nonisolated static func installDetail(for mode: FeishuSetupMode) -> String {
        switch mode {
        case .reuseConfiguredBot:
            return "Clawbar 会直接调用官方 CLI 复用当前 OpenClaw 中已有的 Feishu 机器人配置。"
        case .useProvidedCredentials:
            return "Clawbar 会调用官方 CLI 写入并校验你输入的 App ID / App Secret。"
        case .createOrConfigureNewBot:
            return "二维码只负责获取新机器人的凭证；后续仍由官方 CLI 负责真正安装和写入配置。"
        }
    }

    private nonisolated static func doctorCommand(fix: Bool) -> String {
        fix ? "npx -y @larksuite/openclaw-lark doctor --fix" : "npx -y @larksuite/openclaw-lark doctor"
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
            || output.contains("authorization URL")
            || output.contains("Scan with Feishu to configure your bot") {
            return FeishuInstallProgress(
                stage: .configure,
                summary: "官方安装器要求继续完成浏览器配置",
                detail: "Clawbar 已从最近输出里发现一个继续配置的 URL，可作为扫码流程的兜底入口。",
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

    nonisolated static func parseLiveProgressStatus(from output: String) -> (summary: String, detail: String)? {
        guard trimmedNonEmpty(output) != nil else { return nil }

        let candidates: [([String], (summary: String, detail: String))] = [
            (
                [
                    "$ openclaw config set tools.sessions.visibility",
                    "$ openclaw config set tools.profile",
                    "$ openclaw config set channels.feishu.groups",
                    "$ openclaw config set channels.feishu.groupPolicy",
                    "$ openclaw config set channels.feishu.allowFrom",
                    "$ openclaw config set channels.feishu.dmPolicy",
                ],
                (
                    "正在补齐默认权限配置",
                    "Clawbar 正在把 Feishu 群聊默认权限和 OpenClaw 工具权限写回配置。"
                )
            ),
            (
                [
                    "$ openclaw gateway restart --json",
                    "Restarted LaunchAgent",
                    "Restart the gateway",
                    "Gateway service already loaded.",
                ],
                (
                    "正在重启 OpenClaw Gateway",
                    "日志显示 Gateway 正在重启并重新加载 Feishu 插件。"
                )
            ),
            (
                [
                    "Validating provided credentials for App ID",
                    "正在验证 App ID",
                ],
                (
                    "正在验证 Feishu 机器人凭证",
                    "官方安装器正在校验当前 App ID / App Secret。"
                )
            ),
            (
                [
                    "Installing plugin dependencies",
                    "Installing plugin from local package",
                    "Packing @larksuite/openclaw-lark",
                    "Installing new version",
                    "Extracting /",
                ],
                (
                    "正在安装 Feishu 官方插件",
                    "官方安装器正在写入并安装 Feishu 插件文件。"
                )
            ),
        ]

        let latest = candidates.compactMap { markers, status -> (String.Index, (summary: String, detail: String))? in
            let latestMarker = markers.compactMap { output.range(of: $0, options: .backwards)?.lowerBound }.max()
            guard let latestMarker else { return nil }
            return (latestMarker, status)
        }
        .max { lhs, rhs in lhs.0 < rhs.0 }

        return latest?.1
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
        guard let value = readConfigValue(
            openClawBinaryPath: openClawBinaryPath,
            environment: environment,
            runCommand: runCommand,
            path: path
        ) as? Bool else {
            return nil
        }
        return value
    }

    private nonisolated static func readStringConfig(
        openClawBinaryPath: String,
        environment: [String: String],
        runCommand: CommandRunner,
        path: String
    ) -> String? {
        readConfigValue(
            openClawBinaryPath: openClawBinaryPath,
            environment: environment,
            runCommand: runCommand,
            path: path
        ) as? String
    }

    private nonisolated static func readStringArrayConfig(
        openClawBinaryPath: String,
        environment: [String: String],
        runCommand: CommandRunner,
        path: String
    ) -> [String] {
        (readConfigValue(
            openClawBinaryPath: openClawBinaryPath,
            environment: environment,
            runCommand: runCommand,
            path: path
        ) as? [Any])?.compactMap { $0 as? String } ?? []
    }

    private nonisolated static func readJSONObjectConfig(
        openClawBinaryPath: String,
        environment: [String: String],
        runCommand: CommandRunner,
        path: String
    ) -> [String: Any]? {
        readConfigValue(
            openClawBinaryPath: openClawBinaryPath,
            environment: environment,
            runCommand: runCommand,
            path: path
        ) as? [String: Any]
    }

    private nonisolated static func readConfigValue(
        openClawBinaryPath: String,
        environment: [String: String],
        runCommand: CommandRunner,
        path: String
    ) -> Any? {
        let result = runCommand(
            openClawBinaryPath,
            ["config", "get", path, "--json"],
            environment,
            8
        )

        guard result.exitStatus == 0,
              let data = result.output.data(using: .utf8) else {
            return nil
        }

        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private nonisolated static func writeJSONStringConfig(
        openClawBinaryPath: String,
        environment: [String: String],
        runCommand: CommandRunner,
        path: String,
        value: String?,
        log: @escaping @Sendable (String) async -> Void
    ) throws {
        guard let value else { return }
        try writeJSONConfig(
            openClawBinaryPath: openClawBinaryPath,
            environment: environment,
            runCommand: runCommand,
            path: path,
            value: value,
            log: log
        )
    }

    private nonisolated static func writeJSONConfig(
        openClawBinaryPath: String,
        environment: [String: String],
        runCommand: CommandRunner,
        path: String,
        value: Any,
        log: @escaping @Sendable (String) async -> Void
    ) throws {
        let json = try jsonLiteral(value)
        Task {
            await log("$ openclaw config set \(path) \(json) --strict-json\n")
        }
        let result = runCommand(
            openClawBinaryPath,
            ["config", "set", path, json, "--strict-json"],
            environment,
            12
        )
        Task {
            await log(result.output)
        }
        if result.timedOut || result.exitStatus != 0 {
            throw NSError(
                domain: "OpenClawFeishuChannelManager",
                code: Int(result.exitStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: ChannelCommandSupport.extractFailureDetail(from: result.output)
                        ?? "写入 \(path) 失败。",
                ]
            )
        }
    }

    private nonisolated static func mergeUniqueString(_ value: String, into existing: [String]) -> [String] {
        var merged = existing.filter { trimmedNonEmpty($0) != nil }
        if !merged.contains(value) {
            merged.append(value)
        }
        return merged
    }

    private nonisolated static func normalizeAdvancedPolicyDraft(_ draft: FeishuAdvancedPolicyDraft) -> FeishuAdvancedPolicyDraft {
        FeishuAdvancedPolicyDraft(
            dmMode: draft.dmMode,
            dmUIDs: normalizeUIDs(draft.dmUIDs),
            groupMode: draft.groupMode,
            groupUIDs: normalizeUIDs(draft.groupUIDs),
            ownerOpenID: trimmedNonEmpty(draft.ownerOpenID)
        )
    }

    private nonisolated static func normalizeUIDs(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            guard let trimmed = trimmedNonEmpty(value), trimmed != "*" else { continue }
            if seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }
        return result
    }

    private nonisolated static func resolveAdvancedPolicySnapshot(
        dmPolicy: String,
        allowFrom: [String],
        groupPolicy: String,
        groupAllowFrom: [String],
        ownerOpenID: String?
    ) -> FeishuAdvancedPolicySnapshot {
        let owner = trimmedNonEmpty(ownerOpenID)
        let normalizedAllowFrom = normalizeUIDs(allowFrom)
        let normalizedGroupAllowFrom = normalizeUIDs(groupAllowFrom)

        let dmMode: FeishuPermissionMode
        let dmUIDs: [String]
        if dmPolicy == "open" || allowFrom.contains("*") {
            dmMode = .open
            dmUIDs = []
        } else if let owner,
                  normalizedAllowFrom.count == 1,
                  normalizedAllowFrom.first == owner {
            dmMode = .onlyMe
            dmUIDs = [owner]
        } else if normalizedAllowFrom.isEmpty {
            dmMode = .open
            dmUIDs = []
        } else {
            dmMode = .selected
            dmUIDs = normalizedAllowFrom
        }

        let groupMode: FeishuPermissionMode
        let groupUIDs: [String]
        if groupPolicy == "disabled" {
            groupMode = .selected
            groupUIDs = []
        } else if let owner,
                  normalizedGroupAllowFrom.count == 1,
                  normalizedGroupAllowFrom.first == owner {
            groupMode = .onlyMe
            groupUIDs = [owner]
        } else if normalizedGroupAllowFrom.isEmpty {
            groupMode = .open
            groupUIDs = []
        } else {
            groupMode = .selected
            groupUIDs = normalizedGroupAllowFrom
        }

        return FeishuAdvancedPolicySnapshot(
            dmMode: dmMode,
            dmUIDs: dmUIDs,
            groupMode: groupMode,
            groupUIDs: groupUIDs,
            ownerOpenID: owner
        )
    }

    private nonisolated static func jsonLiteral(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
        return String(decoding: data, as: UTF8.self)
    }

    private nonisolated static func resolvedSetupMode(
        preferred: FeishuSetupMode,
        reusableConfiguredBotAvailable: Bool
    ) -> FeishuSetupMode {
        if reusableConfiguredBotAvailable {
            switch preferred {
            case .useProvidedCredentials:
                return .useProvidedCredentials
            case .reuseConfiguredBot, .createOrConfigureNewBot:
                return .reuseConfiguredBot
            }
        }

        if preferred == .reuseConfiguredBot {
            return .createOrConfigureNewBot
        }

        return preferred
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
