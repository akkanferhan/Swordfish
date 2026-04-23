import Foundation
import AppKit

struct Simulator: Identifiable, Equatable {
    let udid: String
    let name: String
    let runtime: String
    let state: State

    enum State: String {
        case booted = "Booted"
        case shutdown = "Shutdown"
        case other = ""
    }

    var id: String { udid }
    var isBooted: Bool { state == .booted }
}

@MainActor
final class SimulatorService: ObservableObject {
    @Published private(set) var simulators: [Simulator] = []
    @Published private(set) var isLoading = false
    @Published var lastError: String?

    func refresh() {
        isLoading = true
        lastError = nil
        Task.detached(priority: .userInitiated) {
            let result = try? ProcessRunner.run("/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "--json"])
            let parsed = SimulatorService.parse(result?.stdout ?? "")
            let error: String? = (result?.exitCode ?? -1) != 0 ? (result?.stderr ?? "simctl failed") : nil
            await MainActor.run { [weak self] in
                self?.simulators = parsed
                self?.isLoading = false
                if parsed.isEmpty { self?.lastError = error }
            }
        }
    }

    func boot(_ sim: Simulator) {
        run(["simctl", "boot", sim.udid])
    }

    func shutdown(_ sim: Simulator) {
        run(["simctl", "shutdown", sim.udid])
    }

    /// Removes the simulator entirely (disappears from the list).
    /// Requires shutdown first; simctl shutdown blocks until the device is down.
    func delete(_ sim: Simulator) {
        Task.detached(priority: .userInitiated) {
            if sim.isBooted {
                _ = try? ProcessRunner.run("/usr/bin/xcrun", arguments: ["simctl", "shutdown", sim.udid])
            }
            let result = try? ProcessRunner.run("/usr/bin/xcrun", arguments: ["simctl", "delete", sim.udid])
            let errMessage: String?
            if let r = result, r.exitCode != 0 {
                let trimmed = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                errMessage = trimmed.isEmpty ? "simctl delete failed (exit \(r.exitCode))" : trimmed
            } else if result == nil {
                errMessage = "Failed to run simctl"
            } else {
                errMessage = nil
            }
            await MainActor.run { [weak self] in
                self?.lastError = errMessage
                self?.refresh()
            }
        }
    }

    func shutdownAll() {
        run(["simctl", "shutdown", "all"])
    }

    func openSimulatorApp() {
        let url = URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app")
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            // fallback: find Simulator via xcode-select
            Task.detached(priority: .userInitiated) {
                let r = try? ProcessRunner.run("/usr/bin/xcode-select", arguments: ["-p"])
                let dev = r?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let sim = URL(fileURLWithPath: dev).appendingPathComponent("Applications/Simulator.app")
                await MainActor.run { NSWorkspace.shared.open(sim) }
            }
        }
    }

    // MARK: - Helpers

    private func run(_ args: [String]) {
        Task.detached(priority: .userInitiated) {
            _ = try? ProcessRunner.run("/usr/bin/xcrun", arguments: args)
            await MainActor.run { [weak self] in self?.refresh() }
        }
    }

    nonisolated private static func parse(_ json: String) -> [Simulator] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = root["devices"] as? [String: [[String: Any]]]
        else { return [] }

        var all: [Simulator] = []
        for (runtimeKey, list) in devices {
            let runtime = shortRuntime(runtimeKey)
            for dev in list {
                if let available = dev["isAvailable"] as? Bool, !available { continue }
                guard let udid = dev["udid"] as? String,
                      let name = dev["name"] as? String else { continue }
                let raw = dev["state"] as? String ?? ""
                let state: Simulator.State = .init(rawValue: raw) ?? .other
                all.append(Simulator(udid: udid, name: name, runtime: runtime, state: state))
            }
        }
        // Booted first, then by runtime desc (newest), then by name
        return all.sorted { a, b in
            if a.isBooted != b.isBooted { return a.isBooted }
            if a.runtime != b.runtime { return a.runtime > b.runtime }
            return a.name < b.name
        }
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-18-2" → "iOS 18.2"
    nonisolated private static func shortRuntime(_ key: String) -> String {
        let last = key.split(separator: ".").last.map(String.init) ?? key
        let parts = last.split(separator: "-")
        guard parts.count >= 2 else { return last }
        let platform = String(parts[0])
        let version = parts.dropFirst().joined(separator: ".")
        return "\(platform) \(version)"
    }
}
