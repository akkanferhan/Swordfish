import AppKit
import CoreGraphics

// MARK: - App language

/// In-app language override stored in the standard `AppleLanguages` user
/// default for the app's domain. `.system` removes the override so the app
/// follows the system (or per-app System Settings) language.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case turkish = "tr"
    case spanish = "es"
    case french = "fr"
    case serbian = "sr"
    case serbianLatin = "sr-Latn"
    case japanese = "ja"

    var id: String { rawValue }

    /// Language names are shown in their own language by convention,
    /// so only "System Default" goes through the catalog.
    var label: String {
        switch self {
        case .system:   return String(localized: "System Default")
        case .english:  return "English"
        case .turkish:  return "Türkçe"
        case .spanish:      return "Español"
        case .french:       return "Français"
        case .serbian:      return "Српски (ћирилица)"
        case .serbianLatin: return "Srpski (latinica)"
        case .japanese:     return "日本語"
        }
    }

    static var current: AppLanguage {
        let domain = UserDefaults.standard.persistentDomain(
            forName: Bundle.main.bundleIdentifier ?? ""
        ) ?? [:]
        guard let langs = domain["AppleLanguages"] as? [String],
              let first = langs.first else { return .system }
        // Longest raw value first, so "sr-Latn" wins over the "sr" prefix.
        let candidates = AppLanguage.allCases
            .filter { $0 != .system }
            .sorted { $0.rawValue.count > $1.rawValue.count }
        for lang in candidates where first.hasPrefix(lang.rawValue) {
            return lang
        }
        return .system
    }

    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }

    /// Relaunches the app so the new language takes effect. `open -n` runs
    /// detached, so it survives this process terminating.
    static func relaunch() {
        let path = Bundle.main.bundleURL.path
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", "sleep 0.4; /usr/bin/open -n \"\(path)\""]
        try? proc.run()
        NSApp.terminate(nil)
    }
}

// MARK: - Permissions overview

/// Live status of every permission / helper Swordfish features depend on,
/// for the Settings → Permissions tab.
@MainActor
final class PermissionsModel: ObservableObject {
    enum Grant {
        case granted, denied, notDetermined
    }

    @Published private(set) var screenRecording = false
    @Published private(set) var automation: Grant = .notDetermined
    @Published private(set) var lidHelperInstalled = false
    @Published private(set) var throttleHelperInstalled = false
    @Published private(set) var developerDir: String?
    @Published private(set) var simctlAvailable = false
    @Published private(set) var isFixingDevTools = false
    @Published var devToolsError: String?

    static let xcodeFixCommand = "sudo xcode-select -s /Applications/Xcode.app"

    nonisolated static var xcodeAppExists: Bool {
        FileManager.default.fileExists(atPath: "/Applications/Xcode.app")
    }

    func refresh() {
        screenRecording = CGPreflightScreenCaptureAccess()
        lidHelperInstalled = LidSleepService.helperFileExists
        throttleHelperInstalled = NetworkThrottleService.helperFileExists

        Task.detached(priority: .userInitiated) {
            let auto = Self.automationGrant(ask: false)
            let devDir = (try? ProcessRunner.run("/usr/bin/xcode-select", arguments: ["-p"]))?
                .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let simctl = (try? ProcessRunner.run("/usr/bin/xcrun", arguments: ["--find", "simctl"]))?.exitCode == 0
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.automation = auto
                self.developerDir = (devDir?.isEmpty ?? true) ? nil : devDir
                self.simctlAvailable = simctl
            }
        }
    }

    /// Shows the system Screen Recording prompt the first time; afterwards
    /// macOS only allows changing it in System Settings.
    func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
        refresh()
    }

    func requestAutomation() {
        Task.detached(priority: .userInitiated) {
            // The consent prompt only appears while the target is running.
            _ = try? ProcessRunner.run("/usr/bin/open", arguments: ["-g", "-b", "com.apple.systemevents"])
            try? await Task.sleep(nanoseconds: 500_000_000)
            let result = Self.automationGrant(ask: true)
            await MainActor.run { [weak self] in self?.automation = result }
        }
    }

    /// Points `xcode-select` at /Applications/Xcode.app through the admin
    /// auth dialog, so Simulator features work without a trip to Terminal.
    func fixDeveloperTools() {
        guard !isFixingDevTools, Self.xcodeAppExists else { return }
        isFixingDevTools = true
        devToolsError = nil

        Task.detached(priority: .userInitiated) {
            let err = AdminShell.runScript(
                "/usr/bin/xcode-select -s /Applications/Xcode.app",
                prompt: String(localized: "Swordfish needs your password to point xcode-select at Xcode.")
            )
            await MainActor.run { [weak self] in
                self?.isFixingDevTools = false
                self?.devToolsError = err
                self?.refresh()
            }
        }
    }

    static func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    nonisolated private static func automationGrant(ask: Bool) -> Grant {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents")
        let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask)
        switch Int(status) {
        case 0:
            return .granted
        case Int(errAEEventNotPermitted):
            return .denied
        default:
            // errAEEventWouldRequireUserConsent, procNotFound (System Events
            // not running), or anything else we can't classify.
            return .notDetermined
        }
    }
}
