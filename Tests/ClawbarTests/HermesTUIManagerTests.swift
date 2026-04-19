import XCTest
@testable import Clawbar

@MainActor
final class HermesTUIManagerTests: XCTestCase {
    func testMakeShellCommandClassicStyleOmitsEnvPrefix() {
        let command = HermesTUIManager.makeShellCommand(binaryPath: "/usr/local/bin/hermes", style: .classic)

        XCTAssertEqual(command, "'/usr/local/bin/hermes'; exec $SHELL -l")
    }

    func testMakeShellCommandInkStylePrefixesHermesTUIEnvVar() {
        let command = HermesTUIManager.makeShellCommand(binaryPath: "/usr/local/bin/hermes", style: .ink)

        XCTAssertEqual(command, "HERMES_TUI=1 '/usr/local/bin/hermes'; exec $SHELL -l")
    }

    func testMakeShellCommandQuotesPathContainingSpaces() {
        let command = HermesTUIManager.makeShellCommand(binaryPath: "/Users/x/My Tools/hermes", style: .classic)

        XCTAssertTrue(command.hasPrefix("'/Users/x/My Tools/hermes'"))
    }

    func testLaunchTUIRecordsSummaryWhenHermesMissing() {
        let installer = HermesInstaller(
            refreshInterval: 0,
            homeOverride: URL(fileURLWithPath: "/tmp/hermes"),
            runCommand: { _, _, _, _ in OpenClawChannelCommandResult(output: "", exitStatus: 1, timedOut: false) },
            configReader: { _ in nil }
        )
        let manager = HermesTUIManager(installer: installer, launcher: { _ in true })

        manager.launchTUI()

        XCTAssertEqual(manager.lastLaunchSummary, "未检测到 hermes，请先安装。")
    }

    func testLaunchTUIInvokesLauncherWithComposedCommandWhenInstalled() async {
        let installer = HermesInstaller(
            refreshInterval: 0,
            homeOverride: URL(fileURLWithPath: "/tmp/hermes"),
            runCommand: { executable, arguments, _, _ in
                if arguments.first == "-lc", arguments.dropFirst().first == "command -v hermes" {
                    return OpenClawChannelCommandResult(output: "/usr/local/bin/hermes\n", exitStatus: 0, timedOut: false)
                }
                if executable.hasSuffix("/hermes"), arguments == ["--version"] {
                    return OpenClawChannelCommandResult(output: "Hermes Agent v0.6.0\n", exitStatus: 0, timedOut: false)
                }
                return OpenClawChannelCommandResult(output: "", exitStatus: 1, timedOut: false)
            },
            configReader: { _ in nil }
        )
        await installer.refreshStatus(force: true)

        var captured: String?
        let manager = HermesTUIManager(installer: installer, launcher: { command in
            captured = command
            return true
        })
        manager.preferredStyle = .ink
        manager.launchTUI()

        XCTAssertEqual(captured, "HERMES_TUI=1 '/usr/local/bin/hermes'; exec $SHELL -l")
        XCTAssertEqual(manager.lastLaunchSummary, "已在 Terminal 中打开 Hermes（Ink）。")
    }

    func testLaunchGatewaySetupComposesSetupSubcommand() async {
        let installer = HermesInstaller(
            refreshInterval: 0,
            homeOverride: URL(fileURLWithPath: "/tmp/hermes"),
            runCommand: { _, arguments, _, _ in
                if arguments.first == "-lc", arguments.dropFirst().first == "command -v hermes" {
                    return OpenClawChannelCommandResult(output: "/opt/homebrew/bin/hermes\n", exitStatus: 0, timedOut: false)
                }
                return OpenClawChannelCommandResult(output: "", exitStatus: 1, timedOut: false)
            },
            configReader: { _ in nil }
        )
        await installer.refreshStatus(force: true)

        var captured: String?
        let manager = HermesTUIManager(installer: installer, launcher: { command in
            captured = command
            return true
        })
        manager.launchGatewaySetup()

        XCTAssertEqual(captured, "'/opt/homebrew/bin/hermes' gateway setup; exec $SHELL -l")
    }
}
