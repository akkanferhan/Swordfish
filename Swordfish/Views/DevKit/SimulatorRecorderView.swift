import SwiftUI
import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

struct SimulatorRecorderView: View {
    @StateObject private var service = SimulatorService()
    @StateObject private var recorder = SimulatorRecorder()
    @AppStorage("swordfish.recorder.format") private var format: Format = .mp4
    @State private var selectedUDID: String = ""
    @State private var showTouches = SimulatorTouches.isEnabled
    @State private var gifStatus: ToolboxStatus?
    @State private var isMakingGIF = false

    enum Format: String, CaseIterable, Identifiable {
        case mp4, mov
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            targetRow
            controlRow
            if let status = recorder.status { statusLine(status) }
            if let gifStatus { ToolboxStatusLine(status: gifStatus) }
            extrasRow
        }
        .task { service.refresh() }
    }

    // MARK: - Target

    private var targetRow: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "iphone")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.TextColor.tertiary)
                simulatorPicker
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .fill(Theme.Surface.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            .strokeBorder(Theme.Border.subtle, lineWidth: 1)
                    )
            )
            Spacer()
            Picker("", selection: $format) {
                ForEach(Format.allCases) { f in
                    Text(f.rawValue.uppercased()).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 110)
            .disabled(recorder.isRecording)
        }
    }

    @ViewBuilder
    private var simulatorPicker: some View {
        let booted = service.simulators.filter { $0.isBooted }
        if booted.isEmpty {
            Text("No booted simulators")
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.tertiary)
        } else {
            Picker("", selection: $selectedUDID) {
                ForEach(booted) { sim in Text(sim.name).tag(sim.udid) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .font(Typography.monoSmall)
            .frame(minWidth: 120)
            .disabled(recorder.isRecording)
            .onAppear {
                if !booted.contains(where: { $0.udid == selectedUDID }) {
                    selectedUDID = booted.first?.udid ?? ""
                }
            }
        }
    }

    // MARK: - Controls

    private var controlRow: some View {
        HStack(spacing: Spacing.sm) {
            if recorder.isRecording {
                HStack(spacing: 6) {
                    Circle().fill(Theme.Semantic.danger).frame(width: 8, height: 8)
                        .opacity(pulse ? 1 : 0.35)
                    Text(recorder.elapsedString)
                        .font(Typography.mono)
                        .foregroundStyle(Theme.TextColor.primary)
                }
                .onAppear { pulse = true }
            }
            Spacer()
            if recorder.isRecording {
                Button(action: stop) {
                    recordButtonLabel(symbol: "stop.fill", label: String(localized: "Stop"), tint: Theme.Semantic.danger)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: start) {
                    recordButtonLabel(symbol: "record.circle", label: String(localized: "Record"), tint: Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(selectedUDID.isEmpty)
                .opacity(selectedUDID.isEmpty ? 0.5 : 1)
            }
        }
    }

    @State private var pulse: Bool = false

    private func recordButtonLabel(symbol: String, label: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
            Text(label)
                .font(Typography.bodyMedium)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                .fill(tint)
        )
    }

    // MARK: - Status

    private func statusLine(_ status: SimulatorRecorder.Status) -> some View {
        HStack(spacing: 6) {
            Image(systemName: status.isError ? "xmark.circle" : "checkmark.circle")
                .font(.system(size: 11))
            Text(status.message)
                .font(Typography.monoSmall)
                .lineLimit(1)
            if case .saved(let url) = status {
                Spacer()
                Button {
                    makeGIF(from: url)
                } label: {
                    Text("Make GIF")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Color.accentColor)
                        .underline()
                }
                .buttonStyle(.plain)
                .disabled(isMakingGIF)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Text("Reveal in Finder")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Color.accentColor)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(status.isError ? Theme.Semantic.danger : Theme.Semantic.ok)
    }

    // MARK: - Extras (touches, GIF)

    private var extrasRow: some View {
        HStack(spacing: Spacing.sm) {
            Toggle("Show touches", isOn: Binding(
                get: { showTouches },
                set: { on in
                    SimulatorTouches.setEnabled(on)
                    showTouches = on
                }
            ))
            .toggleStyle(.checkbox)
            .font(Typography.monoSmall)
            .help("Draws touch circles in the Simulator window (applies after Simulator restarts). They appear in window / screen recordings such as ⇧⌘5 — simctl captures the device screen only.")
            Spacer()
            PillButton(title: isMakingGIF ? "Making GIF…" : "Video → GIF…", symbol: "photo.stack") {
                chooseVideoForGIF()
            }
            .disabled(isMakingGIF)
        }
    }

    private func chooseVideoForGIF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        if case .saved(let url) = recorder.status {
            panel.directoryURL = url.deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        makeGIF(from: url)
    }

    private func makeGIF(from url: URL) {
        isMakingGIF = true
        gifStatus = nil
        Task {
            do {
                let gif = try await GIFMaker.convert(url)
                gifStatus = .ok(String(localized: "Saved \(gif.lastPathComponent)"), gif)
            } catch {
                gifStatus = .error(error.localizedDescription)
            }
            isMakingGIF = false
        }
    }

    // MARK: - Actions

    private func start() {
        recorder.start(udid: selectedUDID, format: format)
    }

    private func stop() {
        recorder.stop()
    }
}

// MARK: - Recorder driver

@MainActor
final class SimulatorRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var status: Status?
    @Published private(set) var elapsed: TimeInterval = 0

    enum Status {
        case recording, saved(URL), error(String)
        var isError: Bool { if case .error = self { return true }; return false }
        var message: String {
            switch self {
            case .recording:    return String(localized: "Recording…")
            case .saved(let u): return String(localized: "Saved to \(u.lastPathComponent)")
            case .error(let m): return m
            }
        }
    }

    private var process: Process?
    private var outputURL: URL?
    private var startedAt: Date?
    private var timer: Timer?
    private var stderrPipe: Pipe?

    var elapsedString: String {
        let total = Int(elapsed)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    func start(udid: String, format: SimulatorRecorderView.Format) {
        guard !isRecording else { return }
        guard !udid.isEmpty else {
            status = .error(String(localized: "Pick a booted simulator first"))
            return
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "sim-\(fmt.string(from: Date())).\(format.rawValue)"
        let url = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
            .appendingPathComponent(filename)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        proc.arguments = ["simctl", "io", udid, "recordVideo",
                          "--codec", format == .mp4 ? "h264" : "hevc",
                          "--force", url.path]
        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = Pipe()

        do {
            try proc.run()
        } catch {
            status = .error(String(localized: "Failed to launch: \(error.localizedDescription)"))
            return
        }

        self.process = proc
        self.outputURL = url
        self.stderrPipe = errPipe
        self.startedAt = Date()
        self.isRecording = true
        self.status = .recording
        self.elapsed = 0

        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }

    func stop() {
        guard isRecording, let proc = process else { return }
        // simctl writes the mp4 when it receives SIGINT, not SIGTERM.
        proc.interrupt()

        Task.detached(priority: .userInitiated) { [proc, outputURL, stderrPipe] in
            proc.waitUntilExit()
            let exitCode = proc.terminationStatus
            let errData = stderrPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
            let errStr = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.timer?.invalidate()
                self.timer = nil
                self.isRecording = false
                self.process = nil
                self.stderrPipe = nil

                if let url = outputURL,
                   FileManager.default.fileExists(atPath: url.path),
                   (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 0 {
                    self.status = .saved(url)
                } else if exitCode != 0, !errStr.isEmpty {
                    self.status = .error(errStr)
                } else {
                    self.status = .error(String(localized: "Recording produced no file"))
                }
                self.outputURL = nil
                self.startedAt = nil
            }
        }
    }

    private func tick() {
        guard let started = startedAt else { return }
        elapsed = Date().timeIntervalSince(started)
    }
}

// MARK: - Touch indicators

/// Simulator.app's hidden "show single touches" preference.
enum SimulatorTouches {
    private static let domain = "com.apple.iphonesimulator" as CFString
    private static let key = "ShowSingleTouches" as CFString

    static var isEnabled: Bool {
        CFPreferencesAppSynchronize(domain)
        return (CFPreferencesCopyAppValue(key, domain) as? Bool) ?? false
    }

    static func setEnabled(_ on: Bool) {
        CFPreferencesSetAppValue(key, NSNumber(value: on), domain)
        CFPreferencesAppSynchronize(domain)
    }
}

// MARK: - GIF export

/// Turns a screen recording into a looping GIF next to it (12 fps, at most
/// 480 px wide — small enough for PR descriptions and Slack).
enum GIFMaker {
    static func convert(_ video: URL, fps: Double = 12, maxWidth: CGFloat = 480) async throws -> URL {
        let asset = AVURLAsset(url: video)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            throw SimulatorToolbox.CommandError(message: String(localized: "Couldn't read the video"))
        }
        let frameCount = min(Int(duration * fps), 600)   // cap at ~50 s of GIF
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxWidth, height: maxWidth * 4)
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 60)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 60)

        let output = video.deletingPathExtension().appendingPathExtension("gif")
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString,
                                                                 frameCount, nil) else {
            throw SimulatorToolbox.CommandError(message: String(localized: "Couldn't create the GIF file"))
        }
        let fileProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0],
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: 1.0 / fps],
        ]

        for index in 0..<frameCount {
            let time = CMTime(seconds: Double(index) / fps, preferredTimescale: 600)
            let (image, _) = try await generator.image(at: time)
            CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw SimulatorToolbox.CommandError(message: String(localized: "Couldn't write the GIF"))
        }
        return output
    }
}
