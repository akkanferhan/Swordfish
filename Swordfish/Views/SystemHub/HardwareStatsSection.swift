import SwiftUI

struct HardwareStatsSection: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                CPUTile()
                FanTile()
            }
            MemoryTile()
            DiskTile()
        }
    }
}

private struct CPUTile: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Label("CPU", systemImage: "cpu")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                    Spacer()
                }
                Text(String(format: "%.0f°C", monitor.cpuTemp))
                    .font(Typography.statNumber)
                    .foregroundStyle(color)
                ProgressBar(value: min(1, monitor.cpuTemp / 100), tint: color)
                    .frame(height: 3)
                Sparkline(values: monitor.cpuHistory, color: color)
                    .frame(height: 18)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var color: Color {
        switch monitor.cpuState {
        case .ok:     return Theme.Semantic.ok
        case .warn:   return Theme.Semantic.warn
        case .danger: return Theme.Semantic.danger
        }
    }
}

private struct FanTile: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Label("Fan", systemImage: "fanblades")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(monitor.fanRPM)")
                        .font(Typography.statNumber)
                        .foregroundStyle(Theme.TextColor.primary)
                    Text("rpm")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                }
                ProgressBar(value: min(1, Double(monitor.fanRPM) / 5000), tint: Color.accentColor)
                    .frame(height: 3)
                Sparkline(values: monitor.fanHistory, color: Color.accentColor)
                    .frame(height: 18)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ProgressBar: View {
    let value: Double   // 0...1
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Theme.Surface.surface2)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(tint)
                    .frame(width: proxy.size.width * CGFloat(min(1, max(0, value))))
            }
        }
    }
}
