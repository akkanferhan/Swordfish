import AppKit
import SwiftUI

@MainActor
final class SigningWindowController: NSObject {
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: SigningView())
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Signing & Profiles")
        window.setContentSize(NSSize(width: 980, height: 620))
        window.contentMinSize = NSSize(width: 760, height: 420)
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
