import Foundation

struct LogLine: Identifiable, Equatable {
    enum Level { case debug, info, `default`, error, fault }

    let id: Int
    let text: String
    let level: Level

    /// `log stream --style compact` lines look like
    /// `2026-10-01 12:00:00.123 Df MyApp[123:456] [com.x:net] message`;
    /// the third token is the type (Db, I, Df, E, F).
    init(id: Int, text: String) {
        self.id = id
        self.text = text
        let tokens = text.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        switch tokens.count > 2 ? String(tokens[2]) : "" {
        case "Db": level = .debug
        case "I":  level = .info
        case "E":  level = .error
        case "F":  level = .fault
        default:   level = .default
        }
    }
}

/// Streams a booted simulator's unified log (`simctl spawn <udid> log
/// stream`) filtered by process and/or subsystem, keeping the most recent
/// `maxLines` in memory.
@MainActor
final class SimulatorLogService: ObservableObject {
    enum MinimumLevel: String, CaseIterable, Identifiable {
        case `default`, info, debug
        var id: String { rawValue }
        var label: String {
            switch self {
            case .default: return String(localized: "Default")
            case .info:    return String(localized: "Info")
            case .debug:   return String(localized: "Debug")
            }
        }
    }

    @Published private(set) var lines: [LogLine] = []
    @Published private(set) var isRunning = false
    @Published var lastError: String?

    private let maxLines = 5_000
    private var nextID = 0
    private var stream: StreamingProcess?

    func start(udid: String, process: String, subsystem: String, level: MinimumLevel) {
        stop()
        lastError = nil
        var args = ["simctl", "spawn", udid, "log", "stream", "--style", "compact", "--level", level.rawValue]
        if let predicate = Self.predicate(process: process, subsystem: subsystem) {
            args += ["--predicate", predicate]
        }
        let proc = StreamingProcess("/usr/bin/xcrun", arguments: args)
        do {
            try proc.start(
                onLines: { [weak self] in self?.append($0) },
                onExit: { [weak self] status in
                    guard let self, self.stream === proc else { return }
                    self.isRunning = false
                    self.stream = nil
                    // SIGTERM (15, or 143 once xcrun relays it) means a normal stop.
                    if ![0, 15, 143].contains(status) {
                        self.lastError = String(localized: "log stream exited with status \(status)")
                    }
                }
            )
            stream = proc
            isRunning = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        stream?.stop()
        stream = nil
        isRunning = false
    }

    func clear() {
        lines.removeAll()
    }

    private func append(_ newLines: [String]) {
        // The first line of `log stream` is a "Filtering the log data…" banner.
        let incoming = newLines.filter { !$0.hasPrefix("Filtering the log data") && !$0.hasPrefix("Timestamp ") }
        guard !incoming.isEmpty else { return }
        lines.append(contentsOf: incoming.map { text in
            defer { nextID += 1 }
            return LogLine(id: nextID, text: text)
        })
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }

    /// Builds an NSPredicate string for `log stream`. Double quotes inside
    /// user input are escaped so they can't break out of the literal.
    nonisolated static func predicate(process: String, subsystem: String) -> String? {
        func literal(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        var clauses: [String] = []
        let p = process.trimmingCharacters(in: .whitespaces)
        let s = subsystem.trimmingCharacters(in: .whitespaces)
        if !p.isEmpty { clauses.append("process == \(literal(p))") }
        if !s.isEmpty { clauses.append("subsystem BEGINSWITH \(literal(s))") }
        return clauses.isEmpty ? nil : clauses.joined(separator: " AND ")
    }
}
