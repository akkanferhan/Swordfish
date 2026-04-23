import SwiftUI

/// A row that visually matches `ExpandableSection` but triggers an action
/// (e.g., opens a dedicated window) instead of expanding inline content.
struct LaunchSection: View {
    let title: String
    var subtitle: String? = nil
    let symbol: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.TextColor.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Theme.TextColor.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(Typography.monoSmall)
                            .foregroundStyle(Theme.TextColor.tertiary)
                    }
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(hovering ? Color.accentColor : Theme.TextColor.tertiary)
            }
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .fill(hovering ? Theme.Surface.surface2 : Theme.Surface.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                            .strokeBorder(Theme.Border.subtle, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
