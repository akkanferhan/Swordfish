import Foundation

struct PhysicalDevice: Identifiable, Equatable {
    let identifier: String
    let name: String
    let model: String?
    let platform: String?
    let osVersion: String?
    let udid: String?
    /// "connected", "disconnected", … (CoreDevice tunnel state).
    let connectionState: String?
    /// "wired", "localNetwork", …
    let transport: String?

    var id: String { identifier }
    var isConnected: Bool { connectionState == "connected" }
}

/// `xcrun devicectl` wrapper for real (non-simulated) devices: list, install,
/// launch, screenshot, crash-log export. devicectl's stdout is explicitly
/// unstable, so every query goes through `--json-output` to a temp file.
enum PhysicalDeviceTool {
    struct CommandError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func listDevices() throws -> [PhysicalDevice] {
        let json = try devicectlJSON(["list", "devices"])
        let devices = ((json["result"] as? [String: Any])?["devices"] as? [[String: Any]]) ?? []
        return devices.compactMap(parse).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Reads the `properties` dictionary (JSON v5+) and falls back to the
    /// deprecated `deviceProperties` / `hardwareProperties` /
    /// `connectionProperties` keys of older Xcodes.
    private static func parse(_ d: [String: Any]) -> PhysicalDevice? {
        let props = d["properties"] as? [String: Any] ?? [:]
        let hardware = props["hardware"] as? [String: Any] ?? d["hardwareProperties"] as? [String: Any] ?? [:]
        guard (hardware["reality"] as? String) == "physical",
              let identifier = d["identifier"] as? String else { return nil }
        let state = props["state"] as? [String: Any] ?? [:]
        let software = props["software"] as? [String: Any] ?? [:]
        let connection = props["connection"] as? [String: Any] ?? [:]
        let legacyDevice = d["deviceProperties"] as? [String: Any] ?? [:]
        let legacyConnection = d["connectionProperties"] as? [String: Any] ?? [:]

        let os = ((software["osVersionNumber"] as? [String: Any])?["stringValue"] as? String)
            ?? (legacyDevice["osVersionNumber"] as? String)
        return PhysicalDevice(
            identifier: identifier,
            name: (state["name"] as? String) ?? (legacyDevice["name"] as? String) ?? identifier,
            model: hardware["marketingName"] as? String,
            platform: hardware["platform"] as? String,
            osVersion: os,
            udid: hardware["udid"] as? String,
            connectionState: (connection["state"] as? String) ?? (legacyConnection["tunnelState"] as? String),
            transport: (connection["transportType"] as? String) ?? (legacyConnection["transportType"] as? String)
        )
    }

    /// Installs a `.app`, or the app inside an `.ipa` (unzipped to a temp dir
    /// first — `devicectl device install app` only takes bundles).
    static func install(device: String, app: URL) throws {
        var bundle = app
        var tempDir: URL?
        defer { if let tempDir { try? FileManager.default.removeItem(at: tempDir) } }
        if app.pathExtension.lowercased() == "ipa" {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swordfish-ipa-\(UUID().uuidString)")
            tempDir = dir
            let unzip = try ProcessRunner.run("/usr/bin/ditto", arguments: ["-x", "-k", app.path, dir.path])
            guard unzip.exitCode == 0 else {
                throw CommandError(message: unzip.stderr.isEmpty ? String(localized: "Could not unzip the .ipa") : unzip.stderr)
            }
            let payload = dir.appendingPathComponent("Payload")
            guard let found = (try? FileManager.default.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil))?
                .first(where: { $0.pathExtension == "app" }) else {
                throw CommandError(message: String(localized: "No .app found inside the .ipa's Payload folder"))
            }
            bundle = found
        }
        try devicectl(["device", "install", "app", "--device", device, bundle.path])
    }

    static func launch(device: String, bundleID: String) throws {
        try devicectl(["device", "process", "launch", "--terminate-existing", "--device", device, bundleID])
    }

    /// Launches the app with a URL to open — deep links and universal links
    /// on a real device, without typing them into Notes or Safari.
    static func openURL(device: String, bundleID: String, url: String) throws {
        try devicectl(["device", "process", "launch", "--terminate-existing", "--device", device,
                       "--payload-url", url, bundleID])
    }

    /// Saves a PNG of the device screen to the Desktop and returns its URL.
    static func screenshot(device: PhysicalDevice) throws -> URL {
        let url = desktop.appendingPathComponent("\(safeName(device.name))-screenshot-\(stamp()).png")
        try devicectl(["device", "capture", "screenshot", "--device", device.identifier, "--destination", url.path])
        return url
    }

    /// Copies the device's crash logs into a new Desktop folder.
    static func copyCrashLogs(device: PhysicalDevice) throws -> URL {
        let url = desktop.appendingPathComponent("\(safeName(device.name))-crashlogs-\(stamp())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try devicectl(["device", "copy", "from", "--device", device.identifier,
                       "--domain-type", "systemCrashLogs", "--source", "/", "--destination", url.path])
        return url
    }

    // MARK: - Helpers

    private static var desktop: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
    }

    private static func stamp() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return fmt.string(from: Date())
    }

    private static func safeName(_ s: String) -> String {
        s.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
    }

    @discardableResult
    private static func devicectl(_ args: [String]) throws -> ProcessRunner.Result {
        let result = try ProcessRunner.run("/usr/bin/xcrun", arguments: ["devicectl"] + args)
        guard result.exitCode == 0 else {
            let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = err.isEmpty ? out : err
            throw CommandError(message: message.isEmpty ? "devicectl \(args.prefix(2).joined(separator: " ")) failed (exit \(result.exitCode))" : message)
        }
        return result
    }

    private static func devicectlJSON(_ args: [String]) throws -> [String: Any] {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("swordfish-devicectl-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try devicectl(args + ["--quiet", "--json-output", file.path])
        guard let data = try? Data(contentsOf: file),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw CommandError(message: String(localized: "Could not read devicectl output"))
        }
        return json
    }
}

@MainActor
final class PhysicalDeviceService: ObservableObject {
    @Published private(set) var devices: [PhysicalDevice] = []
    @Published private(set) var isLoading = false
    @Published private(set) var busyDeviceID: String?
    @Published var status: ToolboxStatus?

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let outcome = Result { try PhysicalDeviceTool.listDevices() }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isLoading = false
                switch outcome {
                case .success(let list): self.devices = list
                case .failure(let error):
                    self.devices = []
                    self.status = .error(error.localizedDescription)
                }
            }
        }
    }

    /// Runs one devicectl action for a device, one at a time per device.
    func run(on device: PhysicalDevice, _ work: @escaping () throws -> ToolboxStatus) {
        guard busyDeviceID == nil else { return }
        busyDeviceID = device.id
        status = nil
        Task.detached(priority: .userInitiated) {
            let outcome: ToolboxStatus
            do { outcome = try work() }
            catch { outcome = .error(error.localizedDescription) }
            await MainActor.run { [weak self] in
                self?.busyDeviceID = nil
                self?.status = outcome
            }
        }
    }
}
