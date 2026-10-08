import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings → Developer Keys: APNs and App Store Connect API keys. IDs are
/// stored in UserDefaults, the .p8 private keys in the Keychain.
struct DeveloperKeysSettingsView: View {
    @AppStorage(AppleKeys.apnsTeamIDKey) private var apnsTeamID = ""
    @AppStorage(AppleKeys.apnsKeyIDKey) private var apnsKeyID = ""
    @AppStorage(AppleKeys.ascIssuerIDKey) private var ascIssuerID = ""
    @AppStorage(AppleKeys.ascKeyIDKey) private var ascKeyID = ""
    @State private var apnsStored = AppleKeys.privateKey(.apns) != nil
    @State private var ascStored = AppleKeys.privateKey(.appStoreConnect) != nil
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            keyTile(
                title: "APNs Auth Key",
                subtitle: "Certificates, Identifiers & Profiles → Keys → Apple Push Notifications service. Used by the Push tester's Device (APNs) mode.",
                firstLabel: "Team ID", first: $apnsTeamID,
                secondLabel: "Key ID", second: $apnsKeyID,
                stored: apnsStored,
                kind: .apns
            )
            keyTile(
                title: "App Store Connect API Key",
                subtitle: "Users and Access → Integrations → App Store Connect API (Developer role is enough). Used for TestFlight build status.",
                firstLabel: "Issuer ID", first: $ascIssuerID,
                secondLabel: "Key ID", second: $ascKeyID,
                stored: ascStored,
                kind: .appStoreConnect
            )
            if let error {
                Text(error)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.Semantic.danger)
            }
            Text("Private keys are stored in your login Keychain and never leave this Mac except to sign requests to Apple.")
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.quaternary)
        }
    }

    private func keyTile(title: LocalizedStringKey, subtitle: LocalizedStringKey,
                         firstLabel: LocalizedStringKey, first: Binding<String>,
                         secondLabel: LocalizedStringKey, second: Binding<String>,
                         stored: Bool, kind: AppleKeys.Kind) -> some View {
        Tile {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text(title)
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Theme.TextColor.primary)
                    Spacer()
                    Badge(label: AppleKeys.hasKey(kind) ? String(localized: "Ready") : String(localized: "Incomplete"),
                          tint: AppleKeys.hasKey(kind) ? Theme.Semantic.ok : Theme.TextColor.tertiary)
                }
                Text(subtitle)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Spacing.sm) {
                    Text(firstLabel).font(Typography.monoSmall).frame(width: 64, alignment: .leading)
                    TextField("", text: first).textFieldStyle(.roundedBorder).font(Typography.mono)
                }
                HStack(spacing: Spacing.sm) {
                    Text(secondLabel).font(Typography.monoSmall).frame(width: 64, alignment: .leading)
                    TextField("", text: second).textFieldStyle(.roundedBorder).font(Typography.mono)
                }
                HStack(spacing: Spacing.sm) {
                    Text(".p8").font(Typography.monoSmall).frame(width: 64, alignment: .leading)
                    if stored {
                        Label("Stored in Keychain", systemImage: "lock.fill")
                            .font(Typography.monoSmall)
                            .foregroundStyle(Theme.Semantic.ok)
                        PillButton(title: "Remove", symbol: "trash") {
                            KeychainStore.delete(account: kind.keychainAccount)
                            refresh()
                        }
                    }
                    PillButton(title: stored ? "Replace…" : "Import .p8…", symbol: "key") { importKey(kind, keyID: second) }
                }
            }
        }
    }

    /// Imports AuthKey_XXXXXXXXXX.p8 and fills the Key ID from its file name when empty.
    private func importKey(_ kind: AppleKeys.Kind, keyID: Binding<String>) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "p8") ?? .data, .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let pem = try String(contentsOf: url, encoding: .utf8)
            try AppleKeys.storePrivateKey(pem, for: kind)
            let name = url.deletingPathExtension().lastPathComponent
            if keyID.wrappedValue.isEmpty, name.hasPrefix("AuthKey_") {
                keyID.wrappedValue = String(name.dropFirst("AuthKey_".count))
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }

    private func refresh() {
        apnsStored = AppleKeys.privateKey(.apns) != nil
        ascStored = AppleKeys.privateKey(.appStoreConnect) != nil
    }
}
