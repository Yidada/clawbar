import XCTest
@testable import Clawbar

final class OpenClawGatewayManagerTests: XCTestCase {
    func testMakeStatusSnapshotReturnsRunningStateFromStatusJson() {
        let output = """
        {"service":{"label":"openclaw-gateway","loaded":true,"loadedText":"loaded","notLoadedText":"not loaded","command":{"sourcePath":"~/Library/LaunchAgents/ai.openclaw.gateway.plist"},"runtime":{"status":"running","pid":4242}}}
        """

        let snapshot = OpenClawGatewayManager.makeStatusSnapshot(
            binaryPath: "/opt/homebrew/bin/openclaw",
            commandResult: OpenClawGatewayCommandResult(
                output: output,
                exitStatus: 0,
                timedOut: false
            )
        )

        XCTAssertEqual(snapshot.state, .running)
        XCTAssertEqual(snapshot.binaryPath, "/opt/homebrew/bin/openclaw")
        XCTAssertEqual(snapshot.pid, 4242)
        XCTAssertEqual(snapshot.runtimeStatus, "running")
        XCTAssertTrue(snapshot.serviceInstalled)
    }

    func testMakeStatusSnapshotReturnsStoppedStateWhenServiceNotLoaded() {
        let output = """
        {"service":{"label":"openclaw-gateway","loaded":false,"loadedText":"loaded","notLoadedText":"service not loaded"}}
        """

        let snapshot = OpenClawGatewayManager.makeStatusSnapshot(
            binaryPath: "/opt/homebrew/bin/openclaw",
            commandResult: OpenClawGatewayCommandResult(
                output: output,
                exitStatus: 0,
                timedOut: false
            )
        )

        XCTAssertEqual(snapshot.state, .stopped)
        XCTAssertEqual(snapshot.detail, "service not loaded")
        XCTAssertTrue(snapshot.serviceInstalled)
        XCTAssertFalse(snapshot.serviceLoaded)
    }

    func testMakeStatusSnapshotTreatsInstalledButStoppedLaunchAgentAsStopped() {
        let output = """
        {"service":{"label":"LaunchAgent","loaded":false,"loadedText":"loaded","notLoadedText":"not loaded","command":{"sourcePath":"~/Library/LaunchAgents/ai.openclaw.gateway.plist"},"runtime":{"status":"unknown","detail":"Bad request. Could not find service ai.openclaw.gateway","missingUnit":true}}}
        """

        let snapshot = OpenClawGatewayManager.makeStatusSnapshot(
            binaryPath: "/opt/homebrew/bin/openclaw",
            commandResult: OpenClawGatewayCommandResult(
                output: output,
                exitStatus: 0,
                timedOut: false
            )
        )

        XCTAssertEqual(snapshot.state, .stopped)
        XCTAssertTrue(snapshot.serviceInstalled)
        XCTAssertTrue(snapshot.missingUnit)
        XCTAssertEqual(snapshot.detail, "Gateway 服务已安装，但当前未加载；通常表示尚未启动，或已经被暂停。")
    }

    func testMakeStatusSnapshotReturnsMissingStateWhenLaunchAgentIsNotInstalled() {
        let output = """
        {"service":{"label":"LaunchAgent","loaded":false,"loadedText":"loaded","notLoadedText":"not loaded","runtime":{"status":"unknown","detail":"Bad request. Could not find service ai.openclaw.gateway","missingUnit":true}}}
        """

        let snapshot = OpenClawGatewayManager.makeStatusSnapshot(
            binaryPath: "/opt/homebrew/bin/openclaw",
            commandResult: OpenClawGatewayCommandResult(
                output: output,
                exitStatus: 0,
                timedOut: false
            )
        )

        XCTAssertEqual(snapshot.state, .missing)
        XCTAssertFalse(snapshot.serviceInstalled)
        XCTAssertTrue(snapshot.missingUnit)
        XCTAssertEqual(snapshot.detail, "Bad request. Could not find service ai.openclaw.gateway")
    }

    func testParseActionFeedbackReturnsSuccessMessageFromJson() {
        let output = #"{"ok":true,"result":"started","message":"Gateway scheduled for start."}"#

        let feedback = OpenClawGatewayManager.parseActionFeedback(
            OpenClawGatewayCommandResult(output: output, exitStatus: 0, timedOut: false),
            action: .start
        )

        XCTAssertTrue(feedback.isSuccess)
        XCTAssertEqual(feedback.summary, "Gateway 已启动。")
        XCTAssertEqual(feedback.detail, "已提交启动请求，Gateway 会很快进入运行状态。")
    }

    func testParseActionFeedbackKeepsBootstrapRepairMessageInDetail() {
        let output =
            #"{"ok":true,"result":"started","message":"Gateway LaunchAgent was installed but not loaded; re-bootstrapped launchd service."}"#

        let feedback = OpenClawGatewayManager.parseActionFeedback(
            OpenClawGatewayCommandResult(output: output, exitStatus: 0, timedOut: false),
            action: .start
        )

        XCTAssertTrue(feedback.isSuccess)
        XCTAssertEqual(feedback.summary, "Gateway 已启动。")
        XCTAssertEqual(feedback.detail, "Gateway LaunchAgent 已安装但未加载，已自动重新注册并拉起服务。")
    }

    func testParseActionFeedbackReturnsFailureDetailFromJson() {
        let output = #"{"ok":false,"error":"Gateway start failed: invalid config"}"#

        let feedback = OpenClawGatewayManager.parseActionFeedback(
            OpenClawGatewayCommandResult(output: output, exitStatus: 1, timedOut: false),
            action: .start
        )

        XCTAssertFalse(feedback.isSuccess)
        XCTAssertEqual(feedback.summary, "Gateway 启动失败")
        XCTAssertEqual(feedback.detail, "Gateway start failed: invalid config")
    }
}
