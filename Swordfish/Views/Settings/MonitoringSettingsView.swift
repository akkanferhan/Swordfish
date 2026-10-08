import SwiftUI
import UserNotifications

/// Settings → Monitoring: the menu bar metric and threshold notifications.
struct MonitoringSettingsView: View {
    @EnvironmentObject var alerts: AlertService

    @AppStorage(MenuBarMetric.defaultsKey) private var metric: MenuBarMetric = .none
    @AppStorage(AlertSettings.cpuTempEnabled) private var cpuEnabled = false
    @AppStorage(AlertSettings.cpuTempThreshold) private var cpuThreshold = AlertSettings.defaultCPUTemp
    @AppStorage(AlertSettings.diskEnabled) private var diskEnabled = false
    @AppStorage(AlertSettings.diskThresholdGB) private var diskThreshold = AlertSettings.defaultDiskGB
    @AppStorage(AlertSettings.memoryEnabled) private var memoryEnabled = false
    @AppStorage(AlertSettings.thermalEnabled) private var thermalEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Tile {
                row(symbol: "menubar.rectangle", title: "Menu bar shows",
                    subtitle: "A live value next to the Swordfish icon") {
                    Picker("", selection: $metric) {
                        ForEach(MenuBarMetric.allCases) { m in Text(m.label).tag(m) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 170)
                }
            }

            Tile {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        Text("Alerts").sectionTitleStyle()
                        Spacer()
                        authorizationBadge
                    }
                    if alerts.authorization == .denied {
                        Text("Notifications are turned off for Swordfish in System Settings → Notifications.")
                            .font(Typography.monoSmall)
                            .foregroundStyle(Theme.Semantic.warn)
                    }
                    row(symbol: "thermometer.high", title: "CPU temperature",
                        subtitle: Text("Notify above \(cpuThreshold)°C for a few seconds")) {
                        Stepper("", value: $cpuThreshold, in: 60...105, step: 5)
                            .labelsHidden()
                            .disabled(!cpuEnabled)
                        alertToggle($cpuEnabled)
                    }
                    SoftDivider()
                    row(symbol: "internaldrive", title: "Low disk space",
                        subtitle: Text("Notify below \(diskThreshold) GB free")) {
                        Stepper("", value: $diskThreshold, in: 5...200, step: 5)
                            .labelsHidden()
                            .disabled(!diskEnabled)
                        alertToggle($diskEnabled)
                    }
                    SoftDivider()
                    row(symbol: "memorychip", title: "Critical memory pressure",
                        subtitle: Text("When macOS starts swapping heavily")) {
                        alertToggle($memoryEnabled)
                    }
                    SoftDivider()
                    row(symbol: "flame", title: "Thermal throttling",
                        subtitle: Text("When macOS slows the CPU down to cool off")) {
                        alertToggle($thermalEnabled)
                    }
                    HStack {
                        Text("Each alert fires at most once every 30 minutes.")
                            .font(Typography.monoSmall)
                            .foregroundStyle(Theme.TextColor.quaternary)
                        Spacer()
                        PillButton(title: "Send Test", symbol: "bell") { alerts.sendTest() }
                            .disabled(alerts.authorization != .authorized && alerts.authorization != .provisional)
                    }
                }
            }
        }
        .onAppear { alerts.refreshAuthorization() }
    }

    /// Turning any alert on asks for notification permission first time.
    private func alertToggle(_ binding: Binding<Bool>) -> some View {
        Toggle("", isOn: Binding(
            get: { binding.wrappedValue },
            set: { on in
                binding.wrappedValue = on
                if on && alerts.authorization == .notDetermined { alerts.requestAuthorization() }
            }
        ))
        .toggleStyle(.switch)
        .controlSize(.small)
        .labelsHidden()
    }

    @ViewBuilder
    private var authorizationBadge: some View {
        switch alerts.authorization {
        case .authorized, .provisional, .ephemeral:
            Badge(label: String(localized: "Notifications on"), tint: Theme.Semantic.ok)
        case .denied:
            Badge(label: String(localized: "Notifications off"), tint: Theme.Semantic.danger)
        default:
            Badge(label: String(localized: "Not asked yet"), tint: Theme.TextColor.tertiary)
        }
    }

    private func row<Accessory: View>(
        symbol: String,
        title: LocalizedStringKey,
        subtitle: Text,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(Theme.TextColor.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(Theme.TextColor.primary)
                subtitle
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
            }
            Spacer()
            accessory()
        }
    }

    private func row<Accessory: View>(
        symbol: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        row(symbol: symbol, title: title, subtitle: Text(subtitle), accessory: accessory)
    }
}
