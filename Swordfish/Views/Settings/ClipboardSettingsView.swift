import SwiftUI
import AppKit

/// Settings → Clipboard: history persistence & size, quick-paste hotkey,
/// Accessibility (for direct paste), and the excluded-apps list.
struct ClipboardSettingsView: View {
    @EnvironmentObject var clipboard: ClipboardService

    @AppStorage(ClipboardSettings.persistKey) private var persist = true
    @AppStorage(ClipboardSettings.capacityKey) private var capacity = 100
    @AppStorage(ClipboardSettings.hotkeyKey) private var hotkey: QuickPasteHotkey = .controlCommandV
    @State private var excluded: [String] = ClipboardSettings.excludedApps
    @State private var accessibilityGranted = QuickPasteController.canPaste

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Tile {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    row(symbol: "externaldrive", title: "Keep history after quitting",
                        subtitle: "Stored in ~/Library/Application Support/Swordfish (secrets never are)") {
                        Toggle("", isOn: $persist)
                            .toggleStyle(.switch).controlSize(.small).labelsHidden()
                            .onChange(of: persist) { _ in clipboard.settingsChanged() }
                    }
                    SoftDivider()
                    row(symbol: "list.number", title: "History size", subtitle: "Pinned items don't count") {
                        Picker("", selection: $capacity) {
                            ForEach(ClipboardSettings.capacities, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 80)
                        .onChange(of: capacity) { _ in clipboard.settingsChanged() }
                    }
                }
            }

            Tile {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    row(symbol: "keyboard", title: "Quick paste panel",
                        subtitle: "Search clipboard history from any app") {
                        Picker("", selection: $hotkey) {
                            ForEach(QuickPasteHotkey.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }
                    if hotkey == .shiftCommandV {
                        Text("⇧⌘V replaces “Paste and Match Style” in Xcode, Slack and most editors.")
                            .font(Typography.monoSmall)
                            .foregroundStyle(Theme.Semantic.warn)
                    }
                    SoftDivider()
                    row(symbol: "accessibility", title: "Paste directly",
                        subtitle: accessibilityGranted
                            ? "Enter pastes into the app you were using"
                            : "Without Accessibility, Enter only copies — then press ⌘V yourself") {
                        if accessibilityGranted {
                            Badge(label: String(localized: "Granted"), tint: Theme.Semantic.ok)
                        } else {
                            PillButton(title: "Grant Access", symbol: "hand.raised") {
                                QuickPasteController.requestAccessibility()
                            }
                            PillButton(title: "Recheck", symbol: "arrow.clockwise") {
                                accessibilityGranted = QuickPasteController.canPaste
                            }
                        }
                    }
                }
            }

            Tile {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Never record copies from")
                                .font(Typography.bodyMedium)
                                .foregroundStyle(Theme.TextColor.primary)
                            Text("Copies marked private by any app (1Password, Bitwarden…) are always skipped. Tokens & API keys are masked and auto-deleted after 2 minutes.")
                                .font(Typography.monoSmall)
                                .foregroundStyle(Theme.TextColor.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Menu {
                            ForEach(runningApps, id: \.bundleIdentifier) { app in
                                Button(app.localizedName ?? app.bundleIdentifier ?? "?") {
                                    if let id = app.bundleIdentifier { add(id) }
                                }
                            }
                        } label: {
                            Label("Add App", systemImage: "plus")
                                .font(Typography.monoSmall)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    ForEach(excluded, id: \.self) { bundleID in
                        HStack(spacing: Spacing.sm) {
                            if let icon = ClipboardImageCache.appIcon(bundleID: bundleID) {
                                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "app.dashed").frame(width: 16, height: 16)
                            }
                            Text(Self.appName(bundleID))
                                .font(Typography.mono)
                                .foregroundStyle(Theme.TextColor.secondary)
                            Text(bundleID)
                                .font(Typography.monoSmall)
                                .foregroundStyle(Theme.TextColor.quaternary)
                                .lineLimit(1)
                            Spacer()
                            Button { remove(bundleID) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain)
                                .foregroundStyle(Theme.TextColor.tertiary)
                        }
                    }
                }
            }
        }
        .onAppear { accessibilityGranted = QuickPasteController.canPaste }
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && !excluded.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func add(_ id: String) {
        excluded.append(id)
        UserDefaults.standard.set(excluded, forKey: ClipboardSettings.excludedAppsKey)
    }

    private func remove(_ id: String) {
        excluded.removeAll { $0 == id }
        UserDefaults.standard.set(excluded, forKey: ClipboardSettings.excludedAppsKey)
    }

    /// Installed apps show their real name; not-installed defaults fall back to the ID's last part.
    private static func appName(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }

    private func row<Accessory: View>(symbol: String, title: LocalizedStringKey, subtitle: LocalizedStringKey,
                                      @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(Theme.TextColor.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(Theme.TextColor.primary)
                Text(subtitle)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            accessory()
        }
    }
}
