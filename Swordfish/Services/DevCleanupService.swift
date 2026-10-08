import Foundation

/// One deletable chunk of developer disk usage (a DerivedData project, a
/// DeviceSupport version, a cache folder).
struct CleanupItem: Identifiable, Equatable {
    enum Group: Int, CaseIterable, Identifiable {
        case derivedData, runtimes, deviceSupport, archives, caches
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .derivedData:   return String(localized: "DerivedData")
            case .runtimes:      return String(localized: "Simulator Runtimes")
            case .deviceSupport: return String(localized: "Device Support")
            case .archives:      return String(localized: "Archives")
            case .caches:        return String(localized: "Caches")
            }
        }
    }

    let url: URL
    let group: Group
    let title: String
    let detail: String?
    var bytes: Int64?
    /// Set for simulator runtimes, which must be removed through
    /// `simctl runtime delete` (they're mounted disk images), not the file system.
    var runtimeID: String? = nil

    var id: String { url.path }
}

/// Scans the usual places Xcode leaves gigabytes behind and deletes the
/// pieces the user picks. Sizes come from `du -sk` (one call for all paths),
/// which is far faster than enumerating with FileManager.
@MainActor
final class DevCleanupService: ObservableObject {
    @Published private(set) var items: [CleanupItem] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isDeleting = false
    @Published var lastMessage: String?
    @Published var lastError: String?

    nonisolated private static let home = URL(fileURLWithPath: NSHomeDirectory())
    nonisolated private static let developer = home.appendingPathComponent("Library/Developer")

    var totalBytes: Int64 { items.compactMap(\.bytes).reduce(0, +) }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        Task.detached(priority: .userInitiated) {
            var found = Self.discover()
            // Runtimes report their own size; `du` on the cryptex store is slow and partly unreadable.
            let sizes = Self.sizes(of: found.filter { $0.runtimeID == nil }.map(\.url))
            for i in found.indices where found[i].runtimeID == nil {
                found[i].bytes = sizes[found[i].url.path]
            }
            found += Self.discoverRuntimes()
            // Biggest first inside each group — that's what people come for.
            found.sort {
                if $0.group != $1.group { return $0.group.rawValue < $1.group.rawValue }
                return ($0.bytes ?? 0) > ($1.bytes ?? 0)
            }
            let scanned = found
            await MainActor.run { [weak self] in
                self?.items = scanned
                self?.isScanning = false
            }
        }
    }

    func delete(_ ids: Set<String>) {
        guard !isDeleting, !ids.isEmpty else { return }
        let targets = items.filter { ids.contains($0.id) }
        let freed = targets.compactMap(\.bytes).reduce(0, +)
        isDeleting = true
        lastMessage = nil
        lastError = nil
        Task.detached(priority: .userInitiated) {
            var failures: [String] = []
            for item in targets {
                do {
                    if let runtimeID = item.runtimeID {
                        try SimulatorToolbox.simctl(["runtime", "delete", runtimeID])
                    } else {
                        try FileManager.default.removeItem(at: item.url)
                    }
                } catch {
                    failures.append("\(item.title): \(error.localizedDescription)")
                }
            }
            let errors = failures
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isDeleting = false
                if errors.isEmpty {
                    self.lastMessage = String(localized: "Freed \(Self.format(freed))")
                } else {
                    self.lastError = errors.joined(separator: "\n")
                }
                self.scan()
            }
        }
    }

    /// `simctl delete unavailable` removes simulators whose runtime is no
    /// longer installed — they can't boot anyway but keep their data around.
    func deleteUnavailableSimulators() {
        guard !isDeleting else { return }
        isDeleting = true
        lastMessage = nil
        lastError = nil
        Task.detached(priority: .userInitiated) {
            let outcome = Result { try SimulatorToolbox.simctl(["delete", "unavailable"]) }
            await MainActor.run { [weak self] in
                self?.isDeleting = false
                switch outcome {
                case .success: self?.lastMessage = String(localized: "Unavailable simulators deleted")
                case .failure(let error): self?.lastError = error.localizedDescription
                }
            }
        }
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Discovery

    nonisolated private static func discover() -> [CleanupItem] {
        var result: [CleanupItem] = []
        let xcode = developer.appendingPathComponent("Xcode")

        // DerivedData — one item per project folder ("MyApp-abcdefgh…").
        let derived = xcode.appendingPathComponent("DerivedData")
        for dir in subdirectories(of: derived) {
            let name = dir.lastPathComponent
            if name == "ModuleCache.noindex" {
                result.append(CleanupItem(url: dir, group: .derivedData,
                                          title: String(localized: "Module cache"),
                                          detail: name, bytes: nil))
                continue
            }
            let project = name.range(of: "-", options: .backwards).map { String(name[..<$0.lowerBound]) } ?? name
            let workspace = (NSDictionary(contentsOf: dir.appendingPathComponent("info.plist"))?["WorkspacePath"] as? String)
                .map { ($0 as NSString).abbreviatingWithTildeInPath }
            result.append(CleanupItem(url: dir, group: .derivedData, title: project,
                                      detail: workspace, bytes: nil))
        }

        // DeviceSupport — one item per OS version, per platform.
        for platform in ["iOS", "watchOS", "tvOS", "visionOS", "macOS"] {
            let root = xcode.appendingPathComponent("\(platform) DeviceSupport")
            for dir in subdirectories(of: root) {
                result.append(CleanupItem(url: dir, group: .deviceSupport,
                                          title: dir.lastPathComponent,
                                          detail: "\(platform) DeviceSupport", bytes: nil))
            }
        }

        // Archives — one item per date folder.
        for dir in subdirectories(of: xcode.appendingPathComponent("Archives")) {
            let count = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?
                .filter { $0.hasSuffix(".xcarchive") }.count ?? 0
            result.append(CleanupItem(url: dir, group: .archives, title: dir.lastPathComponent,
                                      detail: String(localized: "\(count) archive(s)"), bytes: nil))
        }

        // Caches — whole folders that Xcode / SPM / CoreSimulator rebuild on demand.
        let caches: [(String, URL)] = [
            (String(localized: "Swift Package Manager cache"), home.appendingPathComponent("Library/Caches/org.swift.swiftpm")),
            (String(localized: "Xcode cache"), home.appendingPathComponent("Library/Caches/com.apple.dt.Xcode")),
            (String(localized: "CoreSimulator caches"), developer.appendingPathComponent("CoreSimulator/Caches")),
            (String(localized: "Xcode documentation cache"), xcode.appendingPathComponent("DocumentationCache")),
            (String(localized: "Old device logs"), xcode.appendingPathComponent("iOS Device Logs")),
        ]
        for (title, url) in caches where FileManager.default.fileExists(atPath: url.path) {
            result.append(CleanupItem(url: url, group: .caches, title: title,
                                      detail: (url.path as NSString).abbreviatingWithTildeInPath, bytes: nil))
        }
        return result
    }

    /// Installed simulator runtimes (`simctl runtime list -j`), with their
    /// size and when a simulator last used them — unused betas pile up fast.
    nonisolated private static func discoverRuntimes() -> [CleanupItem] {
        guard let r = try? ProcessRunner.run("/usr/bin/xcrun", arguments: ["simctl", "runtime", "list", "-j"]),
              r.exitCode == 0,
              let root = (try? JSONSerialization.jsonObject(with: Data(r.stdout.utf8))) as? [String: [String: Any]]
        else { return [] }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        let relative = RelativeDateTimeFormatter()

        var result: [CleanupItem] = []
        for (key, info) in root {
            guard info["deletable"] as? Bool ?? true else { continue }
            let identifier = info["identifier"] as? String ?? key
            let version = info["version"] as? String ?? "?"
            let build = info["build"] as? String ?? ""
            // "com.apple.CoreSimulator.SimRuntime.iOS-27-0" → "iOS"
            let platform = (info["runtimeIdentifier"] as? String)?
                .split(separator: ".").last?
                .split(separator: "-").first.map(String.init) ?? ""
            let lastUsed = (info["lastUsedAt"] as? String).flatMap { iso.date(from: $0) ?? isoPlain.date(from: $0) }
            let detail = lastUsed.map { String(localized: "Last used \(relative.localizedString(for: $0, relativeTo: Date()))") }
                ?? String(localized: "Never used")
            let path = info["path"] as? String ?? "/runtime/\(identifier)"
            var item = CleanupItem(url: URL(fileURLWithPath: path), group: .runtimes,
                                   title: "\(platform) \(version) (\(build))".trimmingCharacters(in: .whitespaces),
                                   detail: detail,
                                   bytes: (info["sizeBytes"] as? NSNumber)?.int64Value)
            item.runtimeID = identifier
            result.append(item)
        }
        return result
    }

    nonisolated private static func subdirectories(of url: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        return contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    /// `du -sk` prints "<KiB>\t<path>" per argument.
    nonisolated private static func sizes(of urls: [URL]) -> [String: Int64] {
        guard !urls.isEmpty,
              let r = try? ProcessRunner.run("/usr/bin/du", arguments: ["-sk"] + urls.map(\.path))
        else { return [:] }
        var map: [String: Int64] = [:]
        for line in r.stdout.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let kib = Int64(parts[0]) else { continue }
            map[String(parts[1])] = kib * 1024
        }
        return map
    }
}
