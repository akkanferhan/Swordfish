import SwiftUI
import AppKit

struct ClipboardHistoryView: View {
    @EnvironmentObject var clipboard: ClipboardService
    @State private var status: ToolboxStatus?
    @State private var confirmingClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                SectionTitle(title: "Clipboard History", badge: String(localized: "\(clipboard.items.count) items"))
                if confirmingClear {
                    PillButton(title: "Cancel", symbol: "xmark") { confirmingClear = false }
                    DangerActionButton(title: "Clear unpinned", symbol: "trash.fill") {
                        clipboard.clearHistory()
                        confirmingClear = false
                    }
                } else if !clipboard.items.isEmpty {
                    ToolboxIconButton(symbol: "trash", help: "Clear history (keeps pinned items)") {
                        confirmingClear = true
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.TextColor.tertiary)
                TextField("Search history", text: $clipboard.search)
                    .textFieldStyle(.plain)
                    .font(Typography.mono)
                if !clipboard.search.isEmpty {
                    Button { clipboard.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.TextColor.tertiary)
                }
            }
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

            Picker("", selection: $clipboard.filter) {
                ForEach(ClipboardService.Filter.allCases) { f in
                    Text(f.label).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if let skipped = clipboard.lastSkipped {
                Label(skipped, systemImage: "eye.slash")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                    .lineLimit(1)
            }
            if let status {
                ToolboxStatusLine(status: status)
            }

            if clipboard.filtered.isEmpty {
                emptyState
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(clipboard.filtered.enumerated()), id: \.element.id) { idx, item in
                        ClipboardRow(index: idx, item: item, report: { status = $0 })
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 22))
                .foregroundStyle(Theme.TextColor.quaternary)
            Text(clipboard.search.isEmpty ? "Nothing copied yet" : "No matches")
                .font(Typography.body)
                .foregroundStyle(Theme.TextColor.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }
}

private struct ClipboardRow: View {
    let index: Int
    let item: ClipboardItem
    let report: (ToolboxStatus?) -> Void
    @EnvironmentObject var clipboard: ClipboardService
    @EnvironmentObject var devTools: DevToolsState
    @Environment(\.popoverController) private var popoverController
    @State private var hovering = false
    @State private var contentType: ClipboardContentType = .plain

    private var isTextual: Bool { [.text, .link, .code, .secret].contains(item.kind) }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            leading
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                if item.kind == .image, let url = item.imageURL, let image = ClipboardImageCache.thumbnail(for: url) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 64, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    Text(item.displayText)
                        .font(Typography.code)
                        .foregroundStyle(Theme.TextColor.primary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                metaLine
            }
            Spacer(minLength: 0)

            if hovering || item.pinned {
                HStack(spacing: 4) {
                    if hovering { smartButtons }
                    if hovering { moreMenu }
                    if item.kind != .secret {
                        Button { clipboard.togglePin(item) } label: {
                            Image(systemName: item.pinned ? "pin.fill" : "pin")
                                .font(.system(size: 11))
                                .foregroundStyle(item.pinned ? Color.accentColor : Theme.TextColor.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Pin")
                    }
                    if hovering {
                        Button { clipboard.remove(item) } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.TextColor.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Delete")
                    }
                }
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(hovering ? Theme.Surface.surface2 : Theme.Surface.surface1)
        )
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
        .onTapGesture {
            clipboard.copyToPasteboard(item)
            report(.ok(String(localized: "Copied"), nil))
        }
        .contextMenu { menuContent }
        .task(id: item.id) {
            // Detection parses JSON / base64 — do it once per item, not per redraw.
            if isTextual { contentType = ClipboardSmartActions.detect(item.content) }
        }
    }

    // MARK: Leading / meta

    @ViewBuilder
    private var leading: some View {
        if case .hexColor(let color) = contentType {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(nsColor: color))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.Border.default, lineWidth: 1))
        } else {
            ClipboardThumbnail(item: item)
        }
    }

    private var metaLine: some View {
        HStack(spacing: Spacing.sm) {
            Badge(label: badgeLabel, tint: badgeTint)
            if case .timestamp(let date) = contentType {
                Text(verbatim: "→ " + date.formatted(date: .abbreviated, time: .shortened))
                    .font(Typography.monoSmall)
                    .foregroundStyle(Color.accentColor)
            }
            if let app = item.sourceApp {
                Text(app)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                    .lineLimit(1)
            }
            Text(relativeTime(item.capturedAt))
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.tertiary)
            if item.kind == .secret {
                Text("auto-deletes in 2 min")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.Semantic.warn)
            } else if isTextual {
                Text("\(item.content.count) chars")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.quaternary)
            }
        }
    }

    // MARK: Smart actions

    @ViewBuilder
    private var smartButtons: some View {
        switch contentType {
        case .json:
            rowButton("curlybraces", help: "Open in JSON Viewer") { openJSON() }
        case .jwt:
            rowButton("key.viewfinder", help: "Decode JWT") { openUtility(.jwt) }
        case .timestamp(let date):
            rowButton("clock", help: "Copy as ISO 8601 date") {
                copy(ISO8601DateFormatter().string(from: date), String(localized: "Copied ISO date"))
            }
        case .base64(let decoded):
            rowButton("textformat.abc", help: "Copy decoded Base64") {
                copy(decoded, String(localized: "Copied decoded text"))
            }
        case .url(let url):
            rowButton("iphone", help: "Open in booted Simulator") { openInSimulator(url) }
            if ["http", "https"].contains(url.scheme ?? "") {
                rowButton("safari", help: "Open in browser") { NSWorkspace.shared.open(url) }
            }
        case .hexColor(let color):
            rowButton("swift", help: "Copy as SwiftUI Color") {
                copy(ClipboardSmartActions.swiftUIColor(color), String(localized: "Copied SwiftUI Color"))
            }
        case .uuid, .plain:
            EmptyView()
        }
        if item.kind == .file, let first = item.fileURLs.first {
            rowButton("folder", help: "Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([first])
            }
        }
        if item.kind == .image, let url = item.imageURL {
            rowButton("square.and.arrow.down", help: "Save to Desktop") { saveImage(url) }
        }
    }

    private var moreMenu: some View {
        Menu {
            menuContent
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 11))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(Theme.TextColor.tertiary)
    }

    @ViewBuilder
    private var menuContent: some View {
        Button("Copy") { clipboard.copyToPasteboard(item) }
        if case .json = contentType {
            Button("Open in JSON Viewer") { openJSON() }
            Button("Copy formatted JSON") {
                if let pretty = try? DevUtilities.prettyJSON(Data(item.content.utf8)) {
                    copy(pretty, String(localized: "Copied formatted JSON"))
                }
            }
        }
        if case .hexColor(let color) = contentType {
            Button("Copy as SwiftUI Color") { copy(ClipboardSmartActions.swiftUIColor(color), String(localized: "Copied SwiftUI Color")) }
            Button("Copy as UIColor") { copy(ClipboardSmartActions.uiColor(color), String(localized: "Copied UIColor")) }
        }
        if case .timestamp = contentType {
            Button("Open in Timestamp tool") { openUtility(.timestamp) }
        }
        if case .base64 = contentType {
            Button("Open in Base64 tool") { openUtility(.base64) }
        }
        if isTextual && item.kind != .secret {
            Menu("Transform & Copy") {
                ForEach(ClipboardTransform.allCases) { t in
                    Button(t.label) {
                        if clipboard.apply(t, to: item) {
                            report(.ok(String(localized: "Copied: \(t.label)"), nil))
                        } else {
                            report(.error(String(localized: "Couldn't apply \(t.label)")))
                        }
                    }
                }
            }
        }
        Divider()
        if item.kind != .secret {
            Button(item.pinned ? "Unpin" : "Pin") { clipboard.togglePin(item) }
        }
        Button("Delete") { clipboard.remove(item) }
    }

    private func rowButton(_ symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Action helpers

    private func copy(_ text: String, _ message: String) {
        clipboard.copyText(text)
        report(.ok(message, nil))
    }

    private func openJSON() {
        devTools.jsonInput = (try? DevUtilities.prettyJSON(Data(item.content.utf8))) ?? item.content
        popoverController?.openJSONViewer()
    }

    private func openUtility(_ tool: DevToolsState.UtilityRequest.Tool) {
        devTools.utilityRequest = .init(tool: tool, input: item.content.trimmingCharacters(in: .whitespacesAndNewlines))
        popoverController?.openDevUtilities()
    }

    private func openInSimulator(_ url: URL) {
        Task.detached(priority: .userInitiated) {
            let result = try? ProcessRunner.run("/usr/bin/xcrun", arguments: ["simctl", "openurl", "booted", url.absoluteString])
            let outcome: ToolboxStatus = result?.exitCode == 0
                ? .ok(String(localized: "Opened in Simulator"), nil)
                : .error((result?.stderr.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                         ?? String(localized: "No booted simulator"))
            await MainActor.run { report(outcome) }
        }
    }

    private func saveImage(_ url: URL) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let target = desktop.appendingPathComponent("clipboard-\(fmt.string(from: item.capturedAt)).png")
        do {
            try FileManager.default.copyItem(at: url, to: target)
            report(.ok(String(localized: "Saved \(target.lastPathComponent)"), target))
        } catch {
            report(.error(error.localizedDescription))
        }
    }

    // MARK: Badge

    private var badgeLabel: String {
        switch contentType {
        case .json:      return "json"
        case .jwt:       return "jwt"
        case .timestamp: return String(localized: "timestamp")
        case .base64:    return "base64"
        case .hexColor:  return String(localized: "color")
        case .uuid:      return "uuid"
        case .url, .plain: break
        }
        switch item.kind {
        case .text:   return String(localized: "text")
        case .link:   return String(localized: "link")
        case .code:   return String(localized: "code")
        case .image:  return String(localized: "image")
        case .file:   return item.fileURLs.count > 1 ? String(localized: "\(item.fileURLs.count) files") : String(localized: "file")
        case .secret: return String(localized: "secret")
        }
    }

    private var badgeTint: Color {
        switch item.kind {
        case .text:   return contentType == .plain ? Theme.TextColor.tertiary : Color.accentColor
        case .link:   return Color.accentColor
        case .code:   return Theme.Semantic.ok
        case .image, .file: return Theme.Syntax.null
        case .secret: return Theme.Semantic.warn
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}
