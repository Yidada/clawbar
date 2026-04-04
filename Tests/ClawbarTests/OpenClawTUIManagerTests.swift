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
}
