import AppKit
import SwiftUI

@MainActor
final class OpenClawInstallWindowPresenter {
    static let shared = OpenClawInstallWindowPresenter()

    private var window: NSWindow?

    func showWindow(installer: OpenClawInstaller = .shared) {
        let contentView = OpenClawInstallView(installer: installer)
        let hostingController = NSHostingController(rootView: contentView)

        if let window {
            window.contentViewController = hostingController
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(contentViewController: hostingController)
        window.title = "OpenClaw 安装"
        window.setContentSize(NSSize(width: 760, height: 520))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
