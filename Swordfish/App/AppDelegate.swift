import SwiftUI
import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private(set) var env: AppEnvironment!
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        env = AppEnvironment.makeDefault()
        setupStatusItem()
        setupPopover()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp])
        }
        updateIcon()

        env.caffeine.$isEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let name = env.caffeine.isEnabled ? "cup.and.saucer.fill" : "gauge.medium"
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: "Swordfish") {
            image.isTemplate = true
            button.image = image
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 440, height: 580)
        popover.behavior = .transient
        popover.animates = true
        let root = PopoverRootView()
            .environmentObject(env)
            .environmentObject(env.systemMonitor)
            .environmentObject(env.displayController)
            .environmentObject(env.caffeine)
            .environmentObject(env.loginItem)
            .environment(\.popoverController, PopoverController(delegate: self))
        popover.contentViewController = NSHostingController(rootView: root)
        self.popover = popover
    }

    @objc func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closePopover() {
        popover.performClose(nil)
    }

    /// Temporarily suspends the popover's auto-close behavior (for modal
    /// interactions like NSColorSampler). Returns a token to restore it.
    func suspendAutoClose() -> PopoverBehaviorGuard {
        let prior = popover.behavior
        popover.behavior = .applicationDefined
        return PopoverBehaviorGuard(delegate: self, previous: prior)
    }

    fileprivate func restoreBehavior(_ behavior: NSPopover.Behavior) {
        popover.behavior = behavior
    }
}

// MARK: - PopoverController facade exposed to views

@MainActor
struct PopoverController {
    let delegate: AppDelegate

    func showPopover() { delegate.showPopover() }
    func suspendAutoClose() -> PopoverBehaviorGuard { delegate.suspendAutoClose() }
}

@MainActor
final class PopoverBehaviorGuard {
    private weak var delegate: AppDelegate?
    private let previous: NSPopover.Behavior
    private var released = false

    init(delegate: AppDelegate, previous: NSPopover.Behavior) {
        self.delegate = delegate
        self.previous = previous
    }

    func release() {
        guard !released else { return }
        released = true
        delegate?.restoreBehavior(previous)
    }
}

// MARK: - Environment key

private struct PopoverControllerKey: EnvironmentKey {
    static let defaultValue: PopoverController? = nil
}

extension EnvironmentValues {
    var popoverController: PopoverController? {
        get { self[PopoverControllerKey.self] }
        set { self[PopoverControllerKey.self] = newValue }
    }
}
