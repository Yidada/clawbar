import SwiftUI
import ClawbarKit

enum ClawbarWindow {
    static let openClawInstallID = "openclaw-install"
    static let openClawInstallTitle = "OpenClaw 操作"
    static let applicationManagementID = "application-management"
}

@main
struct ClawbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let configuration = AppConfiguration.makeDefault()
    private let installer = OpenClawInstaller.shared
    private let gatewayManager = OpenClawGatewayManager.shared
    private let tuiManager = OpenClawTUIManager.shared
    private let applicationManagementRouter = ApplicationManagementRouter.shared

    @SceneBuilder
    var body: some Scene {
        menuBarScene
        installScene
        applicationManagementScene
    }

    private var menuBarScene: some Scene {
        MenuBarExtra {
            MenuContentView(
                model: .makeDefault(configuration: configuration),
                installer: installer,
                gatewayManager: gatewayManager,
                tuiManager: tuiManager,
                applicationManagementRouter: applicationManagementRouter
            )
        } label: {
            Image(nsImage: ClawbarMenuBarIcon.templateImage)
                .accessibilityLabel(Text(configuration.menuBarTitle))
        }
        .menuBarExtraStyle(.window)
    }

    private var installScene: some Scene {
        Window(ClawbarWindow.openClawInstallTitle, id: ClawbarWindow.openClawInstallID) {
            OpenClawInstallView(installer: installer)
        }
        .defaultSize(width: 760, height: 520)
    }

    private var applicationManagementScene: some Scene {
        Window(configuration.applicationWindowTitle, id: ClawbarWindow.applicationManagementID) {
            ApplicationManagementView(
                configuration: configuration,
                gatewayManager: gatewayManager,
                router: applicationManagementRouter
            )
        }
        .defaultSize(width: 820, height: 660)
    }
}
