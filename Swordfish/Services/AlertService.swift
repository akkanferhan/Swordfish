import Foundation
import Combine
import AppKit
import UserNotifications

// MARK: - Settings

/// What the status item shows next to its icon.
enum MenuBarMetric: String, CaseIterable, Identifiable {
    case none, cpuTemp, cpuLoad, memory, network
    var id: String { rawValue }

    static let defaultsKey = "menuBarMetric"
    static var current: MenuBarMetric {
        MenuBarMetric(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .none
    }

    var label: String {
        switch self {
        case .none:    return String(localized: "Icon only")
        case .cpuTemp: return String(localized: "CPU temperature")
        case .cpuLoad: return String(localized: "CPU load")
        case .memory:  return String(localized: "Memory used")
        case .network: return String(localized: "Network speed")
        }
    }

    @MainActor
    func text(from monitor: SystemMonitor) -> String? {
        switch self {
        case .none:    return nil
        case .cpuTemp: return String(format: "%.0f°", monitor.cpuTemp)
        case .cpuLoad: return String(format: "%.0f%%", monitor.cpuLoad * 100)
        case .memory:  return String(format: "%.0f%%", monitor.memory.usedFraction * 100)
        case .network:
            return "↓\(Self.compact(monitor.network.downBytesPerSec)) ↑\(Self.compact(monitor.network.upBytesPerSec))"
        }
    }

    /// "820K" / "1.4M" — narrow enough for the menu bar.
    private static func compact(_ bytesPerSec: Double) -> String {
        switch bytesPerSec {
        case ..<1_000:         return String(format: "%.0fB", bytesPerSec)
        case ..<1_000_000:     return String(format: "%.0fK", bytesPerSec / 1_000)
        case ..<10_000_000:    return String(format: "%.1fM", bytesPerSec / 1_000_000)
        default:               return String(format: "%.0fM", bytesPerSec / 1_000_000)
        }
    }
}

/// UserDefaults keys + defaults for the alert thresholds (shared by
/// `AlertService` and the Settings → Monitoring tab's `@AppStorage`).
enum AlertSettings {
    static let cpuTempEnabled = "alerts.cpuTemp.enabled"
    static let cpuTempThreshold = "alerts.cpuTemp.threshold"
    static let diskEnabled = "alerts.diskFree.enabled"
    static let diskThresholdGB = "alerts.diskFree.thresholdGB"
    static let memoryEnabled = "alerts.memoryPressure.enabled"
    static let thermalEnabled = "alerts.thermal.enabled"

    static let defaultCPUTemp = 90
    static let defaultDiskGB = 10

    static func register() {
        UserDefaults.standard.register(defaults: [
            cpuTempThreshold: defaultCPUTemp,
            diskThresholdGB: defaultDiskGB,
        ])
    }
}

// MARK: - Service

/// Posts a local notification when CPU temperature, free disk space, memory
/// pressure or thermal throttling cross a threshold. Each kind has a
/// cooldown so a sustained condition doesn't spam.
@MainActor
final class AlertService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    enum Kind: String {
        case cpuTemp, disk, memory, thermal, build
    }

    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined

    /// Called when the user clicks a notification (opens the popover).
    var onOpen: (() -> Void)?

    private let monitor: SystemMonitor
    private var cancellables = Set<AnyCancellable>()
    private var lastFired: [Kind: Date] = [:]
    private var hotSamples = 0
    private var memorySource: DispatchSourceMemoryPressure?
    private let cooldown: TimeInterval = 30 * 60
    private let defaults = UserDefaults.standard

    init(monitor: SystemMonitor) {
        self.monitor = monitor
        super.init()
        AlertSettings.register()
    }

    func start() {
        UNUserNotificationCenter.current().delegate = self
        refreshAuthorization()

        monitor.$cpuTemp
            .sink { [weak self] in self?.checkCPU($0) }
            .store(in: &cancellables)
        monitor.$disk
            .sink { [weak self] in self?.checkDisk($0) }
            .store(in: &cancellables)
        monitor.$thermalState
            .removeDuplicates()
            .sink { [weak self] in self?.checkThermal($0) }
            .store(in: &cancellables)

        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.critical], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.memoryPressureCritical() }
        }
        source.resume()
        memorySource = source
    }

    // MARK: - Authorization

    func refreshAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let status = settings.authorizationStatus
            Task { @MainActor in self?.authorization = status }
        }
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            Task { @MainActor in self?.refreshAuthorization() }
        }
    }

    func sendTest() {
        post(.cpuTemp, title: String(localized: "Swordfish alerts are working"),
             body: String(localized: "You'll get a notification like this when a threshold is crossed."), force: true)
    }

    // MARK: - Checks

    private func checkCPU(_ temp: Double) {
        guard defaults.bool(forKey: AlertSettings.cpuTempEnabled) else { hotSamples = 0; return }
        let threshold = Double(defaults.integer(forKey: AlertSettings.cpuTempThreshold))
        // Require ~6 s above the line so a single spike doesn't fire.
        hotSamples = temp >= threshold ? hotSamples + 1 : 0
        guard hotSamples >= 3 else { return }
        post(.cpuTemp,
             title: String(localized: "CPU is running hot"),
             body: String(format: String(localized: "CPU temperature is %.0f°C (alert at %.0f°C)."), temp, threshold))
    }

    private func checkDisk(_ disk: DiskStats) {
        guard defaults.bool(forKey: AlertSettings.diskEnabled), disk.totalBytes > 0 else { return }
        let thresholdBytes = UInt64(defaults.integer(forKey: AlertSettings.diskThresholdGB)) * 1_000_000_000
        guard disk.freeBytes < thresholdBytes else { return }
        post(.disk,
             title: String(localized: "Disk space is low"),
             body: String(localized: "Only \(disk.freeBytes.humanBytes) free on \(disk.volumeName). Dev Kit → Disk Cleanup can usually free several GB."))
    }

    private func checkThermal(_ state: ProcessInfo.ThermalState) {
        guard defaults.bool(forKey: AlertSettings.thermalEnabled),
              state == .serious || state == .critical else { return }
        post(.thermal,
             title: String(localized: "Mac is throttling"),
             body: String(localized: "macOS reports heavy thermal pressure — builds and simulators will run slower."))
    }

    private func memoryPressureCritical() {
        guard defaults.bool(forKey: AlertSettings.memoryEnabled) else { return }
        post(.memory,
             title: String(localized: "Memory pressure is critical"),
             body: String(localized: "Close a simulator or two, or check System → Processes → Top Memory."))
    }

    /// Xcode build finished. Respects Settings → Monitoring: on/off, a minimum
    /// duration (failures always notify) and "only while Xcode is in the background".
    func announceBuild(_ record: BuildRecord, slowerThanUsual: Bool) {
        BuildSettings.register()
        guard defaults.bool(forKey: BuildSettings.notifyKey) else { return }
        let minSeconds = Double(defaults.integer(forKey: BuildSettings.minSecondsKey))
        if record.status != .failed && record.duration < minSeconds && !slowerThanUsual { return }
        if defaults.bool(forKey: BuildSettings.onlyBackgroundKey),
           NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.dt.Xcode" { return }

        let duration = BuildRecord.formatDuration(record.duration)
        let title: String
        switch record.status {
        case .failed:
            title = String(localized: "❌ Build failed — \(record.scheme)")
        case .succeeded, .warnings, .other:
            title = String(localized: "✅ Build succeeded — \(record.scheme)")
        }
        var body = record.status == .failed
            ? String(localized: "\(record.errors) error(s) after \(duration)")
            : String(localized: "Took \(duration)")
        if record.warnings > 0 { body += String(localized: " · \(record.warnings) warning(s)") }
        if slowerThanUsual { body += String(localized: " · slower than usual") }
        notify(title: title, body: body)
    }

    /// An App Store Connect build left the PROCESSING state.
    func announceASC(_ build: ASCBuild, previous: ASCBuild.State) {
        ASCSettings.register()
        guard defaults.bool(forKey: ASCSettings.notifyKey), previous == .processing else { return }
        switch build.state {
        case .valid:
            notify(title: String(localized: "🚀 \(build.appName) \(build.title) is ready"),
                   body: String(localized: "Finished processing — available in TestFlight."))
        case .failed, .invalid:
            notify(title: String(localized: "⚠️ \(build.appName) \(build.title) failed processing"),
                   body: String(localized: "Check App Store Connect / your email for details."))
        default:
            break
        }
    }

    /// Fire-and-forget notification without cooldown (build results etc.).
    func notify(title: String, body: String) {
        post(.build, title: title, body: body, force: true)
    }

    // MARK: - Posting

    private func post(_ kind: Kind, title: String, body: String, force: Bool = false) {
        if !force, let last = lastFired[kind], Date().timeIntervalSince(last) < cooldown { return }
        lastFired[kind] = Date()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "swordfish.\(kind.rawValue).\(UUID().uuidString)",
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show banners even while Swordfish is the active app.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor [weak self] in self?.onOpen?() }
        completionHandler()
    }
}
