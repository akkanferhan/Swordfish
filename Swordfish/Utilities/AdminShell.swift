import Foundation

/// Privileged shell execution shared by services that manage sudoers helpers
/// (network throttling, lid-closed anti-sleep).
enum AdminShell {
    /// Runs an arbitrary shell script as root via osascript's authentication
    /// dialog. Returns nil on success, error message otherwise.
    static func runScript(_ script: String, prompt: String) -> String? {
        // Quote for AppleScript: backslash, then double-quote.
        let quoted = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let promptQuoted = prompt
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let osa = "do shell script \"\(quoted)\" with prompt \"\(promptQuoted)\" with administrator privileges"
        let r = try? ProcessRunner.run("/usr/bin/osascript", arguments: ["-e", osa])
        if let r, r.exitCode == 0 { return nil }
        let msg = (r?.stderr ?? "Failed to run admin script").trimmingCharacters(in: .whitespacesAndNewlines)
        if msg.localizedCaseInsensitiveContains("user canceled") || msg.localizedCaseInsensitiveContains("user cancelled") {
            return nil // silent on user cancel
        }
        return msg.isEmpty ? "Failed (exit \(r?.exitCode ?? -1))" : msg
    }
}
