import SwiftUI

struct ProductivityView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            QuickActionsView()
            SoftDivider()
            ClipboardHistoryView()
        }
    }
}
