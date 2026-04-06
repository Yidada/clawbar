import SwiftUI
import ClawbarKit

struct ApplicationManagementView: View {
    let configuration: AppConfiguration
    @ObservedObject var gatewayManager: OpenClawGatewayManager
    @ObservedObject var router: ApplicationManagementRouter

    var body: some View {
        TabView(selection: $router.selectedSection) {
            ProviderManagementView()
                .tabItem {
                    Label(configuration.providerLabel, systemImage: "slider.horizontal.3")
                }
                .tag(ApplicationManagementSection.provider)

            GatewayManagementView(manager: gatewayManager)
                .tabItem {
                    Label(configuration.gatewayLabel, systemImage: "server.rack")
                }
                .tag(ApplicationManagementSection.gateway)

            ChannelsManagementView()
                .tabItem {
                    Label(configuration.channelsLabel, systemImage: "bubble.left.and.bubble.right")
                }
                .tag(ApplicationManagementSection.channels)
        }
        .onAppear {
            gatewayManager.refreshStatus()
        }
    }
}
