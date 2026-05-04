import SwiftUI

struct PopoverFooter: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        HStack(spacing: Spacing.smMd) {
            Text("v\(AppVersion.short)")
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.quaternary)
            Spacer()
            HStack(spacing: Spacing.smMd) {
                Label(String(format: "%.0f°", monitor.cpuTemp), systemImage: "cpu")
                Label(String(format: "%.0f%%", monitor.memory.usedFraction * 100), systemImage: "memorychip")
            }
            .font(Typography.monoSmall)
            .foregroundStyle(Theme.TextColor.tertiary)
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
