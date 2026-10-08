import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings shared by the control window and the overlay panel.
@MainActor
final class DesignOverlayModel: ObservableObject {
    @Published var image: NSImage?
    @Published var imageName = ""
    @Published var opacity: Double = 0.5
    @Published var showImage = true
    @Published var showGrid = false
    @Published var gridSpacing: Double = 8
    @Published var gridColor: Color = .red
    @Published var clickThrough = true
    @Published var isVisible = false
    @Published var frame = NSRect(x: 200, y: 200, width: 393, height: 852)
    @Published var status: String?
}

/// Pixel-comparison overlay: a design export laid semi-transparently over
/// the Simulator window, plus an optional layout grid. The overlay ignores
/// the mouse by default so the app underneath stays usable.
@MainActor
final class DesignOverlayController: NSObject {
    private let model = DesignOverlayModel()
    private var controlWindow: NSWindow?
    private var overlay: NSPanel?
    private var observers: [Any] = []

    func show() {
        if let controlWindow {
            controlWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = DesignOverlayControls(model: model,
                                         chooseImage: { [weak self] in self?.chooseImage() },
                                         snap: { [weak self] in self?.snapToSimulator() },
                                         apply: { [weak self] in self?.applyModel() })
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = String(localized: "Design Overlay")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        controlWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Closing the controls hides the overlay too.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.model.isVisible = false
                self?.applyModel()
            }
        })
    }

    // MARK: Overlay panel

    private func makeOverlay() -> NSPanel {
        let panel = NSPanel(contentRect: model.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: DesignOverlayCanvas(model: model))
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self, weak panel] _ in
            guard let frame = panel?.frame else { return }
            Task { @MainActor in self?.model.frame = frame }
        })
        return panel
    }

    func applyModel() {
        if model.isVisible {
            let panel = overlay ?? makeOverlay()
            overlay = panel
            if panel.frame != model.frame { panel.setFrame(model.frame, display: true) }
            panel.ignoresMouseEvents = model.clickThrough
            panel.orderFrontRegardless()
        } else {
            overlay?.orderOut(nil)
        }
    }

    // MARK: Actions

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .pdf, .heic, .tiff]
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
        model.image = image
        model.imageName = url.lastPathComponent
        // Start at the image's point size (exports are usually @3x).
        if let rep = image.representations.first, rep.pixelsWide > 0 {
            let scale: CGFloat = rep.pixelsWide >= 1000 ? 3 : (rep.pixelsWide >= 600 ? 2 : 1)
            model.frame.size = NSSize(width: CGFloat(rep.pixelsWide) / scale, height: CGFloat(rep.pixelsHigh) / scale)
        }
        model.isVisible = true
        applyModel()
    }

    /// Fits the overlay to the frontmost Simulator window's device area.
    private func snapToSimulator() {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        guard let window = info.first(where: {
                  ($0[kCGWindowOwnerName as String] as? String) == "Simulator"
                      && ($0[kCGWindowLayer as String] as? Int) == 0
              }),
              let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict) else {
            model.status = String(localized: "No Simulator window on screen")
            return
        }
        // CGWindow bounds are top-left based on the main display; Cocoa is bottom-left.
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let titleBar: CGFloat = 28
        var frame = NSRect(x: bounds.minX, y: mainHeight - bounds.maxY,
                           width: bounds.width, height: bounds.height - titleBar)
        // Keep the design's aspect ratio inside the window's device area.
        if let image = model.image, image.size.width > 0 {
            let aspect = image.size.height / image.size.width
            let height = min(frame.height, frame.width * aspect)
            let width = height / aspect
            frame = NSRect(x: frame.midX - width / 2, y: frame.minY + (frame.height - height) / 2,
                           width: width, height: height)
        }
        model.frame = frame
        model.isVisible = true
        model.status = String(localized: "Snapped to Simulator — fine-tune with the arrows")
        applyModel()
    }
}

// MARK: - Overlay content

private struct DesignOverlayCanvas: View {
    @ObservedObject var model: DesignOverlayModel

    var body: some View {
        ZStack {
            if model.showImage, let image = model.image {
                Image(nsImage: image)
                    .resizable()
                    .opacity(model.opacity)
            }
            if model.showGrid {
                Canvas { context, size in
                    let step = max(2, model.gridSpacing)
                    var path = Path()
                    var x: CGFloat = 0
                    while x <= size.width {
                        path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                        x += step
                    }
                    var y: CGFloat = 0
                    while y <= size.height {
                        path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
                        y += step
                    }
                    context.stroke(path, with: .color(model.gridColor.opacity(0.35)), lineWidth: 0.5)
                }
            }
            if !model.clickThrough {
                Rectangle().strokeBorder(Color.accentColor, lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Controls

private struct DesignOverlayControls: View {
    @ObservedObject var model: DesignOverlayModel
    let chooseImage: () -> Void
    let snap: () -> Void
    let apply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                PillButton(title: "Choose Design…", symbol: "photo") { chooseImage() }
                Text(model.imageName.isEmpty ? String(localized: "PNG / JPEG / PDF export") : model.imageName)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                    .lineLimit(1)
                Spacer()
                Toggle("Visible", isOn: binding(\.isVisible))
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            HStack(spacing: Spacing.sm) {
                Toggle("Design", isOn: binding(\.showImage)).toggleStyle(.checkbox)
                Slider(value: binding(\.opacity), in: 0.05...1)
                Text(String(format: "%.0f%%", model.opacity * 100))
                    .font(Typography.monoSmall)
                    .frame(width: 40, alignment: .trailing)
            }
            .font(Typography.monoSmall)

            HStack(spacing: Spacing.sm) {
                Toggle("Grid", isOn: binding(\.showGrid)).toggleStyle(.checkbox)
                Stepper("\(Int(model.gridSpacing)) pt", value: binding(\.gridSpacing), in: 2...64, step: 2)
                ColorPicker("", selection: binding(\.gridColor))
                    .labelsHidden()
                Spacer()
            }
            .font(Typography.monoSmall)

            SoftDivider()

            HStack(spacing: Spacing.sm) {
                AccentActionButton(title: "Snap to Simulator", symbol: "rectangle.dashed") { snap() }
                Toggle("Click-through", isOn: binding(\.clickThrough))
                    .toggleStyle(.checkbox)
                    .font(Typography.monoSmall)
                    .help("Off: drag the overlay to position it. On: clicks reach the Simulator.")
                Spacer()
            }

            HStack(spacing: 4) {
                nudge("arrow.left") { model.frame.origin.x -= 1 }
                nudge("arrow.right") { model.frame.origin.x += 1 }
                nudge("arrow.up") { model.frame.origin.y += 1 }
                nudge("arrow.down") { model.frame.origin.y -= 1 }
                Divider().frame(height: 16)
                nudge("minus.magnifyingglass") { scale(0.99) }
                nudge("plus.magnifyingglass") { scale(1.01) }
                Spacer()
                Text(verbatim: "\(Int(model.frame.width)) × \(Int(model.frame.height))")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
            }

            if let status = model.status {
                Text(status)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
            }
        }
        .padding(Spacing.lg)
        .frame(width: 420)
    }

    /// Bindings that also push the change to the overlay panel.
    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<DesignOverlayModel, T>) -> Binding<T> {
        Binding(get: { model[keyPath: keyPath] },
                set: { model[keyPath: keyPath] = $0; apply() })
    }

    private func nudge(_ symbol: String, _ change: @escaping () -> Void) -> some View {
        ToolboxIconButton(symbol: symbol) {
            change()
            apply()
        }
    }

    private func scale(_ factor: CGFloat) {
        let f = model.frame
        let size = NSSize(width: f.width * factor, height: f.height * factor)
        model.frame = NSRect(x: f.midX - size.width / 2, y: f.midY - size.height / 2,
                             width: size.width, height: size.height)
    }
}
