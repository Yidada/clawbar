import Foundation

@MainActor
final class HermesRuntime: AgentRuntime,
    AgentInstallable,
    AgentProviderCapable,
    AgentMessagingGatewayCapable,
    AgentTUILaunchable
{
    static let shared = HermesRuntime(
        installer: .shared,
        providerManager: .shared,
        gatewayManager: .shared,
        tuiManager: .shared
    )

    let installer: HermesInstaller
    let providerManager: HermesProviderManager
    let gatewayManager: HermesGatewayManager
    let tuiManager: HermesTUIManager

    init(
        installer: HermesInstaller = .shared,
        providerManager: HermesProviderManager = .shared,
        gatewayManager: HermesGatewayManager = .shared,
        tuiManager: HermesTUIManager = .shared
    ) {
        self.installer = installer
        self.providerManager = providerManager
        self.gatewayManager = gatewayManager
        self.tuiManager = tuiManager
    }

    var identifier: AgentRuntimeID { .hermes }
    var displayName: String { AgentRuntimeID.hermes.displayName }

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
        HermesProviderManager.supportedProviders
    }

    func refresh(force: Bool) async {
        await installer.refreshStatus(force: force)
        if installer.isInstalled {
            await gatewayManager.refreshStatus()
        }
    }

    func install() async {
        await installer.startInstallIfNeeded()
    }

    func uninstall() async {
        await installer.startUninstallIfNeeded()
    }

    func launchTUI() {
        tuiManager.launchTUI()
    }
}
