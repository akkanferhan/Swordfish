import SwiftUI

struct IOSSimulatorView: View {
    @StateObject private var service = SimulatorService()
    @State private var pendingDeleteUDID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            bulkActions

            if let error = service.lastError, !service.simulators.isEmpty {
                errorBanner(error)
            }

            if service.isLoading && service.simulators.isEmpty {
                placeholder("Loading simulators…")
            } else if let error = service.lastError, service.simulators.isEmpty {
                placeholder(error)
            } else if service.simulators.isEmpty {
                placeholder("No simulators available")
            } else {
                simulatorList
            }
        }
        .task { service.refresh() }
        .onChange(of: service.lastError) { newValue in
            guard newValue != nil else { return }
            let captured = newValue
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if service.lastError == captured {
                    service.lastError = nil
                }
            }
        }
    }

    // MARK: - Bulk

    private var bulkActions: some View {
        HStack(spacing: Spacing.sm) {
            PillButton(title: "Open Simulator", symbol: "iphone", action: service.openSimulatorApp)
            PillButton(title: "Shutdown All", symbol: "power", action: service.shutdownAll)
            Spacer()
            Button(action: service.refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.TextColor.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            .fill(Theme.Surface.surface1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(service.isLoading)
        }
    }

    // MARK: - List

    private var simulatorList: some View {
        let booted = service.simulators.filter { $0.isBooted }.count
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("\(service.simulators.count) simulator\(service.simulators.count == 1 ? "" : "s") · \(booted) booted")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                Spacer()
            }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(service.simulators) { sim in
                        SimulatorRow(
                            sim: sim,
                            isPendingDelete: pendingDeleteUDID == sim.udid,
                            onToggleBootState: {
                                sim.isBooted ? service.shutdown(sim) : service.boot(sim)
                            },
                            onDeleteRequest: { requestDelete(sim) }
                        )
                    }
                }
            }
            .frame(maxHeight: 260)
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(Typography.monoSmall)
            .foregroundStyle(Theme.TextColor.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, Spacing.md)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
            Text(message)
                .font(Typography.monoSmall)
                .lineLimit(2)
            Spacer()
            Button { service.lastError = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Theme.Semantic.danger)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(Theme.Semantic.danger.opacity(0.12))
        )
    }

    // MARK: - Two-step delete confirm

    private func requestDelete(_ sim: Simulator) {
        if pendingDeleteUDID == sim.udid {
            pendingDeleteUDID = nil
            service.delete(sim)
        } else {
            pendingDeleteUDID = sim.udid
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if pendingDeleteUDID == sim.udid { pendingDeleteUDID = nil }
            }
        }
    }
}

// MARK: - Row

private struct SimulatorRow: View {
    let sim: Simulator
    let isPendingDelete: Bool
    let onToggleBootState: () -> Void
    let onDeleteRequest: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(sim.isBooted ? Color.accentColor : Theme.TextColor.tertiary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(sim.name)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(Theme.TextColor.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(sim.runtime)
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                    if sim.isBooted {
                        Text("● Booted")
                            .font(Typography.monoSmall)
                            .foregroundStyle(Theme.Semantic.ok)
                    }
                }
            }
            Spacer(minLength: 0)

            if hovering || sim.isBooted || isPendingDelete {
                HStack(spacing: 4) {
                    ActionButton(
                        symbol: sim.isBooted ? "stop.fill" : "play.fill",
                        tint: sim.isBooted ? Theme.Semantic.warn : Theme.Semantic.ok,
                        action: onToggleBootState
                    )
                    ActionButton(
                        symbol: isPendingDelete ? "checkmark" : "trash",
                        label: isPendingDelete ? "Confirm?" : nil,
                        tint: isPendingDelete ? Theme.Semantic.danger : Theme.TextColor.tertiary,
                        action: onDeleteRequest
                    )
                }
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(hovering ? Theme.Surface.surface2 : Theme.Surface.surface1)
        )
        .onHover { hovering = $0 }
    }

    private var icon: String {
        let lower = sim.name.lowercased()
        if lower.contains("ipad") { return "ipad" }
        if lower.contains("watch") { return "applewatch" }
        if lower.contains("tv") { return "appletv" }
        if lower.contains("vision") { return "visionpro" }
        return "iphone"
    }
}

private struct ActionButton: View {
    let symbol: String
    var label: String? = nil
    let tint: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                if let label {
                    Text(label)
                        .font(Typography.monoSmall)
                }
            }
            .foregroundStyle(tint)
            .padding(.horizontal, label == nil ? 6 : Spacing.sm)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .fill(hovering ? tint.opacity(0.18) : tint.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
