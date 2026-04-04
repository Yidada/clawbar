import XCTest
@testable import Clawbar

final class OpenClawTUIManagerTests: XCTestCase {
    func testResolveLaunchCredentialPrefersEnvironmentToken() {
        let credential = OpenClawTUIManager.resolveLaunchCredential(
            environment: [
                "OPENCLAW_GATEWAY_TOKEN": "env-token",
                "OPENCLAW_GATEWAY_PASSWORD": "env-password",
            ],
            launchdEnvironmentLookup: { key in
                switch key {
                case "OPENCLAW_GATEWAY_TOKEN":
                    "launchd-token"
                case "OPENCLAW_GATEWAY_PASSWORD":
                    "launchd-password"
                default:
                    nil
                }
            },
            shellPath: "/bin/zsh",
            shellEnvironmentLookup: { _, _, _ in
                "shell-token"
            }
        )

        XCTAssertEqual(credential?.kind, .token)
        XCTAssertEqual(credential?.value, "env-token")
    }

    func testResolveLaunchCredentialFallsBackToLaunchdPassword() {
        let credential = OpenClawTUIManager.resolveLaunchCredential(
            environment: [:],
            launchdEnvironmentLookup: { key in
                key == "OPENCLAW_GATEWAY_PASSWORD" ? "launchd-password" : nil
            },
            shellPath: "/bin/zsh",
            shellEnvironmentLookup: { _, _, _ in
                nil
            }
        )

        XCTAssertEqual(credential?.kind, .password)
        XCTAssertEqual(credential?.value, "launchd-password")
    }

    func testResolveLaunchCredentialFallsBackToInteractiveShellEnvironment() {
        let credential = OpenClawTUIManager.resolveLaunchCredential(
            environment: [:],
            launchdEnvironmentLookup: { _ in nil },
            shellPath: "/bin/zsh",
            shellEnvironmentLookup: { shellPath, key, environment in
                XCTAssertEqual(shellPath, "/bin/zsh")
                XCTAssertTrue(environment.isEmpty)
                return key == "OPENCLAW_GATEWAY_TOKEN" ? "shell-token" : nil
            }
        )

        XCTAssertEqual(credential?.kind, .token)
        XCTAssertEqual(credential?.value, "shell-token")
    }

    func testMakeLaunchShellCommandPassesTokenBeforeLaunchingTUI() {
        let command = OpenClawTUIManager.makeLaunchShellCommand(
            openClawBinaryAvailable: true,
            credential: OpenClawTUILaunchCredential(kind: .token, value: "secret-token"),
            path: "/opt/homebrew/bin:/usr/bin:/bin"
        )

        XCTAssertTrue(command.contains("export PATH='/opt/homebrew/bin:/usr/bin:/bin'"))
        XCTAssertTrue(command.contains("openclaw tui --token 'secret-token'"))
        XCTAssertTrue(command.contains("exec $SHELL -l"))
    }

    func testMakeLaunchShellCommandPrintsPreflightNoticesBeforeLaunchingTUI() {
        let command = OpenClawTUIManager.makeLaunchShellCommand(
            openClawBinaryAvailable: true,
            credential: OpenClawTUILaunchCredential(kind: .token, value: "secret-token"),
            path: "/opt/homebrew/bin:/usr/bin:/bin",
            notices: ["Clawbar 已自动批准本机 TUI 的 Gateway 权限升级请求。"]
        )

        XCTAssertTrue(command.contains("Clawbar 已自动批准本机 TUI 的 Gateway 权限升级请求。"))
        XCTAssertTrue(command.contains("openclaw tui --token 'secret-token'"))
    }

    func testMakeLaunchShellCommandWithoutCredentialShowsGuidanceAndStillRunsTUI() {
        let command = OpenClawTUIManager.makeLaunchShellCommand(
            openClawBinaryAvailable: true,
            credential: nil,
            path: "/opt/homebrew/bin:/usr/bin:/bin"
        )

        XCTAssertTrue(command.contains("OPENCLAW_GATEWAY_TOKEN"))
        XCTAssertTrue(command.contains("openclaw tui"))
        XCTAssertTrue(command.contains("exec $SHELL -l"))
    }

    func testMakeLaunchShellCommandWithoutBinaryKeepsTerminalOpenForDebugging() {
        let command = OpenClawTUIManager.makeLaunchShellCommand(
            openClawBinaryAvailable: false,
            credential: OpenClawTUILaunchCredential(kind: .token, value: "secret-token"),
            path: "/opt/homebrew/bin:/usr/bin:/bin"
        )

        XCTAssertTrue(command.contains("没有在当前 PATH 里找到 openclaw"))
        XCTAssertFalse(command.contains("openclaw tui"))
        XCTAssertTrue(command.contains("exec $SHELL -l"))
    }

    func testExtractJSONObjectStringIgnoresLeadingNoise() {
        let output = """
        gateway connect failed: pairing required
        {
          "pending": []
        }
        """

        XCTAssertEqual(
            OpenClawTUIManager.extractJSONObjectString(from: output),
            """
            {
              "pending": []
            }
            """
        )
    }

    func testPendingLocalRepairRequestReturnsMatchingCliRepairRequest() {
        let output = """
        gateway connect failed: pairing required
        {
          "pending": [
            {
              "requestId": "req-1",
              "clientId": "cli",
              "clientMode": "cli",
              "role": "operator",
              "isRepair": true
            }
          ]
        }
        """

        let request = OpenClawTUIManager.pendingLocalRepairRequest(from: output)
        XCTAssertEqual(request?.requestId, "req-1")
    }

    func testPendingLocalRepairRequestIgnoresFreshOrNonCliPairingRequests() {
        let output = """
        {
          "pending": [
            {
              "requestId": "req-1",
              "clientId": "mobile",
              "clientMode": "mobile",
              "role": "operator",
              "isRepair": false
            }
          ]
        }
        """

        XCTAssertNil(OpenClawTUIManager.pendingLocalRepairRequest(from: output))
    }

    func testPrepareLocalPairingRepairApprovesMatchingPendingRequest() {
        let result = OpenClawTUIManager.prepareLocalPairingRepair(
            openClawBinaryPath: "/opt/homebrew/bin/openclaw",
            token: "secret-token",
            environment: [:],
            runCommand: { executablePath, arguments, _, _ in
                XCTAssertEqual(executablePath, "/opt/homebrew/bin/openclaw")

                if arguments.starts(with: ["devices", "list"]) {
                    return OpenClawChannelCommandResult(
                        output: """
                        gateway connect failed: pairing required
                        {
                          "pending": [
                            {
                              "requestId": "req-1",
                              "clientId": "cli",
                              "clientMode": "cli",
                              "role": "operator",
                              "isRepair": true
                            }
                          ]
                        }
                        """,
                        exitStatus: 0,
                        timedOut: false
                    )
                }

                XCTAssertEqual(arguments, ["devices", "approve", "req-1", "--json", "--token", "secret-token"])
                return OpenClawChannelCommandResult(
                    output: #"{"ok":true,"message":"approved"}"#,
                    exitStatus: 0,
                    timedOut: false
                )
            }
        )

        XCTAssertEqual(result.state, .approved)
        XCTAssertEqual(result.detail, "approved")
    }

    func testPrepareLocalPairingRepairReturnsFailureWhenApproveFails() {
        let result = OpenClawTUIManager.prepareLocalPairingRepair(
            openClawBinaryPath: "/opt/homebrew/bin/openclaw",
            token: "secret-token",
            environment: [:],
            runCommand: { _, arguments, _, _ in
                if arguments.starts(with: ["devices", "list"]) {
                    return OpenClawChannelCommandResult(
                        output: """
                        {
                          "pending": [
                            {
                              "requestId": "req-1",
                              "clientId": "openclaw-tui",
                              "clientMode": "cli",
                              "role": "operator",
                              "isRepair": true
                            }
                          ]
                        }
                        """,
                        exitStatus: 0,
                        timedOut: false
                    )
                }

                return OpenClawChannelCommandResult(
                    output: #"{"ok":false,"error":"approval failed"}"#,
                    exitStatus: 1,
                    timedOut: false
                )
            }
        )

        XCTAssertEqual(result.state, .failed)
        XCTAssertEqual(result.detail, "approval failed")
    }
}
