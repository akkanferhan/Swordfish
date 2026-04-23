import SwiftUI
import AppKit

struct PillButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: .medium))
                Text(title)
                    .font(Typography.monoSmall)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 5)
            .foregroundStyle(Theme.TextColor.secondary)
            .background(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .fill(hovering ? Theme.Surface.surface2 : Theme.Surface.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            .strokeBorder(Theme.Border.subtle, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button(action: copy) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(copied ? Theme.Semantic.ok : Theme.TextColor.secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .fill(Theme.Surface.surface1)
                )
        }
        .buttonStyle(.plain)
        .disabled(text.isEmpty)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            copied = false
        }
    }
}

struct CodeEditor: View {
    @Binding var text: String
    var placeholder: String
    var minHeight: CGFloat = 120

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(Theme.Surface.codeBg)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                        .strokeBorder(Theme.Border.subtle, lineWidth: 1)
                )
            if text.isEmpty {
                Text(placeholder)
                    .font(Typography.code)
                    .foregroundStyle(Theme.TextColor.quaternary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(Typography.code)
                .foregroundStyle(Theme.TextColor.primary)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
        }
        .frame(minHeight: minHeight)
    }
}
