import SwiftUI

struct DeepLinkLauncherView: View {
    @StateObject private var service = SimulatorService()
    @AppStorage("swordfish.deeplink.url") private var url: String = ""
    @State private var selectedUDID: String = ""
    @State private var status: LaunchStatus?
    @State private var isLaunching = false
    @State private var recent: [String] = loadRecent()

    enum LaunchStatus {
        case ok(String), error(String)
        var isError: Bool { if case .error = self { return true }; return false }
        var message: String { switch self { case .ok(let s), .error(let s): return s } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            targetRow
            if !recent.isEmpty { recentRow }
            footerRow
        }
        .task { service.refresh() }
    }

    // MARK: - Target row

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
            TextField("URL (myapp://… or https://…)", text: $url)
                .textFieldStyle(.plain)
                .font(Typography.mono)
                .foregroundStyle(Theme.TextColor.primary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .fill(Theme.Surface.surface1)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                                .strokeBorder(Theme.Border.subtle, lineWidth: 1)
                        )
                )
        }
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

    // MARK: - Recent URLs

    private var recentRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent")
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.tertiary)
            VStack(spacing: 3) {
                ForEach(recent.prefix(5), id: \.self) { u in
                    Button {
                        url = u
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.TextColor.quaternary)
                            Text(u)
                                .font(Typography.monoSmall)
                                .foregroundStyle(Theme.TextColor.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                                .fill(Theme.Surface.surface1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Footer row (status + refresh + launch)

    private var footerRow: some View {
        HStack {
            if let status {
                HStack(spacing: 6) {
                    Image(systemName: status.isError ? "xmark.circle" : "checkmark.circle")
                        .font(.system(size: 11))
                    Text(status.message)
                        .font(Typography.monoSmall)
                        .lineLimit(1)
                }
                .foregroundStyle(status.isError ? Theme.Semantic.danger : Theme.Semantic.ok)
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
            Button(action: launch) {
                HStack(spacing: 6) {
                    Image(systemName: isLaunching ? "arrow.clockwise" : "arrow.up.right.square.fill")
                        .font(.system(size: 11, weight: .medium))
                    Text(isLaunching ? "Opening…" : "Open URL")
                        .font(Typography.bodyMedium)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .fill(canLaunch ? Color.accentColor : Color.accentColor.opacity(0.35))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canLaunch || isLaunching)
        }
    }

    private var canLaunch: Bool {
        !selectedUDID.isEmpty && URL(string: url)?.scheme != nil
    }

    // MARK: - Actions

    private func launch() {
        guard canLaunch else { return }
        let udid = selectedUDID
        let target = url
        isLaunching = true
        status = nil

        Task.detached(priority: .userInitiated) {
            let result = try? ProcessRunner.run("/usr/bin/xcrun", arguments: [
                "simctl", "openurl", udid, target
            ])
            let outcome: LaunchStatus = (result?.exitCode == 0)
                ? .ok("Opened in simulator")
                : .error((result?.stderr.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "simctl failed")

            await MainActor.run {
                status = outcome
                isLaunching = false
                if !outcome.isError {
                    rememberURL(target)
                }
            }
        }
    }

    private func rememberURL(_ u: String) {
        var list = recent
        list.removeAll { $0 == u }
        list.insert(u, at: 0)
        list = Array(list.prefix(8))
        recent = list
        UserDefaults.standard.set(list, forKey: "swordfish.deeplink.recent")
    }

    private static func loadRecent() -> [String] {
        UserDefaults.standard.stringArray(forKey: "swordfish.deeplink.recent") ?? []
    }
}
