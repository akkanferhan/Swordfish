import SwiftUI
import AppKit

struct JSONViewerView: View {
    @EnvironmentObject var state: DevToolsState
    @State private var toast: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                editorPane.frame(minWidth: 280)
                rightPane.frame(minWidth: 280)
            }
            Divider()
            statusBar
        }
        .background(Theme.Surface.popover)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: Spacing.sm) {
            PillButton(title: "Paste", symbol: "doc.on.clipboard") { paste() }
            PillButton(title: "Format", symbol: "text.alignleft") { apply(.beautify) }
            PillButton(title: "Minify", symbol: "minus.rectangle") { apply(.minify) }
            PillButton(title: "Sort Keys", symbol: "arrow.up.arrow.down") { apply(.sort) }
            PillButton(title: "Clear", symbol: "xmark.circle") { state.jsonInput = "" }
            Spacer()
            copyButton
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    private var copyButton: some View {
        Button {
            guard !state.jsonInput.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(state.jsonInput, forType: .string)
            showToast("Copied")
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 11))
                .foregroundStyle(Theme.TextColor.secondary)
                .frame(width: 28, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .fill(Theme.Surface.surface1)
                )
        }
        .buttonStyle(.plain)
        .disabled(state.jsonInput.isEmpty)
    }

    // MARK: - Panes

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneHeader("RAW")
            TextEditor(text: $state.jsonInput)
                .font(Typography.code)
                .foregroundStyle(Theme.TextColor.primary)
                .scrollContentBackground(.hidden)
                .padding(Spacing.sm)
                .background(Theme.Surface.codeBg)
        }
    }

    @ViewBuilder
    private var rightPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneHeader("TREE")
            switch parseResult {
            case .empty:    emptyPane
            case .valid(let obj): JSONTreeView(root: obj)
            case .invalid(let info): errorPane(info)
            }
        }
    }

    private func paneHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(Typography.monoSmall)
                .tracking(1.2)
                .foregroundStyle(Theme.TextColor.tertiary)
            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 6)
        .background(Theme.Surface.surface1)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Border.subtle).frame(height: 1)
        }
    }

    private var emptyPane: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "curlybraces")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.TextColor.quaternary)
            Text("Paste JSON into the editor to explore")
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.tertiary)
            Button {
                state.jsonInput = Self.sampleJSON
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("Load sample").font(Typography.bodyMedium)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Surface.codeBg)
    }

    private func errorPane(_ info: ErrorInfo) -> some View {
        VStack(alignment: .leading, spacing: Spacing.smMd) {
            Label {
                if let loc = info.location {
                    Text("Parse error · line \(loc.line), col \(loc.col)")
                } else {
                    Text("Parse error")
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(Typography.bodyMedium)
            .foregroundStyle(Theme.Semantic.danger)

            Text(info.message)
                .font(Typography.code)
                .foregroundStyle(Theme.TextColor.secondary)
                .textSelection(.enabled)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Spacing.md)
        .background(Theme.Surface.codeBg)
    }

    // MARK: - Status

    private var statusBar: some View {
        HStack(spacing: Spacing.md) {
            switch parseResult {
            case .empty:
                Badge(label: "Empty", tint: Theme.TextColor.tertiary)
            case .valid(let obj):
                Badge(label: "Valid", tint: Theme.Semantic.ok)
                Text(stats(for: obj))
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
            case .invalid(let info):
                Badge(label: "Invalid", tint: Theme.Semantic.danger)
                if let loc = info.location {
                    Text("line \(loc.line), col \(loc.col)")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.Semantic.danger)
                }
            }
            Spacer()
            if let toast {
                Text(toast)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.Semantic.ok)
                    .transition(.opacity)
            }
            Text("\(lineCount) lines · \(sizeFormatted)")
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.tertiary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 6)
    }

    private var lineCount: Int {
        state.jsonInput.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private var sizeFormatted: String {
        let bytes = state.jsonInput.utf8.count
        if bytes < 1024 { return "\(bytes) B" }
        return String(format: "%.1f KB", Double(bytes) / 1024.0)
    }

    // MARK: - Parsing

    private enum ParseResult {
        case empty
        case valid(Any)
        case invalid(ErrorInfo)
    }

    struct ErrorInfo {
        let message: String
        let location: (line: Int, col: Int)?
    }

    private var parseResult: ParseResult {
        let trimmed = state.jsonInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = state.jsonInput.data(using: .utf8) else { return .empty }
        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: [.allowFragments])
            return .valid(obj)
        } catch {
            let ns = error as NSError
            let message = ns.userInfo[NSDebugDescriptionErrorKey] as? String ?? ns.localizedDescription
            let loc: (Int, Int)?
            if let idx = ns.userInfo["NSJSONSerializationErrorIndex"] as? Int {
                loc = location(at: idx, in: state.jsonInput)
            } else {
                loc = nil
            }
            return .invalid(ErrorInfo(message: message, location: loc))
        }
    }

    private func location(at byteIndex: Int, in s: String) -> (line: Int, col: Int) {
        let clamped = min(byteIndex, s.utf8.count)
        let prefix = String(decoding: s.utf8.prefix(clamped), as: UTF8.self)
        let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
        let line = max(1, lines.count)
        let col = (lines.last?.count ?? 0) + 1
        return (line, col)
    }

    private func stats(for obj: Any) -> String {
        let top: String
        if let dict = obj as? [String: Any] { top = "\(dict.count) \(dict.count == 1 ? "key" : "keys")" }
        else if let arr = obj as? [Any] { top = "\(arr.count) \(arr.count == 1 ? "item" : "items")" }
        else { top = "scalar" }
        return "\(top) · depth \(maxDepth(obj))"
    }

    private func maxDepth(_ obj: Any) -> Int {
        if let dict = obj as? [String: Any] { return 1 + (dict.values.map { maxDepth($0) }.max() ?? 0) }
        if let arr = obj as? [Any] { return 1 + (arr.map { maxDepth($0) }.max() ?? 0) }
        return 1
    }

    // MARK: - Actions

    private enum Op { case beautify, minify, sort }

    private func apply(_ op: Op) {
        guard case .valid(let obj) = parseResult else {
            showToast("Nothing to format")
            return
        }
        do {
            let options: JSONSerialization.WritingOptions
            switch op {
            case .beautify: options = [.prettyPrinted, .withoutEscapingSlashes]
            case .minify:   options = [.withoutEscapingSlashes]
            case .sort:     options = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            }
            let data = try JSONSerialization.data(withJSONObject: obj, options: options)
            if let s = String(data: data, encoding: .utf8) {
                state.jsonInput = s
            }
        } catch {
            showToast("Failed: \(error.localizedDescription)")
        }
    }

    private func paste() {
        guard let raw = NSPasteboard.general.string(forType: .string), !raw.isEmpty else {
            showToast("Clipboard is empty")
            return
        }
        state.jsonInput = raw
        if case .valid = parseResult {
            apply(.beautify)
            showToast("Pasted and beautified")
        } else {
            showToast("Pasted")
        }
    }

    private func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            toast = nil
        }
    }

    private static let sampleJSON = """
    {
      "user": {
        "id": 42,
        "name": "Ada Lovelace",
        "emails": ["ada@example.com", "ada@computing.org"],
        "active": true,
        "metadata": null,
        "score": 3.14
      },
      "tags": ["admin", "founder"],
      "items": [
        {"id": 1, "name": "first"},
        {"id": 2, "name": "second"}
      ],
      "createdAt": "2026-04-23T18:00:00Z"
    }
    """
}
