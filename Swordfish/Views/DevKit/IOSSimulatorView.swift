import SwiftUI

struct IOSSimulatorView: View {
    @StateObject private var service = SimulatorService()
    @State private var pendingDeleteUDID: String?
    @State private var showingCreate = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            bulkActions

            if showingCreate {
                CreateSimulatorForm(service: service) { showingCreate = false }
            }
            if let message = service.lastMessage {
                ToolboxStatusLine(status: .ok(message, nil))
            }

            if let error = service.lastError, !service.simulators.isEmpty {
                errorBanner(error)
            }

            if service.isLoading && service.simulators.isEmpty {
                placeholder(String(localized: "Loading simulators…"))
            } else if let error = service.lastError, service.simulators.isEmpty {
                placeholder(error)
            } else if service.simulators.isEmpty {
                placeholder(String(localized: "No simulators available"))
            } else {
                simulatorList
            }
        }
        .task {
            // Poll while the section is visible so booting/shutdown transitions
            // and changes made from Simulator.app or Xcode show up without a
            // manual refresh. The task is cancelled automatically when the view
            // is collapsed.
            while !Task.isCancelled {
                service.refresh()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
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
            PillButton(title: "New", symbol: "plus") {
                withAnimation(Motion.fast) { showingCreate.toggle() }
            }
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
                Text("\(service.simulators.count) simulator(s) · \(booted) booted")
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
                            pendingAction: service.pendingActions[sim.udid],
                            onToggleBootState: {
                                sim.isBooted ? service.shutdown(sim) : service.boot(sim)
                            },
                            onDeleteRequest: { requestDelete(sim) },
                            onRename: { service.rename(sim, to: $0) },
                            onClone: { service.clone(sim) },
                            onErase: { service.erase(sim) }
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
    let pendingAction: SimulatorService.PendingAction?
    let onToggleBootState: () -> Void
    let onDeleteRequest: () -> Void
    let onRename: (String) -> Void
    let onClone: () -> Void
    let onErase: () -> Void

    @State private var hovering = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmingErase = false

    private var isPendingBootChange: Bool { pendingAction != nil }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(sim.isBooted ? Color.accentColor : Theme.TextColor.tertiary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                if renaming {
                    TextField("Name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .font(Typography.bodyMedium)
                        .onSubmit {
                            onRename(newName)
                            renaming = false
                        }
                        .onExitCommand { renaming = false }
                } else {
                    Text(sim.name)
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Theme.TextColor.primary)
                        .lineLimit(1)
                }
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

            if confirmingErase {
                Text("Erase all content?")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.Semantic.danger)
                ActionButton(symbol: "xmark", tint: Theme.TextColor.tertiary) { confirmingErase = false }
                ActionButton(symbol: "checkmark", tint: Theme.Semantic.danger) {
                    confirmingErase = false
                    onErase()
                }
            } else if hovering || sim.isBooted || isPendingDelete || isPendingBootChange {
                HStack(spacing: 4) {
                    ActionButton(
                        symbol: sim.isBooted ? "stop.fill" : "play.fill",
                        tint: sim.isBooted ? Theme.Semantic.warn : Theme.Semantic.ok,
                        isLoading: isPendingBootChange,
                        action: onToggleBootState
                    )
                    ActionButton(
                        symbol: isPendingDelete ? "checkmark" : "trash",
                        label: isPendingDelete ? String(localized: "Confirm?") : nil,
                        tint: isPendingDelete ? Theme.Semantic.danger : Theme.TextColor.tertiary,
                        action: onDeleteRequest
                    )
                }
            }

            Menu {
                Button("Rename…") {
                    newName = sim.name
                    renaming = true
                }
                Button("Clone") { onClone() }
                Divider()
                Button("Erase Content & Settings…") { confirmingErase = true }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.TextColor.tertiary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
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
    var isLoading: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isLoading {
                    // controlSize(.mini) yields a ~12pt spinner that matches
                    // the icon weight. Avoid scaleEffect + fixed frame here —
                    // those clash with NSProgressIndicator's intrinsic size
                    // and emit constraint warnings on macOS Tahoe.
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                        .tint(tint)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .medium))
                    if let label {
                        Text(label)
                            .font(Typography.monoSmall)
                    }
                }
            }
            .foregroundStyle(tint)
            .padding(.horizontal, (label == nil || isLoading) ? 6 : Spacing.sm)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .fill(hovering ? tint.opacity(0.18) : tint.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onHover { hovering = $0 }
    }
}

// MARK: - Create form

private struct CreateSimulatorForm: View {
    @ObservedObject var service: SimulatorService
    let close: () -> Void
    @State private var runtimes: [SimulatorService.Runtime] = []
    @State private var runtime: SimulatorService.Runtime?
    @State private var deviceType: SimulatorService.DeviceType?
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if runtimes.isEmpty {
                Text("Loading runtimes…")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
            } else {
                HStack(spacing: Spacing.sm) {
                    Picker("", selection: $runtime) {
                        ForEach(runtimes) { rt in Text(rt.name).tag(Optional(rt)) }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                    Picker("", selection: $deviceType) {
                        ForEach(runtime?.deviceTypes ?? []) { dt in Text(dt.name).tag(Optional(dt)) }
                    }
                    .labelsHidden()
                }
                HStack(spacing: Spacing.sm) {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(Typography.mono)
                    PillButton(title: "Cancel", symbol: "xmark", action: close)
                    AccentActionButton(title: "Create", symbol: "plus",
                                       enabled: runtime != nil && deviceType != nil && !name.isEmpty) {
                        if let runtime, let deviceType {
                            service.create(name: name, deviceType: deviceType, runtime: runtime)
                            close()
                        }
                    }
                }
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
        )
        .task {
            runtimes = await Task.detached(priority: .userInitiated) { SimulatorService.availableRuntimes() }.value
            runtime = runtimes.first
        }
        .onChange(of: runtime) { rt in
            // Prefer the newest iPhone of the selected runtime.
            deviceType = rt?.deviceTypes.last { $0.name.hasPrefix("iPhone") } ?? rt?.deviceTypes.first
        }
        .onChange(of: deviceType) { dt in
            if let dt { name = dt.name }
        }
    }
}
