import Foundation

private let helperPath = "/etc/sudoers.d/swordfish-lidsleep"

/// Keeps the Mac awake even when the lid is closed, via `pmset -a disablesleep`.
/// IOPMAssertion (CaffeineService) cannot block clamshell sleep — `disablesleep`
/// is the only supported switch, and it requires root.
///
/// First use prompts for the admin password once and writes a sudoers entry
/// scoped to exactly `pmset -a disablesleep 1` / `0`. Later toggles run
/// silently via `sudo -n`, which also lets the app restore normal sleep
/// behavior when it quits.
@MainActor
final class LidSleepService: ObservableObject {
    @Published private(set) var isHelperInstalled = false
    @Published private(set) var isEnabled = false
    @Published private(set) var isBusy = false
    @Published var lastError: String?

    init() {
        refreshHelperStatus()
        refreshState()
    }

    // MARK: - Public actions

    func refreshHelperStatus() {
        isHelperInstalled = FileManager.default.fileExists(atPath: helperPath)
    }

    /// Whether the sudoers helper is present — exposed for the Settings
    /// permissions overview without spinning up the full service.
    nonisolated static var helperFileExists: Bool {
        FileManager.default.fileExists(atPath: helperPath)
    }

    /// Reads the live `SleepDisabled` flag so the toggle reflects reality even
    /// after a crash or an external `pmset` change.
    func refreshState() {
        Task.detached(priority: .background) {
            let on = Self.readSleepDisabled()
            await MainActor.run { [weak self] in
                self?.isEnabled = on
            }
        }
    }

    func setEnabled(_ on: Bool) {
        guard !isBusy else { return }
        isBusy = true
        lastError = nil
        let needsInstall = !isHelperInstalled

        Task.detached(priority: .userInitiated) {
            let installErr: String? = needsInstall ? Self.installHelper() : nil
            // Install may have been cancelled at the auth dialog (no error,
            // file absent) — only touch pmset once the NOPASSWD entry exists.
            let installed = FileManager.default.fileExists(atPath: helperPath)
            let err: String? = installErr ?? (installed ? Self.runPmset(disableSleep: on) : nil)
            let actual = Self.readSleepDisabled()
            await MainActor.run { [weak self] in
                self?.isBusy = false
                self?.isHelperInstalled = installed
                self?.isEnabled = actual
                if let err { self?.lastError = err }
            }
        }
    }

    /// Installs the sudoers helper without touching the current sleep state —
    /// used by Settings → Permissions to set things up ahead of first use.
    func installHelperOnly() {
        guard !isBusy, !isHelperInstalled else { return }
        isBusy = true
        lastError = nil

        Task.detached(priority: .userInitiated) {
            let err = Self.installHelper()
            await MainActor.run { [weak self] in
                self?.isBusy = false
                if let err { self?.lastError = err }
                self?.refreshHelperStatus()
            }
        }
    }

    func uninstallHelper() {
        guard !isBusy else { return }
        isBusy = true
        lastError = nil

        Task.detached(priority: .userInitiated) {
            // Best-effort: restore normal sleep while we still have NOPASSWD.
            _ = Self.runPmset(disableSleep: false)
            let err = AdminShell.runScript(
                "rm -f '\(helperPath)'",
                prompt: String(localized: "Swordfish needs your password to remove the lid-closed anti-sleep helper.")
            )
            let actual = Self.readSleepDisabled()
            await MainActor.run { [weak self] in
                self?.isBusy = false
                if let err { self?.lastError = err }
                self?.isEnabled = actual
                self?.refreshHelperStatus()
            }
        }
    }

    /// Synchronous best-effort reset for app termination — quitting Swordfish
    /// must not leave the Mac permanently unable to sleep.
    func disableOnQuit() {
        guard isEnabled, isHelperInstalled else { return }
        _ = Self.runPmset(disableSleep: false)
    }

    // MARK: - Private (shell)

    nonisolated private static func installHelper() -> String? {
        let user = NSUserName()
        let script = """
        set -e
        tmp=$(mktemp /tmp/swordfish-sudoers.XXXXXX)
        cat > "$tmp" <<'SUDOERS'
        # Managed by Swordfish.app — allows lid-closed anti-sleep without password.
        \(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0
        SUDOERS
        chown root:wheel "$tmp"
        chmod 0440 "$tmp"
        /usr/sbin/visudo -cf "$tmp" >/dev/null
        mv "$tmp" '\(helperPath)'
        """
        return AdminShell.runScript(script, prompt: String(localized: "Swordfish needs your password once to control lid-closed sleep without further prompts."))
    }

    nonisolated private static func runPmset(disableSleep on: Bool) -> String? {
        let r: ProcessRunner.Result
        do {
            r = try ProcessRunner.run("/usr/bin/sudo", arguments: [
                "-n", "/usr/bin/pmset", "-a", "disablesleep", on ? "1" : "0"
            ])
        } catch {
            return error.localizedDescription
        }
        if r.exitCode == 0 { return nil }
        let msg = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return msg.isEmpty ? "exit \(r.exitCode)" : msg
    }

    nonisolated private static func readSleepDisabled() -> Bool {
        guard let r = try? ProcessRunner.run("/usr/bin/pmset", arguments: ["-g"]) else { return false }
        for line in r.stdout.split(separator: "\n") where line.contains("SleepDisabled") {
            return line.trimmingCharacters(in: .whitespaces).hasSuffix("1")
        }
        return false
    }
}
