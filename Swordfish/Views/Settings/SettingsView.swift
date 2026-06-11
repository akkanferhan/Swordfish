import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var loginItem: LoginItemManager
    @EnvironmentObject var lidSleep: LidSleepService
    @StateObject private var permissions = PermissionsModel()
    // Settings owns its own throttle service instance — it's only used to
    // install/remove the sudoers helper and read its file-backed status.
    @StateObject private var throttle = NetworkThrottleService()
    @State private var tab: SettingsTab = .general
    @State private var language = AppLanguage.current
    private let initialLanguage = AppLanguage.current

    enum SettingsTab: CaseIterable, Identifiable {
        case general, permissions
        var id: Self { self }
        var label: LocalizedStringKey {
            switch self {
            case .general:     return "General"
            case .permissions: return "Permissions"
            }
        }
        var symbol: String {
            switch self {
            case .general:     return "gearshape"
            case .permissions: return "lock.shield"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            tabBar
            ScrollView {
                switch tab {
                case .general:     generalTab
                case .permissions: permissionsTab
                }
            }
        }
        .padding(Spacing.mdLg)
        .frame(minWidth: 500, idealWidth: 520, minHeight: 460, idealHeight: 540)
        .task { permissions.refresh() }
    }

    // MARK: - Tabs

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { t in
                SettingsTabChip(title: t.label, symbol: t.symbol, isSelected: tab == t) {
                    withAnimation(Motion.default) { tab = t }
                }
            }
            Spacer()
            if tab == .permissions {
                ToolboxIconButton(symbol: "arrow.clockwise", help: "Refresh") {
                    permissions.refresh()
                    lidSleep.refreshHelperStatus()
                    throttle.refreshHelperStatus()
                }
            }
        }
    }

    // MARK: - General

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Tile {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    settingRow(
                        symbol: "globe",
                        title: "Language",
                        subtitle: Text("Applies after the app relaunches")
                    ) {
                        Picker("", selection: $language) {
                            ForEach(AppLanguage.allCases) { lang in
                                Text(lang.label).tag(lang)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 160)
                        .onChange(of: language) { newValue in
                            newValue.apply()
                        }
                    }
                    if language != initialLanguage {
                        relaunchBanner
                    }
                    SoftDivider()
                    settingRow(
                        symbol: "power",
                        title: "Launch at Login",
                        subtitle: Text("Start Swordfish automatically when you log in")
                    ) {
                        Toggle("", isOn: Binding(
                            get: { loginItem.isEnabled },
                            set: { _ in loginItem.toggle() }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                    }
                    if let err = loginItem.lastError {
                        Text("Login item error: \(err)")
                            .font(Typography.monoSmall)
                            .foregroundStyle(Theme.Semantic.danger)
                    }
                    SoftDivider()
                    settingRow(
                        symbol: "info.circle",
                        title: "Version",
                        subtitle: nil
                    ) {
                        Text(verbatim: "v\(AppVersion.short) (\(AppVersion.build))")
                            .font(Typography.monoSmall)
                            .foregroundStyle(Theme.TextColor.tertiary)
                    }
                }
            }
        }
    }

    private var relaunchBanner: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Semantic.warn)
            Text("Relaunch Swordfish to apply the new language.")
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.secondary)
            Spacer()
            AccentActionButton(title: "Relaunch Now", symbol: "arrow.clockwise") {
                AppLanguage.relaunch()
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(Theme.Semantic.warn.opacity(0.10))
        )
    }

    private func settingRow<Accessory: View>(
        symbol: String,
        title: LocalizedStringKey,
        subtitle: Text?,
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
                if let subtitle {
                    subtitle
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                }
            }
            Spacer()
            accessory()
        }
    }

    // MARK: - Permissions

    private var permissionsTab: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            PermissionRow(
                symbol: "camera.viewfinder",
                title: "Screen Recording",
                subtitle: Text("Color Picker eyedropper and Quick Screenshot"),
                badge: permissions.screenRecording
                    ? .ok("Granted")
                    : .warn("Not granted")
            ) {
                if !permissions.screenRecording {
                    PillButton(title: "Request", symbol: "hand.raised") {
                        permissions.requestScreenRecording()
                    }
                }
                PillButton(title: "Open System Settings", symbol: "arrow.up.right.square") {
                    PermissionsModel.openPrivacyPane("Privacy_ScreenCapture")
                }
            }
            PermissionRow(
                symbol: "command.square",
                title: "Automation · System Events",
                subtitle: Text("Lock Screen quick action (⌃⌘Q)"),
                badge: automationBadge
            ) {
                if permissions.automation == .notDetermined {
                    PillButton(title: "Request", symbol: "hand.raised") {
                        permissions.requestAutomation()
                    }
                }
                PillButton(title: "Open System Settings", symbol: "arrow.up.right.square") {
                    PermissionsModel.openPrivacyPane("Privacy_Automation")
                }
            }
            PermissionRow(
                symbol: "laptopcomputer",
                title: "Lid-Closed Mode helper",
                subtitle: Text("Sudoers entry for pmset — one-time admin prompt"),
                badge: lidSleep.isHelperInstalled
                    ? .ok("Installed")
                    : .neutral("Not installed"),
                error: lidSleep.lastError
            ) {
                if lidSleep.isHelperInstalled {
                    PillButton(title: lidSleep.isBusy ? "Working…" : "Remove helper", symbol: "trash") {
                        lidSleep.uninstallHelper()
                    }
                } else {
                    PillButton(title: lidSleep.isBusy ? "Working…" : "Install helper", symbol: "square.and.arrow.down") {
                        lidSleep.installHelperOnly()
                    }
                }
            }
            PermissionRow(
                symbol: "speedometer",
                title: "Network throttling helper",
                subtitle: Text("Sudoers entry for dnctl/pfctl — one-time admin prompt"),
                badge: throttle.isHelperInstalled
                    ? .ok("Installed")
                    : .neutral("Not installed"),
                error: throttle.lastError
            ) {
                if throttle.isHelperInstalled {
                    PillButton(title: throttle.isBusy ? "Working…" : "Remove helper", symbol: "trash") {
                        throttle.uninstallHelper()
                    }
                } else {
                    PillButton(title: throttle.isBusy ? "Working…" : "Install helper", symbol: "square.and.arrow.down") {
                        throttle.installHelper()
                    }
                }
            }
            PermissionRow(
                symbol: "hammer",
                title: "Xcode Developer Tools",
                subtitle: devToolsSubtitle,
                badge: permissions.simctlAvailable
                    ? .ok("Ready")
                    : .bad("Missing"),
                error: permissions.devToolsError
            ) {
                if !permissions.simctlAvailable {
                    if PermissionsModel.xcodeAppExists {
                        PillButton(title: permissions.isFixingDevTools ? "Working…" : "Fix now", symbol: "wrench.adjustable") {
                            permissions.fixDeveloperTools()
                        }
                    }
                    PillButton(title: "Copy fix command", symbol: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(PermissionsModel.xcodeFixCommand, forType: .string)
                    }
                }
            }
            PermissionRow(
                symbol: "key",
                title: "Admin privileges",
                subtitle: Text("Flush DNS asks for your password each time it runs"),
                badge: .neutral("Prompts on use")
            ) {}
        }
    }

    private var automationBadge: PermissionBadge {
        switch permissions.automation {
        case .granted:       return .ok("Granted")
        case .denied:        return .bad("Denied")
        case .notDetermined: return .warn("Not asked yet")
        }
    }

    private var devToolsSubtitle: Text {
        if permissions.simctlAvailable, let dir = permissions.developerDir {
            return Text(verbatim: dir)
        }
        return Text("simctl powers all Simulator features — point xcode-select at Xcode")
    }
}

// MARK: - Permission row

/// Tinted status chip for a permission row.
struct PermissionBadge {
    let label: String
    let tint: Color

    static func ok(_ key: String.LocalizationValue) -> PermissionBadge {
        PermissionBadge(label: String(localized: key), tint: Theme.Semantic.ok)
    }
    static func warn(_ key: String.LocalizationValue) -> PermissionBadge {
        PermissionBadge(label: String(localized: key), tint: Theme.Semantic.warn)
    }
    static func bad(_ key: String.LocalizationValue) -> PermissionBadge {
        PermissionBadge(label: String(localized: key), tint: Theme.Semantic.danger)
    }
    static func neutral(_ key: String.LocalizationValue) -> PermissionBadge {
        PermissionBadge(label: String(localized: key), tint: Theme.TextColor.tertiary)
    }
}

private struct PermissionRow<Actions: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let subtitle: Text?
    let badge: PermissionBadge
    var error: String? = nil
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: symbol)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.TextColor.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(Typography.bodyMedium)
                            .foregroundStyle(Theme.TextColor.primary)
                        if let subtitle {
                            subtitle
                                .font(Typography.monoSmall)
                                .foregroundStyle(Theme.TextColor.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                    Badge(label: badge.label, tint: badge.tint)
                }
                if let error {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text(error)
                            .font(Typography.monoSmall)
                            .lineLimit(2)
                    }
                    .foregroundStyle(Theme.Semantic.danger)
                }
                HStack(spacing: Spacing.sm) {
                    Spacer()
                    actions()
                }
            }
        }
    }
}

private struct SettingsTabChip: View {
    let title: LocalizedStringKey
    let symbol: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(Typography.bodyMedium)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.white : Theme.TextColor.secondary)
            .background(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .fill(isSelected
                          ? Color.accentColor
                          : (hovering ? Theme.Surface.surface2 : Theme.Surface.surface1))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
