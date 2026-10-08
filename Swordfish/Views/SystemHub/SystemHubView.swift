import SwiftUI

struct SystemHubView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            DisplaysSection()
            AntiSleepSection()
            QuickTogglesSection()
            HardwareSection()
            ProcessesSection()
        }
    }
}

private struct AntiSleepSection: View {
    var body: some View {
        CollapsibleSection(title: "Anti-Sleep", id: "antiSleep") {
            AntiSleepRow()
        }
    }
}

private struct HardwareSection: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        CollapsibleSection(title: "Hardware", badge: thermalBadge, id: "hardware") {
            HardwareStatsSection()
        }
    }
}

private extension HardwareSection {
    /// Only shown once macOS reports thermal pressure — "nominal" is noise.
    var thermalBadge: String? {
        switch monitor.thermalState {
        case .fair:     return String(localized: "Thermal: fair")
        case .serious:  return String(localized: "Thermal: throttling")
        case .critical: return String(localized: "Thermal: critical")
        default:        return nil
        }
    }
}
