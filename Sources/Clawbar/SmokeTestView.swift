import SwiftUI
import ClawbarKit

struct SmokeTestView: View {
    let windowTitle: String
    let model: MenuContentModel
    @ObservedObject var installer: OpenClawInstaller
    @ObservedObject var gatewayManager: OpenClawGatewayManager
    @ObservedObject var tuiManager: OpenClawTUIManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(windowTitle)
                .font(.title3)
                .fontWeight(.semibold)

            Text("This window only appears in smoke test mode so the harness can capture a deterministic artifact.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            MenuContentView(
                model: model,
                installer: installer,
                gatewayManager: gatewayManager,
                tuiManager: tuiManager
            )
        }
        .padding(20)
        .frame(width: 360)
    }
}
