import SwiftUI
import ClawbarKit

struct MenuContentView: View {
    let model: MenuContentModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.title)
                .font(.headline)
                .accessibilityIdentifier(model.accessibilityIdentifier(for: .title))

            Text(model.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(model.accessibilityIdentifier(for: .subtitle))

            Divider()

            Button(model.quitButtonTitle) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
            .accessibilityIdentifier(model.accessibilityIdentifier(for: .quitButton))
        }
        .padding(12)
        .frame(width: model.width)
    }
}
