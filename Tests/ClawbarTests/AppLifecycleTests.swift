import XCTest
@testable import ClawbarKit

final class AppLifecycleTests: XCTestCase {
    func testDetectReturnsMenuBarModeByDefault() {
        let mode = AppMode.detect(in: [:])

        XCTAssertEqual(mode, .menuBar)
    }

    func testDetectReturnsSmokeTestModeWhenFlagIsSet() {
        let mode = AppMode.detect(in: ["CLAWBAR_SMOKE_TEST": "1"])

        XCTAssertEqual(mode, .smokeTest)
    }

    func testDetectReturnsUITestModeWhenFlagIsSet() {
        let mode = AppMode.detect(in: ["CLAWBAR_UI_TEST": "1"])

        XCTAssertEqual(mode, .uiTest)
    }

    func testModePropertiesMatchExpectedBehavior() {
        XCTAssertEqual(AppMode.menuBar.activationPolicy, .accessory)
        XCTAssertFalse(AppMode.menuBar.showsSmokeTestWindow)
        XCTAssertFalse(AppMode.menuBar.shouldActivateOnLaunch)

        XCTAssertEqual(AppMode.smokeTest.activationPolicy, .regular)
        XCTAssertTrue(AppMode.smokeTest.showsSmokeTestWindow)
        XCTAssertTrue(AppMode.smokeTest.shouldActivateOnLaunch)

        XCTAssertEqual(AppMode.uiTest.activationPolicy, .regular)
        XCTAssertFalse(AppMode.uiTest.showsSmokeTestWindow)
        XCTAssertTrue(AppMode.uiTest.shouldActivateOnLaunch)
    }

    func testLifecycleControllerReturnsMenuBarLaunchPlanByDefault() {
        let controller = AppLifecycleController()
        let plan = controller.launchPlan(in: [:])

        XCTAssertEqual(controller.mode(in: [:]), .menuBar)
        XCTAssertEqual(plan, ApplicationLaunchPlan(activationPolicy: .accessory, activatesApp: false, showsSmokeTestWindow: false))
    }

    func testLifecycleControllerReturnsSmokeTestLaunchPlanWhenFlagIsSet() {
        let controller = AppLifecycleController()
        let environment = ["CLAWBAR_SMOKE_TEST": "1"]
        let plan = controller.launchPlan(in: environment)

        XCTAssertEqual(controller.mode(in: environment), .smokeTest)
        XCTAssertEqual(plan, ApplicationLaunchPlan(activationPolicy: .regular, activatesApp: true, showsSmokeTestWindow: true))
    }

    func testLifecycleControllerReturnsUITestLaunchPlanWhenFlagIsSet() {
        let controller = AppLifecycleController()
        let environment = ["CLAWBAR_UI_TEST": "1"]
        let plan = controller.launchPlan(in: environment)

        XCTAssertEqual(controller.mode(in: environment), .uiTest)
        XCTAssertEqual(plan, ApplicationLaunchPlan(activationPolicy: .regular, activatesApp: true, showsSmokeTestWindow: false))
    }
}
