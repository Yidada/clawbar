import XCTest
@testable import Clawbar

final class OpenClawGatewayManagerTests: XCTestCase {
    func testMakeStatusSnapshotReturnsRunningStateFromStatusJson() {
        let output = """
        {"service":{"label":"openclaw-gateway","loaded":true,"loadedText":"loaded","notLoadedText":"not loaded","runtime":{"status":"running","pid":4242}}}
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
        XCTAssertFalse(snapshot.serviceLoaded)
    }

    func testParseActionFeedbackReturnsSuccessMessageFromJson() {
        let output = #"{"ok":true,"result":"started","message":"Gateway scheduled for start."}"#

        let feedback = OpenClawGatewayManager.parseActionFeedback(
            OpenClawGatewayCommandResult(output: output, exitStatus: 0, timedOut: false),
            action: .start
        )

        XCTAssertTrue(feedback.isSuccess)
        XCTAssertEqual(feedback.summary, "Gateway scheduled for start.")
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
