import Foundation
import Darwin

struct MemoryStats: Equatable {
    var totalBytes: UInt64
    var usedBytes: UInt64
    var appBytes: UInt64
    var wiredBytes: UInt64
    var cacheBytes: UInt64

    static let zero = MemoryStats(totalBytes: 0, usedBytes: 0, appBytes: 0, wiredBytes: 0, cacheBytes: 0)

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    static func current() -> MemoryStats {
        let total = ProcessInfo.processInfo.physicalMemory

        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, raw, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return MemoryStats(totalBytes: total, usedBytes: 0, appBytes: 0, wiredBytes: 0, cacheBytes: 0)
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let app    = UInt64(info.internal_page_count) * pageSize
        let wired  = UInt64(info.wire_count) * pageSize
        let compressed = UInt64(info.compressor_page_count) * pageSize
        let cache  = UInt64(info.external_page_count) * pageSize
        let used   = app + wired + compressed

        return MemoryStats(
            totalBytes: total,
            usedBytes: used,
            appBytes: app,
            wiredBytes: wired,
            cacheBytes: cache
        )
    }
}

extension UInt64 {
    var humanBytes: String {
        let fmt = ByteCountFormatter()
        fmt.allowedUnits = [.useGB, .useMB]
        fmt.countStyle = .memory
        return fmt.string(fromByteCount: Int64(self))
    }
}
