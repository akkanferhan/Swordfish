import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject {
    private var window: NSWindow?
    private let env: AppEnvironment

    init(env: AppEnvironment) {
        self.env = env
    }

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(
            rootView: SettingsView()
                .environmentObject(env.loginItem)
                .environmentObject(env.lidSleep)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Settings")
        window.setContentSize(NSSize(width: 520, height: 540))
        window.contentMinSize = NSSize(width: 500, height: 460)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
