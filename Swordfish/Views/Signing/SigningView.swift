import SwiftUI
import AppKit

struct SigningView: View {
    enum Tab: CaseIterable, Identifiable {
        case profiles, certificates
        var id: Self { self }
        var label: LocalizedStringKey {
            switch self {
            case .profiles:     return "Provisioning Profiles"
            case .certificates: return "Signing Certificates"
            }
        }
    }

    @StateObject private var service = SigningService()
    @State private var tab: Tab = .profiles
    @State private var search = ""
    @State private var hideExpired = false
    @State private var selectedID: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            switch tab {
            case .profiles:     profilesPane
            case .certificates: certificatesPane
            }
            if let err = service.lastError {
                Divider()
                Text(err)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.Semantic.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 5)
            }
        }
        .background(Theme.Surface.popover)
        .task { service.refresh() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: Spacing.sm) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { t in Text(t.label).tag(t) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 340)
            if tab == .profiles {
                TextField("Search name, bundle ID, team", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .font(Typography.mono)
                Toggle("Hide expired", isOn: $hideExpired)
                    .toggleStyle(.checkbox)
                    .font(Typography.monoSmall)
                let expired = service.profiles.filter(\.isExpired)
                if !expired.isEmpty {
                    PillButton(title: "Trash \(expired.count) Expired", symbol: "trash") {
                        service.trash(expired)
                    }
                }
            } else {
                Spacer()
            }
            ToolboxIconButton(symbol: "arrow.clockwise", help: "Reload") { service.refresh() }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Profiles

    private var filteredProfiles: [ProvisioningProfile] {
        service.profiles.filter { p in
            if hideExpired && p.isExpired { return false }
            guard !search.isEmpty else { return true }
            return [p.name, p.bundleID, p.teamName ?? "", p.teamID ?? "", p.uuid]
                .contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    private var profilesPane: some View {
        HSplitView {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filteredProfiles) { profile in
                        ProfileRow(profile: profile,
                                   hasIdentity: !profile.certificateFingerprints.isDisjoint(with: service.identityFingerprints),
                                   isSelected: selectedID == profile.id)
                            .onTapGesture { selectedID = profile.id }
                    }
                }
                .padding(Spacing.sm)
            }
            .overlay {
                if filteredProfiles.isEmpty {
                    Text(service.isLoading ? "Loading profiles…" : "No provisioning profiles found")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                }
            }
            .frame(minWidth: 380)

            Group {
                if let profile = service.profiles.first(where: { $0.id == selectedID }) {
                    ProfileDetail(profile: profile,
                                  matchingIdentities: service.identities.filter { profile.certificateFingerprints.contains($0.fingerprint) },
                                  onTrash: { service.trash([profile]) })
                } else {
                    Text("Select a profile")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 340)
        }
    }

    // MARK: - Certificates

    private var certificatesPane: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(service.identities) { identity in
                    IdentityRow(identity: identity,
                                profileCount: service.profiles.filter { $0.certificateFingerprints.contains(identity.fingerprint) }.count)
                }
            }
            .padding(Spacing.sm)
        }
        .overlay {
            if service.identities.isEmpty {
                Text(service.isLoading ? "Loading certificates…" : "No code-signing identities in the keychain")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
            }
        }
    }
}

// MARK: - Rows

private func expiryText(_ date: Date?) -> String {
    guard let date else { return "—" }
    return date.formatted(date: .abbreviated, time: .omitted)
        + " · " + date.formatted(.relative(presentation: .named))
}

private func expiryColor(expired: Bool, soon: Bool) -> Color {
    expired ? Theme.Semantic.danger : (soon ? Theme.Semantic.warn : Theme.TextColor.tertiary)
}

private struct ProfileRow: View {
    let profile: ProvisioningProfile
    let hasIdentity: Bool
    let isSelected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile.name)
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Theme.TextColor.primary)
                        .lineLimit(1)
                    KindBadge(text: profile.kind.label)
                    if profile.isXcodeManaged { KindBadge(text: String(localized: "Xcode")) }
                }
                Text(profile.bundleID)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(verbatim: [profile.teamName, profile.teamID].compactMap { $0 }.joined(separator: " · "))
                    if !profile.devices.isEmpty {
                        Text("· \(profile.devices.count) device(s)")
                    }
                }
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.tertiary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(expiryText(profile.expires))
                    .font(Typography.monoSmall)
                    .foregroundStyle(expiryColor(expired: profile.isExpired, soon: profile.expiresSoon))
                if !hasIdentity && !profile.isExpired {
                    Label("No certificate in keychain", systemImage: "exclamationmark.triangle")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.Semantic.warn)
                }
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.15)
                      : (hovering ? Theme.Surface.surface2 : Theme.Surface.surface1))
        )
        .opacity(profile.isExpired ? 0.6 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

private struct IdentityRow: View {
    let identity: SigningIdentity
    let profileCount: Int

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.seal")
                .foregroundStyle(expiryColor(expired: identity.isExpired, soon: identity.expiresSoon))
            VStack(alignment: .leading, spacing: 2) {
                Text(identity.name)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(Theme.TextColor.primary)
                Text(verbatim: "SHA-1 \(identity.fingerprint)")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.quaternary)
                    .textSelection(.enabled)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(expiryText(identity.expires))
                    .font(Typography.monoSmall)
                    .foregroundStyle(expiryColor(expired: identity.isExpired, soon: identity.expiresSoon))
                Text("Used by \(profileCount) profile(s)")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(Theme.Surface.surface1)
        )
    }
}

private struct KindBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(Theme.TextColor.secondary)
            .background(
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .fill(Theme.Surface.surface3)
            )
    }
}

// MARK: - Detail

private struct ProfileDetail: View {
    let profile: ProvisioningProfile
    let matchingIdentities: [SigningIdentity]
    let onTrash: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(profile.name)
                    .font(Typography.title)
                    .foregroundStyle(Theme.TextColor.primary)
                HStack(spacing: Spacing.sm) {
                    PillButton(title: "Reveal in Finder", symbol: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([profile.url])
                    }
                    PillButton(title: "Move to Trash", symbol: "trash", action: onTrash)
                }
                VStack(alignment: .leading, spacing: 4) {
                    ValueRow(label: "UUID", value: profile.uuid)
                    ValueRow(label: "Bundle ID", value: profile.bundleID)
                    if let v = profile.appIDName { ValueRow(label: "App ID name", value: v) }
                    if let v = profile.teamID { ValueRow(label: "Team", value: [profile.teamName, v].compactMap { $0 }.joined(separator: " · ")) }
                    ValueRow(label: "Type", value: profile.kind.label)
                    ValueRow(label: "Platforms", value: profile.platforms.joined(separator: ", "))
                    if let d = profile.created { ValueRow(label: "Created", value: d.formatted(date: .abbreviated, time: .shortened)) }
                    if let d = profile.expires { ValueRow(label: "Expires", value: d.formatted(date: .abbreviated, time: .shortened)) }
                }

                Text("Certificates in keychain").sectionTitleStyle()
                if matchingIdentities.isEmpty {
                    Label("None of this profile's certificates are in your keychain — Xcode can't sign with it on this Mac.",
                          systemImage: "exclamationmark.triangle")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.Semantic.warn)
                } else {
                    ForEach(matchingIdentities) { identity in
                        Text(identity.name)
                            .font(Typography.mono)
                            .foregroundStyle(Theme.TextColor.secondary)
                    }
                }

                HStack {
                    Text("Entitlements").sectionTitleStyle()
                    Spacer()
                    CopyButton(text: profile.entitlementsJSON)
                }
                Text(verbatim: profile.entitlementsJSON)
                    .font(Typography.code)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                            .fill(Theme.Surface.codeBg)
                    )

                if !profile.devices.isEmpty {
                    HStack {
                        Text("Devices (\(profile.devices.count))").sectionTitleStyle()
                        Spacer()
                        CopyButton(text: profile.devices.joined(separator: "\n"))
                    }
                    Text(verbatim: profile.devices.joined(separator: "\n"))
                        .font(Typography.code)
                        .foregroundStyle(Theme.TextColor.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
