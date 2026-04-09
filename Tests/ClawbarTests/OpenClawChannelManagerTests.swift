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
        XCTAssertNil(payload?.channelSnapshot)
        XCTAssertEqual(payload?.gateway.reachable, true)
        XCTAssertEqual(payload?.gateway.url, "ws://127.0.0.1:18789")
        XCTAssertEqual(payload?.gatewayService.runtimeShort, "running (pid 95663, state active)")
    }

    func testDeriveStateReturnsPluginMissingWhenPluginIsUnavailable() {
        XCTAssertEqual(
            OpenClawChannelManager.deriveState(from: makeWeixinPayload()),
            .pluginMissing
        )
    }

    func testDeriveStateReturnsConfiguredGatewayReachableWhenWeixinRuntimeIsRunning() {
        XCTAssertEqual(
            OpenClawChannelManager.deriveState(
                from: makeWeixinPayload(
                    channelSnapshot: makeWeixinChannel(configured: true, running: true, accountID: "wx-bot-default"),
                    pluginInspection: makeWeixinPlugin(active: true)
                )
            ),
            .pluginConfiguredGatewayReachable(accountLabel: "wx-bot-default")
        )
    }

    func testDeriveStateReturnsConfiguredGatewayUnreachableWhenWeixinConfiguredButRuntimeStopped() {
        XCTAssertEqual(
            OpenClawChannelManager.deriveState(
                from: makeWeixinPayload(
                    channelSnapshot: makeWeixinChannel(
                        configured: true,
                        running: false,
                        lastError: "connection refused",
                        accountID: "wx-bot-default"
                    ),
                    pluginInspection: makeWeixinPlugin(active: true)
                )
            ),
            .pluginConfiguredGatewayUnreachable(
                accountLabel: "wx-bot-default",
                gatewayDetail: "connection refused"
            )
        )
    }

    func testDeriveStateReturnsPluginPresentButNotConfiguredWhenPluginExistsWithoutRuntimeAccount() {
        XCTAssertEqual(
            OpenClawChannelManager.deriveState(
                from: makeWeixinPayload(
                    channelSnapshot: makeWeixinChannel(configured: false, running: false),
                    pluginInspection: makeWeixinPlugin(active: true)
                )
            ),
            .pluginPresentButNotConfigured
        )
    }

    func testIsEnabledReturnsFalseBeforeAnyStatusResolves() {
        let manager = OpenClawChannelManager(
            environmentProvider: { [:] },
            runCommand: makeCommandRunner([:])
        )

        XCTAssertFalse(manager.hasResolvedStatus)
        XCTAssertFalse(manager.isEnabled)
    }

    func testRefreshWeChatStatusKeepsLastKnownStateWhileRefreshing() async {
        let statusOutput = """
        {
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
            MockCommand("/opt/homebrew/bin/openclaw", ["channels", "status", "--json"]): [
                .immediate(.init(output: weixinChannelsStatusOutput, exitStatus: 0, timedOut: false)),
                .immediate(.init(output: weixinChannelsStatusOutput, exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["channels", "list", "--json"]): [
                .immediate(.init(output: weixinChannelsListOutput, exitStatus: 0, timedOut: false)),
                .immediate(.init(output: weixinChannelsListOutput, exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["plugins", "inspect", "openclaw-weixin", "--json"]): [
                .immediate(.init(output: weixinPluginInspectOutput, exitStatus: 0, timedOut: false)),
                .immediate(.init(output: weixinPluginInspectOutput, exitStatus: 0, timedOut: false)),
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
                accountLabel: "wx-bot-default"
            )
        )

        manager.refreshWeChatStatus()

        XCTAssertEqual(
            manager.cardState,
            .refreshing(
                lastKnown: .pluginConfiguredGatewayReachable(
                    accountLabel: "wx-bot-default"
                )
            )
        )

        await waitUntilRefreshFinishes(for: manager)
    }

    func testRefreshWeChatStatusMarksConfiguredPluginAsEnabled() async {
        let manager = OpenClawChannelManager(
            environmentProvider: { [:] },
            runCommand: makeCommandRunner([
                MockCommand("/bin/zsh", ["-lc", "command -v openclaw"]): .init(
                    output: "/opt/homebrew/bin/openclaw\n",
                    exitStatus: 0,
                    timedOut: false
                ),
                MockCommand("/opt/homebrew/bin/openclaw", ["status", "--json"]): .init(
                    output: """
                    {
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
                    """,
                    exitStatus: 0,
                    timedOut: false
                ),
                MockCommand("/opt/homebrew/bin/openclaw", ["channels", "status", "--json"]): .init(
                    output: weixinChannelsStatusOutput,
                    exitStatus: 0,
                    timedOut: false
                ),
                MockCommand("/opt/homebrew/bin/openclaw", ["channels", "list", "--json"]): .init(
                    output: weixinChannelsListOutput,
                    exitStatus: 0,
                    timedOut: false
                ),
                MockCommand("/opt/homebrew/bin/openclaw", ["plugins", "inspect", "openclaw-weixin", "--json"]): .init(
                    output: weixinPluginInspectOutput,
                    exitStatus: 0,
                    timedOut: false
                ),
            ])
        )

        manager.refreshWeChatStatus()
        await waitUntilRefreshFinishes(for: manager)

        XCTAssertTrue(manager.hasResolvedStatus)
        XCTAssertTrue(manager.isEnabled)
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

    private func makeWeixinPayload(
        channelSnapshot: OpenClawChannelSnapshot? = nil,
        pluginInspection: OpenClawPluginInspectionSnapshot? = nil,
        gatewayError: String? = nil,
        gatewayRuntimeShort: String? = "running"
    ) -> OpenClawWeixinStatusPayload {
        OpenClawWeixinStatusPayload(
            runtimeVersion: "2026.4.2",
            gateway: .init(reachable: nil, error: gatewayError, url: "ws://127.0.0.1:18789"),
            gatewayService: .init(
                installed: true,
                loaded: true,
                runtimeShort: gatewayRuntimeShort
            ),
            channelSnapshot: channelSnapshot,
            pluginInspection: pluginInspection
        )
    }

    private func makeWeixinChannel(
        configured: Bool,
        running: Bool,
        lastError: String? = nil,
        accountID: String? = nil
    ) -> OpenClawChannelSnapshot {
        let accounts = accountID.map {
            [
                OpenClawChannelAccountSnapshot(
                    accountID: $0,
                    enabled: true,
                    configured: configured,
                    running: running,
                    appID: nil,
                    brand: nil,
                    lastError: lastError
                )
            ]
        } ?? []

        return OpenClawChannelSnapshot(
            id: "openclaw-weixin",
            label: "WeChat",
            detailLabel: nil,
            exists: true,
            configured: configured,
            running: running,
            lastError: lastError,
            defaultAccountID: accountID,
            accounts: accounts
        )
    }

    private func makeWeixinPlugin(active: Bool) -> OpenClawPluginInspectionSnapshot {
        OpenClawPluginInspectionSnapshot(
            pluginID: "openclaw-weixin",
            exists: true,
            enabled: active,
            activated: active,
            status: active ? "loaded" : "disabled",
            channelIDs: ["openclaw-weixin"],
            failureDetail: nil
        )
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

private let weixinChannelsStatusOutput = """
{
  "channelOrder": ["openclaw-weixin"],
  "channelLabels": {
    "openclaw-weixin": "WeChat"
  },
  "channels": {
    "openclaw-weixin": {
      "configured": true,
      "running": true,
      "lastError": null
    }
  },
  "channelAccounts": {
    "openclaw-weixin": [
      {
        "accountId": "wx-bot-default",
        "enabled": true,
        "configured": true,
        "running": true,
        "lastError": null
      }
    ]
  },
  "channelDefaultAccountId": {
    "openclaw-weixin": "wx-bot-default"
  }
}
"""

private let weixinChannelsListOutput = """
{
  "chat": {
    "openclaw-weixin": ["wx-bot-default"]
  }
}
"""

private let weixinPluginInspectOutput = """
{
  "plugin": {
    "id": "openclaw-weixin",
    "enabled": true,
    "activated": true,
    "status": "loaded",
    "channelIds": ["openclaw-weixin"]
  }
}
"""
