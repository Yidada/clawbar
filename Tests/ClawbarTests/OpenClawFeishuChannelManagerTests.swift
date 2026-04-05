import XCTest
@testable import Clawbar

@MainActor
final class OpenClawFeishuChannelManagerTests: XCTestCase {
    func testRefreshStatusReturnsPreflightWhenOpenClawMissing() async {
        let manager = OpenClawFeishuChannelManager(
            environmentProvider: { [:] },
            runCommand: makeCommandRunner([
                MockCommand("/bin/zsh", ["-lc", "command -v openclaw"]): .init(output: "", exitStatus: 1, timedOut: false),
                MockCommand("/bin/zsh", ["-lc", "command -v npx"]): .init(output: "/opt/homebrew/bin/npx\n", exitStatus: 0, timedOut: false),
            ])
        )

        manager.refreshStatus()
        await waitUntilIdle(for: manager)

        XCTAssertEqual(manager.snapshot.stage, .preflight)
        XCTAssertEqual(manager.snapshot.summary, "未检测到 OpenClaw")
    }

    func testRefreshStatusReturnsPreflightWhenOpenClawVersionTooLow() async {
        let manager = OpenClawFeishuChannelManager(
            environmentProvider: { [:] },
            runCommand: makeCommandRunner([
                MockCommand("/bin/zsh", ["-lc", "command -v openclaw"]): .init(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false),
                MockCommand("/bin/zsh", ["-lc", "command -v npx"]): .init(output: "/opt/homebrew/bin/npx\n", exitStatus: 0, timedOut: false),
                MockCommand("/bin/bash", ["-lc", "npx -y @larksuite/openclaw-lark info"]): .init(
                    output: """
                    feishu-plugin-onboard: 1.0.37
                    openclaw: OpenClaw 2026.2.25 (legacy)
                    openclaw-lark: Not Installed
                    """,
                    exitStatus: 0,
                    timedOut: false
                ),
            ])
        )

        manager.refreshStatus()
        await waitUntilIdle(for: manager)

        XCTAssertEqual(manager.snapshot.stage, .preflight)
        XCTAssertEqual(manager.snapshot.openClawVersion, "2026.2.25")
    }

    func testEnableStartsInstallFlowAndMovesToConfigureStage() async {
        let manager = OpenClawFeishuChannelManager(
            environmentProvider: { [:] },
            runCommand: makeCommandRunner([
                MockCommand("/bin/zsh", ["-lc", "command -v openclaw"]): .init(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false),
                MockCommand("/bin/zsh", ["-lc", "command -v npx"]): .init(output: "/opt/homebrew/bin/npx\n", exitStatus: 0, timedOut: false),
                MockCommand("/bin/bash", ["-lc", "npx -y @larksuite/openclaw-lark info"]): .init(
                    output: """
                    feishu-plugin-onboard: 1.0.37
                    openclaw: OpenClaw 2026.4.2 (d74a122)
                    openclaw-lark: Not Installed
                    """,
                    exitStatus: 0,
                    timedOut: false
                ),
            ]),
            makeStreamingProcess: { _, _, outputHandler, _ in
                StubStreamingProcess {
                    outputHandler("""
                    打开以下链接配置应用:
                    https://open.feishu.cn/page/cli?user_code=ABCD-EFGH
                    等待配置应用...
                    """)
                }
            }
        )

        manager.refreshStatus()
        await waitUntilIdle(for: manager)
        manager.enable()
        await waitUntilConfigureStage(for: manager)

        XCTAssertEqual(manager.snapshot.stage, .configure)
        XCTAssertEqual(manager.primaryActionTitle, "继续配置")
        XCTAssertEqual(manager.snapshot.continueURL, "https://open.feishu.cn/page/cli?user_code=ABCD-EFGH")
    }

    func testEnableRedactsExistingAppSecretInLoggedCommand() async {
        let manager = OpenClawFeishuChannelManager(
            environmentProvider: { [:] },
            runCommand: makeCommandRunner([
                MockCommand("/bin/zsh", ["-lc", "command -v openclaw"]): .init(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false),
                MockCommand("/bin/zsh", ["-lc", "command -v npx"]): .init(output: "/opt/homebrew/bin/npx\n", exitStatus: 0, timedOut: false),
                MockCommand("/bin/bash", ["-lc", "npx -y @larksuite/openclaw-lark info"]): .init(
                    output: """
                    feishu-plugin-onboard: 1.0.37
                    openclaw: OpenClaw 2026.4.2 (d74a122)
                    openclaw-lark: Not Installed
                    """,
                    exitStatus: 0,
                    timedOut: false
                ),
            ]),
            makeStreamingProcess: { _, _, _, _ in
                StubStreamingProcess {}
            }
        )

        manager.refreshStatus()
        await waitUntilIdle(for: manager)
        manager.enable(using: FeishuAppCredentials(appID: "cli_test", appSecret: "super-secret"))

        XCTAssertTrue(manager.lastCommandOutput.contains("cli_test:<redacted>"))
        XCTAssertFalse(manager.lastCommandOutput.contains("super-secret"))
    }

    func testRefreshStatusReturnsReadyWhenPluginInstalledEnabledAndHealthy() async {
        let manager = OpenClawFeishuChannelManager(
            environmentProvider: { [:] },
            runCommand: makeCommandRunner([
                MockCommand("/bin/zsh", ["-lc", "command -v openclaw"]): .init(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false),
                MockCommand("/bin/zsh", ["-lc", "command -v npx"]): .init(output: "/opt/homebrew/bin/npx\n", exitStatus: 0, timedOut: false),
                MockCommand("/bin/bash", ["-lc", "npx -y @larksuite/openclaw-lark info"]): .init(
                    output: """
                    feishu-plugin-onboard: 1.0.37
                    openclaw: OpenClaw 2026.4.2 (d74a122)
                    openclaw-lark: 2026.4.1
                    """,
                    exitStatus: 0,
                    timedOut: false
                ),
                MockCommand("/opt/homebrew/bin/openclaw", ["config", "get", "channels.feishu.enabled", "--json"]): .init(output: "true\n", exitStatus: 0, timedOut: false),
                MockCommand("/opt/homebrew/bin/openclaw", ["gateway", "status", "--json", "--no-probe"]): .init(
                    output: """
                    {
                      "service": {
                        "loaded": true,
                        "runtime": { "status": "running" }
                      }
                    }
                    """,
                    exitStatus: 0,
                    timedOut: false
                ),
                MockCommand("/bin/bash", ["-lc", "npx -y @larksuite/openclaw-lark doctor"]): .init(
                    output: "Running diagnostic checks...\n[PASS] All checks passed\n",
                    exitStatus: 0,
                    timedOut: false
                ),
            ])
        )

        manager.refreshStatus()
        await waitUntilIdle(for: manager)

        XCTAssertEqual(manager.snapshot.stage, .ready)
        XCTAssertEqual(manager.snapshot.summary, "Feishu 已启用并可用")
        XCTAssertEqual(manager.primaryActionTitle, "重新验证")
    }

    func testRefreshStatusReturnsDiagnoseWhenDoctorFails() async {
        let manager = OpenClawFeishuChannelManager(
            environmentProvider: { [:] },
            runCommand: makeCommandRunner([
                MockCommand("/bin/zsh", ["-lc", "command -v openclaw"]): .init(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false),
                MockCommand("/bin/zsh", ["-lc", "command -v npx"]): .init(output: "/opt/homebrew/bin/npx\n", exitStatus: 0, timedOut: false),
                MockCommand("/bin/bash", ["-lc", "npx -y @larksuite/openclaw-lark info"]): .init(
                    output: """
                    feishu-plugin-onboard: 1.0.37
                    openclaw: OpenClaw 2026.4.2 (d74a122)
                    openclaw-lark: 2026.4.1
                    """,
                    exitStatus: 0,
                    timedOut: false
                ),
                MockCommand("/opt/homebrew/bin/openclaw", ["config", "get", "channels.feishu.enabled", "--json"]): .init(output: "true\n", exitStatus: 0, timedOut: false),
                MockCommand("/opt/homebrew/bin/openclaw", ["gateway", "status", "--json", "--no-probe"]): .init(
                    output: """
                    {
                      "service": {
                        "loaded": true,
                        "runtime": { "status": "running" }
                      }
                    }
                    """,
                    exitStatus: 0,
                    timedOut: false
                ),
                MockCommand("/bin/bash", ["-lc", "npx -y @larksuite/openclaw-lark doctor"]): .init(
                    output: """
                    Running diagnostic checks...
                    [FAIL] Plugin directory missing at /Users/example/.openclaw/extensions/openclaw-lark
                    Suggestion: Plugin is not installed. Use "feishu-plugin-onboard install" command to install it.
                    """,
                    exitStatus: 1,
                    timedOut: false
                ),
            ])
        )

        manager.refreshStatus()
        await waitUntilIdle(for: manager)

        XCTAssertEqual(manager.snapshot.stage, .diagnose)
        XCTAssertEqual(manager.primaryActionTitle, "运行修复")
    }

    func testDisableWritesConfigWithoutUninstallingPlugin() async {
        let runner = SequencedCommandRunner([
            MockCommand("/bin/zsh", ["-lc", "command -v openclaw"]): [
                .immediate(.init(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false)),
                .immediate(.init(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false)),
                .immediate(.init(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/bin/zsh", ["-lc", "command -v npx"]): [
                .immediate(.init(output: "/opt/homebrew/bin/npx\n", exitStatus: 0, timedOut: false)),
                .immediate(.init(output: "/opt/homebrew/bin/npx\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/bin/bash", ["-lc", "npx -y @larksuite/openclaw-lark info"]): [
                .immediate(.init(output: installedInfoOutput, exitStatus: 0, timedOut: false)),
                .immediate(.init(output: installedInfoOutput, exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["config", "get", "channels.feishu.enabled", "--json"]): [
                .immediate(.init(output: "true\n", exitStatus: 0, timedOut: false)),
                .immediate(.init(output: "false\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["gateway", "status", "--json", "--no-probe"]): [
                .immediate(.init(output: runningGatewayStatus, exitStatus: 0, timedOut: false)),
                .immediate(.init(output: runningGatewayStatus, exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/bin/bash", ["-lc", "npx -y @larksuite/openclaw-lark doctor"]): [
                .immediate(.init(output: "Running diagnostic checks...\n[PASS] All checks passed\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["config", "set", "channels.feishu.enabled", "false", "--strict-json"]): [
                .immediate(.init(output: "{ \"ok\": true }\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["gateway", "restart", "--json"]): [
                .immediate(.init(output: "{ \"ok\": true }\n", exitStatus: 0, timedOut: false)),
            ],
        ])

        let manager = OpenClawFeishuChannelManager(
            environmentProvider: { [:] },
            runCommand: runner.runner
        )

        manager.refreshStatus()
        await waitUntilIdle(for: manager)
        XCTAssertTrue(manager.snapshot.channelEnabled)

        manager.disable()
        await waitUntilIdle(for: manager)

        XCTAssertFalse(manager.snapshot.channelEnabled)
        XCTAssertEqual(manager.snapshot.stage, .verify)
        XCTAssertTrue(manager.lastCommandOutput.contains("openclaw config set channels.feishu.enabled false --strict-json"))
        XCTAssertFalse(manager.lastCommandOutput.contains("uninstall"))
    }

    func testEnableFailureDoesNotRestartGatewayOrKeepToggleEnabled() async {
        let runner = SequencedCommandRunner([
            MockCommand("/bin/zsh", ["-lc", "command -v openclaw"]): [
                .immediate(.init(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false)),
                .immediate(.init(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/bin/zsh", ["-lc", "command -v npx"]): [
                .immediate(.init(output: "/opt/homebrew/bin/npx\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/bin/bash", ["-lc", "npx -y @larksuite/openclaw-lark info"]): [
                .immediate(.init(output: installedInfoOutput, exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["config", "get", "channels.feishu.enabled", "--json"]): [
                .immediate(.init(output: "false\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["gateway", "status", "--json", "--no-probe"]): [
                .immediate(.init(output: runningGatewayStatus, exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["config", "set", "channels.feishu.enabled", "true", "--strict-json"]): [
                .immediate(.init(output: "{ \"error\": \"write failed\" }\n", exitStatus: 1, timedOut: false)),
            ],
        ])

        let manager = OpenClawFeishuChannelManager(
            environmentProvider: { [:] },
            runCommand: runner.runner
        )

        manager.refreshStatus()
        await waitUntilIdle(for: manager)
        XCTAssertEqual(manager.snapshot.stage, .verify)
        XCTAssertFalse(manager.snapshot.channelEnabled)

        manager.enable()
        await waitUntilIdle(for: manager)

        XCTAssertEqual(manager.snapshot.stage, .diagnose)
        XCTAssertFalse(manager.isEnabled)
        XCTAssertFalse(manager.lastCommandOutput.contains("$ openclaw gateway restart --json"))
    }

    func testFailedInstallClearsOptimisticToggleIntent() async {
        let manager = OpenClawFeishuChannelManager(
            environmentProvider: { [:] },
            runCommand: makeCommandRunner([
                MockCommand("/bin/zsh", ["-lc", "command -v openclaw"]): .init(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false),
                MockCommand("/bin/zsh", ["-lc", "command -v npx"]): .init(output: "/opt/homebrew/bin/npx\n", exitStatus: 0, timedOut: false),
                MockCommand("/bin/bash", ["-lc", "npx -y @larksuite/openclaw-lark info"]): .init(
                    output: """
                    feishu-plugin-onboard: 1.0.37
                    openclaw: OpenClaw 2026.4.2 (d74a122)
                    openclaw-lark: Not Installed
                    """,
                    exitStatus: 0,
                    timedOut: false
                ),
            ]),
            makeStreamingProcess: { _, _, outputHandler, terminationHandler in
                StubStreamingProcess {
                    outputHandler("installation failed\n")
                    terminationHandler(1)
                }
            }
        )

        manager.refreshStatus()
        await waitUntilIdle(for: manager)
        manager.enable()
        await waitUntilIdle(for: manager)

        XCTAssertFalse(manager.isEnabled)
        XCTAssertEqual(manager.snapshot.stage, .diagnose)
    }

    private func waitUntilIdle(
        for manager: OpenClawFeishuChannelManager,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while manager.isRefreshing || manager.activeAction != nil {
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                XCTFail("Timed out waiting for Feishu manager to become idle")
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func waitUntilConfigureStage(
        for manager: OpenClawFeishuChannelManager,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while manager.snapshot.stage != .configure {
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                XCTFail("Timed out waiting for Feishu manager to enter configure stage")
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private let installedInfoOutput = """
feishu-plugin-onboard: 1.0.37
openclaw: OpenClaw 2026.4.2 (d74a122)
openclaw-lark: 2026.4.1
"""

private let runningGatewayStatus = """
{
  "service": {
    "loaded": true,
    "runtime": { "status": "running" }
  }
}
"""

private struct MockCommand: Hashable {
    let executablePath: String
    let arguments: [String]

    init(_ executablePath: String, _ arguments: [String]) {
        self.executablePath = executablePath
        self.arguments = arguments
    }
}

private final class SequencedCommandRunner: @unchecked Sendable {
    enum Step {
        case immediate(OpenClawChannelCommandResult)
        case delayed(OpenClawChannelCommandResult, nanoseconds: UInt64)
    }

    private let lock = NSLock()
    private var stepsByCommand: [MockCommand: [Step]]

    init(_ stepsByCommand: [MockCommand: [Step]]) {
        self.stepsByCommand = stepsByCommand
    }

    var runner: OpenClawFeishuChannelManager.CommandRunner {
        { [self] executablePath, arguments, _, _ in
            let command = MockCommand(executablePath, arguments)
            let step: Step = lock.withLock {
                guard var steps = stepsByCommand[command], !steps.isEmpty else {
                    return .immediate(.init(output: "", exitStatus: 1, timedOut: false))
                }
                let next = steps.removeFirst()
                stepsByCommand[command] = steps
                return next
            }

            switch step {
            case .immediate(let result):
                return result
            case .delayed(let result, let nanoseconds):
                Thread.sleep(forTimeInterval: TimeInterval(nanoseconds) / 1_000_000_000)
                return result
            }
        }
    }
}

private final class StubStreamingProcess: Process, @unchecked Sendable {
    private let onRun: () -> Void

    init(onRun: @escaping () -> Void) {
        self.onRun = onRun
        super.init()
    }

    override func run() throws {
        onRun()
    }
}

private extension OpenClawFeishuChannelManagerTests {
    func makeCommandRunner(
        _ responses: [MockCommand: OpenClawChannelCommandResult]
    ) -> OpenClawFeishuChannelManager.CommandRunner {
        { executablePath, arguments, _, _ in
            responses[MockCommand(executablePath, arguments)]
                ?? .init(output: "", exitStatus: 1, timedOut: false)
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
