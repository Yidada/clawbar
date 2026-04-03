import AppKit
import ClawbarKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let lifecycleController: AppLifecycleController
    private let environmentProvider: () -> [String: String]
    private let setActivationPolicy: (AppActivationPolicy) -> Void
    private let showSmokeTestWindow: () -> Void
    private let activateApplication: (Bool) -> Void

    override init() {
        self.lifecycleController = AppLifecycleController()
        self.environmentProvider = { ProcessInfo.processInfo.environment }
        self.setActivationPolicy = { policy in
            NSApp.setActivationPolicy(appKitActivationPolicy(for: policy))
        }
        self.showSmokeTestWindow = {
            SmokeTestWindowPresenter.shared.showWindow()
        }
        self.activateApplication = { ignoringOtherApps in
            NSApp.activate(ignoringOtherApps: ignoringOtherApps)
        }
        super.init()
    }

    init(
        lifecycleController: AppLifecycleController,
        environmentProvider: @escaping () -> [String: String],
        setActivationPolicy: @escaping (AppActivationPolicy) -> Void,
        showSmokeTestWindow: @escaping () -> Void,
        activateApplication: @escaping (Bool) -> Void
    ) {
        self.lifecycleController = lifecycleController
        self.environmentProvider = environmentProvider
        self.setActivationPolicy = setActivationPolicy
        self.showSmokeTestWindow = showSmokeTestWindow
        self.activateApplication = activateApplication
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = environmentProvider()
        let launchPlan = lifecycleController.launchPlan(in: environment)

        setActivationPolicy(launchPlan.activationPolicy)

        if launchPlan.showsSmokeTestWindow {
            showSmokeTestWindow()
        }

        if launchPlan.activatesApp {
            activateApplication(true)
        }
    }
}

func appKitActivationPolicy(for policy: AppActivationPolicy) -> NSApplication.ActivationPolicy {
    switch policy {
    case .accessory:
        .accessory
    case .regular:
        .regular
    }
}
