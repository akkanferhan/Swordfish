import AppKit
import SwiftUI

@MainActor
final class SimulatorLogsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let logs = SimulatorLogService()

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: SimulatorLogsView().environmentObject(logs))
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Simulator Logs")
        window.setContentSize(NSSize(width: 1000, height: 640))
        window.contentMinSize = NSSize(width: 760, height: 360)
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Don't keep a `log stream` process running behind a closed window.
    func windowWillClose(_ notification: Notification) {
        logs.stop()
    }
}
