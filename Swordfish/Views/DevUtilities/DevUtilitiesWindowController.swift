import AppKit
import SwiftUI

@MainActor
final class DevUtilitiesWindowController: NSObject {
    private var window: NSWindow?
    private let devTools: DevToolsState

    init(devTools: DevToolsState) {
        self.devTools = devTools
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: DevUtilitiesView().environmentObject(devTools))
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Dev Utilities")
        window.setContentSize(NSSize(width: 860, height: 560))
        window.contentMinSize = NSSize(width: 680, height: 420)
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
