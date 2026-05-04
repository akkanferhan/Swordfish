import Foundation

enum AppVersion {
    /// `CFBundleShortVersionString` (e.g. "1.2"). Returns "?" if missing.
    static var short: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// `CFBundleVersion` (e.g. "3"). Returns "?" if missing.
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }
}
