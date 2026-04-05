import XCTest
@testable import Clawbar

@MainActor
final class OpenClawChannelManagerTests: XCTestCase {
    func testRefreshWeChatStatusSetsMissingCLIWhenCommandVFails() async {
        let manager = OpenClawChannelManager(
            environmentProvider: { [:] },
            runCommand: makeCommandRunner([
                MockCommand("/bin/zsh", ["-lc", "command -v openclaw"]): .init(
                    output: "",
                    exitStatus: 1,
                    timedOut: false
                ),
            ])
        )

        manager.refreshWeChatStatus()
        await waitUntilRefreshFinishes(for: manager)

        XCTAssertEqual(manager.cardState, .missingCLI)
        XCTAssertNil(manager.statusPayload)
        XCTAssertNil(manager.openClawBinaryPath)
    }

    func testRefreshWeChatStatusSetsStatusCommandFailedWhenStatusFails() async {
        let manager = OpenClawChannelManager(
            environmentProvider: { [:] },
            runCommand: makeCommandRunner([
                MockCommand("/bin/zsh", ["-lc", "command -v openclaw"]): .init(
                    output: "/opt/homebrew/bin/openclaw\n",
                    exitStatus: 0,
                    timedOut: false
                ),
                MockCommand("/opt/homebrew/bin/openclaw", ["status", "--json"]): .init(
                    output: "gateway down",
                    exitStatus: 1,
                    timedOut: false
                ),
            ])
        )

        manager.refreshWeChatStatus()
        await waitUntilRefreshFinishes(for: manager)

        XCTAssertEqual(
            manager.cardState,
            .statusCommandFailed(detail: "gateway down")
        )
        XCTAssertNil(manager.statusPayload)
    }

    func testParseStatusPayloadExtractsTrailingJSONAfterWarningPrefix() {
        let output = """
        [plugins] plugins.allow is empty; discovered non-bundled plugins may auto-load.
        {
          "runtimeVersion": "2026.4.2",
          "channelSummary": [
            "openclaw-weixin: configured",
            "  - 5aca4a01a0b0-im-bot (https://ilinkai.weixin.qq.com)"
          ],
          "gateway": {
            "reachable": true,
            "error": null,
            "url": "ws://127.0.0.1:18789"
          },
          "gatewayService": {
            "installed": true,
            "loaded": true,
            "runtimeShort": "running (pid 95663, state active)"
          }
        }
        """

        let payload = OpenClawChannelManager.parseStatusPayload(from: output)

        XCTAssertEqual(payload?.runtimeVersion, "2026.4.2")
        XCTAssertEqual(payload?.channelSummary.count, 2)
        XCTAssertEqual(payload?.gateway.reachable, true)
        XCTAssertEqual(payload?.gateway.url, "ws://127.0.0.1:18789")
        XCTAssertEqual(payload?.gatewayService.runtimeShort, "running (pid 95663, state active)")
    }

    func testDeriveStateReturnsPluginMissingWhenChannelSummaryHasNoWeixinSection() {
        let payload = OpenClawWeixinStatusPayload(
            runtimeVersion: "2026.4.2",
            channelSummary: ["telegram: configured"],
            gateway: .init(reachable: true, error: nil, url: "ws://127.0.0.1:18789"),
            gatewayService: .init(installed: true, loaded: true, runtimeShort: "running")
        )

        XCTAssertEqual(
            OpenClawChannelManager.deriveState(from: payload),
            .pluginMissing
        )
    }

    func testDeriveStateReturnsConfiguredGatewayReachableWhenWeixinConfiguredAndGatewayReachable() {
        let payload = OpenClawWeixinStatusPayload(
            runtimeVersion: "2026.4.2",
            channelSummary: [
                "openclaw-weixin: configured",
                "  - 5aca4a01a0b0-im-bot (https://ilinkai.weixin.qq.com)",
            ],
            gateway: .init(reachable: true, error: nil, url: "ws://127.0.0.1:18789"),
            gatewayService: .init(installed: true, loaded: true, runtimeShort: "running")
        )

        XCTAssertEqual(
            OpenClawChannelManager.deriveState(from: payload),
            .pluginConfiguredGatewayReachable(
                accountLabel: "5aca4a01a0b0-im-bot (https://ilinkai.weixin.qq.com)"
            )
        )
    }

    func testDeriveStateReturnsConfiguredGatewayUnreachableWhenWeixinConfiguredButGatewayUnavailable() {
        let payload = OpenClawWeixinStatusPayload(
            runtimeVersion: "2026.4.2",
            channelSummary: [
                "openclaw-weixin: configured",
                "  - 5aca4a01a0b0-im-bot (https://ilinkai.weixin.qq.com)",
            ],
            gateway: .init(reachable: false, error: "connection refused", url: "ws://127.0.0.1:18789"),
            gatewayService: .init(installed: true, loaded: false, runtimeShort: "not loaded")
        )

        XCTAssertEqual(
            OpenClawChannelManager.deriveState(from: payload),
            .pluginConfiguredGatewayUnreachable(
                accountLabel: "5aca4a01a0b0-im-bot (https://ilinkai.weixin.qq.com)",
                gatewayDetail: "connection refused"
            )
        )
    }

    func testDeriveStateReturnsPluginPresentButNotConfiguredWhenWeixinSectionExistsWithoutConfiguredState() {
        let payload = OpenClawWeixinStatusPayload(
            runtimeVersion: "2026.4.2",
            channelSummary: ["openclaw-weixin: not configured"],
            gateway: .init(reachable: true, error: nil, url: "ws://127.0.0.1:18789"),
            gatewayService: .init(installed: true, loaded: true, runtimeShort: "running")
        )

        XCTAssertEqual(
            OpenClawChannelManager.deriveState(from: payload),
            .pluginPresentButNotConfigured
        )
    }

    func testRefreshWeChatStatusKeepsLastKnownStateWhileRefreshing() async {
        let statusOutput = """
        {
          "channelSummary": [
            "openclaw-weixin: configured",
            "  - 5aca4a01a0b0-im-bot (https://ilinkai.weixin.qq.com)"
          ],
          "gateway": {
            "reachable": true,
            "error": null,
            "url": "ws://127.0.0.1:18789"
          },
          "gatewayService": {
            "installed": true,
            "loaded": true,
            "runtimeShort": "running"
          }
        }
        """

        let runner = SequencedCommandRunner([
            MockCommand("/bin/zsh", ["-lc", "command -v openclaw"]): [
                .immediate(.init(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false)),
                .immediate(.init(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["status", "--json"]): [
                .immediate(.init(output: statusOutput, exitStatus: 0, timedOut: false)),
                .delayed(
                    .init(output: statusOutput, exitStatus: 0, timedOut: false),
                    nanoseconds: 300_000_000
                ),
            ],
        ])

        let manager = OpenClawChannelManager(
            environmentProvider: { [:] },
            runCommand: runner.runner
        )

        manager.refreshWeChatStatus()
        await waitUntilRefreshFinishes(for: manager)

        XCTAssertEqual(
            manager.cardState,
            .pluginConfiguredGatewayReachable(
                accountLabel: "5aca4a01a0b0-im-bot (https://ilinkai.weixin.qq.com)"
            )
        )

        manager.refreshWeChatStatus()

        XCTAssertEqual(
            manager.cardState,
            .refreshing(
                lastKnown: .pluginConfiguredGatewayReachable(
                    accountLabel: "5aca4a01a0b0-im-bot (https://ilinkai.weixin.qq.com)"
                )
            )
        )

        await waitUntilRefreshFinishes(for: manager)
    }

    func testParseRuntimeSnapshotExtractsQRCodeAndProgressSignals() {
        let output = """
        Installed plugin: openclaw-weixin
        Restart the gateway to load plugins.
        [openclaw-weixin] 插件就绪，开始首次连接...
        使用微信扫描以下二维码，以完成连接：
        https://liteapp.weixin.qq.com/q/7GiQu1?qrcode=edc16d9d61346c3ec3ada33da3f312a6&bot_type=3
        等待连接结果...
        """

        let snapshot = OpenClawChannelManager.parseRuntimeSnapshot(from: output)

        XCTAssertTrue(snapshot.pluginInstalled)
        XCTAssertTrue(snapshot.pluginReadyForLogin)
        XCTAssertTrue(snapshot.waitingForConnection)
        XCTAssertEqual(
            snapshot.qrCodeURL,
            "https://liteapp.weixin.qq.com/q/7GiQu1?qrcode=edc16d9d61346c3ec3ada33da3f312a6&bot_type=3"
        )
    }

    func testParseRuntimeSnapshotMarksConnectedAndGatewayRestart() {
        let output = """
        ✅ 与微信连接成功！
        [openclaw-weixin] 正在重启 OpenClaw Gateway...
        """

        let snapshot = OpenClawChannelManager.parseRuntimeSnapshot(from: output)

        XCTAssertTrue(snapshot.connected)
        XCTAssertTrue(snapshot.restartingGateway)
    }

    private func waitUntilRefreshFinishes(
        for manager: OpenClawChannelManager,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while manager.isRefreshing {
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                XCTFail("Timed out waiting for refresh to finish")
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func makeCommandRunner(
        _ responses: [MockCommand: OpenClawChannelCommandResult]
    ) -> OpenClawChannelManager.CommandRunner {
        { executablePath, arguments, _, _ in
            responses[MockCommand(executablePath, arguments)]
                ?? .init(output: "", exitStatus: 1, timedOut: false)
        }
    }
}

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

    var runner: OpenClawChannelManager.CommandRunner {
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

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
