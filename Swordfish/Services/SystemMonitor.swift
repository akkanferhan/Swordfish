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

    func clearRAM() async {
        await Task.detached(priority: .userInitiated) {
            _ = try? ProcessRunner.run("/usr/sbin/purge", arguments: [])
        }.value
        tick()
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
