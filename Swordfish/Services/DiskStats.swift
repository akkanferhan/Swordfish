import Foundation

struct DiskStats: Equatable {
    var totalBytes: UInt64
    var freeBytes: UInt64
    var volumeName: String

    static let zero = DiskStats(totalBytes: 0, freeBytes: 0, volumeName: "—")

    var usedBytes: UInt64 { totalBytes > freeBytes ? totalBytes - freeBytes : 0 }

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    static func current() -> DiskStats {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeNameKey
        ]) else {
            return .zero
        }
        let total = UInt64(values.volumeTotalCapacity ?? 0)
        let availInt64: Int64 = values.volumeAvailableCapacityForImportantUsage
            ?? Int64(values.volumeAvailableCapacity ?? 0)
        let free = UInt64(max(0, availInt64))
        return DiskStats(
            totalBytes: total,
            freeBytes: free,
            volumeName: values.volumeName ?? "Macintosh HD"
        )
    }
}
