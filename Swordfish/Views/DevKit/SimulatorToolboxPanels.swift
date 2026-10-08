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
    @State private var routeMode = false

    private static let presets: [(name: String, lat: Double, lon: Double)] = [
        ("Istanbul", 41.0082, 28.9784),
        ("London", 51.5074, -0.1278),
        ("New York", 40.7128, -74.0060),
        ("San Francisco", 37.7749, -122.4194),
        ("Tokyo", 35.6762, 139.6503),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Picker("", selection: $routeMode) {
                Text("Point").tag(false)
                Text("Route").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)
            if routeMode {
                RouteSection(udid: udid)
            } else {
                pointBody
            }
        }
    }

    private var pointBody: some View {
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

/// Moving location: preset or custom waypoints (or a GPX file) played at a
/// chosen speed — for maps, navigation and geofencing work.
private struct RouteSection: View {
    let udid: String
    @State private var waypointsText = ""
    @State private var speed: Double = 14
    @State private var status: ToolboxStatus?

    private static let speeds: [(label: LocalizedStringKey, metersPerSecond: Double)] = [
        ("Walk", 1.4), ("Run", 3.5), ("Bike", 6), ("City", 14), ("Highway", 30),
    ]

    private static let presets: [(name: String, points: [SimulatorToolbox.Coordinate])] = [
        ("Istanbul · Taksim → Kadıköy", [(41.0370, 28.9850), (41.0256, 28.9744), (41.0165, 28.9770), (41.0082, 28.9784),
                                          (41.0021, 28.9765), (40.9989, 29.0180), (40.9923, 29.0287)]),
        ("London · Westminster → Tower", [(51.5007, -0.1246), (51.5055, -0.1160), (51.5081, -0.0990),
                                           (51.5094, -0.0870), (51.5081, -0.0759)]),
        ("San Francisco · Bay Bridge", [(37.7955, -122.3937), (37.7983, -122.3778), (37.8030, -122.3620),
                                         (37.8120, -122.3480), (37.8240, -122.3420)]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: 4) {
                ForEach(Self.presets, id: \.name) { preset in
                    PillButton(title: LocalizedStringKey(preset.name), symbol: "point.topleft.down.to.point.bottomright.curvepath") {
                        waypointsText = preset.points.map { "\($0.lat), \($0.lon)" }.joined(separator: "\n")
                    }
                }
            }
            CodeEditor(text: $waypointsText, placeholder: "lat, lon — one waypoint per line", minHeight: 70)
            HStack(spacing: Spacing.sm) {
                Picker("", selection: $speed) {
                    ForEach(Self.speeds, id: \.metersPerSecond) { s in
                        Text(s.label).tag(s.metersPerSecond)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 260)
                Text(String(format: "%.0f km/h", speed * 3.6))
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                Spacer()
            }
            HStack {
                if let status { ToolboxStatusLine(status: status) }
                Spacer()
                PillButton(title: "Import GPX…", symbol: "square.and.arrow.down") { importGPX() }
                PillButton(title: "Stop", symbol: "stop") {
                    run(String(localized: "Route stopped")) { try SimulatorToolbox.clearLocation(udid: udid) }
                }
                AccentActionButton(title: "Start Route", symbol: "car.fill", enabled: waypoints.count >= 2) {
                    let points = waypoints
                    let speed = speed
                    run(String(localized: "Following \(points.count) waypoints")) {
                        try SimulatorToolbox.startRoute(udid: udid, waypoints: points, speed: speed)
                    }
                }
            }
        }
    }

    private var waypoints: [SimulatorToolbox.Coordinate] {
        waypointsText.split(separator: "\n").compactMap { line in
            let parts = line.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" }).compactMap { Double($0) }
            guard parts.count >= 2, (-90...90).contains(parts[0]), (-180...180).contains(parts[1]) else { return nil }
            return (parts[0], parts[1])
        }
    }

    private func importGPX() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "gpx") ?? .xml, .xml]
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        let points = SimulatorToolbox.gpxWaypoints(data)
        if points.isEmpty {
            status = .error(String(localized: "No track or route points in \(url.lastPathComponent)"))
        } else {
            waypointsText = points.map { String(format: "%.6f, %.6f", $0.lat, $0.lon) }.joined(separator: "\n")
            status = .ok(String(localized: "Loaded \(points.count) points"), nil)
        }
    }

    private func run(_ successMessage: String, _ work: @escaping () throws -> Void) {
        status = nil
        Task.detached(priority: .userInitiated) {
            let outcome: ToolboxStatus
            do { try work(); outcome = .ok(successMessage, nil) }
            catch { outcome = .error(error.localizedDescription) }
            await MainActor.run { status = outcome }
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

// MARK: - Apps (install, lifecycle, data containers)

struct AppsPanel: View {
    let udid: String
    @StateObject private var appsModel = InstalledAppsModel()
    @EnvironmentObject private var devTools: DevToolsState
    @Environment(\.popoverController) private var popoverController
    @State private var status: ToolboxStatus?
    @State private var isInstalling = false
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Text(countLine)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                Spacer()
                PillButton(title: isInstalling ? "Installing…" : "Install .app…", symbol: "square.and.arrow.down") {
                    chooseApp()
                }
                ToolboxIconButton(symbol: "arrow.clockwise", help: "Reload installed apps") {
                    appsModel.load(udid: udid)
                }
            }
            if let status { ToolboxStatusLine(status: status) }
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
                            InstalledAppRow(app: app, perform: { perform($0, on: app) })
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
            Text("Drop a simulator .app build here to install it.")
                .font(Typography.monoSmall)
                .foregroundStyle(isTargeted ? Color.accentColor : Theme.TextColor.quaternary)
        }
        .padding(isTargeted ? 4 : 0)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .strokeBorder(isTargeted ? Color.accentColor : .clear,
                              style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
        .task(id: udid) { appsModel.load(udid: udid) }
    }

    private var countLine: String {
        let n = appsModel.apps.count
        return String(localized: "\(n) user app(s) installed")
    }

    // MARK: Install

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.message = String(localized: "Choose a simulator build (.app) — e.g. from DerivedData/…/Build/Products/Debug-iphonesimulator")
        if panel.runModal() == .OK, let url = panel.url {
            install(url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL? = (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) } ?? (item as? URL)
            guard let url, url.pathExtension == "app" else { return }
            DispatchQueue.main.async { install(url) }
        }
        return true
    }

    private func install(_ url: URL) {
        guard !isInstalling else { return }
        isInstalling = true
        status = nil
        Task.detached(priority: .userInitiated) {
            let outcome: ToolboxStatus
            do {
                try SimulatorToolbox.install(udid: udid, app: url)
                outcome = .ok(String(localized: "Installed \(url.deletingPathExtension().lastPathComponent)"), nil)
            } catch {
                outcome = .error(error.localizedDescription)
            }
            await MainActor.run {
                isInstalling = false
                status = outcome
                appsModel.load(udid: udid)
            }
        }
    }

    // MARK: Row actions

    private func perform(_ action: InstalledAppRow.Action, on app: InstalledApp) {
        status = nil
        if action == .userDefaults {
            do {
                devTools.jsonInput = try SimulatorToolbox.userDefaultsJSON(app: app)
                popoverController?.openJSONViewer()
            } catch {
                status = .error(error.localizedDescription)
            }
            return
        }
        if action == .editDefaults {
            popoverController?.openUserDefaultsEditor(udid: udid, app: app)
            return
        }
        Task.detached(priority: .userInitiated) {
            let outcome: ToolboxStatus
            do {
                switch action {
                case .launch:
                    try SimulatorToolbox.launch(udid: udid, bundleID: app.bundleID)
                    outcome = .ok(String(localized: "Launched \(app.name)"), nil)
                case .terminate:
                    try SimulatorToolbox.terminate(udid: udid, bundleID: app.bundleID)
                    outcome = .ok(String(localized: "Terminated \(app.name)"), nil)
                case .resetData:
                    try SimulatorToolbox.resetData(udid: udid, app: app)
                    outcome = .ok(String(localized: "Cleared data for \(app.name)"), nil)
                case .uninstall:
                    try SimulatorToolbox.uninstall(udid: udid, bundleID: app.bundleID)
                    outcome = .ok(String(localized: "Uninstalled \(app.name)"), nil)
                case .launchLocale(let locale):
                    try SimulatorToolbox.launch(udid: udid, bundleID: app.bundleID, arguments: locale.arguments)
                    outcome = .ok(String(localized: "Launched \(app.name) · \(locale.label)"), nil)
                case .userDefaults, .editDefaults:
                    return
                }
            } catch {
                outcome = .error(error.localizedDescription)
            }
            await MainActor.run {
                status = outcome
                if action == .uninstall { appsModel.load(udid: udid) }
            }
        }
    }
}

private struct InstalledAppRow: View {
    enum Action: Equatable {
        case launch, terminate, userDefaults, editDefaults, resetData, uninstall
        case launchLocale(SimulatorToolbox.LaunchLocale)
    }

    let app: InstalledApp
    let perform: (Action) -> Void
    @State private var hovering = false
    /// Destructive actions need a second click on the confirm button.
    @State private var confirming: Action?
    @State private var databases: [URL] = []

    /// The app's own languages, or a common set when it ships none.
    private var launchLanguages: [String] {
        let own = app.localizations
        return own.isEmpty ? ["en", "tr", "de", "fr", "es", "ja", "ar"] : own
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "app")
                .font(.system(size: 13))
                .foregroundStyle(Theme.TextColor.tertiary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(app.name)
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Theme.TextColor.primary)
                        .lineLimit(1)
                    if let version = app.version {
                        Text(verbatim: version)
                            .font(Typography.monoSmall)
                            .foregroundStyle(Theme.TextColor.quaternary)
                    }
                }
                Text(app.bundleID)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if let confirming {
                Text(confirming == .uninstall ? "Uninstall?" : "Erase data?")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.Semantic.danger)
                ToolboxIconButton(symbol: "xmark", help: "Cancel") { self.confirming = nil }
                ToolboxIconButton(symbol: "checkmark", help: "Confirm") {
                    perform(confirming)
                    self.confirming = nil
                }
            } else {
                if hovering {
                    ToolboxIconButton(symbol: "play", help: "Launch (restarts if running)") { perform(.launch) }
                    ToolboxIconButton(symbol: "stop", help: "Terminate") { perform(.terminate) }
                    if let container = app.dataContainer {
                        ToolboxIconButton(symbol: "folder", help: "Open data container in Finder") {
                            NSWorkspace.shared.open(container)
                        }
                    }
                }
                // Always visible: a menu must not vanish when the pointer
                // leaves the row on its way into it.
                moreMenu
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(hovering ? Theme.Surface.surface2 : Theme.Surface.surface1)
        )
        .onHover { hovering = $0 }
        .task(id: app.id) {
            let target = app
            databases = await Task.detached(priority: .utility) {
                SimulatorToolbox.databaseFiles(app: target)
            }.value
        }
    }

    private var moreMenu: some View {
        Menu {
            Menu("Launch in…") {
                ForEach(launchLanguages, id: \.self) { code in
                    Button(SimulatorToolbox.LaunchLocale.language(code).label) {
                        perform(.launchLocale(.language(code)))
                    }
                }
                Divider()
                ForEach([SimulatorToolbox.LaunchLocale.doubleLength, .rightToLeft, .showUnlocalized], id: \.self) { mode in
                    Button(mode.label) { perform(.launchLocale(mode)) }
                }
            }
            Menu("UserDefaults") {
                Button("Edit…") { perform(.editDefaults) }
                Button("View in JSON Viewer") { perform(.userDefaults) }
            }
            if !databases.isEmpty {
                Menu("Databases (\(databases.count))") {
                    ForEach(databases, id: \.self) { db in
                        Menu(db.lastPathComponent) {
                            Button("Open") { NSWorkspace.shared.open(db) }
                            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([db]) }
                            Button("Copy Path") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(db.path, forType: .string)
                            }
                        }
                    }
                }
            }
            Button("Copy Bundle ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(app.bundleID, forType: .string)
            }
            Divider()
            Button("Erase App Data…") { confirming = .resetData }
            Button("Uninstall…") { confirming = .uninstall }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 12))
                .foregroundStyle(Theme.TextColor.tertiary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Device (biometrics, keychain, pasteboard)

struct DevicePanel: View {
    let udid: String
    @State private var status: ToolboxStatus?
    @State private var contentSize: SimulatorToolbox.ContentSize?
    @State private var increaseContrast: Bool?
    @AppStorage("swordfish.toolbox.rootCertPath") private var rootCertPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            deviceRow(symbol: "textformat.size", title: "Dynamic Type",
                      subtitle: "Text size the simulator's apps render with") {
                PillButton(title: "Smaller", symbol: "textformat.size.smaller") { stepContentSize(-1) }
                Picker("", selection: Binding(
                    get: { contentSize ?? .large },
                    set: { setContentSize($0) }
                )) {
                    ForEach(SimulatorToolbox.ContentSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(Typography.monoSmall)
                .frame(width: 110)
                .disabled(contentSize == nil)
                PillButton(title: "Larger", symbol: "textformat.size.larger") { stepContentSize(1) }
            }
            deviceRow(symbol: "circle.lefthalf.filled", title: "Increase Contrast",
                      subtitle: increaseContrast == nil ? "Not supported by this runtime" : "Accessibility → Display → Increase Contrast") {
                Toggle("", isOn: Binding(
                    get: { increaseContrast ?? false },
                    set: { on in
                        run(on ? String(localized: "Increase Contrast on") : String(localized: "Increase Contrast off")) {
                            try SimulatorToolbox.setIncreaseContrast(udid: udid, on)
                        }
                        increaseContrast = on
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(increaseContrast == nil)
            }
            deviceRow(symbol: "faceid", title: "Face ID / Touch ID",
                      subtitle: "Enroll, then answer the app's biometric prompt") {
                PillButton(title: "Enroll", symbol: "person.crop.circle.badge.checkmark") {
                    run(String(localized: "Biometrics enrolled")) {
                        try SimulatorToolbox.setBiometricEnrollment(udid: udid, enrolled: true)
                    }
                }
                PillButton(title: "Match", symbol: "checkmark.circle") {
                    run(String(localized: "Sent matching face / finger")) {
                        try SimulatorToolbox.biometricAttempt(udid: udid, match: true)
                    }
                }
                PillButton(title: "No Match", symbol: "xmark.circle") {
                    run(String(localized: "Sent non-matching face / finger")) {
                        try SimulatorToolbox.biometricAttempt(udid: udid, match: false)
                    }
                }
            }
            deviceRow(symbol: "key", title: "Keychain",
                      subtitle: "Removes every keychain item on the simulator") {
                PillButton(title: "Reset Keychain", symbol: "arrow.counterclockwise") {
                    run(String(localized: "Keychain reset")) {
                        try SimulatorToolbox.resetKeychain(udid: udid)
                    }
                }
            }
            deviceRow(symbol: "doc.on.clipboard", title: "Pasteboard",
                      subtitle: "Copy text between the Mac and the simulator") {
                PillButton(title: "Mac → Sim", symbol: "arrow.right") {
                    run(String(localized: "Mac clipboard sent to simulator")) {
                        try SimulatorToolbox.syncPasteboard(udid: udid, .macToSimulator)
                    }
                }
                PillButton(title: "Sim → Mac", symbol: "arrow.left") {
                    run(String(localized: "Simulator clipboard copied to Mac")) {
                        try SimulatorToolbox.syncPasteboard(udid: udid, .simulatorToMac)
                    }
                }
            }
            deviceRow(symbol: "lock.shield", title: "Proxy CA certificate",
                      subtitle: "Trust Proxyman / Charles / mitmproxy to inspect HTTPS (export the CA as .pem first)") {
                PillButton(title: "Choose & Install…", symbol: "folder") { chooseCertificate() }
                if !rootCertPath.isEmpty {
                    PillButton(title: "Reinstall \(URL(fileURLWithPath: rootCertPath).lastPathComponent)",
                               symbol: "arrow.clockwise") {
                        installCertificate(URL(fileURLWithPath: rootCertPath))
                    }
                }
            }
            if let status { ToolboxStatusLine(status: status) }
        }
        .task(id: udid) { await loadDisplaySettings() }
    }

    // MARK: Accessibility

    private func loadDisplaySettings() async {
        let id = udid
        let (size, contrast) = await Task.detached(priority: .userInitiated) {
            (SimulatorToolbox.contentSize(udid: id), SimulatorToolbox.increaseContrast(udid: id))
        }.value
        contentSize = size
        increaseContrast = contrast
    }

    private func setContentSize(_ size: SimulatorToolbox.ContentSize) {
        contentSize = size
        run(String(localized: "Dynamic Type set to \(size.label)")) {
            try SimulatorToolbox.setContentSize(udid: udid, size)
        }
    }

    private func stepContentSize(_ delta: Int) {
        let all = SimulatorToolbox.ContentSize.allCases
        let index = all.firstIndex(of: contentSize ?? .large) ?? 3
        let next = all[min(all.count - 1, max(0, index + delta))]
        if next != contentSize { setContentSize(next) }
    }

    // MARK: Certificates

    private func chooseCertificate() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["pem", "crt", "cer", "der"].compactMap { UTType(filenameExtension: $0) }
        panel.message = String(localized: "Choose your proxy's root CA certificate")
        if panel.runModal() == .OK, let url = panel.url {
            rootCertPath = url.path
            installCertificate(url)
        }
    }

    private func installCertificate(_ url: URL) {
        run(String(localized: "Trusted \(url.lastPathComponent) — restart the app to pick it up")) {
            try SimulatorToolbox.addRootCertificate(udid: udid, certificate: url)
        }
    }

    private func deviceRow<Buttons: View>(
        symbol: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        @ViewBuilder buttons: () -> Buttons
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.TextColor.tertiary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Theme.TextColor.primary)
                    Text(subtitle)
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                }
            }
            HStack(spacing: 4) {
                buttons()
            }
            .padding(.leading, 24)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(Theme.Surface.surface1)
        )
    }

    private func run(_ successMessage: String, _ work: @escaping () throws -> Void) {
        status = nil
        Task.detached(priority: .userInitiated) {
            let outcome: ToolboxStatus
            do { try work(); outcome = .ok(successMessage, nil) }
            catch { outcome = .error(error.localizedDescription) }
            await MainActor.run { status = outcome }
        }
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
