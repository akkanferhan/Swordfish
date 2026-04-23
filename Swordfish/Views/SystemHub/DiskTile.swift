import SwiftUI

struct DiskTile: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Label("Storage", systemImage: "internaldrive")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                    Spacer()
                    Text(monitor.disk.volumeName)
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                        .lineLimit(1)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(monitor.disk.usedBytes.humanBytes)
                        .font(Typography.statNumber)
                        .foregroundStyle(Theme.TextColor.primary)
                    Text("/ \(monitor.disk.totalBytes.humanBytes) used")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                    Spacer()
                    Text(String(format: "%.0f%%", monitor.disk.usedFraction * 100))
                        .font(Typography.monoSmall)
                        .foregroundStyle(tint)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Theme.Surface.surface2)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(tint)
                            .frame(width: proxy.size.width * CGFloat(monitor.disk.usedFraction))
                    }
                }
                .frame(height: 4)

                HStack {
                    Text("Free")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                    Text(monitor.disk.freeBytes.humanBytes)
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.secondary)
                    Spacer()
                }
            }
        }
    }

    private var tint: Color {
        let f = monitor.disk.usedFraction
        if f > 0.9 { return Theme.Semantic.danger }
        if f > 0.75 { return Theme.Semantic.warn }
        return Theme.Semantic.ok
    }
}
