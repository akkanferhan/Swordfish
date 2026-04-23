import SwiftUI
import AppKit

struct PopoverHeader: View {
    @EnvironmentObject var loginItem: LoginItemManager
    var onRefresh: () -> Void = {}

    var body: some View {
        HStack(spacing: Spacing.smMd) {
            BrandMonogram(size: 22, tinted: true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Swordfish")
                    .font(Typography.title)
                    .foregroundStyle(Theme.TextColor.primary)
                Text("tabs · v1.0")
                    .font(Typography.subtitle)
                    .foregroundStyle(Theme.TextColor.tertiary)
            }
            Spacer()
            HeaderIconButton(symbol: "arrow.clockwise", action: onRefresh)
            settingsMenu
        }
        .padding(.horizontal, Spacing.mdLg)
        .padding(.vertical, Spacing.smMd)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Border.subtle)
                .frame(height: 1)
        }
    }

    private var settingsMenu: some View {
        Menu {
            Toggle(isOn: Binding(
                get: { loginItem.isEnabled },
                set: { _ in loginItem.toggle() }
            )) {
                Label("Launch at Login", systemImage: "power")
            }
            if let err = loginItem.lastError {
                Text("Login item error: \(err)")
            }
            Divider()
            Button("Quit Swordfish") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: [.command])
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.TextColor.secondary)
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

private struct HeaderIconButton: View {
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.TextColor.secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .fill(hovering ? Theme.Surface.surface1 : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
