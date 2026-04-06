import XCTest
@testable import ClawbarKit

final class MenuContentModelTests: XCTestCase {
    func testMakeDefaultUsesConfigurationValues() {
        let configuration = AppConfiguration(
            appName: "Test",
            menuBarTitle: "Bar",
            systemImageName: "star",
            menuInstalledTitle: "Installed",
            menuLoadingSubtitle: "Loading",
            menuMissingTitle: "Missing",
            menuMissingSubtitle: "Missing subtitle",
            menuRefreshingStatusLabel: "Refreshing",
            installLabel: "Install OpenClaw",
            uninstallLabel: "Uninstall OpenClaw",
            tuiDebugLabel: "Launch TUI",
            applicationLabel: "Manage App",
            applicationWindowTitle: "App Window",
            providerLabel: "Providers",
            providerWindowTitle: "Provider Window",
            gatewayLabel: "Gateway",
            gatewayWindowTitle: "Gateway Window",
            channelsLabel: "Channels",
            channelsWindowTitle: "Channels Window",
            quitLabel: "Exit",
            smokeTestEnvironmentVariable: "SMOKE",
            smokeTestWindowTitle: "Smoke",
            menuWidth: 320
        )

        let model = MenuContentModel.makeDefault(configuration: configuration)

        XCTAssertEqual(model.installedTitle, "Installed")
        XCTAssertEqual(model.loadingSubtitle, "Loading")
        XCTAssertEqual(model.missingTitle, "Missing")
        XCTAssertEqual(model.missingSubtitle, "Missing subtitle")
        XCTAssertEqual(model.refreshingStatusLabel, "Refreshing")
        XCTAssertEqual(model.installButtonTitle, "Install OpenClaw")
        XCTAssertEqual(model.uninstallButtonTitle, "Uninstall OpenClaw")
        XCTAssertEqual(model.tuiDebugButtonTitle, "Launch TUI")
        XCTAssertEqual(model.managementButtonTitle, "Manage App")
        XCTAssertEqual(model.quitButtonTitle, "Exit")
        XCTAssertEqual(model.width, 320)
    }

    func testAccessibilityIdentifierUsesStablePrefix() {
        let model = MenuContentModel.makeDefault()

        XCTAssertEqual(model.accessibilityIdentifier(for: .headerTitle), "clawbar.menu.headerTitle")
        XCTAssertEqual(model.accessibilityIdentifier(for: .headerSubtitle), "clawbar.menu.headerSubtitle")
        XCTAssertEqual(model.accessibilityIdentifier(for: .headerMetadata), "clawbar.menu.headerMetadata")
        XCTAssertEqual(model.accessibilityIdentifier(for: .binaryPath), "clawbar.menu.binaryPath")
        XCTAssertEqual(model.accessibilityIdentifier(for: .providerRow), "clawbar.menu.providerRow")
        XCTAssertEqual(model.accessibilityIdentifier(for: .gatewayRow), "clawbar.menu.gatewayRow")
        XCTAssertEqual(model.accessibilityIdentifier(for: .channelRow), "clawbar.menu.channelRow")
        XCTAssertEqual(model.accessibilityIdentifier(for: .installButton), "clawbar.menu.installButton")
        XCTAssertEqual(model.accessibilityIdentifier(for: .uninstallButton), "clawbar.menu.uninstallButton")
        XCTAssertEqual(model.accessibilityIdentifier(for: .tuiDebugButton), "clawbar.menu.tuiDebugButton")
        XCTAssertEqual(model.accessibilityIdentifier(for: .managementButton), "clawbar.menu.managementButton")
        XCTAssertEqual(model.accessibilityIdentifier(for: .quitButton), "clawbar.menu.quitButton")
    }
}
