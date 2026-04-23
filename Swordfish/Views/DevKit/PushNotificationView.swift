import SwiftUI

struct PushNotificationView: View {
    @StateObject private var service = SimulatorService()
    @AppStorage("swordfish.push.bundleID") private var bundleID: String = ""
    @State private var selectedUDID: String = ""
    @State private var payload: String = defaultPayload(.simple)
    @State private var status: SendStatus?
    @State private var isSending = false

    enum Preset: String, CaseIterable, Identifiable {
        case simple = "Simple", rich = "Rich", silent = "Silent"
        var id: String { rawValue }
    }

    enum SendStatus {
        case ok(String), error(String)
        var isError: Bool { if case .error = self { return true }; return false }
        var message: String { switch self { case .ok(let s), .error(let s): return s } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            targetRow
            presetRow
            CodeEditor(text: $payload, placeholder: "Payload JSON…", minHeight: 140)
            sendRow
        }
        .task { refreshSimulators() }
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
            TextField("Bundle ID (com.example.app)", text: $bundleID)
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
                ForEach(booted) { sim in
                    Text(sim.name).tag(sim.udid)
                }
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

    // MARK: - Preset row

    private var presetRow: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(Preset.allCases) { preset in
                PillButton(title: preset.rawValue, symbol: icon(for: preset)) {
                    payload = Self.defaultPayload(preset)
                }
            }
            Spacer()
            Button(action: refreshSimulators) {
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
        }
    }

    private func icon(for preset: Preset) -> String {
        switch preset {
        case .simple: return "bell"
        case .rich:   return "bell.badge"
        case .silent: return "bell.slash"
        }
    }

    // MARK: - Send row

    private var sendRow: some View {
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
            Button(action: send) {
                HStack(spacing: 6) {
                    Image(systemName: isSending ? "arrow.clockwise" : "paperplane.fill")
                        .font(.system(size: 11, weight: .medium))
                    Text(isSending ? "Sending…" : "Send Push")
                        .font(Typography.bodyMedium)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .fill(canSend ? Color.accentColor : Color.accentColor.opacity(0.35))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSend || isSending)
        }
    }

    private var canSend: Bool {
        !selectedUDID.isEmpty && !bundleID.isEmpty && !payload.isEmpty
    }

    // MARK: - Actions

    private func refreshSimulators() {
        service.refresh()
    }

    private func send() {
        guard canSend else { return }
        // Validate JSON up front
        guard let data = payload.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            status = .error("Payload is not valid JSON")
            return
        }
        let udid = selectedUDID
        let bundle = bundleID
        let body = payload
        isSending = true
        status = nil

        Task.detached(priority: .userInitiated) {
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("swordfish-push-\(UUID().uuidString).apns")
            defer { try? FileManager.default.removeItem(at: tmpURL) }

            do {
                try body.write(to: tmpURL, atomically: true, encoding: .utf8)
                let result = try ProcessRunner.run("/usr/bin/xcrun", arguments: [
                    "simctl", "push", udid, bundle, tmpURL.path
                ])
                let outcome: SendStatus = result.exitCode == 0
                    ? .ok("Sent to simulator")
                    : .error(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty ? "simctl failed" : result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                await MainActor.run {
                    status = outcome
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    status = .error(error.localizedDescription)
                    isSending = false
                }
            }
        }
    }

    // MARK: - Preset payloads

    static func defaultPayload(_ preset: Preset) -> String {
        switch preset {
        case .simple:
            return """
            {
              "aps": {
                "alert": "Hello from Swordfish",
                "sound": "default"
              }
            }
            """
        case .rich:
            return """
            {
              "aps": {
                "alert": {
                  "title": "New message",
                  "subtitle": "From Swordfish",
                  "body": "Tap to open the app"
                },
                "sound": "default",
                "badge": 1,
                "category": "MESSAGE_CATEGORY",
                "thread-id": "swordfish-test"
              }
            }
            """
        case .silent:
            return """
            {
              "aps": {
                "content-available": 1
              }
            }
            """
        }
    }
}
