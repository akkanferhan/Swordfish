import SwiftUI

struct Tile<Content: View>: View {
    let content: Content
    var padding: CGFloat = Spacing.md

    init(padding: CGFloat = Spacing.md, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                    .fill(Theme.Surface.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                            .strokeBorder(Theme.Border.subtle, lineWidth: 1)
                    )
            )
    }
}

struct SoftDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Border.subtle)
            .frame(height: 1)
    }
}
