import SwiftUI

struct ExpandableSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    let symbol: String
    let isExpanded: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button(action: onToggle) {
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
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.TextColor.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
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

            if isExpanded {
                content()
                    .padding(.horizontal, 2)
                    .transition(.opacity)
            }
        }
    }
}
