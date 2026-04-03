import XCTest
@testable import ClawbarKit

final class MenuContentModelTests: XCTestCase {
    func testMakeDefaultUsesConfigurationValues() {
        let configuration = AppConfiguration(
            appName: "Test",
            menuBarTitle: "Bar",
            systemImageName: "star",
            helloTitle: "Hi",
            helloSubtitle: "Subtitle",
            installLabel: "Install OpenClaw",
            quitLabel: "Exit",
            smokeTestEnvironmentVariable: "SMOKE",
            smokeTestWindowTitle: "Smoke",
            menuWidth: 320
        )

        let model = MenuContentModel.makeDefault(configuration: configuration)

        XCTAssertEqual(model.title, "Hi")
        XCTAssertEqual(model.subtitle, "Subtitle")
        XCTAssertEqual(model.installButtonTitle, "Install OpenClaw")
        XCTAssertEqual(model.quitButtonTitle, "Exit")
        XCTAssertEqual(model.width, 320)
    }

    func testAccessibilityIdentifierUsesStablePrefix() {
        let model = MenuContentModel.makeDefault()

        XCTAssertEqual(model.accessibilityIdentifier(for: .title), "clawbar.menu.title")
        XCTAssertEqual(model.accessibilityIdentifier(for: .subtitle), "clawbar.menu.subtitle")
        XCTAssertEqual(model.accessibilityIdentifier(for: .installButton), "clawbar.menu.installButton")
        XCTAssertEqual(model.accessibilityIdentifier(for: .openClawSection), "clawbar.menu.openClawSection")
        XCTAssertEqual(model.accessibilityIdentifier(for: .openClawTitle), "clawbar.menu.openClawTitle")
        XCTAssertEqual(model.accessibilityIdentifier(for: .openClawBinaryPath), "clawbar.menu.openClawBinaryPath")
        XCTAssertEqual(model.accessibilityIdentifier(for: .openClawDetail), "clawbar.menu.openClawDetail")
        XCTAssertEqual(model.accessibilityIdentifier(for: .openClawExcerpt), "clawbar.menu.openClawExcerpt")
        XCTAssertEqual(model.accessibilityIdentifier(for: .quitButton), "clawbar.menu.quitButton")
    }
}
