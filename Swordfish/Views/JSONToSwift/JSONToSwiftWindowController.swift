import AppKit
import SwiftUI

@MainActor
final class JSONToSwiftWindowController: NSObject {
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: JSONToSwiftView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "JSON to Struct"
        window.setContentSize(NSSize(width: 960, height: 640))
        window.contentMinSize = NSSize(width: 680, height: 420)
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
