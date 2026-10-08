import Foundation

enum ProcessRunner {
    struct Result {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    @discardableResult
    static func run(_ launchPath: String, arguments: [String]) throws -> Result {
        try run(launchPath, arguments: arguments, timeout: nil)
    }

    /// Runs a command and terminates it after `timeout` seconds. Some tools
    /// hold their state until killed (e.g. `memory_pressure -l warn` keeps
    /// exerting pressure once the level is reached), so the bounded run is
    /// the intended usage, not an error path.
    @discardableResult
    static func run(_ launchPath: String, arguments: [String], timeout: TimeInterval?) throws -> Result {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        try proc.run()

        // Drain both pipes while the process runs. Reading only after exit
        // deadlocks once a command writes more than the pipe buffer (~64 KB),
        // e.g. `simctl list --json` or `simctl listapps` on a busy machine.
        var outData = Data()
        var errData = Data()
        let drained = DispatchGroup()
        drained.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            drained.leave()
        }
        drained.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            drained.leave()
        }

        if let timeout {
            let deadline = Date().addingTimeInterval(timeout)
            while proc.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if proc.isRunning {
                proc.terminate()
            }
        }
        proc.waitUntilExit()
        drained.wait()

        return Result(
            exitCode: proc.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }
}

/// A long-running process whose stdout/stderr lines are delivered as they
/// arrive (e.g. `log stream`). Lines are batched and handed to `onLines` on
/// the main queue; `onExit` fires once the process ends for any reason.
final class StreamingProcess {
    private let process = Process()
    private let pipe = Pipe()
    private var buffer = Data()
    private let lock = NSLock()

    init(_ launchPath: String, arguments: [String]) {
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
    }

    var isRunning: Bool { process.isRunning }

    func start(onLines: @escaping ([String]) -> Void, onExit: @escaping (Int32) -> Void) throws {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self, !chunk.isEmpty else { return }
            let lines = self.consume(chunk)
            if !lines.isEmpty {
                DispatchQueue.main.async { onLines(lines) }
            }
        }
        process.terminationHandler = { [weak self] proc in
            self?.pipe.fileHandleForReading.readabilityHandler = nil
            let status = proc.terminationStatus
            DispatchQueue.main.async { onExit(status) }
        }
        try process.run()
    }

    func stop() {
        if process.isRunning { process.terminate() }
    }

    /// Splits accumulated bytes on newlines, keeping a trailing partial line
    /// in the buffer for the next chunk.
    private func consume(_ chunk: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(chunk)
        guard let lastNewline = buffer.lastIndex(of: 0x0A) else { return [] }
        let complete = buffer[buffer.startIndex..<lastNewline]
        buffer = Data(buffer[(lastNewline + 1)...])
        return String(decoding: complete, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    deinit { stop() }
}
