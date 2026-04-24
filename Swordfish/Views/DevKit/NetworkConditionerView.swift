import SwiftUI

struct NetworkConditionerView: View {
    @StateObject private var service = NetworkThrottleService()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if service.isHelperInstalled {
                installedBody
            } else {
                notInstalledBody
            }

            if let err = service.lastError {
                Text(err)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.Semantic.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - States

    private var notInstalledBody: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Throttle the Mac's network (Wi-Fi / Ethernet) so iOS Simulators and apps see slower connections. Uses the same dummynet engine as Apple's Network Link Conditioner.")
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: service.installHelper) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: service.isBusy ? "arrow.clockwise" : "lock.shield")
                        .font(.system(size: 12, weight: .medium))
                    Text(service.isBusy ? "Installing…" : "Enable Network Throttling")
                        .font(Typography.bodyMedium)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .frame(maxWidth: .infinity)
                .foregroundStyle(Color.white)
                .background(
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .fill(Color.accentColor.opacity(service.isBusy ? 0.6 : 1.0))
                )
            }
            .buttonStyle(.plain)
            .disabled(service.isBusy)

            Text("One-time admin prompt. Swordfish writes a sudoers entry so future toggles don't ask for your password.")
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.quaternary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var installedBody: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                statusBadge
                Spacer(minLength: 0)
                Menu {
                    Button("Refresh interface", action: service.refreshInterface)
                    Button("Reinstall helper…", action: service.installHelper)
                    Divider()
                    Button("Disable & Uninstall helper…", role: .destructive, action: service.uninstallHelper)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.TextColor.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: 3)
            LazyVGrid(columns: columns, spacing: Spacing.sm) {
                ForEach(ThrottlePreset.allCases) { preset in
                    PresetTile(
                        preset: preset,
                        isActive: service.activePreset == preset,
                        isBusy: service.isBusy,
                        action: { service.apply(preset) }
                    )
                }
            }
        }
    }

    private var statusBadge: some View {
        let active = service.activePreset != .off
        let text: String = {
            if !active { return "Inactive" }
            if let iface = service.activeInterface {
                return "\(service.activePreset.label) · \(iface)"
            }
            return service.activePreset.label
        }()
        return HStack(spacing: 5) {
            Circle()
                .fill(active ? Theme.Semantic.warn : Theme.Semantic.ok)
                .frame(width: 6, height: 6)
            Text(text)
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.secondary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                .fill(Theme.Surface.surface1)
        )
    }
}

private struct PresetTile: View {
    let preset: ThrottlePreset
    let isActive: Bool
    let isBusy: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: preset.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tint)
                Text(preset.label)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(Theme.TextColor.primary)
                Text(preset.subtitle)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                    .fill(background)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                            .strokeBorder(border, lineWidth: isActive ? 1.2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .onHover { hovering = $0 }
        .animation(Motion.fast, value: hovering)
        .animation(Motion.fast, value: isActive)
    }

    private var tint: Color {
        switch preset {
        case .off:                         return Theme.Semantic.ok
        case .loss5, .loss100:             return Theme.Semantic.danger
        default:                           return Color.accentColor
        }
    }

    private var background: Color {
        if isActive { return tint.opacity(0.18) }
        return hovering ? Theme.Surface.surface2 : Theme.Surface.surface1
    }

    private var border: Color {
        isActive ? tint.opacity(0.6) : Theme.Border.subtle
    }
}
