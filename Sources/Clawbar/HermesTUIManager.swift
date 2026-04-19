import Foundation
#if canImport(AppKit)
import AppKit
#endif

enum HermesTUIStyle: String, CaseIterable, Identifiable, Sendable {
    case classic
    case ink

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: "Classic (prompt_toolkit)"
        case .ink: "Ink"
        }
    }
}

@MainActor
final class HermesTUIManager: ObservableObject {
    static let shared = HermesTUIManager()

    typealias Launcher = @MainActor @Sendable (String) -> Bool

    @Published var preferredStyle: HermesTUIStyle = .classic
    @Published private(set) var lastLaunchSummary: String?

    private let installer: HermesInstaller
    private let launcher: Launcher

    init(
        installer: HermesInstaller = .shared,
        launcher: @escaping Launcher = HermesTUIManager.defaultLauncher
    ) {
        self.installer = installer
        self.launcher = launcher
    }

    func launchTUI() {
        guard let binaryPath = installer.hermesBinaryPath else {
            lastLaunchSummary = "未检测到 hermes，请先安装。"
            return
        }
        let command = Self.makeShellCommand(binaryPath: binaryPath, style: preferredStyle)
        if launcher(command) {
            lastLaunchSummary = "已在 Terminal 中打开 Hermes（\(preferredStyle.displayName)）。"
        } else {
            lastLaunchSummary = "无法启动 Terminal，请检查系统权限。"
        }
    }

    func launchGatewaySetup() {
        guard let binaryPath = installer.hermesBinaryPath else {
            lastLaunchSummary = "未检测到 hermes，请先安装。"
            return
        }
        let command = "\(Self.shellQuote(binaryPath)) gateway setup; exec $SHELL -l"
        if launcher(command) {
            lastLaunchSummary = "已在 Terminal 中启动 hermes gateway setup。"
        } else {
            lastLaunchSummary = "无法启动 Terminal，请检查系统权限。"
        }
    }

    nonisolated static func makeShellCommand(binaryPath: String, style: HermesTUIStyle) -> String {
        let envPrefix: String
        switch style {
        case .classic:
            envPrefix = ""
        case .ink:
            envPrefix = "HERMES_TUI=1 "
        }
        return "\(envPrefix)\(shellQuote(binaryPath)); exec $SHELL -l"
    }

    nonisolated static func shellQuote(_ value: String) -> String {
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    @MainActor
    static func defaultLauncher(_ command: String) -> Bool {
        #if canImport(AppKit)
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        do {
            try task.run()
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }
}
