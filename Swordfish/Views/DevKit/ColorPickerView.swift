import SwiftUI
import AppKit

struct ColorPickerView: View {
    @EnvironmentObject var state: DevToolsState
    @Environment(\.popoverController) private var popoverController
    @State private var hexInput: String = ""
    @State private var toast: String?
    @State private var recent: [String] = loadRecent()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            headerRow
            formatRows
            if !recent.isEmpty { recentColors }
            snippetRows
            pickRow
            if let toast {
                Text(toast)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.Semantic.ok)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { hexInput = currentHex }
        .onChange(of: state.pickedColor) { _ in
            hexInput = currentHex
            rememberColor(currentHex)
        }
    }

    // MARK: - Header row (big chip + editable HEX)

    private var headerRow: some View {
        HStack(spacing: Spacing.md) {
            RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                .fill(swiftColor)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                        .strokeBorder(Theme.Border.subtle, lineWidth: 1)
                )
                .frame(width: 96, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text("HEX")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                HStack(spacing: 6) {
                    TextField("#RRGGBB", text: $hexInput)
                        .textFieldStyle(.plain)
                        .font(Typography.mono)
                        .foregroundStyle(Theme.TextColor.primary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                                .fill(Theme.Surface.surface1)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                                        .strokeBorder(Theme.Border.subtle, lineWidth: 1)
                                )
                        )
                        .onSubmit { applyHex(hexInput) }
                    CopyMini(value: currentHex) { copy(currentHex, "HEX") }
                }
            }
        }
    }

    // MARK: - RGB + HSL rows (click to copy)

    private var formatRows: some View {
        VStack(spacing: 4) {
            CopyableRow(label: "RGB", value: currentRGB) { copy(currentRGB, "RGB") }
            CopyableRow(label: "HSL", value: currentHSL) { copy(currentHSL, "HSL") }
        }
    }

    // MARK: - Recent colors

    private var recentColors: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent")
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.tertiary)
            HStack(spacing: 4) {
                ForEach(recent.prefix(10), id: \.self) { hex in
                    Button {
                        applyHex(hex)
                    } label: {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(hex: UInt32(hex.dropFirst(), radix: 16) ?? 0))
                            .frame(width: 22, height: 22)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(
                                        hex.lowercased() == currentHex.lowercased()
                                            ? Color.accentColor
                                            : Theme.Border.subtle,
                                        lineWidth: hex.lowercased() == currentHex.lowercased() ? 2 : 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(hex)
                }
                Spacer()
            }
        }
    }

    // MARK: - Snippets (SwiftUI, UIKit, CSS)

    private var snippetRows: some View {
        VStack(spacing: 4) {
            CopyableRow(label: "SwiftUI", value: swiftUISnippet, mono: true) { copy(swiftUISnippet, "SwiftUI") }
            CopyableRow(label: "UIKit",   value: uiKitSnippet, mono: true)   { copy(uiKitSnippet, "UIKit") }
            CopyableRow(label: "CSS",     value: cssSnippet, mono: true)     { copy(cssSnippet, "CSS") }
        }
    }

    // MARK: - Pick row

    private var pickRow: some View {
        HStack(spacing: Spacing.sm) {
            Button(action: sampleScreen) {
                HStack(spacing: 6) {
                    Image(systemName: "eyedropper")
                    Text("Pick from screen").font(Typography.bodyMedium)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .fill(Color.accentColor)
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    // MARK: - Values

    private var components: (r: Double, g: Double, b: Double)? {
        guard let c = state.pickedColor?.usingColorSpace(NSColorSpace.sRGB) else { return nil }
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
    }

    private var swiftColor: Color {
        Color(nsColor: state.pickedColor ?? NSColor.systemBlue)
    }

    private var currentHex: String {
        guard let (r, g, b) = components else { return "#000000" }
        let ri = Int((r * 255).rounded())
        let gi = Int((g * 255).rounded())
        let bi = Int((b * 255).rounded())
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }

    private var currentRGB: String {
        guard let (r, g, b) = components else { return "—" }
        return String(format: "rgb(%.0f, %.0f, %.0f)", r * 255, g * 255, b * 255)
    }

    private var currentHSL: String {
        guard let (r, g, b) = components else { return "—" }
        let maxC = max(r, max(g, b))
        let minC = min(r, min(g, b))
        let delta = maxC - minC
        let l = (maxC + minC) / 2
        var s = 0.0
        if delta != 0 { s = l > 0.5 ? delta / (2 - maxC - minC) : delta / (maxC + minC) }
        var h = 0.0
        if delta != 0 {
            if maxC == r { h = (g - b) / delta + (g < b ? 6 : 0) }
            else if maxC == g { h = (b - r) / delta + 2 }
            else { h = (r - g) / delta + 4 }
            h *= 60
        }
        return String(format: "hsl(%.0f°, %.0f%%, %.0f%%)", h, s * 100, l * 100)
    }

    private var swiftUISnippet: String {
        guard let (r, g, b) = components else { return "—" }
        return String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)", r, g, b)
    }

    private var uiKitSnippet: String {
        guard let (r, g, b) = components else { return "—" }
        return String(format: "UIColor(red: %.3f, green: %.3f, blue: %.3f, alpha: 1)", r, g, b)
    }

    private var cssSnippet: String { currentHex }

    // MARK: - Actions

    private func copy(_ value: String, _ label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        toast = "Copied \(label)"
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            toast = nil
        }
    }

    private func applyHex(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = String(s.map { "\($0)\($0)" }.joined()) }
        guard s.count == 6, let value = UInt32(s, radix: 16) else {
            hexInput = currentHex
            return
        }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        state.pickedColor = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        hexInput = currentHex
    }

    private func sampleScreen() {
        let behaviorGuard = popoverController?.suspendAutoClose()
        let sampler = NSColorSampler()
        sampler.show { color in
            Task { @MainActor in
                if let color {
                    state.pickedColor = color.usingColorSpace(NSColorSpace.sRGB) ?? color
                }
                behaviorGuard?.release()
                popoverController?.showPopover()
            }
        }
    }

    private func rememberColor(_ hex: String) {
        guard hex.count == 7 else { return }
        var list = recent
        list.removeAll { $0.lowercased() == hex.lowercased() }
        list.insert(hex, at: 0)
        list = Array(list.prefix(10))
        recent = list
        UserDefaults.standard.set(list, forKey: "swordfish.color.recent")
    }

    private static func loadRecent() -> [String] {
        UserDefaults.standard.stringArray(forKey: "swordfish.color.recent") ?? []
    }
}

// MARK: - Row helper

private struct CopyableRow: View {
    let label: String
    let value: String
    var mono: Bool = false
    let onCopy: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onCopy) {
            HStack(spacing: 8) {
                Text(label)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                    .frame(width: 56, alignment: .leading)
                Text(value)
                    .font(mono ? Typography.code : Typography.mono)
                    .foregroundStyle(Theme.TextColor.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(hovering ? Color.accentColor : Theme.TextColor.quaternary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .fill(hovering ? Theme.Surface.surface2 : Theme.Surface.surface1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct CopyMini: View {
    let value: String
    let onCopy: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onCopy) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 11))
                .foregroundStyle(hovering ? Color.accentColor : Theme.TextColor.secondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .fill(hovering ? Theme.Surface.surface2 : Theme.Surface.surface1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
