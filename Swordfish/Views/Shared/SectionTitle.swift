import SwiftUI

struct SectionTitle: View {
    let title: String
    var badge: String? = nil

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(title)
                .sectionTitleStyle()
            if let badge {
                Text(badge)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                            .fill(Theme.Surface.surface1)
                    )
            }
            Spacer()
        }
        .padding(.horizontal, 2)
    }
}
