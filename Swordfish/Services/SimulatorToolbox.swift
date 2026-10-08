import Foundation

/// An app installed on a simulator, parsed from `simctl listapps`.
struct InstalledApp: Identifiable, Equatable {
    let bundleID: String
    let name: String
    let dataContainer: URL?
    var executable: String? = nil
    var version: String? = nil
    /// The installed `.app` bundle inside the simulator.
    var bundlePath: URL? = nil

    /// Languages the app ships (`*.lproj`, minus Base), for "Launch in…".
    var localizations: [String] {
        guard let bundlePath,
              let items = try? FileManager.default.contentsOfDirectory(atPath: bundlePath.path) else { return [] }
        return items
            .filter { $0.hasSuffix(".lproj") && $0 != "Base.lproj" }
            .map { String($0.dropLast(".lproj".count)) }
            .sorted()
    }

    var id: String { bundleID }
}

/// Thin wrappers around the `simctl` subcommands used by the Simulator
/// Toolbox (status bar overrides, appearance, privacy, location, media,
/// app containers, screenshots). All calls block until the command exits —
/// invoke from a detached task.
enum SimulatorToolbox {
    struct CommandError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - Status bar

    struct StatusBarConfig {
        var time = "9:41"
        var batteryLevel = 100
        var batteryState: BatteryState = .charged
        var network: DataNetwork = .wifi

        enum BatteryState: String, CaseIterable, Identifiable {
            case charged, charging, discharging
            var id: String { rawValue }
            var label: String {
                switch self {
                case .charged:     return String(localized: "Charged")
                case .charging:    return String(localized: "Charging")
                case .discharging: return String(localized: "Discharging")
                }
            }
        }

        enum DataNetwork: String, CaseIterable, Identifiable {
            case wifi
            case lte
            case fiveG = "5g"
            case hide
            var id: String { rawValue }
            var label: String {
                switch self {
                case .wifi:  return String(localized: "Wi-Fi")
                case .lte:   return String(localized: "LTE")
                case .fiveG: return String(localized: "5G")
                case .hide:  return String(localized: "Hidden")
                }
            }
        }
    }

    /// Applies a full status-bar override (the classic "App Store screenshot"
    /// look by default: 9:41, full battery, full signal).
    static func overrideStatusBar(udid: String, config: StatusBarConfig) throws {
        try simctl(["status_bar", udid, "override",
                    "--time", config.time,
                    "--batteryState", config.batteryState.rawValue,
                    "--batteryLevel", String(config.batteryLevel),
                    "--dataNetwork", config.network.rawValue,
                    "--wifiMode", "active", "--wifiBars", "3",
                    "--cellularMode", "active", "--cellularBars", "4"])
    }

    static func clearStatusBar(udid: String) throws {
        try simctl(["status_bar", udid, "clear"])
    }

    // MARK: - Appearance

    static func setAppearance(udid: String, dark: Bool) throws {
        try simctl(["ui", udid, "appearance", dark ? "dark" : "light"])
    }

    // MARK: - Location

    static func setLocation(udid: String, latitude: Double, longitude: Double) throws {
        try simctl(["location", udid, "set", "\(latitude),\(longitude)"])
    }

    static func clearLocation(udid: String) throws {
        try simctl(["location", udid, "clear"])
    }

    typealias Coordinate = (lat: Double, lon: Double)

    /// Moves the simulated location along the waypoints at `speed` m/s
    /// (`simctl location start`); the simulator keeps playing it until
    /// cleared or another location is set.
    static func startRoute(udid: String, waypoints: [Coordinate], speed: Double) throws {
        guard waypoints.count >= 2 else {
            throw CommandError(message: String(localized: "A route needs at least two waypoints"))
        }
        try simctl(["location", udid, "start", String(format: "--speed=%.1f", speed)]
                   + waypoints.map { String(format: "%.6f,%.6f", $0.lat, $0.lon) })
    }

    /// Track / route / waypoint coordinates from a GPX file, thinned to at
    /// most `limit` points so the simctl command line stays manageable.
    static func gpxWaypoints(_ data: Data, limit: Int = 400) -> [Coordinate] {
        final class Collector: NSObject, XMLParserDelegate {
            var points: [SimulatorToolbox.Coordinate] = []
            func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                        qualifiedName: String?, attributes: [String: String] = [:]) {
                guard ["trkpt", "rtept", "wpt"].contains(name),
                      let lat = attributes["lat"].flatMap(Double.init),
                      let lon = attributes["lon"].flatMap(Double.init) else { return }
                points.append((lat, lon))
            }
        }
        let collector = Collector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.parse()
        let all = collector.points
        guard all.count > limit else { return all }
        let step = Double(all.count - 1) / Double(limit - 1)
        return (0..<limit).map { all[Int((Double($0) * step).rounded())] }
    }

    // MARK: - Privacy

    enum PrivacyService: String, CaseIterable, Identifiable {
        case location
        case locationAlways = "location-always"
        case photos
        case photosAdd = "photos-add"
        case mediaLibrary = "media-library"
        case contacts
        case calendar
        case reminders
        case microphone
        case motion
        case siri

        var id: String { rawValue }
        var label: String {
            switch self {
            case .location:       return String(localized: "Location (While Using)")
            case .locationAlways: return String(localized: "Location (Always)")
            case .photos:         return String(localized: "Photos (Read/Write)")
            case .photosAdd:      return String(localized: "Photos (Add Only)")
            case .mediaLibrary:   return String(localized: "Media Library")
            case .contacts:       return String(localized: "Contacts")
            case .calendar:       return String(localized: "Calendar")
            case .reminders:      return String(localized: "Reminders")
            case .microphone:     return String(localized: "Microphone")
            case .motion:         return String(localized: "Motion & Fitness")
            case .siri:           return String(localized: "Siri")
            }
        }
    }

    enum PrivacyAction: String {
        case grant, revoke, reset
    }

    static func privacy(udid: String, action: PrivacyAction, service: PrivacyService, bundleID: String) throws {
        try simctl(["privacy", udid, action.rawValue, service.rawValue, bundleID])
    }

    // MARK: - Media

    static func addMedia(udid: String, files: [URL]) throws {
        try simctl(["addmedia", udid] + files.map(\.path))
    }

    // MARK: - Screenshot

    /// Captures a PNG of the simulator screen to the Desktop and returns its URL.
    static func screenshot(udid: String) throws -> URL {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let url = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
            .appendingPathComponent("sim-screenshot-\(fmt.string(from: Date())).png")
        try simctl(["io", udid, "screenshot", "--type", "png", url.path])
        return url
    }

    // MARK: - Installed apps

    /// User-installed apps on the simulator. `simctl listapps` prints an
    /// old-style (NeXTSTEP) plist, so pipe it through plutil to get JSON.
    /// The UDID comes from `simctl list` and is always a UUID, so it's safe
    /// to interpolate into the shell line.
    static func listApps(udid: String) throws -> [InstalledApp] {
        let result = try ProcessRunner.run("/bin/sh", arguments: [
            "-c", "/usr/bin/xcrun simctl listapps '\(udid)' | /usr/bin/plutil -convert json -o - -"
        ])
        guard result.exitCode == 0 else {
            let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CommandError(message: err.isEmpty ? "simctl listapps failed (exit \(result.exitCode))" : err)
        }
        guard let data = result.stdout.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]]
        else {
            throw CommandError(message: "Could not parse simctl listapps output")
        }

        var apps: [InstalledApp] = []
        for (bundleID, info) in root {
            guard (info["ApplicationType"] as? String) == "User" else { continue }
            let name = (info["CFBundleDisplayName"] as? String)
                ?? (info["CFBundleName"] as? String)
                ?? bundleID
            let container = (info["DataContainer"] as? String).flatMap(URL.init(string:))
            apps.append(InstalledApp(bundleID: bundleID, name: name, dataContainer: container,
                                     executable: info["CFBundleExecutable"] as? String,
                                     version: info["CFBundleShortVersionString"] as? String,
                                     bundlePath: (info["Path"] as? String).map { URL(fileURLWithPath: $0) }))
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - App lifecycle

    static func install(udid: String, app: URL) throws {
        try simctl(["install", udid, app.path])
    }

    static func uninstall(udid: String, bundleID: String) throws {
        try simctl(["uninstall", udid, bundleID])
    }

    static func launch(udid: String, bundleID: String, arguments: [String] = []) throws {
        try simctl(["launch", "--terminate-running-process", udid, bundleID] + arguments)
    }

    /// Launch arguments that switch an app's language / locale for one run
    /// (no need to change the whole simulator), plus Foundation's
    /// pseudo-localization switches.
    enum LaunchLocale: Hashable {
        case language(String)
        case doubleLength
        case rightToLeft
        case showUnlocalized

        var arguments: [String] {
            switch self {
            case .language(let code):
                // "pt-BR" → AppleLocale "pt_BR"; plain "tr" → "tr_TR".
                let locale = code.contains("-")
                    ? code.replacingOccurrences(of: "-", with: "_")
                    : "\(code)_\(code == "en" ? "US" : code.uppercased())"
                return ["-AppleLanguages", "(\(code))", "-AppleLocale", locale]
            case .doubleLength:
                return ["-NSDoubleLocalizedStrings", "YES"]
            case .rightToLeft:
                return ["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"]
            case .showUnlocalized:
                return ["-NSShowNonLocalizedStrings", "YES"]
            }
        }

        var label: String {
            switch self {
            case .language(let code):
                let name = Locale.current.localizedString(forIdentifier: code) ?? code
                return "\(name) (\(code))"
            case .doubleLength:    return String(localized: "Pseudo: double-length strings")
            case .rightToLeft:     return String(localized: "Pseudo: right-to-left layout")
            case .showUnlocalized: return String(localized: "Highlight unlocalized strings")
            }
        }
    }

    /// SQLite / Core Data / SwiftData stores inside the app's sandbox.
    static func databaseFiles(app: InstalledApp) -> [URL] {
        guard let container = app.dataContainer,
              let walker = FileManager.default.enumerator(at: container, includingPropertiesForKeys: [.isRegularFileKey])
        else { return [] }
        let extensions: Set<String> = ["sqlite", "sqlite3", "db", "store", "realm"]
        var result: [URL] = []
        for case let url as URL in walker where extensions.contains(url.pathExtension.lowercased()) {
            result.append(url)
            if result.count >= 30 { break }
        }
        return result.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func terminate(udid: String, bundleID: String) throws {
        try simctl(["terminate", udid, bundleID])
    }

    /// Wipes an app's sandbox (Documents, Library, tmp) without reinstalling
    /// it — the "fresh install" state for onboarding / migration testing.
    /// The app is terminated first so it can't write back stale state.
    static func resetData(udid: String, app: InstalledApp) throws {
        guard let container = app.dataContainer else {
            throw CommandError(message: String(localized: "\(app.name) has no data container"))
        }
        _ = try? terminate(udid: udid, bundleID: app.bundleID)
        let fm = FileManager.default
        for sub in ["Documents", "Library", "tmp"] {
            let dir = container.appendingPathComponent(sub)
            for child in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                try fm.removeItem(at: child)
            }
        }
    }

    /// The app's standard UserDefaults domain rendered as pretty JSON, so it
    /// can be explored in the JSON Viewer.
    static func userDefaultsJSON(app: InstalledApp) throws -> String {
        guard let container = app.dataContainer else {
            throw CommandError(message: String(localized: "\(app.name) has no data container"))
        }
        let plist = container.appendingPathComponent("Library/Preferences/\(app.bundleID).plist")
        guard let data = try? Data(contentsOf: plist) else {
            throw CommandError(message: String(localized: "No UserDefaults written yet for \(app.bundleID)"))
        }
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try PlistJSON.jsonString(fromPlistObject: object)
    }

    // MARK: - Accessibility

    /// Dynamic Type categories `simctl ui content_size` accepts, smallest first.
    enum ContentSize: String, CaseIterable, Identifiable {
        case extraSmall = "extra-small"
        case small
        case medium
        case large
        case extraLarge = "extra-large"
        case extraExtraLarge = "extra-extra-large"
        case extraExtraExtraLarge = "extra-extra-extra-large"
        case accessibilityMedium = "accessibility-medium"
        case accessibilityLarge = "accessibility-large"
        case accessibilityExtraLarge = "accessibility-extra-large"
        case accessibilityExtraExtraLarge = "accessibility-extra-extra-large"
        case accessibilityExtraExtraExtraLarge = "accessibility-extra-extra-extra-large"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .extraSmall:                       return "XS"
            case .small:                            return "S"
            case .medium:                           return "M"
            case .large:                            return String(localized: "L (default)")
            case .extraLarge:                       return "XL"
            case .extraExtraLarge:                  return "XXL"
            case .extraExtraExtraLarge:             return "XXXL"
            case .accessibilityMedium:              return "AX1"
            case .accessibilityLarge:               return "AX2"
            case .accessibilityExtraLarge:          return "AX3"
            case .accessibilityExtraExtraLarge:     return "AX4"
            case .accessibilityExtraExtraExtraLarge: return "AX5"
            }
        }
    }

    static func contentSize(udid: String) -> ContentSize? {
        guard let out = try? simctl(["ui", udid, "content_size"]) else { return nil }
        return ContentSize(rawValue: out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func setContentSize(udid: String, _ size: ContentSize) throws {
        try simctl(["ui", udid, "content_size", size.rawValue])
    }

    /// nil when the runtime doesn't support the setting.
    static func increaseContrast(udid: String) -> Bool? {
        guard let out = try? simctl(["ui", udid, "increase_contrast"]) else { return nil }
        switch out.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "enabled":  return true
        case "disabled": return false
        default:         return nil
        }
    }

    static func setIncreaseContrast(udid: String, _ on: Bool) throws {
        try simctl(["ui", udid, "increase_contrast", on ? "enabled" : "disabled"])
    }

    // MARK: - Device

    /// Trusts a proxy's root CA (Proxyman, Charles, mitmproxy…) so HTTPS
    /// traffic from the simulator can be inspected.
    static func addRootCertificate(udid: String, certificate: URL) throws {
        try simctl(["keychain", udid, "add-root-cert", certificate.path])
    }

    static func resetKeychain(udid: String) throws {
        try simctl(["keychain", udid, "reset"])
    }

    /// Biometrics are driven through the simulator's BiometricKit Darwin
    /// notifications — the same thing Features → Face ID / Touch ID does.
    static func setBiometricEnrollment(udid: String, enrolled: Bool) throws {
        let key = "com.apple.BiometricKit.enrollmentChanged"
        try simctl(["spawn", udid, "notifyutil", "-s", key, enrolled ? "1" : "0"])
        try simctl(["spawn", udid, "notifyutil", "-p", key])
    }

    /// Posts both the Face ID ("pearl") and Touch ID ("fingerTouch") events;
    /// the device only listens to the one its hardware has.
    static func biometricAttempt(udid: String, match: Bool) throws {
        let suffix = match ? "match" : "nomatch"
        for sensor in ["pearl", "fingerTouch"] {
            try simctl(["spawn", udid, "notifyutil", "-p", "com.apple.BiometricKit_Sim.\(sensor).\(suffix)"])
        }
    }

    enum PasteboardDirection { case macToSimulator, simulatorToMac }

    /// The UDID comes from `simctl list` (always a UUID), so it's safe to
    /// interpolate into the shell pipe.
    static func syncPasteboard(udid: String, _ direction: PasteboardDirection) throws {
        let line: String
        switch direction {
        case .macToSimulator: line = "/usr/bin/pbpaste | /usr/bin/xcrun simctl pbcopy '\(udid)'"
        case .simulatorToMac: line = "/usr/bin/xcrun simctl pbpaste '\(udid)' | /usr/bin/pbcopy"
        }
        let result = try ProcessRunner.run("/bin/sh", arguments: ["-c", line])
        guard result.exitCode == 0 else {
            let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CommandError(message: err.isEmpty ? "pasteboard sync failed (exit \(result.exitCode))" : err)
        }
    }

    // MARK: - Helpers

    /// Runs `xcrun simctl <args>`, throwing stderr on a non-zero exit.
    @discardableResult
    static func simctl(_ args: [String]) throws -> String {
        let result = try ProcessRunner.run("/usr/bin/xcrun", arguments: ["simctl"] + args)
        guard result.exitCode == 0 else {
            let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let command = args.first ?? "simctl"
            throw CommandError(message: err.isEmpty ? "simctl \(command) failed (exit \(result.exitCode))" : err)
        }
        return result.stdout
    }
}

/// Loads the user-installed apps of a simulator for the Permissions and
/// Apps panels. Each panel owns its instance, mirroring how every DevKit
/// view owns its `SimulatorService`.
@MainActor
final class InstalledAppsModel: ObservableObject {
    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    func load(udid: String) {
        guard !udid.isEmpty, !isLoading else { return }
        isLoading = true
        lastError = nil
        Task.detached(priority: .userInitiated) {
            let outcome = Result { try SimulatorToolbox.listApps(udid: udid) }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isLoading = false
                switch outcome {
                case .success(let apps): self.apps = apps
                case .failure(let error):
                    self.apps = []
                    self.lastError = error.localizedDescription
                }
            }
        }
    }
}
