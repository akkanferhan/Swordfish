import Foundation
import Darwin

struct RunningProcess: Identifiable, Equatable {
    let pid: Int32
    let name: String
    let cpu: Double        // %, ps' decaying average (can exceed 100 on multi-core)
    let memoryBytes: UInt64
    let isOwn: Bool        // owned by the current user → killable without root

    var id: Int32 { pid }

    /// Processes developers usually go hunting for when the Mac bogs down.
    var isDevTool: Bool {
        let devNames = ["Xcode", "SourceKitService", "swift-frontend", "swift-build", "xcodebuild",
                        "clang", "ld", "ibtoold", "Simulator", "launchd_sim", "XCBBuildService",
                        "com.apple.CoreSimulator.CoreSimulatorService", "node", "java", "gradle",
                        "docker", "com.docker.backend", "qemu-system-aarch64", "ruby", "python3"]
        return devNames.contains(name)
    }
}

struct ListeningPort: Identifiable, Equatable {
    let port: Int
    let address: String     // "*", "127.0.0.1", "[::1]" …
    let pid: Int32
    let process: String

    var id: String { "\(pid)-\(port)" }
    var isLoopbackOnly: Bool { address.hasPrefix("127.") || address == "[::1]" || address == "localhost" }
}

/// `ps` / `lsof` / `kill` helpers. Everything blocks — call from a detached task.
enum ProcessTools {
    struct ToolError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// All processes, newest `ps` snapshot. `comm` is the last column and may
    /// contain spaces, so only the first four columns are split off.
    static func processes() -> [RunningProcess] {
        guard let r = try? ProcessRunner.run("/bin/ps", arguments: ["-Aww", "-o", "pid=,pcpu=,rss=,uid=,comm="]) else { return [] }
        let myUID = getuid()
        var result: [RunningProcess] = []
        for line in r.stdout.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard parts.count == 5,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1].replacingOccurrences(of: ",", with: ".")),
                  let rssKiB = UInt64(parts[2]),
                  let uid = UInt32(parts[3]) else { continue }
            let name = (String(parts[4]) as NSString).lastPathComponent
            result.append(RunningProcess(pid: pid, name: name, cpu: cpu,
                                         memoryBytes: rssKiB * 1024, isOwn: uid == myUID))
        }
        return result
    }

    /// TCP sockets in LISTEN state. Without root `lsof` only sees the current
    /// user's processes — which is exactly the set we can kill anyway.
    /// `-F pcn` prints one field per line: p<pid>, c<command>, n<address:port>.
    static func listeningPorts() -> [ListeningPort] {
        guard let r = try? ProcessRunner.run("/usr/sbin/lsof", arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"]) else { return [] }
        var result: [ListeningPort] = []
        var seen = Set<String>()
        var pid: Int32 = 0
        var command = ""
        for line in r.stdout.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": pid = Int32(value) ?? 0
            case "c": command = value
            case "n":
                // "*:8080", "127.0.0.1:3000", "[::1]:5432"
                guard let colon = value.lastIndex(of: ":"), let port = Int(value[value.index(after: colon)...]) else { continue }
                let address = String(value[..<colon])
                // IPv4 + IPv6 listeners of the same process/port collapse into one row.
                guard seen.insert("\(pid)-\(port)").inserted else { continue }
                result.append(ListeningPort(port: port, address: address, pid: pid, process: command))
            default: continue
            }
        }
        return result.sorted { $0.port < $1.port }
    }

    static func kill(pid: Int32, force: Bool) throws {
        guard Darwin.kill(pid, force ? SIGKILL : SIGTERM) == 0 else {
            throw ToolError(message: String(cString: strerror(errno)))
        }
    }

    /// Kills processes by exact name; launchd / Xcode respawn them on demand.
    /// Returns false when nothing was running under that name.
    @discardableResult
    static func killAll(_ name: String) throws -> Bool {
        let r = try ProcessRunner.run("/usr/bin/killall", arguments: ["-9", name])
        if r.exitCode == 0 { return true }
        if r.stderr.contains("No matching processes") { return false }
        throw ToolError(message: r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Polls `ps` and `lsof` while the Processes section is on screen.
@MainActor
final class ProcessMonitorService: ObservableObject {
    enum Sort { case cpu, memory }

    @Published private(set) var processes: [RunningProcess] = []
    @Published private(set) var ports: [ListeningPort] = []
    @Published var status: ToolboxStatus?

    private var isRefreshing = false

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task.detached(priority: .utility) {
            let procs = ProcessTools.processes()
            let ports = ProcessTools.listeningPorts()
            await MainActor.run { [weak self] in
                self?.processes = procs
                self?.ports = ports
                self?.isRefreshing = false
            }
        }
    }

    func top(by sort: Sort, limit: Int = 8) -> [RunningProcess] {
        let sorted: [RunningProcess]
        switch sort {
        case .cpu:    sorted = processes.sorted { $0.cpu > $1.cpu }
        case .memory: sorted = processes.sorted { $0.memoryBytes > $1.memoryBytes }
        }
        return Array(sorted.prefix(limit))
    }

    /// Dev processes that are currently heavy (≥ 5 % CPU or ≥ 500 MB).
    var heavyDevTools: [RunningProcess] {
        processes
            .filter { $0.isDevTool && ($0.cpu >= 5 || $0.memoryBytes >= 500 * 1024 * 1024) }
            .sorted { $0.memoryBytes > $1.memoryBytes }
    }

    func kill(pid: Int32, name: String, force: Bool) {
        status = nil
        do {
            try ProcessTools.kill(pid: pid, force: force)
            status = .ok(force ? String(localized: "Force-killed \(name)") : String(localized: "Sent quit signal to \(name)"), nil)
        } catch {
            status = .error("\(name): \(error.localizedDescription)")
        }
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            refresh()
        }
    }

    func restart(_ processName: String, label: String) {
        status = nil
        Task.detached(priority: .userInitiated) {
            let outcome: ToolboxStatus
            do {
                let killed = try ProcessTools.killAll(processName)
                outcome = killed
                    ? .ok(String(localized: "\(label) restarted — it relaunches on next use"), nil)
                    : .ok(String(localized: "\(label) wasn't running"), nil)
            } catch {
                outcome = .error(error.localizedDescription)
            }
            await MainActor.run { [weak self] in
                self?.status = outcome
                self?.refresh()
            }
        }
    }
}
