import AppKit
import SwiftUI

@MainActor
final class JSONViewerWindowController: NSObject {
    private var window: NSWindow?
    private let devTools: DevToolsState

    init(devTools: DevToolsState) {
        self.devTools = devTools
    }

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(
            rootView: JSONViewerView().environmentObject(devTools)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "JSON Viewer"
        window.setContentSize(NSSize(width: 900, height: 640))
        window.contentMinSize = NSSize(width: 640, height: 420)
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.center()

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
