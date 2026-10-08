import Foundation

struct XcodeInstall: Identifiable, Equatable {
    let url: URL
    let version: String
    let build: String?

    var id: String { url.path }
    var name: String { url.deletingPathExtension().lastPathComponent }
    var label: String {
        build.map { "\(name) — \(version) (\($0))" } ?? "\(name) — \(version)"
    }
}

/// Finds every Xcode in /Applications (and ~/Applications) and switches the
/// active developer directory via `xcode-select -s` behind the admin prompt.
@MainActor
final class XcodeVersionsService: ObservableObject {
    @Published private(set) var installs: [XcodeInstall] = []
    @Published private(set) var activePath: String?
    @Published private(set) var isSwitching = false
    @Published var lastError: String?

    var active: XcodeInstall? {
        guard let activePath else { return nil }
        return installs.first { activePath.hasPrefix($0.url.path + "/") }
    }

    func refresh() {
        Task.detached(priority: .userInitiated) {
            let found = Self.discover()
            let dir = (try? ProcessRunner.run("/usr/bin/xcode-select", arguments: ["-p"]))?
                .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run { [weak self] in
                self?.installs = found
                self?.activePath = (dir?.isEmpty ?? true) ? nil : dir
            }
        }
    }

    func select(_ install: XcodeInstall) {
        guard !isSwitching, install != active else { return }
        isSwitching = true
        lastError = nil
        let path = install.url.path.replacingOccurrences(of: "'", with: "'\\''")
        Task.detached(priority: .userInitiated) {
            let err = AdminShell.runScript(
                "/usr/bin/xcode-select -s '\(path)'",
                prompt: String(localized: "Swordfish needs your password to switch the active Xcode.")
            )
            await MainActor.run { [weak self] in
                self?.isSwitching = false
                self?.lastError = err
                self?.refresh()
            }
        }
    }

    nonisolated private static func discover() -> [XcodeInstall] {
        let fm = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications"),
        ]
        var result: [XcodeInstall] = []
        for root in roots {
            let apps = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for app in apps where app.pathExtension == "app" {
                let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
                guard (info?["CFBundleIdentifier"] as? String) == "com.apple.dt.Xcode" else { continue }
                let version = info?["CFBundleShortVersionString"] as? String ?? "?"
                let build = NSDictionary(contentsOf: app.appendingPathComponent("Contents/version.plist"))?["ProductBuildVersion"] as? String
                result.append(XcodeInstall(url: app, version: version, build: build))
            }
        }
        return result.sorted {
            $0.version.compare($1.version, options: .numeric) == .orderedDescending
        }
    }
}
