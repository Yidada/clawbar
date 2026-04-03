import SwiftUI
import ClawbarKit

@main
struct ClawbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let configuration = AppConfiguration.makeDefault()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: .makeDefault(configuration: configuration))
        } label: {
            Label(configuration.menuBarTitle, systemImage: configuration.systemImageName)
                .labelStyle(.iconOnly)
                .accessibilityLabel(Text(configuration.menuBarTitle))
        }
        .menuBarExtraStyle(.menu)
    }
}
