import XCTest
@testable import ClawbarKit

final class AppConfigurationTests: XCTestCase {
    func testMakeDefaultReturnsExpectedValues() {
        let configuration = AppConfiguration.makeDefault()

        XCTAssertEqual(configuration.appName, "Clawbar")
        XCTAssertEqual(configuration.menuBarTitle, "Clawbar")
        XCTAssertEqual(configuration.systemImageName, "hand.wave.fill")
        XCTAssertEqual(configuration.menuInstalledTitle, "OpenClaw")
        XCTAssertEqual(configuration.menuLoadingSubtitle, "正在读取本机状态…")
        XCTAssertEqual(configuration.menuMissingTitle, "OpenClaw 未安装")
        XCTAssertEqual(configuration.menuMissingSubtitle, "安装后即可在此查看 Ollama、Gateway 和 Channel 摘要。")
        XCTAssertEqual(configuration.installLabel, "安装 OpenClaw")
        XCTAssertEqual(configuration.upgradeLabel, "升级 OpenClaw")
        XCTAssertEqual(configuration.uninstallLabel, "卸载 OpenClaw")
        XCTAssertEqual(configuration.tuiDebugLabel, "启动 TUI")
        XCTAssertEqual(configuration.applicationLabel, "Settings")
        XCTAssertEqual(configuration.applicationWindowTitle, "Settings")
        XCTAssertEqual(configuration.providerLabel, "Ollama / Gemma 4")
        XCTAssertEqual(configuration.providerWindowTitle, "Ollama / Gemma 4")
        XCTAssertEqual(configuration.gatewayLabel, "管理 Gateway")
        XCTAssertEqual(configuration.gatewayWindowTitle, "Gateway 管理")
        XCTAssertEqual(configuration.channelsLabel, "管理 Channels")
        XCTAssertEqual(configuration.channelsWindowTitle, "Channels 管理")
        XCTAssertEqual(configuration.quitLabel, "Quit")
        XCTAssertEqual(configuration.smokeTestEnvironmentVariable, "CLAWBAR_SMOKE_TEST")
        XCTAssertEqual(configuration.smokeTestWindowTitle, "Clawbar Smoke Test")
        XCTAssertEqual(configuration.menuWidth, 360)
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
