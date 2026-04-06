import XCTest
@testable import Clawbar

final class OpenClawChannelsSnapshotTests: XCTestCase {
    func testParseStatusPayloadReadsChannelRuntimeAndAccounts() {
        let output = """
        [plugins] warning
        {
          "channelOrder": ["feishu"],
          "channelLabels": {
            "feishu": "Feishu"
          },
          "channelDetailLabels": {
            "feishu": "Lark/Feishu (飞书)"
          },
          "channels": {
            "feishu": {
              "configured": true,
              "running": true,
              "lastError": null
            }
          },
          "channelAccounts": {
            "feishu": [
              {
                "accountId": "default",
                "enabled": true,
                "configured": true,
                "running": true,
                "appId": "cli_123",
                "brand": "feishu",
                "lastError": null
              }
            ]
          },
          "channelDefaultAccountId": {
            "feishu": "default"
          }
        }
        """

        let snapshot = OpenClawChannelsSnapshotSupport.parseStatusPayload(from: output)

        XCTAssertTrue(snapshot?.statusLoaded == true)
        XCTAssertEqual(snapshot?.orderedChannelIDs, ["feishu"])
        XCTAssertEqual(snapshot?.channel(id: "feishu")?.label, "Feishu")
        XCTAssertEqual(snapshot?.channel(id: "feishu")?.detailLabel, "Lark/Feishu (飞书)")
        XCTAssertEqual(snapshot?.channel(id: "feishu")?.configured, true)
        XCTAssertEqual(snapshot?.channel(id: "feishu")?.running, true)
        XCTAssertEqual(snapshot?.channel(id: "feishu")?.defaultAccountID, "default")
        XCTAssertEqual(snapshot?.channel(id: "feishu")?.primaryAccount?.displayLabel, "cli_123 (feishu)")
    }

    func testParseListPayloadPromotesConfiguredAccounts() {
        let output = """
        {
          "chat": {
            "feishu": ["default"],
            "openclaw-weixin": ["wx-bot"]
          }
        }
        """

        let snapshot = OpenClawChannelsSnapshotSupport.parseListPayload(from: output)

        XCTAssertTrue(snapshot?.listLoaded == true)
        XCTAssertEqual(snapshot?.orderedChannelIDs, ["feishu", "openclaw-weixin"])
        XCTAssertEqual(snapshot?.channel(id: "feishu")?.configured, true)
        XCTAssertEqual(snapshot?.channel(id: "feishu")?.running, false)
        XCTAssertEqual(snapshot?.channel(id: "feishu")?.defaultAccountID, "default")
        XCTAssertEqual(snapshot?.channel(id: "openclaw-weixin")?.primaryAccount?.accountID, "wx-bot")
    }

    func testFetchSnapshotMergesListAccountsIntoRuntimeChannel() {
        let runner = makeRunner([
            ChannelSnapshotMockCommand("/opt/homebrew/bin/openclaw", ["channels", "status", "--json"]): .init(
                output: """
                {
                  "channelOrder": ["feishu"],
                  "channelLabels": {
                    "feishu": "Feishu"
                  },
                  "channels": {
                    "feishu": {
                      "configured": true,
                      "running": false,
                      "lastError": "waiting for reconnect"
                    }
                  },
                  "channelAccounts": {
                    "feishu": []
                  }
                }
                """,
                exitStatus: 0,
                timedOut: false
            ),
            ChannelSnapshotMockCommand("/opt/homebrew/bin/openclaw", ["channels", "list", "--json"]): .init(
                output: """
                {
                  "chat": {
                    "feishu": ["default"]
                  }
                }
                """,
                exitStatus: 0,
                timedOut: false
            ),
            ChannelSnapshotMockCommand("/opt/homebrew/bin/openclaw", ["plugins", "inspect", "openclaw-lark", "--json"]): .init(
                output: """
                {
                  "plugin": {
                    "id": "openclaw-lark",
                    "enabled": true,
                    "activated": true,
                    "status": "loaded",
                    "channelIds": ["feishu"]
                  }
                }
                """,
                exitStatus: 0,
                timedOut: false
            ),
        ])

        let snapshot = OpenClawChannelsSnapshotSupport.fetchSnapshot(
            openClawBinaryPath: "/opt/homebrew/bin/openclaw",
            environment: [:],
            runCommand: runner,
            pluginIDs: ["openclaw-lark"]
        )

        XCTAssertTrue(snapshot.statusLoaded)
        XCTAssertTrue(snapshot.listLoaded)
        XCTAssertEqual(snapshot.channel(id: "feishu")?.configured, true)
        XCTAssertEqual(snapshot.channel(id: "feishu")?.running, false)
        XCTAssertEqual(snapshot.channel(id: "feishu")?.defaultAccountID, "default")
        XCTAssertEqual(snapshot.channel(id: "feishu")?.primaryAccount?.accountID, "default")
        XCTAssertEqual(snapshot.channel(id: "feishu")?.lastError, "waiting for reconnect")
        XCTAssertEqual(snapshot.pluginInspection(id: "openclaw-lark")?.isActive, true)
    }

    func testFetchSnapshotCapturesPluginInspectionAndCommandFailures() {
        let runner = makeRunner([
            ChannelSnapshotMockCommand("/opt/homebrew/bin/openclaw", ["channels", "status", "--json"]): .init(
                output: "status failed",
                exitStatus: 1,
                timedOut: false
            ),
            ChannelSnapshotMockCommand("/opt/homebrew/bin/openclaw", ["channels", "list", "--json"]): .init(
                output: "",
                exitStatus: 0,
                timedOut: true
            ),
            ChannelSnapshotMockCommand("/opt/homebrew/bin/openclaw", ["plugins", "inspect", "openclaw-weixin", "--json"]): .init(
                output: "Plugin not found: openclaw-weixin",
                exitStatus: 1,
                timedOut: false
            ),
        ])

        let snapshot = OpenClawChannelsSnapshotSupport.fetchSnapshot(
            openClawBinaryPath: "/opt/homebrew/bin/openclaw",
            environment: [:],
            runCommand: runner,
            pluginIDs: ["openclaw-weixin"]
        )

        XCTAssertFalse(snapshot.hasUsableChannelData)
        XCTAssertEqual(snapshot.statusFailureDetail, "status failed")
        XCTAssertEqual(snapshot.listFailureDetail, "openclaw channels list --json 未在规定时间内完成。")
        XCTAssertEqual(snapshot.pluginInspection(id: "openclaw-weixin")?.exists, false)
        XCTAssertEqual(
            snapshot.pluginInspection(id: "openclaw-weixin")?.failureDetail,
            "Plugin not found: openclaw-weixin"
        )
    }

    private func makeRunner(
        _ responses: [ChannelSnapshotMockCommand: OpenClawChannelCommandResult]
    ) -> OpenClawChannelsSnapshotSupport.CommandRunner {
        { executablePath, arguments, _, _ in
            responses[ChannelSnapshotMockCommand(executablePath, arguments)]
                ?? .init(output: "", exitStatus: 1, timedOut: false)
        }
    }
}

private struct ChannelSnapshotMockCommand: Hashable {
    let executablePath: String
    let arguments: [String]

    init(_ executablePath: String, _ arguments: [String]) {
        self.executablePath = executablePath
        self.arguments = arguments
    }
}
