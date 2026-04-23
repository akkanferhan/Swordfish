import SwiftUI

struct TabBar: View {
    @Binding var selected: PopoverTab

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(PopoverTab.allCases) { tab in
                TabItem(tab: tab, isActive: selected == tab) {
                    withAnimation(Motion.default) {
                        selected = tab
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.smMd)
        .padding(.vertical, Spacing.sm)
    }
}

private struct TabItem: View {
    let tab: PopoverTab
    let isActive: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 13, weight: .medium))
                Text(tab.rawValue)
                    .font(Typography.bodyMedium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .foregroundStyle(isActive ? Theme.TextColor.primary : Theme.TextColor.secondary)
            .background(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .fill(isActive ? Theme.Surface.surface2 : (hovering ? Theme.Surface.surface1 : .clear))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            .strokeBorder(isActive ? Theme.Border.default : .clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
