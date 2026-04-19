import Foundation
#if canImport(AppKit)
import AppKit
#endif

struct HermesGatewayStatusSnapshot: Equatable, Sendable {
    let isInstalled: Bool
    let isLoaded: Bool
    let isRunning: Bool
    let pid: Int?
    let rawOutput: String

    static let unknown = HermesGatewayStatusSnapshot(
        isInstalled: false,
        isLoaded: false,
        isRunning: false,
        pid: nil,
        rawOutput: ""
    )
}

struct HermesGatewayActionFeedback: Equatable, Sendable {
    let summary: String
    let detail: String
    let isSuccess: Bool
}

private enum HermesGatewayAction {
    case install
    case uninstall
    case start
    case stop
    case restart

    var subcommand: String {
        switch self {
        case .install: "install"
        case .uninstall: "uninstall"
        case .start: "start"
        case .stop: "stop"
        case .restart: "restart"
        }
    }

    var displayName: String {
        switch self {
        case .install: "安装服务"
        case .uninstall: "卸载服务"
        case .start: "启动服务"
        case .stop: "停止服务"
        case .restart: "重启服务"
        }
    }
}

@MainActor
final class HermesGatewayManager: ObservableObject {
    static let shared = HermesGatewayManager()

    typealias EnvironmentProvider = @Sendable () -> [String: String]
    typealias CommandRunner = ChannelCommandSupport.CommandRunner
    typealias ConfigOpener = @MainActor @Sendable (URL) -> Bool

    nonisolated static let statusTimeout: TimeInterval = 10
    nonisolated static let actionTimeout: TimeInterval = 60

    @Published private(set) var statusSnapshot: HermesGatewayStatusSnapshot = .unknown
    @Published private(set) var lastFeedback: HermesGatewayActionFeedback?
    @Published private(set) var isRefreshingStatus = false
    @Published private(set) var isPerformingAction = false
    @Published private(set) var lastRefreshDate: Date?

    private let installer: HermesInstaller
    private let runCommand: CommandRunner
    private let environmentProvider: EnvironmentProvider
    private let configOpener: ConfigOpener
    private let nowProvider: @Sendable () -> Date

    var isBusy: Bool { isRefreshingStatus || isPerformingAction }

    init(
        installer: HermesInstaller = .shared,
        environmentProvider: @escaping EnvironmentProvider = { ProcessInfo.processInfo.environment },
        runCommand: @escaping CommandRunner = ChannelCommandSupport.runCommand,
        configOpener: @escaping ConfigOpener = HermesGatewayManager.defaultConfigOpener,
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.installer = installer
        self.environmentProvider = environmentProvider
        self.runCommand = runCommand
        self.configOpener = configOpener
        self.nowProvider = nowProvider
    }

    func refreshStatus() async {
        guard let binaryPath = installer.hermesBinaryPath else {
            statusSnapshot = .unknown
            return
        }
        if isRefreshingStatus { return }
        isRefreshingStatus = true
        defer { isRefreshingStatus = false }

        let env = ChannelCommandSupport.commandEnvironment(base: environmentProvider())
        let runner = runCommand
        let snapshot = await Task.detached(priority: .utility) { @Sendable in
            let result = runner(binaryPath, ["gateway", "status"], env, Self.statusTimeout)
            return Self.parseStatusOutput(result.output, exitStatus: result.exitStatus, timedOut: result.timedOut)
        }.value

        statusSnapshot = snapshot
        lastRefreshDate = nowProvider()
    }

    func install() async {
        await runAction(.install)
    }

    func uninstall() async {
        await runAction(.uninstall)
    }

    func start() async {
        await runAction(.start)
    }

    func stop() async {
        await runAction(.stop)
    }

    func restart() async {
        await runAction(.restart)
    }

    func openConfigFile() -> Bool {
        let url = installer.configFileURL()
        return configOpener(url)
    }

    func makeSetupTerminalCommand() -> String? {
        guard let binaryPath = installer.hermesBinaryPath else { return nil }
        return "\(Self.shellQuote(binaryPath)) gateway setup"
    }

    private func runAction(_ action: HermesGatewayAction) async {
        guard let binaryPath = installer.hermesBinaryPath else {
            lastFeedback = HermesGatewayActionFeedback(
                summary: "未检测到 hermes",
                detail: "请先安装 Hermes Agent。",
                isSuccess: false
            )
            return
        }
        guard !isPerformingAction else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }

        let env = ChannelCommandSupport.commandEnvironment(base: environmentProvider())
        let runner = runCommand
        let result = await Task.detached(priority: .utility) { @Sendable in
            runner(binaryPath, ["gateway", action.subcommand], env, Self.actionTimeout)
        }.value

        let outputExcerpt = Self.firstNonEmptyLine(result.output)

        if result.timedOut {
            lastFeedback = HermesGatewayActionFeedback(
                summary: "\(action.displayName) 超时",
                detail: "hermes gateway \(action.subcommand) 在 \(Int(Self.actionTimeout)) 秒内未返回。",
                isSuccess: false
            )
        } else if result.exitStatus != 0 {
            lastFeedback = HermesGatewayActionFeedback(
                summary: "\(action.displayName) 失败（退出码 \(result.exitStatus)）",
                detail: outputExcerpt ?? "命令输出为空。",
                isSuccess: false
            )
        } else {
            lastFeedback = HermesGatewayActionFeedback(
                summary: "\(action.displayName) 已执行",
                detail: outputExcerpt ?? "已发出 hermes gateway \(action.subcommand) 指令。",
                isSuccess: true
            )
        }

        await refreshStatus()
    }

    nonisolated static func parseStatusOutput(
        _ output: String,
        exitStatus: Int32,
        timedOut: Bool
    ) -> HermesGatewayStatusSnapshot {
        if timedOut || exitStatus != 0 {
            // Even on non-zero exit hermes may print "service not installed".
            // Still attempt to parse for keywords so we can render a useful message.
        }
        let lower = output.lowercased()
        let isInstalled: Bool
        if lower.contains("not installed") || lower.contains("未安装") {
            isInstalled = false
        } else {
            isInstalled = lower.contains("installed") || lower.contains("已安装")
        }

        let isLoaded = lower.contains("loaded") && !lower.contains("not loaded")
        let isRunning = (lower.contains("running") && !lower.contains("not running"))
            || lower.contains("active (running)")
            || lower.contains("status: running")

        let pid = Self.extractPID(from: output)

        return HermesGatewayStatusSnapshot(
            isInstalled: isInstalled,
            isLoaded: isLoaded,
            isRunning: isRunning,
            pid: pid,
            rawOutput: output
        )
    }

    nonisolated static func extractPID(from output: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"(?:pid|PID)[\s:=]+(\d+)"#) else {
            return nil
        }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return Int(output[valueRange])
    }

    nonisolated static func firstNonEmptyLine(_ output: String) -> String? {
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    nonisolated static func shellQuote(_ value: String) -> String {
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    @MainActor
    static func defaultConfigOpener(_ url: URL) -> Bool {
        #if canImport(AppKit)
        return NSWorkspace.shared.open(url)
        #else
        return false
        #endif
    }
}
