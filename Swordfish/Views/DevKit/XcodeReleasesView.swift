import SwiftUI
import AppKit

struct XcodeRelease: Identifiable {
    let number: String        // "27.2"
    let build: String         // "27B5028f"
    let stage: String         // "", "Beta 2", "RC 1"
    let date: Date?
    let requiresMacOS: String?
    let notesURL: URL?
    let downloadURL: URL?

    var id: String { build }
    var title: String { stage.isEmpty ? "Xcode \(number)" : "Xcode \(number) \(stage)" }
    /// The name `xcodes install` understands ("27.2 Beta 2").
    var xcodesName: String { stage.isEmpty ? number : "\(number) \(stage)" }
}

/// Xcode release list from xcodereleases.com (a community-maintained feed of
/// Apple's releases, with build numbers and download links).
enum XcodeReleaseFeed {
    static func fetch(limit: Int = 10) async throws -> [XcodeRelease] {
        let url = URL(string: "https://xcodereleases.com/data.json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return list.prefix(limit).compactMap { entry -> XcodeRelease? in
            guard (entry["name"] as? String) == "Xcode",
                  let version = entry["version"] as? [String: Any],
                  let number = version["number"] as? String else { return nil }
            let release = version["release"] as? [String: Any] ?? [:]
            let stage: String
            if let beta = release["beta"] as? Int { stage = "Beta \(beta)" }
            else if let rc = release["rc"] as? Int { stage = "RC \(rc)" }
            else if release["gm"] != nil || release["gmSeed"] != nil { stage = "GM" }
            else { stage = "" }
            let d = entry["date"] as? [String: Int] ?? [:]
            let date = DateComponents(calendar: .current, year: d["year"], month: d["month"], day: d["day"]).date
            let links = entry["links"] as? [String: Any] ?? [:]
            return XcodeRelease(
                number: number,
                build: version["build"] as? String ?? "",
                stage: stage,
                date: date,
                requiresMacOS: entry["requires"] as? String,
                notesURL: ((links["notes"] as? [String: Any])?["url"] as? String).flatMap(URL.init(string:)),
                downloadURL: ((links["download"] as? [String: Any])?["url"] as? String).flatMap(URL.init(string:))
            )
        }
    }
}

/// Latest Xcode releases (installed ones marked) and simulator-runtime
/// downloads via `xcodebuild -downloadPlatform`.
struct XcodeReleasesView: View {
    @StateObject private var xcodes = XcodeVersionsService()
    @StateObject private var download = RuntimeDownload()
    @State private var releases: [XcodeRelease] = []
    @State private var error: String?
    @State private var platform = "iOS"
    private let xcodesCLI = ["/opt/homebrew/bin/xcodes", "/usr/local/bin/xcodes"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let error {
                Text(error)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.Semantic.danger)
            } else if releases.isEmpty {
                Text("Loading releases…")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
            }
            VStack(spacing: 3) {
                ForEach(releases) { release in
                    releaseRow(release)
                }
            }
            if xcodesCLI == nil {
                HStack(spacing: 6) {
                    Text("Install from here with the xcodes CLI:")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                    Text(verbatim: "brew install xcodesorg/made/xcodes")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.secondary)
                        .textSelection(.enabled)
                    CopyButton(text: "brew install xcodesorg/made/xcodes")
                }
            }

            SoftDivider()

            HStack(spacing: Spacing.sm) {
                Text("Simulator runtime")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                Picker("", selection: $platform) {
                    ForEach(["iOS", "watchOS", "tvOS", "visionOS"], id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 110)
                .disabled(download.isRunning)
                Spacer()
                if download.isRunning {
                    PillButton(title: "Cancel", symbol: "xmark") { download.cancel() }
                } else {
                    AccentActionButton(title: "Download", symbol: "icloud.and.arrow.down") {
                        download.start(platform: platform)
                    }
                }
            }
            if let line = download.lastLine {
                Text(line)
                    .font(Typography.monoSmall)
                    .foregroundStyle(download.failed ? Theme.Semantic.danger : Theme.TextColor.secondary)
                    .lineLimit(2)
            }
        }
        .task {
            xcodes.refresh()
            do { releases = try await XcodeReleaseFeed.fetch() }
            catch { self.error = error.localizedDescription }
        }
    }

    private func releaseRow(_ release: XcodeRelease) -> some View {
        let installed = xcodes.installs.contains { $0.build == release.build }
        return HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(release.title)
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Theme.TextColor.primary)
                    if installed { Badge(label: String(localized: "Installed"), tint: Theme.Semantic.ok) }
                }
                Text(verbatim: [release.build,
                                release.date?.formatted(date: .abbreviated, time: .omitted),
                                release.requiresMacOS.map { "macOS \($0)+" }]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
            }
            Spacer()
            if let notes = release.notesURL {
                ToolboxIconButton(symbol: "doc.text", help: "Release notes") { NSWorkspace.shared.open(notes) }
            }
            if !installed {
                if xcodesCLI != nil {
                    ToolboxIconButton(symbol: "terminal", help: "Install with xcodes (opens Terminal)") {
                        installWithXcodes(release)
                    }
                }
                if let download = release.downloadURL {
                    ToolboxIconButton(symbol: "arrow.down.circle", help: "Download .xip (developer account sign-in)") {
                        NSWorkspace.shared.open(download)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(Theme.Surface.surface1)
        )
    }

    /// xcodes asks for an Apple ID interactively, so it runs in Terminal via
    /// a throwaway .command file (no Automation permission needed).
    private func installWithXcodes(_ release: XcodeRelease) {
        guard let cli = xcodesCLI else { return }
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("swordfish-xcodes-install.command")
        let name = release.xcodesName.replacingOccurrences(of: "'", with: "")
        let content = "#!/bin/zsh\n'\(cli)' install '\(name)' --experimental-unxip\n"
        do {
            try content.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            NSWorkspace.shared.open(script)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Runs `xcodebuild -downloadPlatform <platform>` and surfaces its progress.
@MainActor
final class RuntimeDownload: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var lastLine: String?
    @Published private(set) var failed = false
    private var process: StreamingProcess?

    func start(platform: String) {
        guard !isRunning else { return }
        failed = false
        lastLine = String(localized: "Starting \(platform) runtime download…")
        let proc = StreamingProcess("/usr/bin/xcrun", arguments: ["xcodebuild", "-downloadPlatform", platform])
        do {
            try proc.start(
                onLines: { [weak self] lines in
                    if let last = lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                        self?.lastLine = last.trimmingCharacters(in: .whitespaces)
                    }
                },
                onExit: { [weak self] status in
                    guard let self else { return }
                    self.isRunning = false
                    self.process = nil
                    if status == 0 {
                        self.lastLine = String(localized: "\(platform) runtime installed")
                    } else if status != 15 && status != 143 {
                        self.failed = true
                    } else {
                        self.lastLine = String(localized: "Download cancelled")
                    }
                }
            )
            process = proc
            isRunning = true
        } catch {
            failed = true
            lastLine = error.localizedDescription
        }
    }

    func cancel() {
        process?.stop()
    }
}
