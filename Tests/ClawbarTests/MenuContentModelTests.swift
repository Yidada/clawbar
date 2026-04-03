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
            quitLabel: "Exit",
            smokeTestEnvironmentVariable: "SMOKE",
            smokeTestWindowTitle: "Smoke",
            menuWidth: 320
        )

        let model = MenuContentModel.makeDefault(configuration: configuration)

        XCTAssertEqual(model.title, "Hi")
        XCTAssertEqual(model.subtitle, "Subtitle")
        XCTAssertEqual(model.quitButtonTitle, "Exit")
        XCTAssertEqual(model.width, 320)
    }

    func testAccessibilityIdentifierUsesStablePrefix() {
        let model = MenuContentModel.makeDefault()

        XCTAssertEqual(model.accessibilityIdentifier(for: .title), "clawbar.menu.title")
        XCTAssertEqual(model.accessibilityIdentifier(for: .subtitle), "clawbar.menu.subtitle")
        XCTAssertEqual(model.accessibilityIdentifier(for: .quitButton), "clawbar.menu.quitButton")
    }
}
