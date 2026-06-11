import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Status Bar

struct StatusBarPanel: View {
    let udid: String
    @State private var time = "9:41"
    @State private var batteryLevel: Double = 100
    @State private var batteryState: SimulatorToolbox.StatusBarConfig.BatteryState = .charged
    @State private var network: SimulatorToolbox.StatusBarConfig.DataNetwork = .wifi
    @State private var status: ToolboxStatus?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                fieldLabel("Time")
                TextField("9:41", text: $time)
                    .textFieldStyle(.plain)
                    .font(Typography.mono)
                    .foregroundStyle(Theme.TextColor.primary)
                    .frame(width: 56)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 4)
                    .background(fieldBackground)
                fieldLabel("Battery")
                Picker("", selection: $batteryState) {
                    ForEach(SimulatorToolbox.StatusBarConfig.BatteryState.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(Typography.monoSmall)
                Spacer()
            }
            HStack(spacing: Spacing.sm) {
                Slider(value: $batteryLevel, in: 0...100, step: 1)
                Text("\(Int(batteryLevel))%")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.secondary)
                    .frame(width: 38, alignment: .trailing)
            }
            HStack(spacing: Spacing.sm) {
                fieldLabel("Network")
                Picker("", selection: $network) {
                    ForEach(SimulatorToolbox.StatusBarConfig.DataNetwork.allCases) { n in
                        Text(n.label).tag(n)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 240)
                Spacer()
            }
            HStack {
                if let status { ToolboxStatusLine(status: status) }
                Spacer()
                PillButton(title: "Clear Override", symbol: "xmark.circle") {
                    run(String(localized: "Status bar restored")) {
                        try SimulatorToolbox.clearStatusBar(udid: udid)
                    }
                }
                AccentActionButton(
                    title: isWorking ? "Applying…" : "Apply",
                    symbol: "battery.100",
                    enabled: !isWorking && !time.isEmpty
                ) {
                    let config = SimulatorToolbox.StatusBarConfig(
                        time: time,
                        batteryLevel: Int(batteryLevel),
                        batteryState: batteryState,
                        network: network
                    )
                    run(String(localized: "Status bar override applied")) {
                        try SimulatorToolbox.overrideStatusBar(udid: udid, config: config)
                    }
                }
            }
        }
    }

    private func run(_ successMessage: String, _ work: @escaping () throws -> Void) {
        isWorking = true
        status = nil
        Task.detached(priority: .userInitiated) {
            let outcome: ToolboxStatus
            do { try work(); outcome = .ok(successMessage, nil) }
            catch { outcome = .error(error.localizedDescription) }
            await MainActor.run {
                status = outcome
                isWorking = false
            }
        }
    }
}

// MARK: - Permissions

struct PermissionsPanel: View {
    let udid: String
    @StateObject private var appsModel = InstalledAppsModel()
    @State private var selectedBundleID = ""
    @State private var service: SimulatorToolbox.PrivacyService = .photos
    @State private var status: ToolboxStatus?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                fieldLabel("App")
                appPicker
                Spacer()
                ToolboxIconButton(symbol: "arrow.clockwise", help: "Reload installed apps") {
                    appsModel.load(udid: udid)
                }
            }
            HStack(spacing: Spacing.sm) {
                fieldLabel("Service")
                Picker("", selection: $service) {
                    ForEach(SimulatorToolbox.PrivacyService.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(Typography.monoSmall)
                Spacer()
            }
            HStack(spacing: Spacing.sm) {
                if let status { ToolboxStatusLine(status: status) }
                Spacer()
                PillButton(title: "Revoke", symbol: "hand.raised.slash") { apply(.revoke) }
                PillButton(title: "Reset", symbol: "arrow.counterclockwise") { apply(.reset) }
                AccentActionButton(
                    title: isWorking ? "Working…" : "Grant",
                    symbol: "checkmark.shield",
                    enabled: canApply
                ) { apply(.grant) }
            }
            Text("Heads-up: simctl restarts the target app when its permissions change.")
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.quaternary)
        }
        .task(id: udid) { appsModel.load(udid: udid) }
    }

    @ViewBuilder
    private var appPicker: some View {
        if appsModel.isLoading && appsModel.apps.isEmpty {
            Text("Loading apps…")
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.tertiary)
        } else if appsModel.apps.isEmpty {
            Text(appsModel.lastError ?? String(localized: "No user apps installed"))
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.tertiary)
                .lineLimit(1)
        } else {
            Picker("", selection: $selectedBundleID) {
                ForEach(appsModel.apps) { app in
                    Text("\(app.name) — \(app.bundleID)").tag(app.bundleID)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .font(Typography.monoSmall)
            .onAppear {
                if !appsModel.apps.contains(where: { $0.bundleID == selectedBundleID }) {
                    selectedBundleID = appsModel.apps.first?.bundleID ?? ""
                }
            }
            .onChange(of: appsModel.apps) { apps in
                if !apps.contains(where: { $0.bundleID == selectedBundleID }) {
                    selectedBundleID = apps.first?.bundleID ?? ""
                }
            }
        }
    }

    private var canApply: Bool {
        !isWorking && !selectedBundleID.isEmpty
    }

    private func apply(_ action: SimulatorToolbox.PrivacyAction) {
        guard canApply else { return }
        let bundle = selectedBundleID
        let svc = service
        isWorking = true
        status = nil
        Task.detached(priority: .userInitiated) {
            let outcome: ToolboxStatus
            do {
                try SimulatorToolbox.privacy(udid: udid, action: action, service: svc, bundleID: bundle)
                let message: String
                switch action {
                case .grant:  message = String(localized: "Grant \(svc.label) for \(bundle)")
                case .revoke: message = String(localized: "Revoke \(svc.label) for \(bundle)")
                case .reset:  message = String(localized: "Reset \(svc.label) for \(bundle)")
                }
                outcome = .ok(message, nil)
            } catch {
                outcome = .error(error.localizedDescription)
            }
            await MainActor.run {
                status = outcome
                isWorking = false
            }
        }
    }
}

// MARK: - Location

struct LocationPanel: View {
    let udid: String
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var status: ToolboxStatus?
    @State private var isWorking = false

    private static let presets: [(name: String, lat: Double, lon: Double)] = [
        ("Istanbul", 41.0082, 28.9784),
        ("London", 51.5074, -0.1278),
        ("New York", 40.7128, -74.0060),
        ("San Francisco", 37.7749, -122.4194),
        ("Tokyo", 35.6762, 139.6503),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: 4) {
                ForEach(Self.presets, id: \.name) { preset in
                    PillButton(title: LocalizedStringKey(preset.name), symbol: "mappin") {
                        latitude = String(preset.lat)
                        longitude = String(preset.lon)
                        set(lat: preset.lat, lon: preset.lon)
                    }
                }
            }
            HStack(spacing: Spacing.sm) {
                coordinateField("Latitude", text: $latitude)
                coordinateField("Longitude", text: $longitude)
            }
            HStack {
                if let status { ToolboxStatusLine(status: status) }
                Spacer()
                PillButton(title: "Clear", symbol: "location.slash") {
                    run(String(localized: "Simulated location cleared")) {
                        try SimulatorToolbox.clearLocation(udid: udid)
                    }
                }
                AccentActionButton(
                    title: isWorking ? "Setting…" : "Set Location",
                    symbol: "location.fill",
                    enabled: canSet
                ) {
                    guard let lat = Double(latitude), let lon = Double(longitude) else { return }
                    set(lat: lat, lon: lon)
                }
            }
        }
    }

    private func coordinateField(_ placeholder: LocalizedStringKey, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(Typography.mono)
            .foregroundStyle(Theme.TextColor.primary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 5)
            .background(fieldBackground)
    }

    private var canSet: Bool {
        !isWorking && Double(latitude) != nil && Double(longitude) != nil
    }

    private func set(lat: Double, lon: Double) {
        run(String(format: String(localized: "Location set to %.4f, %.4f"), lat, lon)) {
            try SimulatorToolbox.setLocation(udid: udid, latitude: lat, longitude: lon)
        }
    }

    private func run(_ successMessage: String, _ work: @escaping () throws -> Void) {
        isWorking = true
        status = nil
        Task.detached(priority: .userInitiated) {
            let outcome: ToolboxStatus
            do { try work(); outcome = .ok(successMessage, nil) }
            catch { outcome = .error(error.localizedDescription) }
            await MainActor.run {
                status = outcome
                isWorking = false
            }
        }
    }
}

// MARK: - Media

struct MediaPanel: View {
    let udid: String
    @State private var status: ToolboxStatus?
    @State private var isWorking = false
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            dropZone
            if let status { ToolboxStatusLine(status: status) }
        }
    }

    private var dropZone: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 20))
                .foregroundStyle(isTargeted ? Color.accentColor : Theme.TextColor.tertiary)
            Text(isWorking ? "Adding to Photos…" : "Drop images or videos to add them to the simulator's Photos library")
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.tertiary)
                .multilineTextAlignment(.center)
            PillButton(title: "Choose Files…", symbol: "folder", action: chooseFiles)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.08) : Theme.Surface.surface1)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                        .strokeBorder(
                            isTargeted ? Color.accentColor : Theme.Border.subtle,
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                        )
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            add(panel.urls)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty { add(urls) }
        }
        return true
    }

    private func add(_ urls: [URL]) {
        isWorking = true
        status = nil
        Task.detached(priority: .userInitiated) {
            let outcome: ToolboxStatus
            do {
                try SimulatorToolbox.addMedia(udid: udid, files: urls)
                outcome = .ok(String(localized: "Added \(urls.count) item(s) to Photos"), nil)
            } catch {
                outcome = .error(error.localizedDescription)
            }
            await MainActor.run {
                status = outcome
                isWorking = false
            }
        }
    }
}

// MARK: - Apps (data containers)

struct AppsPanel: View {
    let udid: String
    @StateObject private var appsModel = InstalledAppsModel()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(countLine)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                Spacer()
                ToolboxIconButton(symbol: "arrow.clockwise", help: "Reload installed apps") {
                    appsModel.load(udid: udid)
                }
            }
            if appsModel.apps.isEmpty {
                Text(appsModel.isLoading ? String(localized: "Loading apps…") : (appsModel.lastError ?? String(localized: "No user apps installed")))
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.md)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(appsModel.apps) { app in
                            InstalledAppRow(app: app)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .task(id: udid) { appsModel.load(udid: udid) }
    }

    private var countLine: String {
        let n = appsModel.apps.count
        return String(localized: "\(n) user app(s) installed")
    }
}

private struct InstalledAppRow: View {
    let app: InstalledApp
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "app")
                .font(.system(size: 13))
                .foregroundStyle(Theme.TextColor.tertiary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(Theme.TextColor.primary)
                    .lineLimit(1)
                Text(app.bundleID)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if hovering {
                CopyButton(text: app.bundleID)
                    .help("Copy bundle ID")
                if let container = app.dataContainer {
                    ToolboxIconButton(symbol: "folder", help: "Open data container in Finder") {
                        NSWorkspace.shared.open(container)
                    }
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
}

// MARK: - Shared panel helpers

private func fieldLabel(_ text: LocalizedStringKey) -> some View {
    Text(text)
        .font(Typography.monoSmall)
        .foregroundStyle(Theme.TextColor.tertiary)
}

private var fieldBackground: some View {
    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
        .fill(Theme.Surface.surface1)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                .strokeBorder(Theme.Border.subtle, lineWidth: 1)
        )
}

/// The filled accent CTA used across DevKit footers (matches the
/// "Send Push" / "Open URL" buttons).
struct AccentActionButton: View {
    let title: LocalizedStringKey
    let symbol: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(Typography.bodyMedium)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .fill(enabled ? Color.accentColor : Color.accentColor.opacity(0.35))
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
