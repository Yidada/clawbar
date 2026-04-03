import SwiftUI
import ClawbarKit

@main
struct ClawbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let configuration = AppConfiguration.makeDefault()

    var body: some Scene {
        MenuBarExtra(configuration.menuBarTitle, systemImage: configuration.systemImageName) {
            MenuContentView(model: .makeDefault(configuration: configuration))
        }
        .menuBarExtraStyle(.menu)
    }
}
