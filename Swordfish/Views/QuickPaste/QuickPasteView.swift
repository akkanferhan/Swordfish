import SwiftUI
import AppKit

struct QuickPasteView: View {
    @ObservedObject var model: QuickPasteModel
    @ObservedObject private var clipboard: ClipboardService
    let canPaste: () -> Bool
    let choose: (ClipboardItem) -> Void
    @FocusState private var searchFocused: Bool

    init(model: QuickPasteModel, canPaste: @escaping () -> Bool, choose: @escaping (ClipboardItem) -> Void) {
        self.model = model
        self.clipboard = model.clipboard
        self.canPaste = canPaste
        self.choose = choose
    }

    var body: some View {
        let entries = model.entries
        VStack(spacing: 0) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.TextColor.tertiary)
                TextField("Search clipboard history", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($searchFocused)
            }
            .padding(Spacing.md)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, item in
                            QuickPasteRow(item: item, index: index, isSelected: index == model.selection)
                                .id(index)
                                .onTapGesture { choose(item) }
                        }
                    }
                    .padding(Spacing.sm)
                }
                .onChange(of: model.selection) { proxy.scrollTo($0) }
            }
            .overlay {
                if entries.isEmpty {
                    Text(model.query.isEmpty ? "Clipboard history is empty" : "No matches")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                }
            }
            Divider()
            HStack(spacing: Spacing.md) {
                hint("↑↓", "select")
                hint("↩", canPaste() ? "paste" : "copy")
                hint("⌘1–9", "quick pick")
                hint("esc", "close")
                Spacer()
                if !canPaste() {
                    Text("Grant Accessibility in Settings → Clipboard to paste directly")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.Semantic.warn)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 6)
        }
        .frame(width: 560, height: 420)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Radius.section, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.section, style: .continuous)
                .strokeBorder(Theme.Border.default, lineWidth: 1)
        )
        .onAppear { searchFocused = true }
    }

    private func hint(_ key: String, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: key)
                .font(Typography.kbd)
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 3).fill(Theme.Surface.surface2))
            Text(label)
                .font(Typography.monoSmall)
        }
        .foregroundStyle(Theme.TextColor.tertiary)
    }
}

private struct QuickPasteRow: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ClipboardThumbnail(item: item)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.code)
                    .foregroundStyle(isSelected ? Color.white : Theme.TextColor.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(Typography.monoSmall)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Theme.TextColor.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if index < 9 {
                Text(verbatim: "⌘\(index + 1)")
                    .font(Typography.kbd)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Theme.TextColor.quaternary)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private var title: String {
        item.displayText.replacingOccurrences(of: "\n", with: " ⏎ ")
    }

    private var subtitle: String {
        let ago = RelativeDateTimeFormatter().localizedString(for: item.capturedAt, relativeTo: Date())
        return [item.sourceApp, ago].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Image thumbnail, file icon, or source-app icon for a history item.
struct ClipboardThumbnail: View {
    let item: ClipboardItem

    var body: some View {
        Group {
            switch item.kind {
            case .image:
                if let url = item.imageURL, let image = ClipboardImageCache.thumbnail(for: url) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    Image(systemName: "photo")
                }
            case .file:
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.fileURLs.first?.path ?? "/"))
                    .resizable()
            case .secret:
                Image(systemName: "key.fill")
                    .foregroundStyle(Theme.Semantic.warn)
            default:
                if let icon = ClipboardImageCache.appIcon(bundleID: item.sourceBundleID) {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "doc.on.clipboard")
                        .foregroundStyle(Theme.TextColor.tertiary)
                }
            }
        }
    }
}

/// Small in-memory caches so scrolling the history doesn't decode PNGs or
/// look up app icons on every redraw.
@MainActor
enum ClipboardImageCache {
    private static var thumbnails: [URL: NSImage] = [:]
    private static var icons: [String: NSImage] = [:]

    static func thumbnail(for url: URL) -> NSImage? {
        if let cached = thumbnails[url] { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        let side: CGFloat = 96
        let scale = min(side / max(1, image.size.width), side / max(1, image.size.height), 1)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let thumb = NSImage(size: size)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))
        thumb.unlockFocus()
        if thumbnails.count > 200 { thumbnails.removeAll() }
        thumbnails[url] = thumb
        return thumb
    }

    static func appIcon(bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = icons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = icon
        return icon
    }
}
