import Foundation
import XCTest
@testable import Clawbar

@MainActor
final class OpenClawFeishuChannelManagerTests: XCTestCase {
    func testRefreshStatusReturnsPreflightWhenOpenClawMissing() async {
        let runner = RecordingCommandRunner([
            MockCommand("/bin/zsh", ["-lc", "command -v openclaw"]): [.result(.init(output: "", exitStatus: 1, timedOut: false))],
            MockCommand("/bin/zsh", ["-lc", "command -v npx"]): [.result(.init(output: "/opt/homebrew/bin/npx\n", exitStatus: 0, timedOut: false))],
        ])
        let manager = OpenClawFeishuChannelManager(
            environmentProvider: { [:] },
            runCommand: runner.runner
        )

        manager.refreshStatus()
        await waitUntilIdle(for: manager)

        XCTAssertEqual(manager.snapshot.stage, .preflight)
        XCTAssertEqual(manager.snapshot.summary, "未检测到 OpenClaw")
    }

    func testRefreshStatusDetectsReusableConfiguredBot() async {
        let manager = makeNotInstalledManager(
            extraResponses: [
                MockCommand("/opt/homebrew/bin/openclaw", ["config", "get", "channels.feishu.appId", "--json"]): [.result(.init(output: "\"cli_saved\"\n", exitStatus: 0, timedOut: false))],
                MockCommand("/opt/homebrew/bin/openclaw", ["config", "get", "channels.feishu.appSecret", "--json"]): [.result(.init(output: "{\"source\":\"env\",\"id\":\"FEISHU_APP_SECRET\"}\n", exitStatus: 0, timedOut: false))],
            ]
        )

        manager.refreshStatus()
        await waitUntilIdle(for: manager)

        XCTAssertEqual(manager.snapshot.stage, .install)
        XCTAssertTrue(manager.snapshot.reusableConfiguredBotAvailable)
        XCTAssertEqual(manager.snapshot.setupMode, .reuseConfiguredBot)
    }

    func testReuseConfiguredBotStartsUseExistingInstallCommand() async {
        let capture = StreamingCommandCapture()
        let manager = makeNotInstalledManager(
            extraResponses: [
                MockCommand("/opt/homebrew/bin/openclaw", ["config", "get", "channels.feishu.appId", "--json"]): [.result(.init(output: "\"cli_saved\"\n", exitStatus: 0, timedOut: false))],
                MockCommand("/opt/homebrew/bin/openclaw", ["config", "get", "channels.feishu.appSecret", "--json"]): [.result(.init(output: "\"secret\"\n", exitStatus: 0, timedOut: false))],
            ],
            makeStreamingProcess: capture.factory
        )

        manager.refreshStatus()
        await waitUntilIdle(for: manager)
        manager.enable()

        XCTAssertEqual(capture.command, "npx -y @larksuite/openclaw-lark install --use-existing")
        XCTAssertTrue(manager.lastCommandOutput.contains("--use-existing"))
    }

    func testProvidedCredentialsInstallUsesAppCommandAndRedactsSecret() async {
        let capture = StreamingCommandCapture()
        let manager = makeNotInstalledManager(makeStreamingProcess: capture.factory)

        manager.refreshStatus()
        await waitUntilIdle(for: manager)
        manager.selectSetupMode(.useProvidedCredentials)
        manager.enable(using: FeishuAppCredentials(appID: "cli_test", appSecret: "super-secret"))

        XCTAssertEqual(capture.command, "npx -y @larksuite/openclaw-lark install --app 'cli_test:super-secret'")
        XCTAssertTrue(manager.lastCommandOutput.contains("cli_test:<redacted>"))
        XCTAssertFalse(manager.lastCommandOutput.contains("super-secret"))
    }

    func testQRCodeFlowPublishesQRPayload() async {
        let registration = SequencedRegistrationTransport([
            .json(#"{"supported_auth_methods":["client_secret"]}"#),
            .json(#"{"device_code":"dev-1","verification_uri_complete":"https://open.feishu.cn/page/cli?user_code=ABCD-EFGH","expire_in":600,"interval":1}"#),
            .json(#"{"error":"authorization_pending"}"#),
        ])

        let manager = makeNotInstalledManager(
            registrationClient: registration.client,
            sleep: fastSleep
        )

        manager.refreshStatus()
        await waitUntilIdle(for: manager)
        manager.enable()
        await waitUntil(
            timeoutNanoseconds: 1_000_000_000,
            condition: { manager.snapshot.qrCodeURL != nil }
        )

        XCTAssertEqual(manager.snapshot.qrCodeURL, "https://open.feishu.cn/page/cli?user_code=ABCD-EFGH")
        XCTAssertEqual(manager.snapshot.browserURL, "https://open.feishu.cn/page/cli?user_code=ABCD-EFGH")
        XCTAssertTrue(manager.isOnboardingActive)
    }

    func testQRCodeSuccessWritesDomainAndOwnerDefaultsBeforeEnable() async {
        let runner = RecordingCommandRunner([
            MockCommand("/bin/zsh", ["-lc", "command -v openclaw"]): [
                .result(.init(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false)),
                .result(.init(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false)),
                .result(.init(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false)),
                .result(.init(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/bin/zsh", ["-lc", "command -v npx"]): [
                .result(.init(output: "/opt/homebrew/bin/npx\n", exitStatus: 0, timedOut: false)),
                .result(.init(output: "/opt/homebrew/bin/npx\n", exitStatus: 0, timedOut: false)),
                .result(.init(output: "/opt/homebrew/bin/npx\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/bin/bash", ["-lc", "npx -y @larksuite/openclaw-lark info"]): [
                .result(.init(output: notInstalledInfoOutput, exitStatus: 0, timedOut: false)),
                .result(.init(output: installedInfoOutput, exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["config", "get", "channels.feishu.appId", "--json"]): [
                .result(.init(output: "", exitStatus: 1, timedOut: false)),
                .result(.init(output: "\"cli_new\"\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["config", "get", "channels.feishu.appSecret", "--json"]): [
                .result(.init(output: "", exitStatus: 1, timedOut: false)),
                .result(.init(output: "\"***\"\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["config", "get", "channels.feishu.allowFrom", "--json"]): [
                .result(.init(output: "[]\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["config", "get", "channels.feishu.groupPolicy", "--json"]): [
                .result(.init(output: "", exitStatus: 1, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["config", "get", "channels.feishu.groupAllowFrom", "--json"]): [
                .result(.init(output: "[]\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["config", "get", "channels.feishu.groups", "--json"]): [
                .result(.init(output: "{}\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["config", "set", "channels.feishu.domain", "\"lark\"", "--strict-json"]): [
                .result(.init(output: "{ \"ok\": true }\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["config", "set", "channels.feishu.dmPolicy", "\"allowlist\"", "--strict-json"]): [
                .result(.init(output: "{ \"ok\": true }\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["config", "set", "channels.feishu.allowFrom", "[\"ou_owner\"]", "--strict-json"]): [
                .result(.init(output: "{ \"ok\": true }\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["config", "set", "channels.feishu.groupPolicy", "\"allowlist\"", "--strict-json"]): [
                .result(.init(output: "{ \"ok\": true }\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["config", "set", "channels.feishu.groupAllowFrom", "[\"ou_owner\"]", "--strict-json"]): [
                .result(.init(output: "{ \"ok\": true }\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["config", "set", "channels.feishu.groups", "{\"*\":{\"enabled\":true}}", "--strict-json"]): [
                .result(.init(output: "{ \"ok\": true }\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["config", "get", "channels.feishu.enabled", "--json"]): [
                .result(.init(output: "true\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["config", "set", "channels.feishu.enabled", "true", "--strict-json"]): [
                .result(.init(output: "{ \"ok\": true }\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["gateway", "restart", "--json"]): [
                .result(.init(output: "{ \"ok\": true }\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["gateway", "status", "--json", "--no-probe"]): [
                .result(.init(output: runningGatewayStatus, exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/bin/bash", ["-lc", "npx -y @larksuite/openclaw-lark doctor"]): [
                .result(.init(output: "Running diagnostic checks...\n[PASS] All checks passed\n", exitStatus: 0, timedOut: false)),
            ],
        ])

        let registration = SequencedRegistrationTransport([
            .json(#"{"supported_auth_methods":["client_secret"]}"#),
            .json(#"{"device_code":"dev-1","verification_uri_complete":"https://open.feishu.cn/page/cli?user_code=ABCD-EFGH","expire_in":600,"interval":0}"#),
            .json(#"{"client_id":"cli_new","client_secret":"secret_new","user_info":{"open_id":"ou_owner","tenant_brand":"lark"}}"#),
        ])
        let streaming = StreamingCommandCapture(autoTerminateStatus: 0)

        let manager = OpenClawFeishuChannelManager(
            environmentProvider: { [:] },
            runCommand: runner.runner,
            makeStreamingProcess: streaming.factory,
            registrationClient: registration.client,
            sleep: fastSleep
        )

        manager.refreshStatus()
        await waitUntilIdle(for: manager)
        manager.enable()
        await waitUntilIdle(for: manager, timeoutNanoseconds: 2_000_000_000)

        let commands = runner.recordedCommands()
        XCTAssertTrue(commands.contains(MockCommand("/opt/homebrew/bin/openclaw", ["config", "set", "channels.feishu.domain", "\"lark\"", "--strict-json"])))
        XCTAssertTrue(commands.contains(MockCommand("/opt/homebrew/bin/openclaw", ["config", "set", "channels.feishu.dmPolicy", "\"allowlist\"", "--strict-json"])))
        XCTAssertTrue(commands.contains(MockCommand("/opt/homebrew/bin/openclaw", ["config", "set", "channels.feishu.allowFrom", "[\"ou_owner\"]", "--strict-json"])))
        XCTAssertTrue(commands.contains(MockCommand("/opt/homebrew/bin/openclaw", ["config", "set", "channels.feishu.groupAllowFrom", "[\"ou_owner\"]", "--strict-json"])))
        XCTAssertTrue(commands.contains(MockCommand("/opt/homebrew/bin/openclaw", ["config", "set", "channels.feishu.groups", "{\"*\":{\"enabled\":true}}", "--strict-json"])))
        XCTAssertEqual(streaming.command, "npx -y @larksuite/openclaw-lark install --app 'cli_new:secret_new'")
        XCTAssertEqual(manager.snapshot.stage, .ready)
    }

    func testCancelQRCodeFlowClearsBusyState() async {
        let registration = SequencedRegistrationTransport([
            .json(#"{"supported_auth_methods":["client_secret"]}"#),
            .json(#"{"device_code":"dev-1","verification_uri_complete":"https://open.feishu.cn/page/cli?user_code=ABCD-EFGH","expire_in":600,"interval":1}"#),
            .json(#"{"error":"authorization_pending"}"#),
            .json(#"{"error":"authorization_pending"}"#),
        ])

        let manager = makeNotInstalledManager(
            registrationClient: registration.client,
            sleep: { _ in try await Task.sleep(nanoseconds: 50_000_000) }
        )

        manager.refreshStatus()
        await waitUntilIdle(for: manager)
        manager.enable()
        await waitUntil(
            timeoutNanoseconds: 1_000_000_000,
            condition: { manager.snapshot.qrCodeURL != nil }
        )

        manager.cancelActiveSetupFlow()
        await waitUntil(
            timeoutNanoseconds: 1_000_000_000,
            condition: { !manager.isBusy }
        )

        XCTAssertFalse(manager.isBusy)
        XCTAssertTrue(manager.snapshot.summary.contains("已取消"))
    }

    func testDisableWritesConfigWithoutUninstallingPlugin() async {
        let runner = RecordingCommandRunner([
            MockCommand("/bin/zsh", ["-lc", "command -v openclaw"]): [
                .result(.init(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false)),
                .result(.init(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false)),
                .result(.init(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/bin/zsh", ["-lc", "command -v npx"]): [
                .result(.init(output: "/opt/homebrew/bin/npx\n", exitStatus: 0, timedOut: false)),
                .result(.init(output: "/opt/homebrew/bin/npx\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/bin/bash", ["-lc", "npx -y @larksuite/openclaw-lark info"]): [
                .result(.init(output: installedInfoOutput, exitStatus: 0, timedOut: false)),
                .result(.init(output: installedInfoOutput, exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["config", "get", "channels.feishu.appId", "--json"]): [
                .result(.init(output: "\"cli_saved\"\n", exitStatus: 0, timedOut: false)),
                .result(.init(output: "\"cli_saved\"\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["config", "get", "channels.feishu.appSecret", "--json"]): [
                .result(.init(output: "\"***\"\n", exitStatus: 0, timedOut: false)),
                .result(.init(output: "\"***\"\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["config", "get", "channels.feishu.enabled", "--json"]): [
                .result(.init(output: "true\n", exitStatus: 0, timedOut: false)),
                .result(.init(output: "false\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["gateway", "status", "--json", "--no-probe"]): [
                .result(.init(output: runningGatewayStatus, exitStatus: 0, timedOut: false)),
                .result(.init(output: runningGatewayStatus, exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/bin/bash", ["-lc", "npx -y @larksuite/openclaw-lark doctor"]): [
                .result(.init(output: "Running diagnostic checks...\n[PASS] All checks passed\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["config", "set", "channels.feishu.enabled", "false", "--strict-json"]): [
                .result(.init(output: "{ \"ok\": true }\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["gateway", "restart", "--json"]): [
                .result(.init(output: "{ \"ok\": true }\n", exitStatus: 0, timedOut: false)),
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
        XCTAssertFalse(manager.lastCommandOutput.contains("uninstall"))
    }

    private func makeNotInstalledManager(
        extraResponses: [MockCommand: [RecordedResult]] = [:],
        makeStreamingProcess: @escaping OpenClawFeishuChannelManager.StreamingProcessFactory = { _, _, _, _ in
            StubStreamingProcess {}
        },
        registrationClient: FeishuRegistrationClient = SequencedRegistrationTransport([]).client,
        sleep: @escaping OpenClawFeishuChannelManager.SleepHandler = fastSleep
    ) -> OpenClawFeishuChannelManager {
        var baseResponses: [MockCommand: [RecordedResult]] = [
            MockCommand("/bin/zsh", ["-lc", "command -v openclaw"]): [
                .result(.init(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false)),
                .result(.init(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false)),
                .result(.init(output: "/opt/homebrew/bin/openclaw\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/bin/zsh", ["-lc", "command -v npx"]): [
                .result(.init(output: "/opt/homebrew/bin/npx\n", exitStatus: 0, timedOut: false)),
                .result(.init(output: "/opt/homebrew/bin/npx\n", exitStatus: 0, timedOut: false)),
                .result(.init(output: "/opt/homebrew/bin/npx\n", exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/bin/bash", ["-lc", "npx -y @larksuite/openclaw-lark info"]): [
                .result(.init(output: notInstalledInfoOutput, exitStatus: 0, timedOut: false)),
                .result(.init(output: notInstalledInfoOutput, exitStatus: 0, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["config", "get", "channels.feishu.appId", "--json"]): [
                .result(.init(output: "", exitStatus: 1, timedOut: false)),
                .result(.init(output: "", exitStatus: 1, timedOut: false)),
            ],
            MockCommand("/opt/homebrew/bin/openclaw", ["config", "get", "channels.feishu.appSecret", "--json"]): [
                .result(.init(output: "", exitStatus: 1, timedOut: false)),
                .result(.init(output: "", exitStatus: 1, timedOut: false)),
            ],
        ]

        for (command, results) in extraResponses {
            baseResponses[command] = results
        }

        let runner = RecordingCommandRunner(baseResponses)

        return OpenClawFeishuChannelManager(
            environmentProvider: { [:] },
            runCommand: runner.runner,
            makeStreamingProcess: makeStreamingProcess,
            registrationClient: registrationClient,
            sleep: sleep
        )
    }

    private func waitUntilIdle(
        for manager: OpenClawFeishuChannelManager,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async {
        await waitUntil(timeoutNanoseconds: timeoutNanoseconds) {
            !manager.isRefreshing && !manager.isBusy
        }
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while !condition() {
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private let notInstalledInfoOutput = """
feishu-plugin-onboard: 1.0.37
openclaw: OpenClaw 2026.4.2 (d74a122)
openclaw-lark: Not Installed
"""

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

private let fastSleep: OpenClawFeishuChannelManager.SleepHandler = { _ in }

private struct MockCommand: Hashable {
    let executablePath: String
    let arguments: [String]

    init(_ executablePath: String, _ arguments: [String]) {
        self.executablePath = executablePath
        self.arguments = arguments
    }
}

private enum RecordedResult {
    case result(OpenClawChannelCommandResult)
}

private final class RecordingCommandRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var stepsByCommand: [MockCommand: [RecordedResult]]
    private var recorded: [MockCommand] = []

    init(_ stepsByCommand: [MockCommand: [RecordedResult]]) {
        self.stepsByCommand = stepsByCommand
    }

    var runner: OpenClawFeishuChannelManager.CommandRunner {
        { [self] executablePath, arguments, _, _ in
            let command = MockCommand(executablePath, arguments)
            return lock.withLock {
                recorded.append(command)
                guard var steps = stepsByCommand[command], !steps.isEmpty else {
                    return .init(output: "", exitStatus: 1, timedOut: false)
                }
                let next = steps.removeFirst()
                stepsByCommand[command] = steps
                switch next {
                case .result(let result):
                    return result
                }
            }
        }
    }

    func recordedCommands() -> [MockCommand] {
        lock.withLock { recorded }
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

private final class StreamingCommandCapture: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var command: String?
    private let autoTerminateStatus: Int32?

    init(autoTerminateStatus: Int32? = nil) {
        self.autoTerminateStatus = autoTerminateStatus
    }

    var factory: OpenClawFeishuChannelManager.StreamingProcessFactory {
        { [self] command, _, _, terminationHandler in
            lock.withLock {
                self.command = command
            }
            return StubStreamingProcess {
                if let autoTerminateStatus = self.autoTerminateStatus {
                    terminationHandler(autoTerminateStatus)
                }
            }
        }
    }
}

private final class SequencedRegistrationTransport: @unchecked Sendable {
    private let lock = NSLock()
    private var payloads: [String]

    init(_ payloads: [RegistrationPayload]) {
        self.payloads = payloads.map(\.rawValue)
    }

    var client: FeishuRegistrationClient {
        FeishuRegistrationClient { request in
            let payload = self.lock.withLock { () -> String in
                if self.payloads.isEmpty {
                    return #"{"error":"authorization_pending"}"#
                }
                return self.payloads.removeFirst()
            }
            let data = Data(payload.utf8)
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://accounts.feishu.cn")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (data, response)
        }
    }
}

private enum RegistrationPayload {
    case json(String)

    var rawValue: String {
        switch self {
        case .json(let value):
            return value
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
