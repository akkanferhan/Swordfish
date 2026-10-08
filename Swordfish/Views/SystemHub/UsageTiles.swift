import SwiftUI

// MARK: - CPU load

struct CPULoadTile: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                TileHeader(title: "CPU Load", symbol: "gauge.with.dots.needle.33percent")
                Text(String(format: "%.0f%%", monitor.cpuLoad * 100))
                    .font(Typography.statNumber)
                    .foregroundStyle(loadTint(monitor.cpuLoad))
                CoreBars(loads: monitor.cpuCoreLoads)
                    .frame(height: 14)
                Sparkline(values: monitor.cpuLoadHistory, color: loadTint(monitor.cpuLoad))
                    .frame(height: 18)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// One thin bar per core — shows at a glance whether a build is using all
/// cores or one thread is pegged.
private struct CoreBars: View {
    let loads: [Double]

    var body: some View {
        GeometryReader { proxy in
            let count = max(1, loads.count)
            let spacing: CGFloat = 1.5
            let width = (proxy.size.width - spacing * CGFloat(count - 1)) / CGFloat(count)
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(loads.enumerated()), id: \.offset) { _, load in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(Theme.Surface.surface2)
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(loadTint(load))
                            .frame(height: max(1, proxy.size.height * CGFloat(min(1, load))))
                    }
                    .frame(width: max(1, width))
                }
            }
        }
    }
}

// MARK: - GPU

struct GPUTile: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                TileHeader(title: "GPU", symbol: "square.stack.3d.up")
                if let gpu = monitor.gpuLoad {
                    Text(String(format: "%.0f%%", gpu * 100))
                        .font(Typography.statNumber)
                        .foregroundStyle(loadTint(gpu))
                    UsageBar(value: gpu, tint: loadTint(gpu))
                        .frame(height: 3)
                    Spacer(minLength: 0)
                    Sparkline(values: monitor.gpuLoadHistory, color: loadTint(gpu))
                        .frame(height: 18)
                } else {
                    Text("—")
                        .font(Typography.statNumber)
                        .foregroundStyle(Theme.TextColor.tertiary)
                    Text("Not reported by this GPU")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Network

struct NetworkTile: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Label("Network", systemImage: "network")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                    Spacer()
                    if monitor.network.vpnActive {
                        Badge(label: "VPN", tint: Theme.Semantic.ok)
                    }
                    if let ip = monitor.network.localIPv4 {
                        Text(verbatim: [monitor.network.interface, ip].compactMap { $0 }.joined(separator: " · "))
                            .font(Typography.monoSmall)
                            .foregroundStyle(Theme.TextColor.tertiary)
                            .textSelection(.enabled)
                    } else {
                        Text("Offline")
                            .font(Typography.monoSmall)
                            .foregroundStyle(Theme.Semantic.warn)
                    }
                }
                HStack(spacing: Spacing.md) {
                    rate(symbol: "arrow.down", value: monitor.network.downBytesPerSec,
                         history: monitor.downHistory, tint: Color.accentColor)
                    rate(symbol: "arrow.up", value: monitor.network.upBytesPerSec,
                         history: monitor.upHistory, tint: Theme.Semantic.ok)
                }
            }
        }
    }

    private func rate(symbol: String, value: Double, history: [Double], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                Text(value.humanRate)
                    .font(Typography.mono.weight(.semibold))
                    .foregroundStyle(Theme.TextColor.primary)
                    .monospacedDigit()
            }
            Sparkline(values: history, color: tint)
                .frame(height: 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Battery

struct BatteryTile: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if let battery = monitor.battery {
                    internalBattery(battery)
                }
                if !monitor.peripheralBatteries.isEmpty {
                    if monitor.battery != nil { SoftDivider() }
                    ForEach(monitor.peripheralBatteries) { device in
                        peripheral(device)
                    }
                }
            }
        }
    }

    private func internalBattery(_ b: BatteryStats) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Label("Battery", systemImage: symbol(for: b))
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                Spacer()
                Text(powerLine(b))
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(b.percent)%")
                    .font(Typography.statNumber)
                    .foregroundStyle(batteryTint(b.percent))
                if let minutes = b.minutesRemaining {
                    Text(b.isCharging
                         ? String(localized: "\(Self.duration(minutes)) to full")
                         : String(localized: "\(Self.duration(minutes)) left"))
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                }
                Spacer()
            }
            UsageBar(value: Double(b.percent) / 100, tint: batteryTint(b.percent))
                .frame(height: 4)
            HStack(spacing: Spacing.md) {
                if let health = b.health {
                    stat(String(localized: "Health"), String(format: "%.0f%%", health * 100),
                         tint: health < 0.8 ? Theme.Semantic.warn : Theme.TextColor.secondary)
                }
                if let cycles = b.cycleCount {
                    stat(String(localized: "Cycles"), "\(cycles)", tint: Theme.TextColor.secondary)
                }
                if let t = b.temperatureC {
                    stat(String(localized: "Temp"), String(format: "%.0f°C", t),
                         tint: t >= 40 ? Theme.Semantic.warn : Theme.TextColor.secondary)
                }
                Spacer()
            }
        }
    }

    private func peripheral(_ device: PeripheralBattery) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: device.name.localizedCaseInsensitiveContains("airpods") ? "airpodspro"
                  : device.name.localizedCaseInsensitiveContains("mouse") ? "magicmouse"
                  : device.name.localizedCaseInsensitiveContains("keyboard") ? "keyboard"
                  : "headphones")
                .font(.system(size: 11))
                .foregroundStyle(Theme.TextColor.tertiary)
                .frame(width: 16)
            Text(device.name)
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.secondary)
                .lineLimit(1)
            Spacer()
            ForEach(device.levels, id: \.label) { level in
                Text(verbatim: level.label.isEmpty ? "\(level.percent)%" : "\(level.label) \(level.percent)%")
                    .font(Typography.monoSmall)
                    .foregroundStyle(batteryTint(level.percent))
            }
        }
    }

    private func stat(_ label: String, _ value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.tertiary)
            Text(verbatim: value)
                .font(Typography.monoSmall)
                .foregroundStyle(tint)
        }
    }

    private func symbol(for b: BatteryStats) -> String {
        if b.isCharging { return "battery.100.bolt" }
        switch b.percent {
        case ..<15: return "battery.0"
        case ..<40: return "battery.25"
        case ..<65: return "battery.50"
        case ..<90: return "battery.75"
        default:    return "battery.100"
        }
    }

    private func powerLine(_ b: BatteryStats) -> String {
        if b.onAC {
            let watts = b.adapterWatts.map { " · \($0) W" } ?? ""
            return (b.isCharging ? String(localized: "Charging") : String(localized: "On power")) + watts
        }
        return String(localized: "On battery")
    }

    private func batteryTint(_ percent: Int) -> Color {
        if percent <= 10 { return Theme.Semantic.danger }
        if percent <= 25 { return Theme.Semantic.warn }
        return Theme.Semantic.ok
    }

    static func duration(_ minutes: Int) -> String {
        let fmt = DateComponentsFormatter()
        fmt.allowedUnits = [.hour, .minute]
        fmt.unitsStyle = .abbreviated
        return fmt.string(from: TimeInterval(minutes * 60)) ?? "\(minutes)m"
    }
}

// MARK: - Shared

private struct TileHeader: View {
    let title: LocalizedStringKey
    let symbol: String

    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.tertiary)
            Spacer()
        }
    }
}

struct UsageBar: View {
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

private func loadTint(_ load: Double) -> Color {
    if load >= 0.85 { return Theme.Semantic.danger }
    if load >= 0.6 { return Theme.Semantic.warn }
    return Theme.Semantic.ok
}
