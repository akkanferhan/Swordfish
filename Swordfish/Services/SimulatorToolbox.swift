import Foundation

/// An app installed on a simulator, parsed from `simctl listapps`.
struct InstalledApp: Identifiable, Equatable {
    let bundleID: String
    let name: String
    let dataContainer: URL?

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
            apps.append(InstalledApp(bundleID: bundleID, name: name, dataContainer: container))
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
