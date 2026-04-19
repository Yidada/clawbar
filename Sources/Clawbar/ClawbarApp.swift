import SwiftUI
import ClawbarKit

enum ClawbarWindow {
    static let openClawInstallID = "openclaw-install"
    static let openClawInstallTitle = "OpenClaw 操作"
    static let applicationManagementID = "application-management"
    static let hermesManagementID = "hermes-management"
    static let hermesManagementTitle = "Hermes 管理"
}

@main
struct ClawbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let configuration = AppConfiguration.makeDefault()
    private let installer = OpenClawInstaller.shared
    private let gatewayManager = OpenClawGatewayManager.shared
    private let tuiManager = OpenClawTUIManager.shared
    private let applicationManagementRouter = ApplicationManagementRouter.shared
    private let hermesInstaller = HermesInstaller.shared
    private let hermesGatewayManager = HermesGatewayManager.shared
    private let hermesTUIManager = HermesTUIManager.shared

    @SceneBuilder
    var body: some Scene {
        menuBarScene
        installScene
        applicationManagementScene
        hermesManagementScene
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

    private var hermesManagementScene: some Scene {
        Window(ClawbarWindow.hermesManagementTitle, id: ClawbarWindow.hermesManagementID) {
            HermesManagementView(
                installer: hermesInstaller,
                gatewayManager: hermesGatewayManager,
                tuiManager: hermesTUIManager
            )
        }
        .defaultSize(width: 760, height: 640)
    }
}
