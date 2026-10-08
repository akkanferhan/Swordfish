import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CrashSymbolicatorView: View {
    @State private var reportURL: URL?
    @State private var extraDSYMs: [URL] = []
    @State private var output: CrashSymbolicator.Output?
    @State private var error: String?
    @State private var isWorking = false
    @State private var isTargeted = false
    @State private var uuidQuery = ""
    @State private var uuidResult: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let output {
                ScrollView([.vertical, .horizontal]) {
                    Text(verbatim: output.text)
                        .font(Typography.code)
                        .foregroundStyle(Theme.TextColor.primary)
                        .textSelection(.enabled)
                        .padding(Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Theme.Surface.codeBg)
            } else {
                dropZone
            }
            Divider()
            footer
        }
        .background(Theme.Surface.popover)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: Spacing.sm) {
            PillButton(title: "Open Report…", symbol: "doc.text.magnifyingglass") { chooseReport() }
            PillButton(title: "Add dSYM…", symbol: "plus.rectangle.on.folder") { chooseDSYM() }
            if !extraDSYMs.isEmpty {
                Text("\(extraDSYMs.count) dSYM(s) added")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
            }
            Spacer()
            if let output {
                CopyButton(text: output.text)
                PillButton(title: "Save…", symbol: "square.and.arrow.down") { save(output.text) }
            }
            if reportURL != nil {
                ToolboxIconButton(symbol: "arrow.clockwise", help: "Symbolicate again") { run() }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    private var dropZone: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: isWorking ? "hourglass" : "ant.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(isTargeted ? Color.accentColor : Theme.TextColor.quaternary)
            Text(isWorking ? "Symbolicating…" : "Drop a .ips or .crash report here")
                .font(Typography.bodyMedium)
                .foregroundStyle(Theme.TextColor.secondary)
            Text("dSYMs are found automatically by UUID (DerivedData, Archives, anything Spotlight indexes). Drop a .dSYM too if yours lives elsewhere.")
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if let error {
                Text(error)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.Semantic.danger)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isTargeted ? Color.accentColor.opacity(0.06) : Theme.Surface.codeBg)
    }

    // MARK: Footer (summary + dSYM finder)

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let output {
                HStack(spacing: Spacing.sm) {
                    Label("\(output.symbolicatedFrames) frame(s) symbolicated", systemImage: "checkmark.circle")
                        .foregroundStyle(Theme.Semantic.ok)
                    if !output.missingDSYMs.isEmpty {
                        Label("No dSYM for: \(output.missingDSYMs.joined(separator: ", "))", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.Semantic.warn)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
                .font(Typography.monoSmall)
            }
            HStack(spacing: Spacing.sm) {
                Text("Find dSYM by UUID")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                TextField("64681874-8343-3FF4-85FD-FC394D987613", text: $uuidQuery)
                    .textFieldStyle(.roundedBorder)
                    .font(Typography.mono)
                    .frame(width: 300)
                    .onSubmit(findUUID)
                PillButton(title: "Find", symbol: "magnifyingglass", action: findUUID)
                if let uuidResult {
                    Text(uuidResult)
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer()
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 6)
    }

    // MARK: Actions

    private func run() {
        guard let reportURL else { return }
        isWorking = true
        error = nil
        let extra = extraDSYMs
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try CrashSymbolicator.symbolicate(reportURL, extraDSYMs: extra) }
            }.value
            switch result {
            case .success(let out):
                output = out
            case .failure(let failure):
                output = nil
                error = failure.localizedDescription
            }
            isWorking = false
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL? = (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) } ?? (item as? URL)
                guard let url else { return }
                DispatchQueue.main.async { accept(url) }
            }
        }
        return true
    }

    private func accept(_ url: URL) {
        if url.pathExtension.lowercased() == "dsym" {
            extraDSYMs.append(url)
            if reportURL != nil { run() }
        } else {
            reportURL = url
            run()
        }
    }

    private func chooseReport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["ips", "crash", "txt"].compactMap { UTType(filenameExtension: $0) }
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/DiagnosticReports")
        if panel.runModal() == .OK, let url = panel.url { accept(url) }
    }

    private func chooseDSYM() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "dSYM") ?? .folder]
        if panel.runModal() == .OK, let url = panel.url { accept(url) }
    }

    private func save(_ text: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (reportURL?.deletingPathExtension().lastPathComponent ?? "crash") + "-symbolicated.txt"
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func findUUID() {
        let query = uuidQuery
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        uuidResult = String(localized: "Searching…")
        Task {
            let found = await Task.detached { CrashSymbolicator.findDSYM(uuid: query) }.value
            uuidResult = found?.path ?? String(localized: "No dSYM with that UUID is indexed")
            if let found { NSWorkspace.shared.activateFileViewerSelecting([found]) }
        }
    }
}

@MainActor
final class CrashSymbolicatorWindowController: NSObject {
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: CrashSymbolicatorView()))
        window.title = String(localized: "Crash Symbolicator")
        window.setContentSize(NSSize(width: 960, height: 620))
        window.contentMinSize = NSSize(width: 720, height: 400)
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
