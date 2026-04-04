import SwiftUI
import ClawbarKit

private enum ApplicationManagementSection: String, CaseIterable, Identifiable {
    case provider
    case gateway
    case channels

    var id: String { rawValue }
}

struct ApplicationManagementView: View {
    let configuration: AppConfiguration
    @ObservedObject var gatewayManager: OpenClawGatewayManager
    @State private var selectedSection: ApplicationManagementSection = .provider

    var body: some View {
        TabView(selection: $selectedSection) {
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
