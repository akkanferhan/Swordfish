import SwiftUI

struct SystemHubView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            DisplaysSection()
            AntiSleepSection()
            HardwareSection()
        }
    }
}

private struct AntiSleepSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionTitle(title: "Anti-Sleep")
            AntiSleepRow()
        }
    }
}

private struct HardwareSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionTitle(title: "Hardware")
            HardwareStatsSection()
        }
    }
}
