import SwiftUI

/// A small tinted text chip — used for status labels like "Valid" / "Invalid",
/// kind indicators, and other inline markers across the app.
struct Badge: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(Typography.monoSmall)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }
}
