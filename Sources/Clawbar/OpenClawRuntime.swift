import Foundation

@MainActor
final class OpenClawRuntime: AgentRuntime,
    AgentInstallable,
    AgentProviderCapable,
    AgentChannelCapable,
    AgentMessagingGatewayCapable,
    AgentTUILaunchable
{
    static let shared = OpenClawRuntime(
        installer: .shared,
        providerManager: .shared,
        gatewayManager: .shared,
        tuiManager: .shared
    )

    let installer: OpenClawInstaller
    let providerManager: OpenClawProviderManager
    let gatewayManager: OpenClawGatewayManager
    let tuiManager: OpenClawTUIManager

    init(
        installer: OpenClawInstaller,
        providerManager: OpenClawProviderManager,
        gatewayManager: OpenClawGatewayManager,
        tuiManager: OpenClawTUIManager
    ) {
        self.installer = installer
        self.providerManager = providerManager
        self.gatewayManager = gatewayManager
        self.tuiManager = tuiManager
    }

    var identifier: AgentRuntimeID { .openClaw }
    var displayName: String { AgentRuntimeID.openClaw.displayName }

    var healthSnapshot: AgentHealthSnapshot? {
        installer.healthSnapshot
    }

    var isInstalled: Bool {
        installer.isInstalled
    }

    var isBusy: Bool {
        installer.isBusy
    }

    var supportedProviders: [ProviderKind] {
        ProviderKind.allCases
    }

    func refresh(force: Bool) async {
        installer.refreshInstallationStatus(force: force)
    }

    func install() async {
        installer.startInstallIfNeeded()
    }

    func uninstall() async {
        installer.startUninstallIfNeeded()
    }

    func launchTUI() {
        tuiManager.launchTUI()
    }
}
