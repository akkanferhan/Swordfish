import Foundation
import AppKit

private let helperPath  = "/etc/sudoers.d/swordfish-throttle"
private let pfRulesPath = "/tmp/swordfish-throttle.pf"
private let presetKey   = "NetworkThrottle.activePreset"

enum ThrottlePreset: String, CaseIterable, Identifiable {
    case off, edge, threeG, dsl, lte, loss5, loss100

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off:     return "Off"
        case .edge:    return "Edge"
        case .threeG:  return "3G"
        case .dsl:     return "DSL"
        case .lte:     return "LTE"
        case .loss5:   return "5% Loss"
        case .loss100: return "100% Loss"
        }
    }

    var symbol: String {
        switch self {
        case .off:     return "antenna.radiowaves.left.and.right"
        case .edge:    return "tortoise"
        case .threeG:  return "wifi.exclamationmark"
        case .dsl:     return "network"
        case .lte:     return "wifi"
        case .loss5:   return "exclamationmark.triangle"
        case .loss100: return "wifi.slash"
        }
    }

    /// Short human-readable line describing the throttle (shown under the tile label).
    var subtitle: String {
        switch self {
        case .off:     return "No limit"
        case .edge:    return "240 / 200 Kbps · 400 ms"
        case .threeG:  return "3 / 1 Mbps · 100 ms"
        case .dsl:     return "2 Mbps / 256 Kbps · 5 ms"
        case .lte:     return "50 / 10 Mbps · 50 ms"
        case .loss5:   return "5% packet loss"
        case .loss100: return "100% packet loss"
        }
    }

    /// Speeds in kilobits per second; 0 = unlimited.
    /// Loss is 0…1 (probability of drop).
    /// Delay is one-way milliseconds.
    struct Config {
        let downKbps: Int
        let upKbps: Int
        let delayMs: Int
        let lossPct: Double
    }

    var config: Config {
        switch self {
        case .off:     return Config(downKbps: 0,      upKbps: 0,     delayMs: 0,   lossPct: 0)
        case .edge:    return Config(downKbps: 240,    upKbps: 200,   delayMs: 400, lossPct: 0)
        case .threeG:  return Config(downKbps: 3_000,  upKbps: 1_000, delayMs: 100, lossPct: 0)
        case .dsl:     return Config(downKbps: 2_000,  upKbps: 256,   delayMs: 5,   lossPct: 0)
        case .lte:     return Config(downKbps: 50_000, upKbps: 10_000, delayMs: 50, lossPct: 0)
        case .loss5:   return Config(downKbps: 0,      upKbps: 0,     delayMs: 0,   lossPct: 0.05)
        case .loss100: return Config(downKbps: 0,      upKbps: 0,     delayMs: 0,   lossPct: 1.0)
        }
    }
}

/// Network throttling on the default route interface using macOS dummynet (`dnctl`)
/// and the packet filter (`pfctl`).
///
/// First use prompts for the admin password once and writes a sudoers entry to
/// `/etc/sudoers.d/swordfish-throttle`. Subsequent toggles run silently via
/// `sudo -n`. Uninstalling removes both the throttling and the sudoers entry.
@MainActor
final class NetworkThrottleService: ObservableObject {
    @Published private(set) var isHelperInstalled: Bool = false
    @Published private(set) var activePreset: ThrottlePreset = .off
    @Published private(set) var activeInterface: String?
    @Published private(set) var isBusy: Bool = false
    @Published var lastError: String?

    init() {
        refreshHelperStatus()
        if let raw = UserDefaults.standard.string(forKey: presetKey),
           let preset = ThrottlePreset(rawValue: raw) {
            activePreset = preset
        }
        refreshInterface()
    }

    // MARK: - Public actions

    func refreshHelperStatus() {
        isHelperInstalled = FileManager.default.fileExists(atPath: helperPath)
    }

    func refreshInterface() {
        Task.detached(priority: .background) {
            let name = Self.currentInterface()
            await MainActor.run { [weak self] in
                self?.activeInterface = name
            }
        }
    }

    func installHelper() {
        guard !isBusy else { return }
        isBusy = true
        lastError = nil

        let user = NSUserName()
        let script = """
        set -e
        tmp=$(mktemp /tmp/swordfish-sudoers.XXXXXX)
        cat > "$tmp" <<'SUDOERS'
        # Managed by Swordfish.app — allows network throttling without password.
        \(user) ALL=(root) NOPASSWD: /usr/sbin/dnctl, /sbin/pfctl
        SUDOERS
        chown root:wheel "$tmp"
        chmod 0440 "$tmp"
        /usr/sbin/visudo -cf "$tmp" >/dev/null
        mv "$tmp" '\(helperPath)'
        """

        Task.detached(priority: .userInitiated) {
            let err = Self.runAdminScript(script, prompt: "Swordfish needs your password once to enable network throttling without further prompts.")
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
            // Best-effort: drop any active throttling first while we still have NOPASSWD.
            _ = await Self.applyOff()

            let script = """
            rm -f '\(helperPath)'
            rm -f '\(pfRulesPath)'
            """
            let err = Self.runAdminScript(script, prompt: "Swordfish needs your password to remove the network throttling helper.")
            await MainActor.run { [weak self] in
                self?.isBusy = false
                if let err { self?.lastError = err }
                UserDefaults.standard.removeObject(forKey: presetKey)
                self?.activePreset = .off
                self?.refreshHelperStatus()
            }
        }
    }

    func apply(_ preset: ThrottlePreset) {
        guard !isBusy else { return }
        guard isHelperInstalled else {
            lastError = "Helper not installed. Click Enable Throttling first."
            return
        }
        isBusy = true
        lastError = nil

        Task.detached(priority: .userInitiated) {
            let err: String?
            if preset == .off {
                err = await Self.applyOff()
            } else {
                err = await Self.applyOn(preset)
            }
            await MainActor.run { [weak self] in
                self?.isBusy = false
                if let err {
                    self?.lastError = err
                } else {
                    self?.activePreset = preset
                    UserDefaults.standard.set(preset.rawValue, forKey: presetKey)
                    self?.refreshInterface()
                }
            }
        }
    }

    // MARK: - Private (shell)

    nonisolated private static func applyOn(_ preset: ThrottlePreset) async -> String? {
        guard let iface = currentInterface(), !iface.isEmpty else {
            return "No active network interface (not connected?)"
        }
        let cfg = preset.config

        // Configure inbound (pipe 1) and outbound (pipe 2) dummynet pipes.
        if let err = runSudo(["/usr/sbin/dnctl"] + pipeArgs(pipe: 1, cfg: cfg, isInbound: true)) {
            return "dnctl pipe 1: \(err)"
        }
        if let err = runSudo(["/usr/sbin/dnctl"] + pipeArgs(pipe: 2, cfg: cfg, isInbound: false)) {
            return "dnctl pipe 2: \(err)"
        }

        // Bind pipes to the interface via a pf ruleset. Trailing newline is
        // mandatory — pfctl throws a syntax error without it.
        let rules = "dummynet in on \(iface) all pipe 1\ndummynet out on \(iface) all pipe 2\n"
        do {
            try rules.write(toFile: pfRulesPath, atomically: true, encoding: .utf8)
        } catch {
            return "Could not write pf rules: \(error.localizedDescription)"
        }
        if let err = runSudo(["/sbin/pfctl", "-f", pfRulesPath, "-E"]) {
            return "pfctl: \(err)"
        }
        return nil
    }

    nonisolated private static func applyOff() async -> String? {
        // pfctl -d disables pf entirely; dnctl flush clears our pipes.
        // Both best-effort: pf may already be off, pipes may not exist.
        _ = runSudo(["/sbin/pfctl", "-d"], allowFailure: true)
        if let err = runSudo(["/usr/sbin/dnctl", "-q", "flush"], allowFailure: true) {
            return "dnctl flush: \(err)"
        }
        return nil
    }

    /// Runs `sudo -n <args>`. Returns nil on success, error message otherwise.
    /// `allowFailure` swallows non-zero exits and only returns errors when the
    /// command could not run at all.
    @discardableResult
    nonisolated private static func runSudo(_ args: [String], allowFailure: Bool = false) -> String? {
        let r: ProcessRunner.Result
        do {
            r = try ProcessRunner.run("/usr/bin/sudo", arguments: ["-n"] + args)
        } catch {
            return error.localizedDescription
        }
        if r.exitCode == 0 { return nil }
        let msg = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        // pfctl prints success info to stderr ("Token : 12345", "pf enabled"); not an error.
        if msg.contains("Token :") || msg.contains("pf enabled") {
            return nil
        }
        if allowFailure { return nil }
        return msg.isEmpty ? "exit \(r.exitCode)" : msg
    }

    nonisolated private static func pipeArgs(pipe: Int, cfg: ThrottlePreset.Config, isInbound: Bool) -> [String] {
        let bw = isInbound ? cfg.downKbps : cfg.upKbps
        var out = ["pipe", String(pipe), "config"]
        if bw > 0 {
            out.append(contentsOf: ["bw", "\(bw)Kbit/s"])
        }
        if cfg.delayMs > 0 {
            out.append(contentsOf: ["delay", String(cfg.delayMs)])
        }
        if cfg.lossPct > 0 {
            out.append(contentsOf: ["plr", String(format: "%.4f", cfg.lossPct)])
        }
        return out
    }

    nonisolated private static func currentInterface() -> String? {
        guard let r = try? ProcessRunner.run("/sbin/route", arguments: ["-n", "get", "default"]) else {
            return nil
        }
        for line in r.stdout.split(separator: "\n") {
            if line.contains("interface:") {
                return line.split(separator: ":").last
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
            }
        }
        return nil
    }

    /// Runs an arbitrary shell script as root via osascript's authentication
    /// dialog. Returns nil on success, error message otherwise.
    nonisolated private static func runAdminScript(_ script: String, prompt: String) -> String? {
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
