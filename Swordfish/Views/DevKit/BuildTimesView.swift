import SwiftUI

/// Recent Xcode builds per scheme with durations, a trend sparkline and
/// the build-notification switches.
struct BuildTimesView: View {
    @EnvironmentObject var monitor: BuildMonitor
    @AppStorage(BuildSettings.notifyKey) private var notify = true
    @AppStorage(BuildSettings.minSecondsKey) private var minSeconds = 10
    @AppStorage(BuildSettings.onlyBackgroundKey) private var onlyBackground = true
    @State private var expandedKey: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            settings
            if monitor.schemes.isEmpty {
                Text("No builds found in DerivedData yet — build something in Xcode.")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.sm)
            } else {
                VStack(spacing: 4) {
                    ForEach(monitor.schemes.prefix(8), id: \.key) { group in
                        SchemeRow(builds: group.builds,
                                  isExpanded: expandedKey == group.key) {
                            withAnimation(Motion.fast) {
                                expandedKey = expandedKey == group.key ? nil : group.key
                            }
                        }
                    }
                }
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Spacing.sm) {
                Toggle("Notify when a build finishes", isOn: $notify)
                    .toggleStyle(.checkbox)
                    .font(Typography.monoSmall)
                Spacer()
                Stepper("≥ \(minSeconds) s", value: $minSeconds, in: 0...300, step: 5)
                    .font(Typography.monoSmall)
                    .disabled(!notify)
                    .help("Skip quick incremental builds; failures always notify")
            }
            Toggle("Only while Xcode is in the background", isOn: $onlyBackground)
                .toggleStyle(.checkbox)
                .font(Typography.monoSmall)
                .disabled(!notify)
        }
    }
}

private struct SchemeRow: View {
    let builds: [BuildRecord]          // newest first
    let isExpanded: Bool
    let toggle: () -> Void
    @State private var hovering = false

    private var latest: BuildRecord { builds[0] }
    private var successful: [BuildRecord] { builds.filter { $0.status != .failed } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Spacing.sm) {
                StatusDot(status: latest.status)
                VStack(alignment: .leading, spacing: 1) {
                    Text(latest.scheme)
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Theme.TextColor.primary)
                    Text(verbatim: "\(latest.project) · \(relative(latest.ended))")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Sparkline(values: successful.prefix(12).reversed().map(\.duration), color: Color.accentColor)
                    .frame(width: 60, height: 16)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(BuildRecord.formatDuration(latest.duration))
                        .font(Typography.mono.weight(.semibold))
                        .foregroundStyle(Theme.TextColor.primary)
                    if let avg = average {
                        Text("avg \(BuildRecord.formatDuration(avg))")
                            .font(Typography.monoSmall)
                            .foregroundStyle(Theme.TextColor.tertiary)
                    }
                }
            }
            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(builds.prefix(10)) { build in
                        HStack(spacing: Spacing.sm) {
                            StatusDot(status: build.status)
                            Text(build.ended.formatted(date: .abbreviated, time: .shortened))
                                .font(Typography.monoSmall)
                                .foregroundStyle(Theme.TextColor.secondary)
                            if build.errors > 0 {
                                Text("\(build.errors) err")
                                    .font(Typography.monoSmall)
                                    .foregroundStyle(Theme.Semantic.danger)
                            }
                            if build.warnings > 0 {
                                Text("\(build.warnings) warn")
                                    .font(Typography.monoSmall)
                                    .foregroundStyle(Theme.Semantic.warn)
                            }
                            Spacer()
                            Text(BuildRecord.formatDuration(build.duration))
                                .font(Typography.monoSmall)
                                .foregroundStyle(Theme.TextColor.secondary)
                        }
                    }
                }
                .padding(.leading, 18)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(hovering ? Theme.Surface.surface2 : Theme.Surface.surface1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { hovering = $0 }
    }

    /// Mean of the last 10 non-failed builds.
    private var average: TimeInterval? {
        let recent = successful.prefix(10)
        guard recent.count >= 2 else { return nil }
        return recent.map(\.duration).reduce(0, +) / Double(recent.count)
    }

    private func relative(_ date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}

private struct StatusDot: View {
    let status: BuildRecord.Status

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 12)
    }

    private var symbol: String {
        switch status {
        case .succeeded: return "checkmark.circle.fill"
        case .warnings:  return "exclamationmark.triangle.fill"
        case .failed:    return "xmark.circle.fill"
        case .other:     return "circle.dashed"
        }
    }

    private var color: Color {
        switch status {
        case .succeeded: return Theme.Semantic.ok
        case .warnings:  return Theme.Semantic.warn
        case .failed:    return Theme.Semantic.danger
        case .other:     return Theme.TextColor.tertiary
        }
    }
}
