import Foundation
import AppKit
import CryptoKit

struct ClipboardItem: Identifiable, Equatable, Codable {
    enum Kind: String, Codable { case text, link, code, image, file, secret }

    var id = UUID()
    var kind: Kind
    /// Text content; newline-separated paths for `.file`; empty for `.image`.
    var content: String
    var capturedAt: Date
    var pinned: Bool
    var sourceApp: String?
    var sourceBundleID: String?
    /// PNG file name inside `ClipboardStore.imagesDirectory` (`.image` only).
    var imageFile: String?
    var imageWidth: Int?
    var imageHeight: Int?
    /// SHA-256 of the image bytes, for de-duplication.
    var imageHash: String?

    var fileURLs: [URL] {
        kind == .file ? content.split(separator: "\n").map { URL(fileURLWithPath: String($0)) } : []
    }

    var imageURL: URL? {
        imageFile.map { ClipboardStore.imagesDirectory.appendingPathComponent($0) }
    }

    /// What search and the UI show (masked for secrets).
    var displayText: String {
        switch kind {
        case .secret: return ClipboardPrivacy.masked(content)
        case .image:  return String(localized: "Image \(imageWidth ?? 0)×\(imageHeight ?? 0)")
        case .file:   return fileURLs.map(\.lastPathComponent).joined(separator: ", ")
        default:      return content
        }
    }
}

@MainActor
final class ClipboardService: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published var filter: Filter = .all
    @Published var search = ""
    /// Shown once when something was deliberately not recorded.
    @Published private(set) var lastSkipped: String?

    enum Filter: String, CaseIterable, Identifiable {
        case all, text, links, code, media
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all:   return String(localized: "All")
            case .text:  return String(localized: "Text")
            case .links: return String(localized: "Links")
            case .code:  return String(localized: "Code")
            case .media: return String(localized: "Media")
            }
        }
    }

    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var saveTask: Task<Void, Never>?

    var filtered: [ClipboardItem] {
        let pinned = items.filter { $0.pinned }
        let rest   = items.filter { !$0.pinned }
        var list   = pinned + rest
        switch filter {
        case .all:   break
        case .text:  list = list.filter { $0.kind == .text || $0.kind == .secret }
        case .links: list = list.filter { $0.kind == .link }
        case .code:  list = list.filter { $0.kind == .code }
        case .media: list = list.filter { $0.kind == .image || $0.kind == .file }
        }
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return list }
        return list.filter {
            $0.displayText.localizedCaseInsensitiveContains(query)
                || ($0.sourceApp?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    // MARK: - Lifecycle

    func start() {
        ClipboardSettings.register()
        if ClipboardSettings.persist {
            items = ClipboardStore.loadHistory()
        }
        timer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
                self?.expireSecrets()
            }
        }
        self.timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Copy back

    func copyToPasteboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .image:
            if let url = item.imageURL, let image = NSImage(contentsOf: url) {
                pb.writeObjects([image])
            }
        case .file:
            pb.writeObjects(item.fileURLs as [NSURL])
        case .secret:
            pb.setString(item.content, forType: .string)
            // Keep password-manager semantics when we hand a secret back.
            pb.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        default:
            pb.setString(item.content, forType: .string)
        }
        lastChangeCount = pb.changeCount
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            let moved = items.remove(at: idx)
            items.insert(moved, at: 0)
            scheduleSave()
        }
    }

    /// Copies plain text produced by a transform / smart action; it becomes
    /// a regular history entry on the next poll.
    func copyText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    func apply(_ transform: ClipboardTransform, to item: ClipboardItem) -> Bool {
        guard let result = transform.apply(item.content) else { return false }
        copyText(result)
        return true
    }

    func togglePin(_ item: ClipboardItem) {
        guard item.kind != .secret, let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].pinned.toggle()
        scheduleSave()
    }

    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        scheduleSave()
    }

    /// Clears everything except pinned items.
    func clearHistory() {
        items.removeAll { !$0.pinned }
        scheduleSave()
    }

    func cleanPaste() {
        let pb = NSPasteboard.general
        guard let s = pb.string(forType: .string) else { return }
        pb.clearContents()
        pb.setString(s, forType: .string)
        lastChangeCount = pb.changeCount
    }

    /// Re-applies the persistence / capacity settings after they change.
    func settingsChanged() {
        trim()
        if ClipboardSettings.persist {
            scheduleSave()
        } else {
            ClipboardStore.deleteHistoryFile()
            ClipboardStore.pruneImages(keeping: Set(items.compactMap(\.imageFile)))
        }
    }

    // MARK: - Polling

    private func poll() {
        let pb = NSPasteboard.general
        if pb.changeCount == lastChangeCount { return }
        lastChangeCount = pb.changeCount

        let front = NSWorkspace.shared.frontmostApplication
        if ClipboardPrivacy.isMarkedPrivate(pb) {
            lastSkipped = String(localized: "Skipped a private copy (marked concealed by \(front?.localizedName ?? "the app"))")
            return
        }
        if let bundleID = front?.bundleIdentifier, ClipboardSettings.excludedApps.contains(bundleID) {
            lastSkipped = String(localized: "Skipped a copy from \(front?.localizedName ?? bundleID) (excluded app)")
            return
        }
        lastSkipped = nil

        let source = (front?.localizedName, front?.bundleIdentifier)

        // Files first: Finder also puts the file's icon and name on the board.
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            let content = urls.map(\.path).joined(separator: "\n")
            if items.first?.content == content { return }
            insert(ClipboardItem(kind: .file, content: content, capturedAt: Date(), pinned: false,
                                 sourceApp: source.0, sourceBundleID: source.1))
            return
        }

        if let raw = pb.string(forType: .string), !raw.isEmpty {
            if items.first?.content == raw { return }  // dedupe consecutive
            let kind: ClipboardItem.Kind = ClipboardPrivacy.looksLikeSecret(raw) ? .secret : classify(raw)
            insert(ClipboardItem(kind: kind, content: raw, capturedAt: Date(), pinned: false,
                                 sourceApp: source.0, sourceBundleID: source.1))
            return
        }

        if let image = NSImage(pasteboard: pb) {
            captureImage(image, source: source)
        }
    }

    /// PNG encoding a big screenshot takes a moment — do it off the main thread.
    private func captureImage(_ image: NSImage, source: (String?, String?)) {
        guard let tiff = image.tiffRepresentation else { return }
        Task.detached(priority: .utility) {
            guard let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]),
                  png.count < 25_000_000 else { return }
            let hash = SHA256.hash(data: png).prefix(12).map { String(format: "%02x", $0) }.joined()
            let name = "\(hash).png"
            ClipboardStore.ensureDirectories()
            let url = ClipboardStore.imagesDirectory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) {
                try? png.write(to: url, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
            let width = rep.pixelsWide
            let height = rep.pixelsHigh
            await MainActor.run { [weak self] in
                guard let self, self.items.first?.imageHash != hash else { return }
                self.insert(ClipboardItem(kind: .image, content: "", capturedAt: Date(), pinned: false,
                                          sourceApp: source.0, sourceBundleID: source.1,
                                          imageFile: name, imageWidth: width, imageHeight: height,
                                          imageHash: hash))
            }
        }
    }

    private func insert(_ item: ClipboardItem) {
        items.insert(item, at: 0)
        trim()
        scheduleSave()
    }

    private func expireSecrets() {
        let cutoff = Date().addingTimeInterval(-ClipboardSettings.secretLifetime)
        if items.contains(where: { $0.kind == .secret && $0.capturedAt < cutoff }) {
            items.removeAll { $0.kind == .secret && $0.capturedAt < cutoff }
        }
    }

    private func classify(_ s: String) -> ClipboardItem.Kind {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true { return .link }
        if trimmed.contains("{") || trimmed.contains("function") || trimmed.contains("=>") || trimmed.contains(";\n") {
            return .code
        }
        return .text
    }

    private func trim() {
        let pinned = items.filter { $0.pinned }
        let unpinned = items.filter { !$0.pinned }
        let room = max(0, ClipboardSettings.capacity - pinned.count)
        items = pinned + unpinned.prefix(room)
    }

    /// Debounced so a burst of copies writes the file once.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, let self else { return }
            let snapshot = self.items
            let persist = ClipboardSettings.persist
            await Task.detached(priority: .utility) {
                if persist { ClipboardStore.saveHistory(snapshot) }
                ClipboardStore.pruneImages(keeping: Set(snapshot.compactMap(\.imageFile)))
            }.value
        }
    }
}
