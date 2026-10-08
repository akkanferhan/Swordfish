import SwiftUI

struct PushNotificationView: View {
    @StateObject private var service = SimulatorService()
    @Environment(\.popoverController) private var popoverController
    @AppStorage("swordfish.push.bundleID") private var bundleID: String = ""
    @AppStorage("swordfish.push.target") private var target: Target = .simulator
    @AppStorage("swordfish.push.deviceToken") private var deviceToken: String = ""
    @AppStorage("swordfish.push.environment") private var environment: APNsClient.Environment = .sandbox
    @AppStorage("swordfish.push.lastPayload") private var lastPayload: String = ""
    @State private var selectedUDID: String = ""
    @State private var payload: String = defaultPayload(.simple)
    @State private var status: SendStatus?
    @State private var isSending = false
    @State private var saved: [SavedPayload] = SavedPayload.load()
    @State private var savingName: String?

    enum Target: String, CaseIterable, Identifiable {
        case simulator, device
        var id: String { rawValue }
        var label: LocalizedStringKey { self == .simulator ? "Simulator" : "Device (APNs)" }
    }

    /// Named payloads kept in UserDefaults.
    struct SavedPayload: Codable, Identifiable, Equatable {
        var id = UUID()
        var name: String
        var payload: String

        private static let key = "swordfish.push.saved"
        static func load() -> [SavedPayload] {
            guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
            return (try? JSONDecoder().decode([SavedPayload].self, from: data)) ?? []
        }
        static func store(_ list: [SavedPayload]) {
            UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: key)
        }
    }

    enum Preset: String, CaseIterable, Identifiable {
        case simple = "Simple", rich = "Rich", silent = "Silent"
        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self {
            case .simple: return "Simple"
            case .rich:   return "Rich"
            case .silent: return "Silent"
            }
        }
    }

    enum SendStatus {
        case ok(String), error(String)
        var isError: Bool { if case .error = self { return true }; return false }
        var message: String { switch self { case .ok(let s), .error(let s): return s } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Picker("", selection: $target) {
                ForEach(Target.allCases) { t in Text(t.label).tag(t) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            if target == .simulator {
                targetRow
            } else {
                deviceRow
            }
            presetRow
            CodeEditor(text: $payload, placeholder: String(localized: "Payload JSON…"), minHeight: 140)
            if let name = savingName {
                saveRow(name)
            }
            sendRow
        }
        .task { refreshSimulators() }
    }

    // MARK: - Device (APNs) row

    private var deviceRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Spacing.sm) {
                field("Device token (hex)", text: $deviceToken)
                field("Bundle ID (topic)", text: $bundleID)
                    .frame(width: 170)
            }
            HStack(spacing: Spacing.sm) {
                Picker("", selection: $environment) {
                    ForEach(APNsClient.Environment.allCases) { e in Text(e.label).tag(e) }
                }
                .labelsHidden()
                .frame(width: 250)
                Spacer()
                if !AppleKeys.hasKey(.apns) {
                    Button("Add APNs key…") { popoverController?.openSettings() }
                        .buttonStyle(.plain)
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.Semantic.warn)
                        .help("Settings → Developer Keys")
                }
            }
        }
    }

    private func field(_ placeholder: LocalizedStringKey, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
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

    // MARK: - Saved payloads

    private var savedMenu: some View {
        Menu {
            ForEach(saved) { item in
                Button(item.name) { payload = item.payload }
            }
            if !saved.isEmpty { Divider() }
            Button("Save Current…") { savingName = "" }
            if !saved.isEmpty {
                Menu("Delete") {
                    ForEach(saved) { item in
                        Button(item.name) {
                            saved.removeAll { $0.id == item.id }
                            SavedPayload.store(saved)
                        }
                    }
                }
            }
        } label: {
            Label("Saved", systemImage: "tray.full")
                .font(Typography.monoSmall)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func saveRow(_ name: String) -> some View {
        HStack(spacing: Spacing.sm) {
            field("Name for this payload", text: Binding(get: { savingName ?? "" }, set: { savingName = $0 }))
            PillButton(title: "Cancel", symbol: "xmark") { savingName = nil }
            AccentActionButton(title: "Save", symbol: "checkmark",
                               enabled: !name.trimmingCharacters(in: .whitespaces).isEmpty) {
                saved.append(SavedPayload(name: name.trimmingCharacters(in: .whitespaces), payload: payload))
                SavedPayload.store(saved)
                savingName = nil
            }
        }
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
                PillButton(title: preset.label, symbol: icon(for: preset)) {
                    payload = Self.defaultPayload(preset)
                }
            }
            savedMenu
            Spacer()
            if !lastPayload.isEmpty {
                ToolboxIconButton(symbol: "arrow.uturn.right", help: "Resend the last push") {
                    payload = lastPayload
                    send()
                }
            }
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
        switch target {
        case .simulator: return !selectedUDID.isEmpty && !bundleID.isEmpty && !payload.isEmpty
        case .device:    return !deviceToken.isEmpty && !bundleID.isEmpty && !payload.isEmpty
        }
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
            status = .error(String(localized: "Payload is not valid JSON"))
            return
        }
        let udid = selectedUDID
        let bundle = bundleID
        let body = payload
        isSending = true
        status = nil
        lastPayload = body

        if target == .device {
            let token = deviceToken
            let env = environment
            Task {
                do {
                    let result = try await APNsClient.send(deviceToken: token, topic: bundle,
                                                           payload: Data(body.utf8), environment: env)
                    status = result.ok
                        ? .ok(String(localized: "Delivered to APNs (\(result.apnsID ?? "ok"))"))
                        : .error("HTTP \(result.status): " + APNsClient.explain(result.reason ?? "?"))
                } catch {
                    status = .error(error.localizedDescription)
                }
                isSending = false
            }
            return
        }

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
                    ? .ok(String(localized: "Sent to simulator"))
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
