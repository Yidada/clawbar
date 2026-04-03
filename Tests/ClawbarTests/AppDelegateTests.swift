import AppKit
import XCTest
@testable import Clawbar
@testable import ClawbarKit

@MainActor
final class AppDelegateTests: XCTestCase {
    func testAppKitActivationPolicyMapsAccessory() {
        XCTAssertEqual(appKitActivationPolicy(for: .accessory), .accessory)
    }

    func testAppKitActivationPolicyMapsRegular() {
        XCTAssertEqual(appKitActivationPolicy(for: .regular), .regular)
    }

    func testApplicationDidFinishLaunchingAppliesMenuBarLaunchPlan() {
        var appliedPolicies: [AppActivationPolicy] = []
        var smokeWindowShown = false
        var activationRequests: [Bool] = []
        let delegate = AppDelegate(
            lifecycleController: AppLifecycleController(),
            environmentProvider: { [:] },
            setActivationPolicy: { appliedPolicies.append($0) },
            showSmokeTestWindow: { smokeWindowShown = true },
            activateApplication: { activationRequests.append($0) }
        )

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        XCTAssertEqual(appliedPolicies, [.accessory])
        XCTAssertFalse(smokeWindowShown)
        XCTAssertTrue(activationRequests.isEmpty)
    }

    func testApplicationDidFinishLaunchingActivatesAppInSmokeTestMode() {
        var appliedPolicies: [AppActivationPolicy] = []
        var smokeWindowShown = false
        var activationRequests: [Bool] = []
        let delegate = AppDelegate(
            lifecycleController: AppLifecycleController(),
            environmentProvider: { ["CLAWBAR_SMOKE_TEST": "1"] },
            setActivationPolicy: { appliedPolicies.append($0) },
            showSmokeTestWindow: { smokeWindowShown = true },
            activateApplication: { activationRequests.append($0) }
        )

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        XCTAssertEqual(appliedPolicies, [.regular])
        XCTAssertTrue(smokeWindowShown)
        XCTAssertEqual(activationRequests, [true])
    }
}
