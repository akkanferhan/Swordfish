import SwiftUI

struct AntiSleepRow: View {
    @EnvironmentObject var caffeine: CaffeineService

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: Spacing.smMd) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(caffeine.isEnabled ? Color.accentColor : Theme.TextColor.secondary)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Anti-Sleep")
                            .font(Typography.bodyMedium)
                            .foregroundStyle(Theme.TextColor.primary)
                        statusLine
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { caffeine.isEnabled },
                        set: { v in v ? caffeine.enable() : caffeine.disable() }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                }

                if caffeine.isEnabled, caffeine.duration != .indefinite {
                    ProgressBar(progress: progress, tint: Color.accentColor)
                        .frame(height: 3)
                }

                DurationPicker(
                    selection: Binding(
                        get: { caffeine.duration },
                        set: { caffeine.setDuration($0) }
                    )
                )
            }
        }
    }

    // MARK: - Status line

    @ViewBuilder
    private var statusLine: some View {
        if caffeine.isEnabled {
            if caffeine.duration == .indefinite {
                Text("Awake · ∞")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Color.accentColor)
            } else {
                HStack(spacing: 4) {
                    Text(formatRemaining(caffeine.remaining))
                        .font(Typography.monoSmall)
                        .foregroundStyle(Color.accentColor)
                    Text("· ends \(formatEndTime(caffeine.expiresAt))")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                }
            }
        } else {
            Text(caffeine.duration == .indefinite ? "Idle" : "Idle · \(caffeine.duration.label) preset")
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.tertiary)
        }
    }

    private var progress: Double {
        let total = Double(caffeine.duration.rawValue)
        guard total > 0 else { return 0 }
        let elapsed = total - caffeine.remaining
        return max(0, min(1, elapsed / total))
    }

    private func formatRemaining(_ t: TimeInterval) -> String {
        let hours = Int(t) / 3600
        let minutes = (Int(t) % 3600) / 60
        let seconds = Int(t) % 60
        if hours > 0 { return String(format: "%dh %02dm", hours, minutes) }
        if minutes > 0 { return String(format: "%dm %02ds", minutes, seconds) }
        return String(format: "%ds", seconds)
    }

    private func formatEndTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }
}

// MARK: - Progress bar

private struct ProgressBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Theme.Surface.surface2)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(tint)
                    .frame(width: proxy.size.width * CGFloat(progress))
            }
        }
    }
}

// MARK: - Duration picker

private struct DurationPicker: View {
    @Binding var selection: CaffeineService.Duration

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CaffeineService.Duration.allCases) { d in
                DurationChip(label: d.label, isSelected: selection == d) {
                    selection = d
                }
            }
        }
    }
}

private struct DurationChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Typography.monoSmall)
                .foregroundStyle(isSelected ? .white : Theme.TextColor.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .fill(isSelected
                              ? Color.accentColor
                              : (hovering ? Theme.Surface.surface2 : Theme.Surface.surface1))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                                .strokeBorder(isSelected ? .clear : Theme.Border.subtle, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.fast, value: isSelected)
    }
}
