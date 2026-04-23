import Foundation
import IOKit

// MARK: - Public protocol

protocol HardwareSensorService: AnyObject {
    func readCPUTemperature() -> Double?
    func readFanRPM() -> Int?
}

// MARK: - Mock (debug fallback via SWORDFISH_MOCK_SENSORS=1)

final class MockHardwareSensorService: HardwareSensorService {
    private var tick: Int = 0

    func readCPUTemperature() -> Double? {
        tick += 1
        let base = 48.0
        let noise = sin(Double(tick) / 3.0) * 6 + Double.random(in: -1.5...1.5)
        return base + noise
    }

    func readFanRPM() -> Int? {
        let base = 1650.0
        let noise = sin(Double(tick) / 5.0) * 120 + Double.random(in: -60...60)
        return Int(max(0, base + noise))
    }
}

// MARK: - Real service (Apple Silicon + Intel)
//
// Temperature: IOHIDEventSystemClient matching Apple Vendor page (0xff00)
// usage 5. Filters to die/device sensors (`PMU tdie*`, `PMU tdev*` on Apple
// Silicon; `TC0*` SMC keys on Intel as fallback).
// Fan RPM: classic SMC FNum / F<i>Ac — works on Apple Silicon MacBook Pros and
// Intel Macs. Fanless MacBook Air returns nil.

final class IOKitHardwareSensorService: HardwareSensorService {
    private let smc = SMC()
    private let hid = IOHIDSensorReader()

    init() {
        _ = smc.open()
        hid.prepare()
    }

    deinit {
        smc.close()
    }

    func readCPUTemperature() -> Double? {
        if let t = hid.averageCPUTemperature() { return t }
        for key in ["TC0P", "TC0D", "TC0E", "TC0F"] {
            if let v = smc.readSP78(key: key), v > 0, v < 120 {
                return v
            }
        }
        return nil
    }

    func readFanRPM() -> Int? {
        guard let count = smc.readUInt8(key: "FNum"), count > 0 else { return nil }
        var maxRPM = 0
        for i in 0..<Int(count) {
            let key = String(format: "F%dAc", i)
            if let rpm = smc.readFPE2(key: key) {
                maxRPM = max(maxRPM, Int(rpm))
            }
        }
        return maxRPM > 0 ? maxRPM : nil
    }
}

// MARK: - IOHID event-system reader (Apple Silicon)

@_silgen_name("IOHIDEventSystemClientCreate")
private func _IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventSystemClientSetMatching")
private func _IOHIDEventSystemClientSetMatching(_ client: CFTypeRef, _ matching: CFDictionary?)

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func _IOHIDEventSystemClientCopyServices(_ client: CFTypeRef) -> Unmanaged<CFArray>?

@_silgen_name("IOHIDServiceClientCopyProperty")
private func _IOHIDServiceClientCopyProperty(_ service: CFTypeRef, _ key: CFString) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDServiceClientCopyEvent")
private func _IOHIDServiceClientCopyEvent(_ service: CFTypeRef, _ type: Int64, _ options: Int32, _ flags: Int64) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventGetFloatValue")
private func _IOHIDEventGetFloatValue(_ event: CFTypeRef, _ field: Int32) -> Double

private let kIOHIDEventTypeTemperature: Int64 = 15
private let kIOHIDEventFieldTemperatureLevel: Int32 = Int32(kIOHIDEventTypeTemperature) << 16

private final class IOHIDSensorReader {
    private var client: CFTypeRef?
    private var sensors: [(name: String, service: CFTypeRef)] = []

    func prepare() {
        guard let clientRef = _IOHIDEventSystemClientCreate(kCFAllocatorDefault) else { return }
        let client = clientRef.takeRetainedValue()
        self.client = client

        let match: [CFString: CFNumber] = [
            "PrimaryUsagePage" as CFString: 0xff00 as CFNumber,
            "PrimaryUsage" as CFString:     5      as CFNumber
        ]
        _IOHIDEventSystemClientSetMatching(client, match as CFDictionary)

        guard let arrRef = _IOHIDEventSystemClientCopyServices(client) else { return }
        let arr = arrRef.takeRetainedValue()

        let count = CFArrayGetCount(arr)
        var all: [(String, CFTypeRef)] = []
        for i in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(arr, i) else { continue }
            let service = Unmanaged<CFTypeRef>.fromOpaque(raw).takeUnretainedValue()
            let name = (_IOHIDServiceClientCopyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String) ?? ""
            all.append((name, service))
        }

        // Prefer die temperatures (actual silicon temperature).
        // `tdie` = die, `tdev` = device, `PECPU`/`PACC` = CPU cluster.
        let preferred = all.filter { e in
            let lower = e.0.lowercased()
            return lower.hasPrefix("pmu tdie")
                || lower.hasPrefix("pmu tdev")
                || lower.contains("pecpu")
                || lower.contains("pacc")
                || lower.contains("ecpu")
        }
        .filter { !$0.0.lowercased().contains("tcal") }   // tcal is a calibration reference

        sensors = preferred.isEmpty ? all : preferred.map { ($0.0, $0.1) }
    }

    func averageCPUTemperature() -> Double? {
        guard !sensors.isEmpty else { return nil }
        var sum: Double = 0
        var count: Int = 0
        for (_, service) in sensors {
            guard let eventRef = _IOHIDServiceClientCopyEvent(service, kIOHIDEventTypeTemperature, 0, 0) else { continue }
            let event = eventRef.takeRetainedValue()
            let value = _IOHIDEventGetFloatValue(event, kIOHIDEventFieldTemperatureLevel)
            if value > 10, value < 120 {
                sum += value
                count += 1
            }
        }
        return count > 0 ? sum / Double(count) : nil
    }
}

// MARK: - Low-level SMC wrapper (Intel temperatures + Apple Silicon fans)

private final class SMC {
    private var connection: io_connect_t = 0

    func open() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        return result == kIOReturnSuccess
    }

    func close() {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    func readSP78(key: String) -> Double? {
        guard let data = readKey(key), data.count >= 2 else { return nil }
        let whole = Int8(bitPattern: data[0])
        let frac = Double(data[1]) / 256.0
        return Double(whole) + frac
    }

    func readFPE2(key: String) -> Double? {
        guard let data = readKey(key), data.count >= 2 else { return nil }
        let raw = (UInt16(data[0]) << 8) | UInt16(data[1])
        return Double(raw) / 4.0
    }

    func readUInt8(key: String) -> UInt8? {
        guard let data = readKey(key), data.count >= 1 else { return nil }
        return data[0]
    }

    private func readKey(_ key: String) -> [UInt8]? {
        guard connection != 0 else { return nil }
        guard let fourCC = fourCharCode(key) else { return nil }

        var inputInfo = SMCKeyInfoInput()
        inputInfo.key = fourCC
        inputInfo.data8 = 9 // kSMCGetKeyInfo

        var outputInfo = SMCKeyInfoOutput()
        if !call(input: &inputInfo, output: &outputInfo) { return nil }
        let size = Int(outputInfo.keyInfo.dataSize)
        guard size > 0, size <= 32 else { return nil }

        var inputRead = SMCKeyInfoInput()
        inputRead.key = fourCC
        inputRead.keyInfo.dataSize = outputInfo.keyInfo.dataSize
        inputRead.keyInfo.dataType = outputInfo.keyInfo.dataType
        inputRead.data8 = 5 // kSMCReadKey

        var outputRead = SMCKeyInfoOutput()
        if !call(input: &inputRead, output: &outputRead) { return nil }

        return withUnsafeBytes(of: outputRead.bytes) { buf in
            Array(buf.prefix(size))
        }
    }

    private func call(input: inout SMCKeyInfoInput, output: inout SMCKeyInfoOutput) -> Bool {
        var outputSize = MemoryLayout<SMCKeyInfoOutput>.stride
        let result = IOConnectCallStructMethod(
            connection,
            2, // kSMCHandleYPCEvent
            &input, MemoryLayout<SMCKeyInfoInput>.stride,
            &output, &outputSize
        )
        return result == kIOReturnSuccess
    }

    private func fourCharCode(_ s: String) -> UInt32? {
        let chars = Array(s.utf8)
        guard chars.count == 4 else { return nil }
        return (UInt32(chars[0]) << 24) | (UInt32(chars[1]) << 16) | (UInt32(chars[2]) << 8) | UInt32(chars[3])
    }
}

private struct SMCKeyInfoInput {
    var key: UInt32 = 0
    var vers: SMCVersion = SMCVersion()
    var pLimitData: SMCPLimitData = SMCPLimitData()
    var keyInfo: SMCKeyInfoData = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8) =
        (0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0,
         0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0)
}

private typealias SMCKeyInfoOutput = SMCKeyInfoInput

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}
