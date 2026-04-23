import SwiftUI

struct PopoverFooter: View {
    var body: some View {
        HStack(spacing: Spacing.smMd) {
            Text("v1.0")
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.quaternary)
            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.Border.subtle)
                .frame(height: 1)
        }
    }
}
