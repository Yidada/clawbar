import AppKit
import ClawbarKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let lifecycleController: AppLifecycleController
    private let environmentProvider: () -> [String: String]
    private let setActivationPolicy: (AppActivationPolicy) -> Void
    private let showSmokeTestWindow: () -> Void
    private let activateApplication: (Bool) -> Void
    private let refreshInstallerStatus: @MainActor () -> Void

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
        self.refreshInstallerStatus = {
            OpenClawInstaller.shared.refreshInstallationStatus(force: true)
        }
        super.init()
    }

    init(
        lifecycleController: AppLifecycleController,
        environmentProvider: @escaping () -> [String: String],
        setActivationPolicy: @escaping (AppActivationPolicy) -> Void,
        showSmokeTestWindow: @escaping () -> Void,
        activateApplication: @escaping (Bool) -> Void,
        refreshInstallerStatus: @escaping @MainActor () -> Void
    ) {
        self.lifecycleController = lifecycleController
        self.environmentProvider = environmentProvider
        self.setActivationPolicy = setActivationPolicy
        self.showSmokeTestWindow = showSmokeTestWindow
        self.activateApplication = activateApplication
        self.refreshInstallerStatus = refreshInstallerStatus
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = environmentProvider()
        let mode = lifecycleController.mode(in: environment)
        let launchPlan = lifecycleController.launchPlan(in: environment)

        ClawbarEventLogger.emit(
            "app.launch",
            fields: [
                "mode": mode.rawValue,
                "activationPolicy": launchPlan.activationPolicy.rawValue,
                "activatesApp": launchPlan.activatesApp ? "true" : "false",
                "showsSmokeTestWindow": launchPlan.showsSmokeTestWindow ? "true" : "false",
            ]
        )

        setActivationPolicy(launchPlan.activationPolicy)

        if launchPlan.showsSmokeTestWindow {
            showSmokeTestWindow()
        }

        if launchPlan.activatesApp {
            activateApplication(true)
        }

        refreshInstallerStatus()
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
