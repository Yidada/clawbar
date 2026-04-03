import AppKit
import ClawbarKit
import SwiftUI

@MainActor
final class SmokeTestWindowPresenter {
    static let shared = SmokeTestWindowPresenter()

    private var window: NSWindow?
    private let configuration: AppConfiguration

    init(configuration: AppConfiguration = .makeDefault()) {
        self.configuration = configuration
    }

    func showWindow() {
        let contentView = SmokeTestView(
            windowTitle: configuration.smokeTestWindowTitle,
            model: .makeDefault(configuration: configuration)
        )

        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = configuration.smokeTestWindowTitle
        window.setContentSize(NSSize(width: 360, height: 220))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}
