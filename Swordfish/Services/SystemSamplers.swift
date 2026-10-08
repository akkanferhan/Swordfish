import Foundation
import Darwin
import IOKit
import IOKit.ps
import SystemConfiguration

// MARK: - CPU load

/// Per-core CPU utilisation from `host_processor_info` tick deltas between
/// two samples (the first sample only primes the baseline).
final class CPULoadSampler {
    private var previous: [(busy: UInt64, total: UInt64)] = []

    struct Sample {
        let total: Double      // 0…1 across all cores
        let perCore: [Double]  // 0…1 each
    }

    func sample() -> Sample? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        var current: [(busy: UInt64, total: UInt64)] = []
        for core in 0..<Int(cpuCount) {
            let base = core * Int(CPU_STATE_MAX)
            let user = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            let system = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            let nice = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            let idle = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            current.append((user + system + nice, user + system + nice + idle))
        }
        defer { previous = current }
        guard previous.count == current.count else { return nil }

        var perCore: [Double] = []
        var busySum: UInt64 = 0
        var totalSum: UInt64 = 0
        for (now, before) in zip(current, previous) {
            // Counters are 32-bit and can wrap; treat a wrap as "no data".
            let busy = now.busy >= before.busy ? now.busy - before.busy : 0
            let total = now.total >= before.total ? now.total - before.total : 0
            perCore.append(total > 0 ? Double(busy) / Double(total) : 0)
            busySum += busy
            totalSum += total
        }
        return Sample(total: totalSum > 0 ? Double(busySum) / Double(totalSum) : 0, perCore: perCore)
    }
}

// MARK: - GPU load

enum GPULoad {
    /// "Device Utilization %" from the IOAccelerator's PerformanceStatistics —
    /// the same number Activity Monitor's GPU History shows. 0…1, or nil when
    /// the driver doesn't publish it.
    static func current() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        var best: Double?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any],
                  let util = (stats["Device Utilization %"] ?? stats["GPU Activity(%)"]) as? NSNumber else { continue }
            best = max(best ?? 0, util.doubleValue / 100)
        }
        return best
    }
}

// MARK: - Network throughput

struct NetworkStats: Equatable {
    var downBytesPerSec: Double = 0
    var upBytesPerSec: Double = 0
    var interface: String?
    var localIPv4: String?
    var vpnActive = false

    static let zero = NetworkStats()
}

/// Byte counters from `getifaddrs` (AF_LINK `if_data`), turned into rates
/// between samples. Only physical-ish interfaces (en*, pdp_ip*) are summed so
/// VPN tunnels don't double-count the same traffic.
final class NetworkSampler {
    private var previous: (down: UInt64, up: UInt64, at: Date)?

    func sample() -> NetworkStats {
        var down: UInt64 = 0
        var up: UInt64 = 0
        var ipv4: [String: String] = [:]
        var tunnelsWithIPv4 = false

        var head: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&head) == 0, let first = head {
            var cursor: UnsafeMutablePointer<ifaddrs>? = first
            while let ifa = cursor {
                defer { cursor = ifa.pointee.ifa_next }
                let name = String(cString: ifa.pointee.ifa_name)
                guard let addr = ifa.pointee.ifa_addr else { continue }
                let isUp = (ifa.pointee.ifa_flags & UInt32(IFF_UP)) != 0
                switch Int32(addr.pointee.sa_family) {
                case AF_LINK where name.hasPrefix("en") || name.hasPrefix("pdp_ip"):
                    if let data = ifa.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                        down += UInt64(data.pointee.ifi_ibytes)
                        up += UInt64(data.pointee.ifi_obytes)
                    }
                case AF_INET where isUp:
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        ipv4[name] = String(cString: host)
                    }
                    // utun/ipsec/ppp carrying IPv4 = a VPN. (macOS keeps several
                    // utun interfaces for iCloud etc., but those are IPv6-only.)
                    if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") {
                        tunnelsWithIPv4 = true
                    }
                default:
                    break
                }
            }
            freeifaddrs(head)
        }

        let now = Date()
        var stats = NetworkStats()
        if let previous, now > previous.at, down >= previous.down, up >= previous.up {
            let dt = now.timeIntervalSince(previous.at)
            stats.downBytesPerSec = Double(down - previous.down) / dt
            stats.upBytesPerSec = Double(up - previous.up) / dt
        }
        previous = (down, up, now)

        let primary = Self.primaryInterface()
        stats.interface = primary
        stats.localIPv4 = primary.flatMap { ipv4[$0] } ?? ipv4.first { $0.key.hasPrefix("en") }?.value
        stats.vpnActive = tunnelsWithIPv4
        return stats
    }

    /// The interface macOS routes default traffic through (State:/Network/Global/IPv4).
    private static func primaryInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "Swordfish" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return nil }
        return global["PrimaryInterface"] as? String
    }
}

extension Double {
    /// "1.2 MB/s" style rate.
    var humanRate: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .decimal) + "/s"
    }
}

// MARK: - Battery

struct BatteryStats: Equatable {
    var percent: Int
    var isCharging: Bool
    var onAC: Bool
    /// Minutes to empty (on battery) or to full (charging); nil while macOS is still estimating.
    var minutesRemaining: Int?
    var cycleCount: Int?
    /// Current full-charge capacity vs. design capacity, 0…1.
    var health: Double?
    var temperatureC: Double?
    var adapterWatts: Int?

    /// nil on Macs without an internal battery.
    static func current() -> BatteryStats? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        guard let source = list.lazy.compactMap({
            IOPSGetPowerSourceDescription(blob, $0)?.takeUnretainedValue() as? [String: Any]
        }).first(where: { ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType }) else { return nil }

        let current = source[kIOPSCurrentCapacityKey] as? Int ?? 0
        let capacity = source[kIOPSMaxCapacityKey] as? Int ?? 100
        let charging = source[kIOPSIsChargingKey] as? Bool ?? false
        let onAC = (source[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let minutesKey = charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
        let minutes = (source[minutesKey] as? Int).flatMap { $0 > 0 ? $0 : nil }

        var stats = BatteryStats(
            percent: capacity > 0 ? Int((Double(current) / Double(capacity) * 100).rounded()) : current,
            isCharging: charging, onAC: onAC, minutesRemaining: minutes,
            cycleCount: nil, health: nil, temperatureC: nil, adapterWatts: nil
        )

        // Cycle count / health / temperature live on the AppleSmartBattery node.
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            func prop(_ key: String) -> Int? {
                (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? NSNumber)?.intValue
            }
            stats.cycleCount = prop("CycleCount")
            // Apple Silicon reports MaxCapacity as a percentage; the raw mAh is AppleRawMaxCapacity.
            if let design = prop("DesignCapacity"), design > 0,
               let full = prop("AppleRawMaxCapacity") ?? prop("MaxCapacity"), full > 100 {
                stats.health = min(1, Double(full) / Double(design))
            }
            if let t = prop("Temperature") { stats.temperatureC = Double(t) / 100 }
        }
        if let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
            stats.adapterWatts = adapter[kIOPSPowerAdapterWattsKey] as? Int
        }
        return stats
    }
}

// MARK: - Bluetooth peripheral batteries

struct PeripheralBattery: Identifiable, Equatable {
    let name: String
    /// ("", 80) for single-battery devices, ("L", 90) / ("R", 85) / ("Case", 40) for AirPods.
    let levels: [Level]

    struct Level: Equatable {
        let label: String
        let percent: Int
    }

    var id: String { name }
}

enum PeripheralBatteries {
    /// Connected Bluetooth devices that report a battery level (AirPods,
    /// Magic Keyboard / Mouse / Trackpad, Beats…). `system_profiler` is the
    /// only public source for AirPods, so this is slow-ish (~0.2 s) and polled rarely.
    static func current() -> [PeripheralBattery] {
        guard let r = try? ProcessRunner.run("/usr/sbin/system_profiler", arguments: ["SPBluetoothDataType", "-json"]),
              let root = (try? JSONSerialization.jsonObject(with: Data(r.stdout.utf8))) as? [String: Any],
              let controller = (root["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = controller["device_connected"] as? [[String: Any]] else { return [] }

        let order: [(key: String, label: String)] = [
            ("device_batteryLevelMain", ""),
            ("device_batteryLevel", ""),
            ("device_batteryLevelLeft", "L"),
            ("device_batteryLevelRight", "R"),
            ("device_batteryLevelCase", String(localized: "Case")),
        ]
        var result: [PeripheralBattery] = []
        for entry in connected {
            for (name, value) in entry {
                guard let info = value as? [String: Any] else { continue }
                let levels = order.compactMap { item -> PeripheralBattery.Level? in
                    guard let raw = info[item.key] as? String,
                          let pct = Int(raw.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) else { return nil }
                    return PeripheralBattery.Level(label: item.label, percent: pct)
                }
                if !levels.isEmpty { result.append(PeripheralBattery(name: name, levels: levels)) }
            }
        }
        return result.sorted { $0.name < $1.name }
    }
}
