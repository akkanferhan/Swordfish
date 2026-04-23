import Foundation
import AppKit

struct ClipboardItem: Identifiable, Equatable {
    enum Kind { case text, link, code }
    let id = UUID()
    let kind: Kind
    let content: String
    let capturedAt: Date
    var pinned: Bool
}

@MainActor
final class ClipboardService: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all, text, links, code
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    private let capacity = 20
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var timer: Timer?

    var filtered: [ClipboardItem] {
        let pinned = items.filter { $0.pinned }
        let rest   = items.filter { !$0.pinned }
        let list   = pinned + rest
        switch filter {
        case .all:   return list
        case .text:  return list.filter { $0.kind == .text }
        case .links: return list.filter { $0.kind == .link }
        case .code:  return list.filter { $0.kind == .code }
        }
    }

    func start() {
        timer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        self.timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func copyToPasteboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.content, forType: .string)
        lastChangeCount = pb.changeCount
        if let idx = items.firstIndex(of: item) {
            let moved = items.remove(at: idx)
            items.insert(moved, at: 0)
        }
    }

    func togglePin(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].pinned.toggle()
    }

    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
    }

    func cleanPaste() {
        let pb = NSPasteboard.general
        guard let s = pb.string(forType: .string) else { return }
        pb.clearContents()
        pb.setString(s, forType: .string)
        lastChangeCount = pb.changeCount
    }

    private func poll() {
        let pb = NSPasteboard.general
        if pb.changeCount == lastChangeCount { return }
        lastChangeCount = pb.changeCount
        guard let raw = pb.string(forType: .string), !raw.isEmpty else { return }
        if items.first?.content == raw { return }  // dedupe consecutive
        let kind = classify(raw)
        items.insert(
            ClipboardItem(kind: kind, content: raw, capturedAt: Date(), pinned: false),
            at: 0
        )
        trim()
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
        let room = max(0, capacity - pinned.count)
        items = pinned + unpinned.prefix(room)
    }
}
