import Foundation

enum ProcessRunner {
    struct Result {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    @discardableResult
    static func run(_ launchPath: String, arguments: [String]) throws -> Result {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        try proc.run()
        proc.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return Result(
            exitCode: proc.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    /// Runs a command and terminates it after `timeout` seconds. Some tools
    /// hold their state until killed (e.g. `memory_pressure -l warn` keeps
    /// exerting pressure once the level is reached), so the bounded run is
    /// the intended usage, not an error path.
    @discardableResult
    static func run(_ launchPath: String, arguments: [String], timeout: TimeInterval) throws -> Result {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        try proc.run()
        let deadline = Date().addingTimeInterval(timeout)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if proc.isRunning {
            proc.terminate()
        }
        proc.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return Result(
            exitCode: proc.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
