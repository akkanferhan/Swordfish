import AppKit
import SwiftUI
import Carbon.HIToolbox
import ApplicationServices

// MARK: - Hotkey presets

/// Selectable global shortcuts for the quick-paste panel. ⇧⌘V is offered but
/// not the default: Xcode, Slack and most editors use it for "Paste and
/// Match Style", which a global hotkey would take over.
enum QuickPasteHotkey: String, CaseIterable, Identifiable {
    case off
    case controlCommandV
    case shiftCommandV
    case optionCommandV
    case shiftCommandC

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off:             return String(localized: "Off")
        case .controlCommandV: return "⌃⌘V"
        case .shiftCommandV:   return "⇧⌘V"
        case .optionCommandV:  return "⌥⌘V"
        case .shiftCommandC:   return "⇧⌘C"
        }
    }

    var keyCode: UInt32? {
        switch self {
        case .off: return nil
        case .shiftCommandC: return UInt32(kVK_ANSI_C)
        default: return UInt32(kVK_ANSI_V)
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .off:             return 0
        case .controlCommandV: return UInt32(controlKey | cmdKey)
        case .shiftCommandV, .shiftCommandC: return UInt32(shiftKey | cmdKey)
        case .optionCommandV:  return UInt32(optionKey | cmdKey)
        }
    }

    static var current: QuickPasteHotkey {
        QuickPasteHotkey(rawValue: UserDefaults.standard.string(forKey: ClipboardSettings.hotkeyKey) ?? "") ?? .controlCommandV
    }
}

// MARK: - Carbon hotkey

/// A system-wide hotkey via Carbon's RegisterEventHotKey — still the only
/// public API that doesn't need Accessibility / Input Monitoring permission.
private final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }
        guard InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec,
                                  Unmanaged.passUnretained(self).toOpaque(), &handlerRef) == noErr else { return nil }
        let id = EventHotKeyID(signature: OSType(0x5357_4648), id: 1) // 'SWFH'
        guard RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr else {
            // deinit still runs for a failed init — clear the ref so it isn't removed twice.
            if let handlerRef { RemoveEventHandler(handlerRef) }
            handlerRef = nil
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

// MARK: - Panel

/// Borderless, non-activating panel: it can take keyboard focus for the
/// search field while the app the user is pasting into stays frontmost.
private final class QuickPastePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Model

@MainActor
final class QuickPasteModel: ObservableObject {
    @Published var query = "" { didSet { selection = 0 } }
    @Published var selection = 0
    let clipboard: ClipboardService

    init(clipboard: ClipboardService) {
        self.clipboard = clipboard
    }

    var entries: [ClipboardItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let pinned = clipboard.items.filter(\.pinned)
        let rest = clipboard.items.filter { !$0.pinned }
        return (pinned + rest).filter {
            q.isEmpty || $0.displayText.localizedCaseInsensitiveContains(q)
                || ($0.sourceApp?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    func move(_ delta: Int) {
        let count = entries.count
        guard count > 0 else { return }
        selection = min(count - 1, max(0, selection + delta))
    }
}

// MARK: - Controller

@MainActor
final class QuickPasteController: NSObject, NSWindowDelegate {
    private let clipboard: ClipboardService
    private lazy var model = QuickPasteModel(clipboard: clipboard)
    private var panel: QuickPastePanel?
    private var hotKey: GlobalHotKey?
    private var registered: QuickPasteHotkey?
    private var keyMonitor: Any?
    private var defaultsObserver: NSObjectProtocol?

    init(clipboard: ClipboardService) {
        self.clipboard = clipboard
        super.init()
    }

    func start() {
        ClipboardSettings.register()
        registerHotKey()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.registerHotKey() }
        }
    }

    private func registerHotKey() {
        let wanted = QuickPasteHotkey.current
        guard wanted != registered else { return }
        hotKey = nil
        registered = wanted
        guard let code = wanted.keyCode else { return }
        hotKey = GlobalHotKey(keyCode: code, modifiers: wanted.modifiers) { [weak self] in
            Task { @MainActor in self?.toggle() }
        }
    }

    // MARK: Accessibility (needed only to send ⌘V into the other app)

    static var canPaste: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: Show / hide

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func show() {
        model.query = ""
        model.selection = 0
        let panel = self.panel ?? makePanel()
        self.panel = panel

        // Upper third of the screen the mouse is on.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                         y: frame.minY + frame.height * 0.62 - size.height / 2))
        }
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        panel?.orderOut(nil)
        removeKeyMonitor()
    }

    private func makePanel() -> QuickPastePanel {
        let panel = QuickPastePanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        let root = QuickPasteView(model: model,
                                  canPaste: { Self.canPaste },
                                  choose: { [weak self] in self?.choose($0) })
        panel.contentView = NSHostingView(rootView: root)
        return panel
    }

    /// Clicking elsewhere closes the panel, like Spotlight.
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel?.isKeyWindow == true else { return event }
            switch Int(event.keyCode) {
            case kVK_Escape:
                self.hide(); return nil
            case kVK_DownArrow:
                self.model.move(1); return nil
            case kVK_UpArrow:
                self.model.move(-1); return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                let entries = self.model.entries
                if entries.indices.contains(self.model.selection) { self.choose(entries[self.model.selection]) }
                return nil
            default:
                // ⌘1…⌘9 picks the n-th entry directly.
                if event.modifierFlags.contains(.command),
                   let digit = event.charactersIgnoringModifiers.flatMap(Int.init), (1...9).contains(digit) {
                    let entries = self.model.entries
                    if entries.indices.contains(digit - 1) { self.choose(entries[digit - 1]) }
                    return nil
                }
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // MARK: Paste

    private func choose(_ item: ClipboardItem) {
        hide()
        clipboard.copyToPasteboard(item)
        guard Self.canPaste else { return }
        // Give the target app a beat to regain key focus, then send ⌘V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let vKey = CGKeyCode(kVK_ANSI_V)
            let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }
}
