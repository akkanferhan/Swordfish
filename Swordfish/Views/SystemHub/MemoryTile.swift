import SwiftUI

struct MemoryTile: View {
    @EnvironmentObject var monitor: SystemMonitor
    @State private var purging = false

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Label("Memory", systemImage: "memorychip")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                    Spacer()
                    Button(action: clearRAM) {
                        HStack(spacing: 6) {
                            Image(systemName: purging ? "arrow.clockwise" : "trash")
                                .font(.system(size: 11, weight: .medium))
                            Text(purging ? "Purging…" : "Clear RAM")
                                .font(Typography.monoSmall)
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                                .fill(Theme.Surface.surface2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                                        .strokeBorder(Theme.Border.subtle, lineWidth: 1)
                                )
                        )
                        .foregroundStyle(Theme.TextColor.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(purging)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(monitor.memory.usedBytes.humanBytes)
                        .font(Typography.statNumber)
                        .foregroundStyle(Theme.TextColor.primary)
                    Text("/ \(monitor.memory.totalBytes.humanBytes) used")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                    Spacer()
                    Text(String(format: "%.0f%%", monitor.memory.usedFraction * 100))
                        .font(Typography.monoSmall)
                        .foregroundStyle(memoryTint)
                }

                MemoryBreakdownBar(stats: monitor.memory)
                    .frame(height: 4)

                HStack(spacing: Spacing.md) {
                    LegendDot(color: Theme.Semantic.accent, label: "App", value: monitor.memory.appBytes)
                    LegendDot(color: Theme.Semantic.warn,   label: "Wired", value: monitor.memory.wiredBytes)
                    LegendDot(color: Theme.Semantic.ok,     label: "Cache", value: monitor.memory.cacheBytes)
                }
            }
        }
    }

    private var memoryTint: Color {
        let f = monitor.memory.usedFraction
        if f > 0.8 { return Theme.Semantic.danger }
        if f > 0.65 { return Theme.Semantic.warn }
        return Theme.Semantic.ok
    }

    private func clearRAM() {
        purging = true
        Task {
            await monitor.clearRAM()
            try? await Task.sleep(nanoseconds: 300_000_000)
            purging = false
        }
    }
}

private struct MemoryBreakdownBar: View {
    let stats: MemoryStats

    var body: some View {
        GeometryReader { proxy in
            let total = max(1, Double(stats.totalBytes))
            let app   = Double(stats.appBytes) / total
            let wired = Double(stats.wiredBytes) / total
            let cache = Double(stats.cacheBytes) / total
            HStack(spacing: 1) {
                Rectangle().fill(Theme.Semantic.accent).frame(width: proxy.size.width * app)
                Rectangle().fill(Theme.Semantic.warn).frame(width: proxy.size.width * wired)
                Rectangle().fill(Theme.Semantic.ok.opacity(0.6)).frame(width: proxy.size.width * cache)
                Spacer(minLength: 0)
            }
            .background(Theme.Surface.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        }
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String
    let value: UInt64

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.secondary)
            Text(value.humanBytes)
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.tertiary)
        }
    }
}
