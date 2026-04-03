import XCTest
@testable import ClawbarKit

final class AppConfigurationTests: XCTestCase {
    func testMakeDefaultReturnsExpectedValues() {
        let configuration = AppConfiguration.makeDefault()

        XCTAssertEqual(configuration.appName, "Clawbar")
        XCTAssertEqual(configuration.menuBarTitle, "Clawbar")
        XCTAssertEqual(configuration.systemImageName, "hand.wave.fill")
        XCTAssertEqual(configuration.helloTitle, "Hello World")
        XCTAssertEqual(configuration.installLabel, "安装 OpenClaw")
        XCTAssertEqual(configuration.quitLabel, "Quit")
        XCTAssertEqual(configuration.smokeTestEnvironmentVariable, "CLAWBAR_SMOKE_TEST")
        XCTAssertEqual(configuration.smokeTestWindowTitle, "Clawbar Smoke Test")
        XCTAssertEqual(configuration.menuWidth, 320)
    }

    func testIsSmokeTestEnabledReturnsTrueWhenFlagIsSet() {
        let configuration = AppConfiguration.makeDefault()

        XCTAssertTrue(configuration.isSmokeTestEnabled(in: ["CLAWBAR_SMOKE_TEST": "1"]))
    }

    func testIsSmokeTestEnabledReturnsFalseWhenFlagIsMissingOrUnexpected() {
        let configuration = AppConfiguration.makeDefault()

        XCTAssertFalse(configuration.isSmokeTestEnabled(in: [:]))
        XCTAssertFalse(configuration.isSmokeTestEnabled(in: ["CLAWBAR_SMOKE_TEST": "0"]))
    }
}
