import SwiftUI
import AppKit

/// One section bundling the day-to-day `simctl` helpers that act on a booted
/// simulator: status bar overrides, privacy permissions, location simulation,
/// adding media, app data containers — plus quick screenshot and light/dark
/// appearance actions in the header row.
struct SimulatorToolboxView: View {
    @StateObject private var service = SimulatorService()
    @State private var selectedUDID: String = ""
    @State private var tool: Tool = .statusBar
    @State private var quickStatus: ToolboxStatus?

    enum Tool: String, CaseIterable, Identifiable {
        case statusBar = "Status Bar"
        case permissions = "Permissions"
        case location = "Location"
        case media = "Media"
        case apps = "Apps"

        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self {
            case .statusBar:   return "Status Bar"
            case .permissions: return "Permissions"
            case .location:    return "Location"
            case .media:       return "Media"
            case .apps:        return "Apps"
            }
        }
        var symbol: String {
            switch self {
            case .statusBar:   return "battery.100"
            case .permissions: return "hand.raised"
            case .location:    return "location"
            case .media:       return "photo.on.rectangle"
            case .apps:        return "app.badge"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            targetRow
            if let quickStatus {
                ToolboxStatusLine(status: quickStatus)
            }
            if selectedUDID.isEmpty {
                placeholder
            } else {
                toolChips
                panel
            }
        }
        .task { service.refresh() }
    }

    // MARK: - Target row (picker + quick actions)

    private var targetRow: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "iphone")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.TextColor.tertiary)
                simulatorPicker
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .fill(Theme.Surface.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            .strokeBorder(Theme.Border.subtle, lineWidth: 1)
                    )
            )
            Spacer()
            ToolboxIconButton(symbol: "camera", help: "Screenshot to Desktop") {
                runQuick {
                    let url = try SimulatorToolbox.screenshot(udid: selectedUDID)
                    return .ok(String(localized: "Saved \(url.lastPathComponent)"), url)
                }
            }
            ToolboxIconButton(symbol: "sun.max", help: "Light appearance") {
                runQuick {
                    try SimulatorToolbox.setAppearance(udid: selectedUDID, dark: false)
                    return .ok(String(localized: "Switched to light appearance"), nil)
                }
            }
            ToolboxIconButton(symbol: "moon", help: "Dark appearance") {
                runQuick {
                    try SimulatorToolbox.setAppearance(udid: selectedUDID, dark: true)
                    return .ok(String(localized: "Switched to dark appearance"), nil)
                }
            }
            ToolboxIconButton(symbol: "arrow.clockwise", help: "Refresh simulators") {
                quickStatus = nil
                service.refresh()
            }
        }
        .disabled(selectedUDID.isEmpty && !service.simulators.contains(where: \.isBooted))
    }

    @ViewBuilder
    private var simulatorPicker: some View {
        let booted = service.simulators.filter { $0.isBooted }
        if booted.isEmpty {
            Text("No booted simulators")
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.tertiary)
        } else {
            Picker("", selection: $selectedUDID) {
                ForEach(booted) { sim in Text(sim.name).tag(sim.udid) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .font(Typography.monoSmall)
            .frame(minWidth: 120)
            .onAppear {
                if !booted.contains(where: { $0.udid == selectedUDID }) {
                    selectedUDID = booted.first?.udid ?? ""
                }
            }
        }
    }

    private var placeholder: some View {
        Text("Boot a simulator to use the toolbox")
            .font(Typography.monoSmall)
            .foregroundStyle(Theme.TextColor.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, Spacing.md)
    }

    // MARK: - Tool chips

    private var toolChips: some View {
        HStack(spacing: 4) {
            ForEach(Tool.allCases) { t in
                ToolChip(title: t.label, symbol: t.symbol, isSelected: tool == t) {
                    withAnimation(Motion.default) { tool = t }
                }
            }
        }
    }

    @ViewBuilder
    private var panel: some View {
        switch tool {
        case .statusBar:   StatusBarPanel(udid: selectedUDID)
        case .permissions: PermissionsPanel(udid: selectedUDID)
        case .location:    LocationPanel(udid: selectedUDID)
        case .media:       MediaPanel(udid: selectedUDID)
        case .apps:        AppsPanel(udid: selectedUDID)
        }
    }

    // MARK: - Quick actions

    private func runQuick(_ work: @escaping () throws -> ToolboxStatus) {
        guard !selectedUDID.isEmpty else { return }
        quickStatus = nil
        Task.detached(priority: .userInitiated) {
            let outcome: ToolboxStatus
            do { outcome = try work() }
            catch { outcome = .error(error.localizedDescription) }
            await MainActor.run { quickStatus = outcome }
        }
    }
}

// MARK: - Shared toolbox widgets

enum ToolboxStatus {
    case ok(String, URL?)
    case error(String)

    var isError: Bool { if case .error = self { return true }; return false }
    var message: String {
        switch self {
        case .ok(let s, _), .error(let s): return s
        }
    }
    var revealURL: URL? { if case .ok(_, let url) = self { return url }; return nil }
}

struct ToolboxStatusLine: View {
    let status: ToolboxStatus

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.isError ? "xmark.circle" : "checkmark.circle")
                .font(.system(size: 11))
            Text(status.message)
                .font(Typography.monoSmall)
                .lineLimit(2)
            if let url = status.revealURL {
                Spacer()
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Text("Reveal in Finder")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Color.accentColor)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(status.isError ? Theme.Semantic.danger : Theme.Semantic.ok)
    }
}

struct ToolboxIconButton: View {
    let symbol: String
    var help: LocalizedStringKey = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.TextColor.secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .fill(hovering ? Theme.Surface.surface2 : Theme.Surface.surface1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

private struct ToolChip: View {
    let title: LocalizedStringKey
    let symbol: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9.5, weight: .medium))
                Text(title)
                    .font(Typography.monoSmall)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? Color.white : Theme.TextColor.secondary)
            .background(
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .fill(isSelected
                          ? Color.accentColor
                          : (hovering ? Theme.Surface.surface2 : Theme.Surface.surface1))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
