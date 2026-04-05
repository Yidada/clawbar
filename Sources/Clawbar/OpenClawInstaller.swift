import Foundation

private enum OpenClawOperation {
    case install
    case uninstall

    var command: String {
        switch self {
        case .install:
            OpenClawInstaller.installCommand
        case .uninstall:
            OpenClawInstaller.uninstallCommand
        }
    }

    var actionName: String {
        switch self {
        case .install:
            "安装"
        case .uninstall:
            "卸载"
        }
    }

    var logURL: URL {
        switch self {
        case .install:
            OpenClawInstaller.defaultLogURL(filename: "openclaw-install.log")
        case .uninstall:
            OpenClawInstaller.defaultLogURL(filename: "openclaw-uninstall.log")
        }
    }

    var logTitle: String {
        switch self {
        case .install:
            "安装日志"
        case .uninstall:
            "卸载日志"
        }
    }

    var placeholderLogText: String {
        switch self {
        case .install:
            "等待安装输出..."
        case .uninstall:
            "等待卸载输出..."
        }
    }

    var idleStatusText: String {
        switch self {
        case .install:
            "准备安装 OpenClaw。"
        case .uninstall:
            "准备卸载 OpenClaw。"
        }
    }

    var idleDetailText: String {
        switch self {
        case .install:
            "点击按钮后会执行官方安装脚本，但不会进入 onboarding。"
        case .uninstall:
            "点击按钮后会执行官方非交互卸载，并移除全局 openclaw CLI。"
        }
    }

    var startingStatusText: String {
        switch self {
        case .install:
            "正在启动 OpenClaw 安装..."
        case .uninstall:
            "正在启动 OpenClaw 卸载..."
        }
    }

    var startingDetailText: String {
        switch self {
        case .install:
            "这会执行官方安装脚本，并把输出实时写入日志窗口。"
        case .uninstall:
            "这会执行官方非交互卸载命令，并把输出实时写入日志窗口。"
        }
    }

    var runningStatusText: String {
        switch self {
        case .install:
            "正在安装 OpenClaw..."
        case .uninstall:
            "正在卸载 OpenClaw..."
        }
    }

    var runningDetailText: String {
        switch self {
        case .install:
            "官方脚本没有稳定的百分比接口，所以这里显示实时输出和当前状态。"
        case .uninstall:
            "卸载过程会清理本机 OpenClaw 数据，并移除全局 CLI。"
        }
    }
}

struct OpenClawStatusSnapshot: Equatable, Sendable {
    let title: String
    let detail: String
    let excerpt: String?
    let binaryPath: String
    let healthSnapshot: OpenClawHealthSnapshot
}

struct OpenClawGatewayPreparationResult: Equatable, Sendable {
    let token: String?
    let statusSnapshot: OpenClawGatewayStatusSnapshot?
    let installCommandOutput: String?
    let failureDetail: String?

    var isReady: Bool {
        failureDetail == nil && !(statusSnapshot?.missingUnit ?? true)
    }
}

struct OpenClawInstallerOverride: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case missing
        case installed(OpenClawStatusSnapshot)
    }

    let state: State

    static func from(environment: [String: String]) -> Self? {
        guard let rawState = environment["CLAWBAR_TEST_OPENCLAW_STATE"]?.lowercased() else {
            return nil
        }

        switch rawState {
        case "missing":
            return Self(state: .missing)
        case "installed":
            let binaryPath = environment["CLAWBAR_TEST_OPENCLAW_BINARY_PATH"] ?? "/opt/homebrew/bin/openclaw"
            let snapshot = OpenClawStatusSnapshot(
                title: environment["CLAWBAR_TEST_OPENCLAW_TITLE"] ?? "OpenClaw 已安装",
                detail: environment["CLAWBAR_TEST_OPENCLAW_DETAIL"] ?? "Provider 已配置 · Gateway 可达 · Channel 已就绪",
                excerpt: environment["CLAWBAR_TEST_OPENCLAW_EXCERPT"] ?? "OpenClaw 2026.4.2",
                binaryPath: OpenClawInstaller.displayBinaryPath(binaryPath),
                healthSnapshot: .deterministicInstalled
            )
            return Self(state: .installed(snapshot))
        default:
            return nil
        }
    }
}

enum OpenClawInstallerError: LocalizedError {
    case commandFailed(operationName: String, status: Int32, logURL: URL)
    case launchFailed(operationName: String, underlyingError: Error)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(operationName, status, logURL):
            "OpenClaw \(operationName)失败，退出码 \(status)。日志位置：\(logURL.path)"
        case let .launchFailed(operationName, underlyingError):
            "无法启动 OpenClaw \(operationName)：\(underlyingError.localizedDescription)"
        }
    }
}

@MainActor
final class OpenClawInstaller: ObservableObject {
    struct StatusPayloadSnapshot: Equatable, Sendable {
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

    struct ChannelSummaryEntry: Equatable, Sendable {
        let label: String
        let status: String
        let accountLabel: String?
    }

    static let shared: OpenClawInstaller = {
        let environment = ProcessInfo.processInfo.environment
        let overrideState = OpenClawInstallerOverride.from(environment: environment)
        return OpenClawInstaller(overrideState: overrideState, autoStartTimer: overrideState == nil)
    }()
    nonisolated static let defaultRefreshInterval: TimeInterval = 30
    nonisolated static let installScriptURL = URL(string: "https://openclaw.ai/install.sh")!
    nonisolated static let installCommand = "curl -fsSL \(installScriptURL.absoluteString) | bash -s -- --no-onboard"
    nonisolated static let uninstallCommand = "openclaw uninstall --all --yes --non-interactive && npm rm -g openclaw"
    nonisolated static let detectCommand = "command -v openclaw"
    nonisolated static let gatewayInstallCommand = "openclaw gateway install --json"
    nonisolated static let statusArguments = ["status", "--json"]
    nonisolated static let providerStatusArguments = ["models", "status", "--json"]
    nonisolated static let gatewayStatusArguments = ["gateway", "status", "--json", "--no-probe"]

    @Published private(set) var isInstalling = false
    @Published private(set) var isUninstalling = false
    @Published private(set) var isInstalled = false
    @Published private(set) var isRefreshingStatus = false
    @Published private(set) var statusText = OpenClawOperation.install.idleStatusText
    @Published private(set) var detailText = OpenClawOperation.install.idleDetailText
    @Published private(set) var installedBinaryPath: String?
    @Published private(set) var statusExcerpt: String?
    @Published private(set) var healthSnapshot: OpenClawHealthSnapshot?
    @Published private(set) var logText = ""
    @Published private(set) var lastLogURL = OpenClawOperation.install.logURL
    @Published private(set) var lastStatusRefreshDate: Date?

    private var activeProcess: Process?
    private var outputHandle: FileHandle?
    private let refreshInterval: TimeInterval
    private let nowProvider: @Sendable () -> Date
    private let overrideState: OpenClawInstallerOverride?
    private var refreshTimer: Timer?
    private var lastOperation: OpenClawOperation = .install

    init(
        refreshInterval: TimeInterval = OpenClawInstaller.defaultRefreshInterval,
        nowProvider: @escaping @Sendable () -> Date = Date.init,
        overrideState: OpenClawInstallerOverride? = nil,
        autoStartTimer: Bool = true
    ) {
        self.refreshInterval = refreshInterval
        self.nowProvider = nowProvider
        self.overrideState = overrideState

        if autoStartTimer, overrideState == nil {
            startPeriodicRefresh()
        }
    }

    var isBusy: Bool {
        isInstalling || isUninstalling
    }

    var operationLogTitle: String {
        activeOperation.logTitle
    }

    var operationHintText: String {
        switch activeOperation {
        case .install:
            "说明：官方安装脚本没有提供稳定的百分比进度，所以这里展示实时输出和当前状态。"
        case .uninstall:
            "说明：卸载会先执行 OpenClaw 官方非交互卸载，再移除通过安装脚本落下的全局 CLI。"
        }
    }

    var emptyLogPlaceholder: String {
        activeOperation.placeholderLogText
    }

    func refreshInstallationStatus(force: Bool = false) {
        if let overrideState {
            applyOverrideState(overrideState)
            return
        }

        let now = nowProvider()
        guard Self.shouldRefreshStatus(
            force: force,
            isRefreshing: isRefreshingStatus,
            lastRefreshDate: lastStatusRefreshDate,
            now: now,
            refreshInterval: refreshInterval
        ) else {
            return
        }

        let environment = Self.installationEnvironment(base: ProcessInfo.processInfo.environment)
        isRefreshingStatus = true

        Task.detached(priority: .utility) {
            let path = Self.detectInstalledBinaryPath(environment: environment)
            let snapshot = path.map { binaryPath in
                Self.fetchStatusSnapshot(binaryPath: binaryPath, environment: environment)
            }

            await MainActor.run {
                self.isRefreshingStatus = false
                self.lastStatusRefreshDate = self.nowProvider()
                self.isInstalled = path != nil
                self.installedBinaryPath = path
                self.statusExcerpt = snapshot?.excerpt
                self.healthSnapshot = snapshot?.healthSnapshot

                guard !self.isBusy else { return }

                if let snapshot {
                    self.statusText = snapshot.title
                    self.detailText = snapshot.detail
                } else {
                    self.statusText = OpenClawOperation.install.idleStatusText
                    self.detailText = OpenClawOperation.install.idleDetailText
                }
            }
        }
    }

    private func applyOverrideState(_ overrideState: OpenClawInstallerOverride) {
        isRefreshingStatus = false
        lastStatusRefreshDate = nowProvider()

        switch overrideState.state {
        case .missing:
            isInstalled = false
            installedBinaryPath = nil
            statusExcerpt = nil
            healthSnapshot = nil
            if !isBusy {
                statusText = OpenClawOperation.install.idleStatusText
                detailText = OpenClawOperation.install.idleDetailText
            }
        case let .installed(snapshot):
            isInstalled = true
            installedBinaryPath = snapshot.binaryPath
            statusExcerpt = snapshot.excerpt
            healthSnapshot = snapshot.healthSnapshot
            if !isBusy {
                statusText = snapshot.title
                detailText = snapshot.detail
            }
        }
    }

    func startInstallIfNeeded() {
        if isBusy {
            statusText = "OpenClaw 正在处理中。"
            detailText = "请等待当前安装或卸载流程结束。"
            return
        }

        startOperation(.install)
    }

    func startUninstallIfNeeded() {
        if isBusy {
            statusText = "OpenClaw 正在处理中。"
            detailText = "请等待当前安装或卸载流程结束。"
            return
        }

        startOperation(.uninstall)
    }

    nonisolated static func defaultLogURL(filename: String) -> URL {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library")
        return libraryURL
            .appending(path: "Logs")
            .appending(path: "Clawbar")
            .appending(path: filename)
    }

    nonisolated static func installationEnvironment(base: [String: String]) -> [String: String] {
        var environment = base
        let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

        if let currentPath = environment["PATH"], !currentPath.isEmpty {
            if !currentPath.contains("/opt/homebrew/bin") {
                environment["PATH"] = "\(defaultPath):\(currentPath)"
            }
        } else {
            environment["PATH"] = defaultPath
        }

        return environment
    }

    nonisolated static func parseDetectedBinaryPath(_ output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    nonisolated static func displayBinaryPath(_ path: String) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(homePath + "/") {
            return "~" + path.dropFirst(homePath.count)
        }
        return path
    }

    nonisolated static func summarizeStatusLine(_ line: String, maxLength: Int = 88) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let normalized = trimmed.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        if normalized.hasPrefix("[plugins] plugins.allow is empty") {
            return "plugins.allow is empty; discovered non-bundled plugins."
        }

        if normalized.count <= maxLength {
            return normalized
        }

        let index = normalized.index(normalized.startIndex, offsetBy: maxLength - 1)
        return String(normalized[..<index]) + "…"
    }

    nonisolated static func shouldRefreshStatus(
        force: Bool,
        isRefreshing: Bool,
        lastRefreshDate: Date?,
        now: Date,
        refreshInterval: TimeInterval
    ) -> Bool {
        if isRefreshing {
            return false
        }

        if force || lastRefreshDate == nil {
            return true
        }

        guard let lastRefreshDate else {
            return true
        }

        return now.timeIntervalSince(lastRefreshDate) >= refreshInterval
    }

    nonisolated static func makeStatusSnapshot(
        binaryPath: String,
        statusResult: OpenClawChannelCommandResult,
        providerSnapshot: OpenClawProviderSnapshot?,
        gatewaySnapshot: OpenClawGatewayStatusSnapshot?
    ) -> OpenClawStatusSnapshot {
        let displayPath = displayBinaryPath(binaryPath)
        let statusPayload = parseStatusPayload(from: statusResult.output)
        let healthSnapshot = buildHealthSnapshot(
            statusPayload: statusPayload,
            providerSnapshot: providerSnapshot,
            gatewaySnapshot: gatewaySnapshot
        )

        let detail: String
        if statusResult.timedOut {
            detail = "openclaw status --json 未在 5 秒内完成；当前展示最近一次可推断的健康视图。"
        } else if statusPayload == nil {
            detail = "openclaw status --json 未返回可解析结果；当前展示本地可推断的健康视图。"
        } else {
            detail = healthSnapshot.overviewText
        }

        return OpenClawStatusSnapshot(
            title: "OpenClaw 已安装",
            detail: detail,
            excerpt: healthSnapshot.runtimeText,
            binaryPath: displayPath,
            healthSnapshot: healthSnapshot
        )
    }

    nonisolated static func parseStatusPayload(from output: String) -> StatusPayloadSnapshot? {
        let jsonString = ChannelCommandSupport.extractTrailingJSONObjectString(from: output) ?? output
        guard let payload = ChannelCommandSupport.parseJSONObject(from: jsonString) else {
            return nil
        }

        let gatewayPayload = payload["gateway"] as? [String: Any]
        let gatewayServicePayload = payload["gatewayService"] as? [String: Any]

        return StatusPayloadSnapshot(
            runtimeVersion: trimmedNonEmpty(payload["runtimeVersion"] as? String),
            channelSummary: payload["channelSummary"] as? [String] ?? [],
            gateway: StatusPayloadSnapshot.GatewaySnapshot(
                reachable: gatewayPayload?["reachable"] as? Bool,
                error: trimmedNonEmpty(gatewayPayload?["error"] as? String),
                url: trimmedNonEmpty(gatewayPayload?["url"] as? String)
            ),
            gatewayService: StatusPayloadSnapshot.GatewayServiceSnapshot(
                installed: gatewayServicePayload?["installed"] as? Bool,
                loaded: gatewayServicePayload?["loaded"] as? Bool,
                runtimeShort: trimmedNonEmpty(gatewayServicePayload?["runtimeShort"] as? String)
            )
        )
    }

    nonisolated static func parseChannelSummaryEntries(_ lines: [String]) -> [ChannelSummaryEntry] {
        var entries: [ChannelSummaryEntry] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else {
                index += 1
                continue
            }

            guard line.first?.isWhitespace != true,
                  let colonIndex = trimmedLine.firstIndex(of: ":") else {
                index += 1
                continue
            }

            let label = String(trimmedLine[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawStatus = String(trimmedLine[trimmedLine.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var accountLabel: String?
            var nextIndex = index + 1

            while nextIndex < lines.count {
                let nextLine = lines[nextIndex]
                let nextTrimmed = nextLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !nextTrimmed.isEmpty else {
                    nextIndex += 1
                    continue
                }
                guard nextLine.first?.isWhitespace == true else { break }

                if accountLabel == nil {
                    let normalized = nextTrimmed.hasPrefix("-")
                        ? String(nextTrimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                        : nextTrimmed
                    accountLabel = trimmedNonEmpty(normalized)
                }
                nextIndex += 1
            }

            entries.append(
                ChannelSummaryEntry(
                    label: label,
                    status: rawStatus.lowercased(),
                    accountLabel: accountLabel
                )
            )
            index = nextIndex
        }

        return entries
    }

    nonisolated static func buildHealthSnapshot(
        statusPayload: StatusPayloadSnapshot?,
        providerSnapshot: OpenClawProviderSnapshot?,
        gatewaySnapshot: OpenClawGatewayStatusSnapshot?
    ) -> OpenClawHealthSnapshot {
        OpenClawHealthSnapshot(
            runtimeVersion: statusPayload?.runtimeVersion,
            dimensions: [
                makeProviderHealthDimension(providerSnapshot),
                makeGatewayHealthDimension(statusPayload: statusPayload, gatewaySnapshot: gatewaySnapshot),
                makeChannelHealthDimension(statusPayload: statusPayload),
            ]
        )
    }

    private nonisolated static func makeProviderHealthDimension(
        _ providerSnapshot: OpenClawProviderSnapshot?
    ) -> OpenClawHealthDimensionSnapshot {
        guard let providerSnapshot else {
            return OpenClawHealthDimensionSnapshot(
                dimension: .provider,
                level: .unknown,
                statusLabel: "未知",
                summary: "未能读取 models status",
                detail: "Clawbar 尚未拿到默认模型和认证来源。"
            )
        }

        let providerID = resolveDefaultProviderID(from: providerSnapshot.defaultModelRef)
            ?? providerSnapshot.authStates.first(where: { $0.value.isConfigured })?.key
        let providerName = providerID.map(providerDisplayName(for:)) ?? "未设置默认 Provider"
        let selectedModel = providerSnapshot.defaultModelRef.flatMap(modelReferenceAfterProvider)
            ?? "未设置默认模型"
        let authState = providerID.flatMap { providerSnapshot.authStates[$0] }
        let isConfigured = authState?.isConfigured ?? false
        let statusLabel = isConfigured ? "已配置" : "待配置"
        let detail: String

        if let source = authState?.source {
            detail = "认证来源：\(source)"
        } else if let authDetail = authState?.detail, isConfigured {
            detail = "认证状态：\(authDetail)"
        } else if let providerID {
            detail = "\(providerDisplayName(for: providerID)) 当前还没有可用认证。"
        } else {
            detail = "当前还没有检测到默认模型或 Provider 认证。"
        }

        return OpenClawHealthDimensionSnapshot(
            dimension: .provider,
            level: isConfigured ? .healthy : .warning,
            statusLabel: statusLabel,
            summary: "\(providerName) / \(selectedModel)",
            detail: detail
        )
    }

    private nonisolated static func makeGatewayHealthDimension(
        statusPayload: StatusPayloadSnapshot?,
        gatewaySnapshot: OpenClawGatewayStatusSnapshot?
    ) -> OpenClawHealthDimensionSnapshot {
        guard let gatewaySnapshot else {
            return OpenClawHealthDimensionSnapshot(
                dimension: .gateway,
                level: .unknown,
                statusLabel: "未知",
                summary: "未能读取 Gateway 状态",
                detail: "Clawbar 尚未拿到 Gateway 服务与可达性信息。"
            )
        }

        let reachable = statusPayload?.gateway.reachable
        let statusLabel: String
        let level: OpenClawHealthLevel

        if gatewaySnapshot.missingUnit || gatewaySnapshot.state == .missing {
            statusLabel = "未安装"
            level = .critical
        } else if reachable == true {
            statusLabel = "可达"
            level = .healthy
        } else {
            switch gatewaySnapshot.state {
            case .running:
                statusLabel = "不可达"
                level = .warning
            case .stopped:
                statusLabel = "未启动"
                level = .warning
            case .transitioning:
                statusLabel = "切换中"
                level = .warning
            case .unknown:
                statusLabel = "未知"
                level = .unknown
            case .missing:
                statusLabel = "未安装"
                level = .critical
            }
        }

        let summary: String
        if reachable == true {
            summary = gatewaySnapshot.state == .running ? "后台服务运行中" : "Gateway 控制面可达"
        } else {
            switch gatewaySnapshot.state {
            case .running:
                summary = "后台服务运行中，但控制面不可达"
            case .stopped:
                summary = "后台服务未加载"
            case .transitioning:
                summary = "后台服务状态切换中"
            case .missing:
                summary = "Gateway 服务尚未安装"
            case .unknown:
                summary = "Gateway 状态暂不可判定"
            }
        }

        let detail = firstNonEmpty([
            gatewaySnapshot.detail,
            statusPayload?.gateway.error,
            statusPayload?.gatewayService.runtimeShort,
            statusPayload?.gateway.url,
        ]) ?? "未返回额外 Gateway 细节。"

        return OpenClawHealthDimensionSnapshot(
            dimension: .gateway,
            level: level,
            statusLabel: statusLabel,
            summary: summary,
            detail: detail
        )
    }

    private nonisolated static func makeChannelHealthDimension(
        statusPayload: StatusPayloadSnapshot?
    ) -> OpenClawHealthDimensionSnapshot {
        guard let statusPayload else {
            return OpenClawHealthDimensionSnapshot(
                dimension: .channel,
                level: .unknown,
                statusLabel: "未知",
                summary: "未能读取 Channel 摘要",
                detail: "Clawbar 尚未拿到 openclaw status --json 的 Channel 汇总。"
            )
        }

        let entries = parseChannelSummaryEntries(statusPayload.channelSummary)
        guard !entries.isEmpty else {
            return OpenClawHealthDimensionSnapshot(
                dimension: .channel,
                level: .warning,
                statusLabel: "未配置",
                summary: "未检测到已启用 Channel",
                detail: "当前 status 结果里还没有可展示的 Channel 摘要。"
            )
        }

        let readyEntries = entries.filter { isReadyChannelStatus($0.status) }
        let statusLabel = readyEntries.isEmpty ? "待配置" : "已就绪"
        let level: OpenClawHealthLevel = readyEntries.isEmpty ? .warning : .healthy
        let summary: String

        if entries.count == 1, let entry = entries.first {
            summary = "\(entry.label) / \(displayChannelStatus(entry.status))"
        } else {
            summary = "\(readyEntries.count)/\(entries.count) 个 Channel 已就绪"
        }

        let detail = entries.prefix(2).map { entry in
            if let accountLabel = entry.accountLabel {
                return "\(entry.label): \(displayChannelStatus(entry.status)) (\(accountLabel))"
            }
            return "\(entry.label): \(displayChannelStatus(entry.status))"
        }.joined(separator: " · ")

        return OpenClawHealthDimensionSnapshot(
            dimension: .channel,
            level: level,
            statusLabel: statusLabel,
            summary: summary,
            detail: trimmedNonEmpty(detail) ?? "当前 status 结果里还没有可展示的 Channel 摘要。"
        )
    }

    private nonisolated static func resolveDefaultProviderID(from modelRef: String?) -> String? {
        guard let modelRef = trimmedNonEmpty(modelRef) else { return nil }
        return trimmedNonEmpty(modelRef.split(separator: "/", maxSplits: 1).first.map(String.init))
    }

    private nonisolated static func modelReferenceAfterProvider(_ modelRef: String) -> String? {
        let components = modelRef.split(separator: "/", maxSplits: 1).map(String.init)
        guard components.count == 2 else { return trimmedNonEmpty(modelRef) }
        return trimmedNonEmpty(components[1])
    }

    private nonisolated static func providerDisplayName(for providerID: String) -> String {
        ProviderKind.allCases.first(where: { $0.rawValue == providerID })?.displayName
            ?? providerID.capitalized
    }

    private nonisolated static func isReadyChannelStatus(_ status: String) -> Bool {
        switch status {
        case "linked", "configured":
            true
        default:
            false
        }
    }

    private nonisolated static func displayChannelStatus(_ status: String) -> String {
        switch status {
        case "linked":
            "已连接"
        case "configured":
            "已配置"
        case "not linked":
            "未连接"
        case "not configured":
            "未配置"
        case "disabled":
            "已禁用"
        default:
            status
        }
    }

    private nonisolated static func firstNonEmpty(_ values: [String?]) -> String? {
        values.compactMap(trimmedNonEmpty).first
    }

    nonisolated static func prepareGatewayService(
        binaryPath: String,
        environment: [String: String],
        configureGateway: @escaping @Sendable () throws -> String,
        runGatewayCommand: @escaping @Sendable (String, [String: String], TimeInterval) -> OpenClawGatewayCommandResult = OpenClawInstaller.runGatewayCommand,
        fetchGatewayStatus: @escaping @Sendable (String, [String: String]) -> OpenClawGatewayStatusSnapshot = OpenClawInstaller.fetchGatewayStatusSnapshot
    ) -> OpenClawGatewayPreparationResult {
        let token: String
        do {
            token = try configureGateway()
        } catch {
            return OpenClawGatewayPreparationResult(
                token: nil,
                statusSnapshot: nil,
                installCommandOutput: nil,
                failureDetail: "Gateway token 初始化失败：\(error.localizedDescription)"
            )
        }

        let installResult = runGatewayCommand(gatewayInstallCommand, environment, 20)
        if let failureDetail = parseGatewayInstallFailure(installResult) {
            return OpenClawGatewayPreparationResult(
                token: token,
                statusSnapshot: nil,
                installCommandOutput: trimmedNonEmpty(installResult.output),
                failureDetail: failureDetail
            )
        }

        let gatewayStatusSnapshot = fetchGatewayStatus(binaryPath, environment)
        if gatewayStatusSnapshot.missingUnit {
            return OpenClawGatewayPreparationResult(
                token: token,
                statusSnapshot: gatewayStatusSnapshot,
                installCommandOutput: trimmedNonEmpty(installResult.output),
                failureDetail: "Gateway 服务安装命令已完成，但 launchd 中仍未注册 ai.openclaw.gateway。"
            )
        }

        return OpenClawGatewayPreparationResult(
            token: token,
            statusSnapshot: gatewayStatusSnapshot,
            installCommandOutput: trimmedNonEmpty(installResult.output),
            failureDetail: nil
        )
    }

    private nonisolated static func makeProcess(
        command: String,
        logURL: URL,
        environment: [String: String],
        outputHandler: @escaping @Sendable (String) -> Void,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) throws -> Process {
        try prepareLogFile(at: logURL)

        let outputPipe = Pipe()
        let outputHandle = try FileHandle(forWritingTo: logURL)
        let process = Process()

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            try? outputHandle.write(contentsOf: data)
            outputHandler(sanitizeOutput(data))
        }

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", command]
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.terminationHandler = { process in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            try? outputHandle.close()

            if process.terminationStatus == 0 {
                completion(.success(()))
            } else {
                completion(.failure(OpenClawInstallerError.commandFailed(operationName: operationName(for: command), status: process.terminationStatus, logURL: logURL)))
            }
        }

        return process
    }

    private nonisolated static func prepareLogFile(at logURL: URL) throws {
        let directoryURL = logURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: logURL.path) {
            try FileManager.default.removeItem(at: logURL)
        }

        FileManager.default.createFile(atPath: logURL.path, contents: Data())
    }

    private nonisolated static func detectInstalledBinaryPath(environment: [String: String]) -> String? {
        detectCommandPath(detectCommand, environment: environment)
    }

    private nonisolated static func detectCommandPath(_ command: String, environment: [String: String]) -> String? {
        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", command]
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return nil
            }

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            return parseDetectedBinaryPath(String(decoding: data, as: UTF8.self))
        } catch {
            return nil
        }
    }

    private nonisolated static func fetchStatusSnapshot(binaryPath: String, environment: [String: String]) -> OpenClawStatusSnapshot {
        let statusResult = ChannelCommandSupport.runCommand(
            binaryPath,
            statusArguments,
            environment,
            5
        )
        let providerSnapshot = fetchProviderStatusSnapshot(binaryPath: binaryPath, environment: environment)
        let gatewaySnapshot = fetchGatewayStatusSnapshot(binaryPath: binaryPath, environment: environment)

        return makeStatusSnapshot(
            binaryPath: binaryPath,
            statusResult: statusResult,
            providerSnapshot: providerSnapshot,
            gatewaySnapshot: gatewaySnapshot
        )
    }

    private nonisolated static func fetchProviderStatusSnapshot(
        binaryPath: String,
        environment: [String: String]
    ) -> OpenClawProviderSnapshot? {
        let result = ChannelCommandSupport.runCommand(
            binaryPath,
            providerStatusArguments,
            environment,
            8
        )
        guard !result.timedOut, result.exitStatus == 0 else { return nil }
        return OpenClawProviderManager.parseStatusSnapshot(result.output, binaryPath: binaryPath)
    }

    private nonisolated static func fetchGatewayStatusSnapshot(binaryPath: String, environment: [String: String]) -> OpenClawGatewayStatusSnapshot {
        let result = ChannelCommandSupport.runCommand(
            binaryPath,
            gatewayStatusArguments,
            environment,
            8
        )
        return OpenClawGatewayManager.makeStatusSnapshot(
            binaryPath: binaryPath,
            commandResult: OpenClawGatewayCommandResult(
                output: result.output,
                exitStatus: result.exitStatus,
                timedOut: result.timedOut
            )
        )
    }

    private nonisolated static func runGatewayCommand(
        _ command: String,
        _ environment: [String: String],
        _ timeout: TimeInterval
    ) -> OpenClawGatewayCommandResult {
        let result = runCommand(command, environment: environment, timeout: timeout)
        return OpenClawGatewayCommandResult(
            output: result.output,
            exitStatus: result.exitStatus,
            timedOut: result.timedOut
        )
    }

    private nonisolated static func parseGatewayInstallFailure(_ result: OpenClawGatewayCommandResult) -> String? {
        if result.timedOut {
            return "Gateway 服务安装命令超时。"
        }

        if let payload = parseJSONObject(from: result.output),
           let ok = payload["ok"] as? Bool,
           !ok {
            return trimmedNonEmpty(payload["error"] as? String)
                ?? trimmedNonEmpty(payload["message"] as? String)
                ?? nonEmptyOr(result.output, fallback: "Gateway 服务安装失败。")
        }

        if result.exitStatus != 0 {
            return nonEmptyOr(result.output, fallback: "Gateway 服务安装返回了非零退出码 \(result.exitStatus)。")
        }

        return nil
    }

    private nonisolated static func trimmedNonEmpty(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private nonisolated static func nonEmptyOr(_ text: String, fallback: String) -> String {
        trimmedNonEmpty(text) ?? fallback
    }

    private nonisolated static func parseJSONObject(from output: String) -> [String: Any]? {
        guard let data = output.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private nonisolated static func runCommand(
        _ command: String,
        environment: [String: String],
        timeout: TimeInterval
    ) -> (output: String, exitStatus: Int32, timedOut: Bool) {
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
            return ("", 1, false)
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
        return (sanitizeOutput(data), process.terminationStatus, timedOut)
    }

    private func appendLog(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        logText += chunk
    }

    private var activeOperation: OpenClawOperation {
        lastOperation
    }

    private func startOperation(_ operation: OpenClawOperation) {
        let logURL = operation.logURL
        let environment = Self.installationEnvironment(base: ProcessInfo.processInfo.environment)
        lastOperation = operation
        lastLogURL = logURL
        logText = "$ \(operation.command)\n\n"
        statusText = operation.startingStatusText
        detailText = operation.startingDetailText

        do {
            let process = try Self.makeProcess(
                command: operation.command,
                logURL: logURL,
                environment: environment,
                outputHandler: { [weak self] chunk in
                    Task { @MainActor in
                        guard let self else { return }
                        self.appendLog(chunk)
                    }
                },
                completion: { [weak self] result in
                    Task { @MainActor in
                        guard let self else { return }
                        self.finishOperation(operation, with: result, logURL: logURL)
                    }
                }
            )

            try process.run()
            activeProcess = process
            isInstalling = operation == .install
            isUninstalling = operation == .uninstall
            statusText = operation.runningStatusText
            detailText = operation.runningDetailText
        } catch {
            finishOperation(operation, with: .failure(OpenClawInstallerError.launchFailed(operationName: operation.actionName, underlyingError: error)), logURL: logURL)
        }
    }

    private func finishInstall(with result: Result<Void, Error>, logURL: URL) {
        activeProcess = nil
        outputHandle = nil
        lastLogURL = logURL

        switch result {
        case .success:
            let environment = Self.installationEnvironment(base: ProcessInfo.processInfo.environment)
            statusText = "正在完成 OpenClaw 安装..."
            detailText = "安装脚本已完成，正在准备 Gateway 配置与后台服务。"

            Task.detached(priority: .utility) {
                let openClawPath = Self.detectInstalledBinaryPath(environment: environment)

                guard let openClawPath else {
                    await MainActor.run {
                        self.isInstalling = false
                        self.statusText = "OpenClaw 安装完成。"
                        self.detailText = "安装脚本执行结束，但尚未检测到全局 openclaw 命令。"
                        self.logText += "\n[Clawbar] OpenClaw 安装完成，但未检测到全局 openclaw 命令。\n"
                        self.refreshInstallationStatus(force: true)
                    }
                    return
                }

                let gatewayPreparation = Self.prepareGatewayService(
                    binaryPath: openClawPath,
                    environment: environment,
                    configureGateway: {
                        try OpenClawGatewayCredentialStore.shared.ensureGatewayTokenConfigured()
                    }
                )

                await MainActor.run {
                    self.isInstalling = false
                    self.isInstalled = true
                    self.installedBinaryPath = openClawPath
                    self.lastStatusRefreshDate = self.nowProvider()

                    if let token = gatewayPreparation.token {
                        self.logText += "\n[Clawbar] 已为 Gateway 准备本地 token：\(token.prefix(12))...\n"
                    }

                    if let installOutput = gatewayPreparation.installCommandOutput {
                        self.logText += "\n$ \(Self.gatewayInstallCommand)\n\n\(installOutput)\n"
                    }

                    if gatewayPreparation.isReady {
                        self.statusText = "OpenClaw 安装完成。"
                        self.detailText = "Gateway 服务已安装；下一步可前往 Channels 页按需安装和绑定微信能力。"
                        self.logText += "\n[Clawbar] OpenClaw 安装完成；Gateway 服务已安装。\n"
                    } else {
                        self.statusText = "OpenClaw 安装完成，但 Gateway 服务未就绪。"
                        self.detailText = gatewayPreparation.failureDetail ?? "请前往 Gateway 页检查服务安装状态。"
                        self.logText += "\n[Clawbar] \(self.detailText)\n"
                    }

                    OpenClawGatewayManager.shared.refreshStatus()
                    self.refreshInstallationStatus(force: true)
                }
            }
        case let .failure(error):
            isInstalling = false
            statusText = "OpenClaw 安装失败。"
            detailText = error.localizedDescription
            logText += "\n[Clawbar] \(error.localizedDescription)\n"
        }
    }

    private func startPeriodicRefresh() {
        guard refreshTimer == nil else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshInstallationStatus(force: true)
            }
        }
        timer.tolerance = min(5, refreshInterval * 0.2)
        refreshTimer = timer
    }

    private func finishOperation(_ operation: OpenClawOperation, with result: Result<Void, Error>, logURL: URL) {
        switch operation {
        case .install:
            finishInstall(with: result, logURL: logURL)
        case .uninstall:
            finishUninstall(with: result, logURL: logURL)
        }
    }

    private func finishUninstall(with result: Result<Void, Error>, logURL: URL) {
        activeProcess = nil
        outputHandle = nil
        lastLogURL = logURL
        isInstalling = false
        isUninstalling = false

        switch result {
        case .success:
            isInstalled = false
            installedBinaryPath = nil
            statusExcerpt = nil
            healthSnapshot = nil
            lastStatusRefreshDate = nowProvider()
            statusText = "OpenClaw 已卸载。"
            detailText = "官方卸载流程和全局 CLI 移除已完成。"
            logText += "\n[Clawbar] OpenClaw 卸载完成。\n"
        case let .failure(error):
            statusText = "OpenClaw 卸载失败。"
            detailText = error.localizedDescription
            logText += "\n[Clawbar] \(error.localizedDescription)\n"
            refreshInstallationStatus(force: true)
        }
    }

    private nonisolated static func operationName(for command: String) -> String {
        if command == uninstallCommand {
            return OpenClawOperation.uninstall.actionName
        }
        return OpenClawOperation.install.actionName
    }
}

private func sanitizeOutput(_ data: Data) -> String {
    let raw = String(decoding: data, as: UTF8.self)
    let pattern = #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#

    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return raw
    }

    let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
    return regex.stringByReplacingMatches(in: raw, options: [], range: range, withTemplate: "")
}
