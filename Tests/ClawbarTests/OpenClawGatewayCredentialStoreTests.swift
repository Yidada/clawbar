import XCTest
@testable import Clawbar

final class OpenClawGatewayCredentialStoreTests: XCTestCase {
    func testEnsureGatewayTokenConfiguredUsesStoredTokenAndSyncsConfig() throws {
        let tempDirectory = try makeTemporaryDirectory()
        let storageDirectory = tempDirectory.appending(path: ".clawbar")
        let configFileURL = tempDirectory.appending(path: ".openclaw").appending(path: "openclaw.json")
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try "stored-token".write(to: storageDirectory.appending(path: "openclaw-gateway-token"), atomically: true, encoding: .utf8)

        let recorder = CommandRecorder()
        let store = OpenClawGatewayCredentialStore(
            environmentProvider: { [:] },
            runCommand: { command, _, _ in
                recorder.commands.append(command)
                if command == "command -v openclaw" {
                    return OpenClawGatewayCommandResult(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false)
                }

                return OpenClawGatewayCommandResult(output: "", exitStatus: 0, timedOut: false)
            },
            tokenGenerator: { "generated-token" },
            storageDirectoryURL: storageDirectory,
            configFileURL: configFileURL
        )

        let token = try store.ensureGatewayTokenConfigured()

        XCTAssertEqual(token, "stored-token")
        XCTAssertEqual(recorder.commands, [
            "command -v openclaw",
            "openclaw config set gateway.mode 'local'",
            "openclaw config set gateway.auth.mode 'token'",
            "openclaw config set gateway.auth.token 'stored-token'",
            "openclaw config set gateway.remote.token 'stored-token'",
        ])
    }

    func testEnsureGatewayTokenConfiguredImportsConfigTokenWhenStoreIsEmpty() throws {
        let tempDirectory = try makeTemporaryDirectory()
        let storageDirectory = tempDirectory.appending(path: ".clawbar")
        let configFileURL = tempDirectory.appending(path: ".openclaw").appending(path: "openclaw.json")

        let recorder = CommandRecorder()
        let store = OpenClawGatewayCredentialStore(
            environmentProvider: { [:] },
            runCommand: { command, _, _ in
                recorder.commands.append(command)
                switch command {
                case "command -v openclaw":
                    return OpenClawGatewayCommandResult(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false)
                case "openclaw config get gateway.auth.token":
                    return OpenClawGatewayCommandResult(output: "config-token\n", exitStatus: 0, timedOut: false)
                default:
                    return OpenClawGatewayCommandResult(output: "", exitStatus: 0, timedOut: false)
                }
            },
            tokenGenerator: { "generated-token" },
            storageDirectoryURL: storageDirectory,
            configFileURL: configFileURL
        )

        let token = try store.ensureGatewayTokenConfigured()

        XCTAssertEqual(token, "config-token")
        XCTAssertEqual(store.storedToken(), "config-token")
        XCTAssertTrue(recorder.commands.contains("openclaw config get gateway.auth.token"))
    }

    func testEnsureGatewayTokenConfiguredGeneratesTokenWhenNothingConfigured() throws {
        let tempDirectory = try makeTemporaryDirectory()
        let storageDirectory = tempDirectory.appending(path: ".clawbar")
        let configFileURL = tempDirectory.appending(path: ".openclaw").appending(path: "openclaw.json")

        let recorder = CommandRecorder()
        let store = OpenClawGatewayCredentialStore(
            environmentProvider: { [:] },
            runCommand: { command, _, _ in
                recorder.commands.append(command)
                switch command {
                case "command -v openclaw":
                    return OpenClawGatewayCommandResult(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false)
                case "openclaw config get gateway.auth.token", "openclaw config get gateway.remote.token":
                    return OpenClawGatewayCommandResult(output: "", exitStatus: 1, timedOut: false)
                default:
                    return OpenClawGatewayCommandResult(output: "", exitStatus: 0, timedOut: false)
                }
            },
            tokenGenerator: { "generated-token" },
            storageDirectoryURL: storageDirectory,
            configFileURL: configFileURL
        )

        let token = try store.ensureGatewayTokenConfigured()

        XCTAssertEqual(token, "generated-token")
        XCTAssertEqual(store.storedToken(), "generated-token")
        XCTAssertTrue(recorder.commands.contains("openclaw config set gateway.auth.token 'generated-token'"))
        XCTAssertTrue(recorder.commands.contains("openclaw config set gateway.remote.token 'generated-token'"))
    }

    func testEnsureGatewayTokenConfiguredSkipsConfigWritesWhenFileAlreadyMatches() throws {
        let tempDirectory = try makeTemporaryDirectory()
        let storageDirectory = tempDirectory.appending(path: ".clawbar")
        let configDirectory = tempDirectory.appending(path: ".openclaw")
        let configFileURL = configDirectory.appending(path: "openclaw.json")
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        try "stored-token".write(to: storageDirectory.appending(path: "openclaw-gateway-token"), atomically: true, encoding: .utf8)
        try """
        {
          "gateway": {
            "mode": "local",
            "auth": {
              "mode": "token",
              "token": "stored-token"
            },
            "remote": {
              "token": "stored-token"
            }
          }
        }
        """.write(to: configFileURL, atomically: true, encoding: .utf8)

        let recorder = CommandRecorder()
        let store = OpenClawGatewayCredentialStore(
            environmentProvider: { [:] },
            runCommand: { command, _, _ in
                recorder.commands.append(command)
                if command == "command -v openclaw" {
                    return OpenClawGatewayCommandResult(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false)
                }

                return OpenClawGatewayCommandResult(output: "", exitStatus: 0, timedOut: false)
            },
            tokenGenerator: { "generated-token" },
            storageDirectoryURL: storageDirectory,
            configFileURL: configFileURL
        )

        let token = try store.ensureGatewayTokenConfigured()

        XCTAssertEqual(token, "stored-token")
        XCTAssertEqual(recorder.commands, ["command -v openclaw"])
    }

    func testEnsureGatewayTokenConfiguredOnlyWritesMismatchedGatewayValues() throws {
        let tempDirectory = try makeTemporaryDirectory()
        let storageDirectory = tempDirectory.appending(path: ".clawbar")
        let configDirectory = tempDirectory.appending(path: ".openclaw")
        let configFileURL = configDirectory.appending(path: "openclaw.json")
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        try "stored-token".write(to: storageDirectory.appending(path: "openclaw-gateway-token"), atomically: true, encoding: .utf8)
        try """
        {
          "gateway": {
            "mode": "local",
            "auth": {
              "mode": "token",
              "token": "old-token"
            },
            "remote": {
              "token": "old-token"
            }
          }
        }
        """.write(to: configFileURL, atomically: true, encoding: .utf8)

        let recorder = CommandRecorder()
        let store = OpenClawGatewayCredentialStore(
            environmentProvider: { [:] },
            runCommand: { command, _, _ in
                recorder.commands.append(command)
                if command == "command -v openclaw" {
                    return OpenClawGatewayCommandResult(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false)
                }

                return OpenClawGatewayCommandResult(output: "", exitStatus: 0, timedOut: false)
            },
            tokenGenerator: { "generated-token" },
            storageDirectoryURL: storageDirectory,
            configFileURL: configFileURL
        )

        let token = try store.ensureGatewayTokenConfigured()

        XCTAssertEqual(token, "stored-token")
        XCTAssertEqual(recorder.commands, [
            "command -v openclaw",
            "openclaw config set gateway.auth.token 'stored-token'",
            "openclaw config set gateway.remote.token 'stored-token'",
        ])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class CommandRecorder: @unchecked Sendable {
    var commands: [String] = []
}
