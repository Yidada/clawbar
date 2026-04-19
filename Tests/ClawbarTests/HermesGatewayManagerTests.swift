import XCTest
@testable import Clawbar

final class HermesGatewayManagerTests: XCTestCase {
    // MARK: parseStatusOutput

    func testParseStatusOutputDetectsRunningServiceWithPID() {
        let output = """
        Hermes Gateway service status:
          Installed: yes
          Loaded: yes
          Running: yes (PID 12345)
        """
        let snapshot = HermesGatewayManager.parseStatusOutput(output, exitStatus: 0, timedOut: false)

        XCTAssertTrue(snapshot.isInstalled)
        XCTAssertTrue(snapshot.isLoaded)
        XCTAssertTrue(snapshot.isRunning)
        XCTAssertEqual(snapshot.pid, 12345)
    }

    func testParseStatusOutputDetectsLoadedButNotRunning() {
        let output = """
        Gateway service installed
        Loaded into launchd
        Status: not running
        """
        let snapshot = HermesGatewayManager.parseStatusOutput(output, exitStatus: 0, timedOut: false)

        XCTAssertTrue(snapshot.isInstalled)
        XCTAssertTrue(snapshot.isLoaded)
        XCTAssertFalse(snapshot.isRunning)
        XCTAssertNil(snapshot.pid)
    }

    func testParseStatusOutputReportsNotInstalled() {
        let output = "Gateway service is not installed."
        let snapshot = HermesGatewayManager.parseStatusOutput(output, exitStatus: 0, timedOut: false)

        XCTAssertFalse(snapshot.isInstalled)
        XCTAssertFalse(snapshot.isLoaded)
        XCTAssertFalse(snapshot.isRunning)
    }

    func testParseStatusOutputHandlesChineseInstalledLabel() {
        let output = "Gateway 状态: 已安装并 running"
        let snapshot = HermesGatewayManager.parseStatusOutput(output, exitStatus: 0, timedOut: false)

        XCTAssertTrue(snapshot.isInstalled)
        XCTAssertTrue(snapshot.isRunning)
    }

    func testParseStatusOutputExtractsPIDFromVariousFormats() {
        XCTAssertEqual(HermesGatewayManager.extractPID(from: "running pid 4242"), 4242)
        XCTAssertEqual(HermesGatewayManager.extractPID(from: "PID: 999"), 999)
        XCTAssertEqual(HermesGatewayManager.extractPID(from: "service ok PID=10"), 10)
        XCTAssertNil(HermesGatewayManager.extractPID(from: "no pid here"))
    }

    // MARK: shellQuote

    func testShellQuoteEscapesSingleQuotes() {
        XCTAssertEqual(HermesGatewayManager.shellQuote("/usr/bin/it's"), "'/usr/bin/it'\\''s'")
    }

    func testShellQuoteWrapsPlainPath() {
        XCTAssertEqual(HermesGatewayManager.shellQuote("/usr/local/bin/hermes"), "'/usr/local/bin/hermes'")
    }

    // MARK: firstNonEmptyLine

    func testFirstNonEmptyLineSkipsBlanks() {
        XCTAssertEqual(HermesGatewayManager.firstNonEmptyLine("\n\n  hello\nworld"), "hello")
        XCTAssertNil(HermesGatewayManager.firstNonEmptyLine(""))
    }

    // MARK: refreshStatus integration with mock runner

    @MainActor
    func testRefreshStatusUpdatesPublishedSnapshot() async {
        let installer = HermesInstaller(
            refreshInterval: 0,
            homeOverride: URL(fileURLWithPath: "/tmp/hermes-test"),
            runCommand: { executable, arguments, _, _ in
                if arguments.first == "-lc", arguments.dropFirst().first == "command -v hermes" {
                    return OpenClawChannelCommandResult(output: "/Users/x/.local/bin/hermes\n", exitStatus: 0, timedOut: false)
                }
                if executable.hasSuffix("/hermes"), arguments == ["--version"] {
                    return OpenClawChannelCommandResult(output: "Hermes Agent v0.5.0\n", exitStatus: 0, timedOut: false)
                }
                return OpenClawChannelCommandResult(output: "", exitStatus: 1, timedOut: false)
            },
            configReader: { _ in nil }
        )

        await installer.refreshStatus(force: true)
        XCTAssertTrue(installer.isInstalled)

        let runner: HermesGatewayManager.CommandRunner = { executable, arguments, _, _ in
            XCTAssertTrue(executable.hasSuffix("/hermes"))
            XCTAssertEqual(arguments, ["gateway", "status"])
            return OpenClawChannelCommandResult(
                output: "Installed: yes\nLoaded: yes\nRunning: yes PID 555\n",
                exitStatus: 0,
                timedOut: false
            )
        }
        let manager = HermesGatewayManager(
            installer: installer,
            runCommand: runner,
            configOpener: { _ in true }
        )

        await manager.refreshStatus()

        XCTAssertTrue(manager.statusSnapshot.isInstalled)
        XCTAssertTrue(manager.statusSnapshot.isRunning)
        XCTAssertEqual(manager.statusSnapshot.pid, 555)
    }

    @MainActor
    func testStartActionRecordsFailureFeedbackOnNonZeroExit() async {
        let installer = HermesInstaller(
            refreshInterval: 0,
            homeOverride: URL(fileURLWithPath: "/tmp/hermes-test"),
            runCommand: { executable, arguments, _, _ in
                if arguments.first == "-lc", arguments.dropFirst().first == "command -v hermes" {
                    return OpenClawChannelCommandResult(output: "/usr/local/bin/hermes\n", exitStatus: 0, timedOut: false)
                }
                if executable.hasSuffix("/hermes"), arguments == ["--version"] {
                    return OpenClawChannelCommandResult(output: "Hermes Agent v0.5.0\n", exitStatus: 0, timedOut: false)
                }
                return OpenClawChannelCommandResult(output: "", exitStatus: 1, timedOut: false)
            },
            configReader: { _ in nil }
        )
        await installer.refreshStatus(force: true)

        let runner: HermesGatewayManager.CommandRunner = { _, arguments, _, _ in
            if arguments == ["gateway", "start"] {
                return OpenClawChannelCommandResult(
                    output: "error: launchd label ai.hermes.gateway not registered\n",
                    exitStatus: 64,
                    timedOut: false
                )
            }
            return OpenClawChannelCommandResult(output: "", exitStatus: 0, timedOut: false)
        }
        let manager = HermesGatewayManager(
            installer: installer,
            runCommand: runner,
            configOpener: { _ in true }
        )

        await manager.start()

        XCTAssertNotNil(manager.lastFeedback)
        XCTAssertEqual(manager.lastFeedback?.isSuccess, false)
        XCTAssertTrue(manager.lastFeedback?.summary.contains("启动服务") ?? false)
    }

    @MainActor
    func testMakeSetupTerminalCommandUsesQuotedHermesPath() async {
        let installer = HermesInstaller(
            refreshInterval: 0,
            homeOverride: URL(fileURLWithPath: "/tmp/hermes-test"),
            runCommand: { executable, arguments, _, _ in
                if arguments.first == "-lc", arguments.dropFirst().first == "command -v hermes" {
                    return OpenClawChannelCommandResult(output: "/Users/x/.local/bin/hermes\n", exitStatus: 0, timedOut: false)
                }
                return OpenClawChannelCommandResult(output: "", exitStatus: 1, timedOut: false)
            },
            configReader: { _ in nil }
        )
        await installer.refreshStatus(force: true)

        let manager = HermesGatewayManager(
            installer: installer,
            runCommand: { _, _, _, _ in OpenClawChannelCommandResult(output: "", exitStatus: 0, timedOut: false) },
            configOpener: { _ in true }
        )

        XCTAssertEqual(manager.makeSetupTerminalCommand(), "'/Users/x/.local/bin/hermes' gateway setup")
    }

    @MainActor
    func testOpenConfigFileDelegatesToOpener() async {
        let installer = HermesInstaller(
            refreshInterval: 0,
            homeOverride: URL(fileURLWithPath: "/tmp/hermes-home"),
            runCommand: { _, _, _, _ in OpenClawChannelCommandResult(output: "", exitStatus: 1, timedOut: false) },
            configReader: { _ in nil }
        )

        actor URLBox {
            var url: URL?
            func set(_ value: URL) { url = value }
        }

        let box = URLBox()
        let manager = HermesGatewayManager(
            installer: installer,
            runCommand: { _, _, _, _ in OpenClawChannelCommandResult(output: "", exitStatus: 0, timedOut: false) },
            configOpener: { url in
                Task { await box.set(url) }
                return true
            }
        )

        XCTAssertTrue(manager.openConfigFile())
        // Tasks scheduled inside the opener resolve eventually.
        await Task.yield()
        await Task.sleep(seconds: 0.01)
        let captured = await box.url
        XCTAssertEqual(captured?.lastPathComponent, "config.yaml")
        XCTAssertTrue(captured?.path.contains("/tmp/hermes-home") ?? false)
    }
}

private extension Task where Success == Never, Failure == Never {
    static func sleep(seconds: TimeInterval) async {
        try? await Task<Never, Never>.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
