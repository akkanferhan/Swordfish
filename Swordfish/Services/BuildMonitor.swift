import Foundation
import AppKit

struct BuildRecord: Identifiable, Equatable {
    enum Status { case succeeded, warnings, failed, other }

    let id: String
    let project: String
    let scheme: String
    let title: String
    let started: Date
    let ended: Date
    let status: Status
    let errors: Int
    let warnings: Int

    var duration: TimeInterval { max(0, ended.timeIntervalSince(started)) }
    /// Groups builds of the same scheme in the same project.
    var key: String { "\(project)·\(scheme)" }

    static func formatDuration(_ t: TimeInterval) -> String {
        if t < 60 { return String(format: "%.1f s", t) }
        return String(format: "%d m %02d s", Int(t) / 60, Int(t) % 60)
    }
}

enum BuildSettings {
    static let notifyKey = "builds.notify"
    static let minSecondsKey = "builds.notifyMinSeconds"
    static let onlyBackgroundKey = "builds.notifyOnlyInBackground"

    static func register() {
        UserDefaults.standard.register(defaults: [
            notifyKey: true,
            minSecondsKey: 10,
            onlyBackgroundKey: true,
        ])
    }
}

/// Watches Xcode's per-project `Logs/Build/LogStoreManifest.plist` files in
/// DerivedData. Xcode records every build there (start/stop time, result,
/// error and warning counts), so durations come for free without parsing
/// the gzipped activity logs.
@MainActor
final class BuildMonitor: ObservableObject {
    @Published private(set) var builds: [BuildRecord] = []

    /// Called for each build that finished after the monitor started.
    var onFinished: ((BuildRecord, _ slowerThanUsual: Bool) -> Void)?

    private var timer: Timer?
    private var manifestDates: [String: Date] = [:]
    private var seenIDs = Set<String>()
    private var primed = false
    private var isScanning = false

    nonisolated private static let derivedData = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Developer/Xcode/DerivedData")

    func start() {
        BuildSettings.register()
        scan()
        let t = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Recent builds per scheme, newest scheme first.
    var schemes: [(key: String, builds: [BuildRecord])] {
        Dictionary(grouping: builds, by: \.key)
            .map { (key: $0.key, builds: $0.value.sorted { $0.ended > $1.ended }) }
            .sorted { ($0.builds.first?.ended ?? .distantPast) > ($1.builds.first?.ended ?? .distantPast) }
    }

    private func scan() {
        guard !isScanning else { return }
        isScanning = true
        let known = manifestDates
        Task.detached(priority: .utility) {
            let result = Self.readChangedManifests(known: known)
            await MainActor.run { [weak self] in
                self?.apply(result)
                self?.isScanning = false
            }
        }
    }

    private func apply(_ result: (dates: [String: Date], records: [String: [BuildRecord]])) {
        guard !result.records.isEmpty || result.dates != manifestDates else { return }
        manifestDates = result.dates

        var byID = Dictionary(uniqueKeysWithValues: builds.map { ($0.id, $0) })
        for (_, records) in result.records {
            for record in records { byID[record.id] = record }
        }
        let all = byID.values.sorted { $0.ended > $1.ended }
        builds = Array(all.prefix(400))

        let fresh = all.filter { !seenIDs.contains($0.id) }
        seenIDs.formUnion(all.map(\.id))
        guard primed else { primed = true; return }   // don't announce history on launch
        for record in fresh.reversed() {
            onFinished?(record, isSlower(record))
        }
    }

    /// 50 % slower than the median of the previous (up to) 10 builds of the
    /// same scheme with the same outcome class.
    private func isSlower(_ record: BuildRecord) -> Bool {
        let previous = builds
            .filter { $0.key == record.key && $0.id != record.id && $0.ended < record.ended && $0.status != .failed }
            .prefix(10)
            .map(\.duration)
            .sorted()
        guard previous.count >= 3, record.status != .failed else { return false }
        let median = previous[previous.count / 2]
        return record.duration > median * 1.5 && record.duration - median > 5
    }

    // MARK: - Reading manifests (off the main thread)

    nonisolated private static func readChangedManifests(known: [String: Date]) -> (dates: [String: Date], records: [String: [BuildRecord]]) {
        let fm = FileManager.default
        let projects = (try? fm.contentsOfDirectory(at: derivedData, includingPropertiesForKeys: nil)) ?? []
        var dates: [String: Date] = [:]
        var records: [String: [BuildRecord]] = [:]
        for project in projects {
            let manifest = project.appendingPathComponent("Logs/Build/LogStoreManifest.plist")
            guard let modified = (try? manifest.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            else { continue }
            dates[manifest.path] = modified
            guard known[manifest.path] != modified else { continue }
            records[manifest.path] = parse(manifest)
        }
        return (dates, records)
    }

    nonisolated private static func parse(_ manifest: URL) -> [BuildRecord] {
        guard let plist = NSDictionary(contentsOf: manifest) as? [String: Any],
              let logs = plist["logs"] as? [String: [String: Any]] else { return [] }
        return logs.compactMap { id, log -> BuildRecord? in
            guard let start = log["timeStartedRecording"] as? Double,
                  let stop = log["timeStoppedRecording"] as? Double,
                  // "Clean …" logs live here too; only builds are interesting.
                  (log["title"] as? String ?? "Build").hasPrefix("Build") else { return nil }
            let observable = log["primaryObservable"] as? [String: Any] ?? [:]
            let status: BuildRecord.Status
            switch observable["highLevelStatus"] as? String {
            case "S": status = .succeeded
            case "W": status = .warnings
            case "E": status = .failed
            default:  status = .other
            }
            let container = (log["schemeIdentifier-containerName"] as? String ?? "")
                .replacingOccurrences(of: " project", with: "")
                .replacingOccurrences(of: " workspace", with: "")
            return BuildRecord(
                id: log["uniqueIdentifier"] as? String ?? id,
                project: container.isEmpty ? manifest.deletingLastPathComponent().deletingLastPathComponent()
                    .deletingLastPathComponent().lastPathComponent : container,
                scheme: log["schemeIdentifier-schemeName"] as? String ?? "?",
                title: log["title"] as? String ?? "Build",
                // Xcode stores reference-date (2001) timestamps.
                started: Date(timeIntervalSinceReferenceDate: start),
                ended: Date(timeIntervalSinceReferenceDate: stop),
                status: status,
                errors: observable["totalNumberOfErrors"] as? Int ?? 0,
                warnings: observable["totalNumberOfWarnings"] as? Int ?? 0
            )
        }
    }
}
