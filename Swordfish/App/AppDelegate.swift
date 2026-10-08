import SwiftUI
import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private(set) var env: AppEnvironment!
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()
    private lazy var jsonViewer = JSONViewerWindowController(devTools: env.devTools)
    private lazy var jsonToSwift = JSONToSwiftWindowController()
    private lazy var settings = SettingsWindowController(env: env)
    private lazy var devUtilities = DevUtilitiesWindowController(devTools: env.devTools)
    private lazy var simulatorLogs = SimulatorLogsWindowController()
    private lazy var signing = SigningWindowController()
    private var quickPaste: QuickPasteController?
    private lazy var userDefaultsEditor = UserDefaultsEditorWindowController()
    private lazy var designOverlay = DesignOverlayController()
    private lazy var crashSymbolicator = CrashSymbolicatorWindowController()
    private var networkLabController: NetworkLabWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        env = AppEnvironment.makeDefault()
        setupStatusItem()
        setupPopover()
        env.alerts.onOpen = { [weak self] in self?.showPopover() }
        let quickPaste = QuickPasteController(clipboard: env.clipboard)
        quickPaste.start()
        self.quickPaste = quickPaste
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Don't leave the Mac unable to sleep after Swordfish is gone.
        env?.lidSleep.disableOnQuit()
        // …or pointing at a proxy that no longer exists.
        networkLabController?.shutdown()
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

        // The optional metric next to the icon follows every monitor tick
        // and the Settings → Monitoring picker.
        env.systemMonitor.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMetricTitle() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMetricTitle() }
            .store(in: &cancellables)
    }

    private func updateMetricTitle() {
        guard let button = statusItem?.button else { return }
        let text = MenuBarMetric.current.text(from: env.systemMonitor) ?? ""
        guard button.title != text else { return }
        button.imagePosition = text.isEmpty ? .imageOnly : .imageLeading
        button.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .baselineOffset: 0.5,
        ])
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
            .environmentObject(env.lidSleep)
            .environmentObject(env.clipboard)
            .environmentObject(env.devTools)
            .environmentObject(env.loginItem)
            .environmentObject(env.alerts)
            .environmentObject(env.builds)
            .environmentObject(env.appStoreConnect)
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

    func openJSONViewer() {
        popover.performClose(nil)
        jsonViewer.show()
    }

    func openJSONToSwift() {
        popover.performClose(nil)
        jsonToSwift.show()
    }

    func openSettings() {
        popover.performClose(nil)
        settings.show()
    }

    func openDevUtilities() {
        popover.performClose(nil)
        devUtilities.show()
    }

    func openSimulatorLogs() {
        popover.performClose(nil)
        simulatorLogs.show()
    }

    func openSigning() {
        popover.performClose(nil)
        signing.show()
    }

    func openUserDefaultsEditor(udid: String, app: InstalledApp) {
        popover.performClose(nil)
        userDefaultsEditor.show(udid: udid, app: app)
    }

    func openDesignOverlay() {
        popover.performClose(nil)
        designOverlay.show()
    }

    func openCrashSymbolicator() {
        popover.performClose(nil)
        crashSymbolicator.show()
    }

    func openNetworkLab() {
        popover.performClose(nil)
        let controller = networkLabController ?? NetworkLabWindowController()
        networkLabController = controller
        controller.show()
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
    func openJSONViewer() { delegate.openJSONViewer() }
    func openJSONToSwift() { delegate.openJSONToSwift() }
    func openSettings() { delegate.openSettings() }
    func openDevUtilities() { delegate.openDevUtilities() }
    func openSimulatorLogs() { delegate.openSimulatorLogs() }
    func openSigning() { delegate.openSigning() }
    func openUserDefaultsEditor(udid: String, app: InstalledApp) { delegate.openUserDefaultsEditor(udid: udid, app: app) }
    func openDesignOverlay() { delegate.openDesignOverlay() }
    func openCrashSymbolicator() { delegate.openCrashSymbolicator() }
    func openNetworkLab() { delegate.openNetworkLab() }
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
