import Foundation
import Combine

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var cpuTemp: Double = 0          // °C
    @Published private(set) var fanRPM: Int = 0
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var fanHistory: [Double] = []
    @Published private(set) var memory: MemoryStats = .zero
    @Published private(set) var disk: DiskStats = .zero

    let sensors: HardwareSensorService
    private var timer: Timer?
    private let historyLimit = 12
    private let pollInterval: TimeInterval = 2.0

    init(sensors: HardwareSensorService) {
        self.sensors = sensors
    }

    func start() {
        tick()
        let timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Frees memory by exerting real, bounded memory pressure
    /// (`memory_pressure -l critical`), which makes the kernel evict file
    /// cache and compress idle pages. `purge` is no help here: it needs root
    /// on modern macOS (and still exits 0 when it fails), and only drops the
    /// file cache anyway. `memory_pressure` keeps holding pressure once the
    /// level is reached, so the bounded run is intentional — terminating it
    /// releases its own allocations and leaves the reclaimed memory free.
    ///
    /// Success is measured as the growth of *free* memory, not the drop in
    /// "used": cache eviction doesn't shrink used at all, and compression
    /// mostly shuffles pages within it, so a used-based delta vastly
    /// under-reports what was reclaimed.
    @discardableResult
    func clearRAM() async -> Int64 {
        let before = MemoryStats.current().freeBytes
        await Task.detached(priority: .userInitiated) {
            _ = try? ProcessRunner.run("/usr/bin/memory_pressure",
                                       arguments: ["-l", "critical"],
                                       timeout: 10)
        }.value
        // Give the kernel a moment to settle before re-sampling.
        try? await Task.sleep(nanoseconds: 700_000_000)
        tick()
        return max(0, Int64(memory.freeBytes) - Int64(before))
    }

    private func tick() {
        let t = sensors.readCPUTemperature() ?? 0
        let f = sensors.readFanRPM() ?? 0
        cpuTemp = t
        fanRPM = f
        append(&cpuHistory, t)
        append(&fanHistory, Double(f))
        memory = MemoryStats.current()
        disk = DiskStats.current()
    }

    private func append(_ arr: inout [Double], _ v: Double) {
        arr.append(v)
        if arr.count > historyLimit { arr.removeFirst(arr.count - historyLimit) }
    }
}

extension SystemMonitor {
    enum CPUState { case ok, warn, danger }
    var cpuState: CPUState {
        switch cpuTemp {
        case ..<65: return .ok
        case ..<80: return .warn
        default:    return .danger
        }
    }
}
