import Foundation

enum GatewayControlAction: String, Sendable {
    case start
    case restart
    case pause

    var commandName: String {
        switch self {
        case .start:
            "start"
        case .restart:
            "restart"
        case .pause:
            "stop"
        }
    }

    var displayName: String {
        switch self {
        case .start:
            "启动"
        case .restart:
            "重启"
        case .pause:
            "暂停"
        }
    }
}

enum GatewayRuntimeState: String, Equatable, Sendable {
    case missing
    case stopped
    case running
    case transitioning
    case unknown

    var title: String {
        switch self {
        case .missing:
            "Gateway 未安装"
        case .stopped:
            "Gateway 已暂停"
        case .running:
            "Gateway 运行中"
        case .transitioning:
            "Gateway 状态切换中"
        case .unknown:
            "Gateway 状态未知"
        }
    }
}

struct OpenClawGatewayStatusSnapshot: Equatable, Sendable {
    let state: GatewayRuntimeState
    let detail: String
    let binaryPath: String?
    let runtimeStatus: String?
    let serviceInstalled: Bool
    let serviceLoaded: Bool
    let serviceLabel: String?
    let pid: Int?
    let missingUnit: Bool

    var title: String { state.title }

    static let missing = OpenClawGatewayStatusSnapshot(
        state: .missing,
        detail: "请先安装 OpenClaw，然后再管理 Gateway 服务。",
        binaryPath: nil,
        runtimeStatus: nil,
        serviceInstalled: false,
        serviceLoaded: false,
        serviceLabel: nil,
        pid: nil,
        missingUnit: true
    )
}

struct OpenClawGatewayActionFeedback: Equatable, Sendable {
    let isSuccess: Bool
    let summary: String
    let detail: String?
}

struct OpenClawGatewayCommandResult: Equatable, Sendable {
    let output: String
    let exitStatus: Int32
    let timedOut: Bool
}

@MainActor
final class OpenClawGatewayManager: ObservableObject {
    static let shared = OpenClawGatewayManager()

    nonisolated static let statusCommand = "openclaw gateway status --json --no-probe"

    @Published private(set) var snapshot: OpenClawGatewayStatusSnapshot = .missing
    @Published private(set) var isRefreshingStatus = false
    @Published private(set) var isPerformingAction = false
    @Published private(set) var lastActionSummary = "等待操作"
    @Published private(set) var lastActionDetail = "点击按钮后会直接调用 openclaw gateway 的后台服务命令。"
    @Published private(set) var lastStatusRefreshDate: Date?

    func refreshStatus() {
        guard !isRefreshingStatus else { return }

        let environment = Self.commandEnvironment(base: ProcessInfo.processInfo.environment)
        isRefreshingStatus = true

        Task.detached(priority: .utility) {
            let binaryPath = Self.detectInstalledBinaryPath(environment: environment)
            let nextSnapshot: OpenClawGatewayStatusSnapshot

            if let binaryPath {
                let result = Self.runCommand(Self.statusCommand, environment: environment, timeout: 8)
                nextSnapshot = Self.makeStatusSnapshot(
                    binaryPath: binaryPath,
                    commandResult: result
                )
            } else {
                nextSnapshot = .missing
            }

            await MainActor.run {
                self.snapshot = nextSnapshot
                self.isRefreshingStatus = false
                self.lastStatusRefreshDate = Date()
            }
        }
    }

    func perform(_ action: GatewayControlAction) {
        guard !isPerformingAction else { return }

        let environment = Self.commandEnvironment(base: ProcessInfo.processInfo.environment)
        guard Self.detectInstalledBinaryPath(environment: environment) != nil else {
            snapshot = .missing
            lastActionSummary = "未检测到 OpenClaw"
            lastActionDetail = "请先完成安装，再执行 Gateway 管理动作。"
            return
        }

        let command = "openclaw gateway \(action.commandName) --json"
        isPerformingAction = true
        lastActionSummary = "正在\(action.displayName) Gateway..."
        lastActionDetail = "等待 openclaw gateway \(action.commandName) 返回。"

        Task.detached(priority: .userInitiated) {
            let result = Self.runCommand(command, environment: environment, timeout: 20)
            let feedback = Self.parseActionFeedback(result, action: action)

            await MainActor.run {
                self.isPerformingAction = false
                self.lastActionSummary = feedback.summary
                self.lastActionDetail = feedback.detail ?? "命令已完成。"
                self.refreshStatus()
            }
        }
    }

    nonisolated static func commandEnvironment(base: [String: String]) -> [String: String] {
        OpenClawInstaller.installationEnvironment(base: base)
    }

    nonisolated static func detectInstalledBinaryPath(environment: [String: String]) -> String? {
        let result = runCommand("command -v openclaw", environment: environment, timeout: 3)
        guard !result.timedOut, result.exitStatus == 0 else { return nil }
        return OpenClawInstaller.parseDetectedBinaryPath(result.output)
    }

    nonisolated static func makeStatusSnapshot(
        binaryPath: String,
        commandResult: OpenClawGatewayCommandResult
    ) -> OpenClawGatewayStatusSnapshot {
        let displayPath = OpenClawInstaller.displayBinaryPath(binaryPath)

        if commandResult.timedOut {
            if let fallback = OpenClawLocalSnapshotSupport.gatewaySnapshot(binaryPath: binaryPath) {
                return fallback
            }

            return OpenClawGatewayStatusSnapshot(
                state: .unknown,
                detail: "gateway status 命令未在 8 秒内完成。",
                binaryPath: displayPath,
                runtimeStatus: nil,
                serviceInstalled: false,
                serviceLoaded: false,
                serviceLabel: nil,
                pid: nil,
                missingUnit: false
            )
        }

        guard
            commandResult.exitStatus == 0,
            let payload = parseJSONObject(from: commandResult.output),
            let service = payload["service"] as? [String: Any]
        else {
            return OpenClawGatewayStatusSnapshot(
                state: .unknown,
                detail: commandResult.output.nonEmptyOr("无法解析 gateway status 的返回结果。"),
                binaryPath: displayPath,
                runtimeStatus: nil,
                serviceInstalled: false,
                serviceLoaded: false,
                serviceLabel: nil,
                pid: nil,
                missingUnit: false
            )
        }

        let loaded = service["loaded"] as? Bool ?? false
        let runtime = service["runtime"] as? [String: Any]
        let runtimeStatus = (runtime?["status"] as? String)?.lowercased()
        let runtimeDetail = (runtime?["detail"] as? String)?.trimmedNonEmpty
        let pid = runtime?["pid"] as? Int
        let missingUnit = runtime?["missingUnit"] as? Bool ?? false
        let serviceLabel = (service["label"] as? String)?.trimmedNonEmpty
        let notLoadedText = (service["notLoadedText"] as? String)?.trimmedNonEmpty
        let serviceInstalled =
            loaded ||
            service["command"] as? [String: Any] != nil ||
            (!missingUnit && (serviceLabel != nil || notLoadedText != nil))

        let state: GatewayRuntimeState
        let detail: String

        switch (loaded, runtimeStatus) {
        case (true, "running"):
            state = .running
            if let runtimeDetail {
                detail = runtimeDetail
            } else if let pid {
                detail = "Gateway 后台服务正在运行，当前 PID 为 \(pid)。"
            } else {
                detail = "Gateway 后台服务已加载并处于运行状态。"
            }
        case (true, "scheduled"), (true, "starting"), (true, "stopping"):
            state = .transitioning
            detail = runtimeDetail ?? "Gateway 服务正在切换状态，请稍后刷新。"
        case (false, _) where missingUnit && !serviceInstalled:
            state = .missing
            detail = runtimeDetail ?? "Gateway 服务尚未安装到 launchd。"
        case (false, _):
            state = .stopped
            if missingUnit && serviceInstalled {
                detail = "Gateway 服务已安装，但当前未加载；通常表示尚未启动，或已经被暂停。"
            } else {
                detail = runtimeDetail ?? notLoadedText ?? "Gateway 服务当前未加载；通常表示尚未启动，或已经被暂停。"
            }
        default:
            state = .unknown
            detail = runtimeDetail ?? "Gateway 服务已加载，但当前运行状态无法识别。"
        }

        return OpenClawGatewayStatusSnapshot(
            state: state,
            detail: detail,
            binaryPath: displayPath,
            runtimeStatus: runtimeStatus,
            serviceInstalled: serviceInstalled,
            serviceLoaded: loaded,
            serviceLabel: serviceLabel,
            pid: pid,
            missingUnit: missingUnit
        )
    }

    nonisolated static func parseActionFeedback(
        _ result: OpenClawGatewayCommandResult,
        action: GatewayControlAction
    ) -> OpenClawGatewayActionFeedback {
        if result.timedOut {
            return OpenClawGatewayActionFeedback(
                isSuccess: false,
                summary: "Gateway \(action.displayName)超时",
                detail: "命令在 20 秒内没有完成。"
            )
        }

        if let payload = parseJSONObject(from: result.output) {
            let ok = payload["ok"] as? Bool ?? (result.exitStatus == 0)
            let resultCode = (payload["result"] as? String)?.trimmedNonEmpty?.lowercased()
            let message = (payload["message"] as? String)?.trimmedNonEmpty
            let error = (payload["error"] as? String)?.trimmedNonEmpty
            let warnings = (payload["warnings"] as? [String])?.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let detailParts = ([localizedGatewayActionMessage(message)] + (warnings ?? [])).compactMap { $0 }
            let detail = detailParts.isEmpty ? nil : detailParts.joined(separator: "\n")

            if ok {
                return OpenClawGatewayActionFeedback(
                    isSuccess: true,
                    summary: successSummary(action: action, resultCode: resultCode),
                    detail: detail
                )
            }

            return OpenClawGatewayActionFeedback(
                isSuccess: false,
                summary: "Gateway \(action.displayName)失败",
                detail: error ?? detail ?? result.output.trimmedNonEmpty
            )
        }

        if result.exitStatus == 0 {
            return OpenClawGatewayActionFeedback(
                isSuccess: true,
                summary: "Gateway 已\(action.displayName)。",
                detail: result.output.trimmedNonEmpty
            )
        }

        return OpenClawGatewayActionFeedback(
            isSuccess: false,
            summary: "Gateway \(action.displayName)失败",
            detail: result.output.trimmedNonEmpty ?? "命令返回了非零退出码 \(result.exitStatus)。"
        )
    }

    private nonisolated static func successSummary(
        action: GatewayControlAction,
        resultCode: String?
    ) -> String {
        switch (action, resultCode) {
        case (.start, "scheduled"):
            "Gateway 启动已调度。"
        case (.restart, "scheduled"):
            "Gateway 重启已调度。"
        case (.restart, "not-loaded"):
            "Gateway 未运行。"
        case (.pause, "not-loaded"), (.pause, "stopped"):
            "Gateway 已暂停。"
        case (.start, "not-loaded"):
            "Gateway 未启动。"
        case (.start, _):
            "Gateway 已启动。"
        case (.restart, _):
            "Gateway 已重启。"
        case (.pause, _):
            "Gateway 已暂停。"
        }
    }

    private nonisolated static func runCommand(
        _ command: String,
        environment: [String: String],
        timeout: TimeInterval
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
            output: sanitizeGatewayCommandOutput(data),
            exitStatus: process.terminationStatus,
            timedOut: timedOut
        )
    }

    private nonisolated static func parseJSONObject(from output: String) -> [String: Any]? {
        guard let data = output.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

private func sanitizeGatewayCommandOutput(_ data: Data) -> String {
    let raw = String(decoding: data, as: UTF8.self)
    let pattern = #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#

    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return raw
    }

    let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
    return regex.stringByReplacingMatches(in: raw, options: [], range: range, withTemplate: "")
}

private func localizedGatewayActionMessage(_ message: String?) -> String? {
    guard let message else { return nil }

    let normalized = message.lowercased()
    if normalized.contains("installed but not loaded"),
       normalized.contains("bootstrap") {
        return "Gateway LaunchAgent 已安装但未加载，已自动重新注册并拉起服务。"
    }
    if normalized.contains("scheduled for start") {
        return "已提交启动请求，Gateway 会很快进入运行状态。"
    }
    if normalized.contains("restart scheduled") {
        return "已提交重启请求，Gateway 会短暂重启。"
    }
    if normalized.contains("service restarted") {
        return "Gateway 服务已重启。"
    }
    if normalized.contains("service not loaded") {
        return "Gateway 服务当前未加载。"
    }

    return message
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
