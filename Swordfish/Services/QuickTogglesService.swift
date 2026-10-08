import Foundation
import AppKit
import CoreAudio

struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
}

/// Default input / output device listing and switching via CoreAudio's
/// HAL property API.
enum AudioDevices {
    enum Direction { case output, input }

    static func list(_ direction: Direction) -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard hasStreams(id, direction), let name = name(of: id) else { return nil }
            return AudioDevice(id: id, name: name)
        }
    }

    static func defaultDevice(_ direction: Direction) -> AudioDeviceID? {
        var address = defaultAddress(direction)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr else { return nil }
        return id
    }

    static func setDefault(_ id: AudioDeviceID, _ direction: Direction) {
        var address = defaultAddress(direction)
        var device = id
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                   UInt32(MemoryLayout<AudioDeviceID>.size), &device)
    }

    // MARK: Input mute

    /// Elements to try: the master element first, then the first channels —
    /// some USB / Bluetooth mics only expose mute or volume per channel.
    private static let inputElements: [AudioObjectPropertyElement] = [kAudioObjectPropertyElementMain, 1, 2]

    private static func inputAddress(_ selector: AudioObjectPropertySelector,
                                     _ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput, mElement: element)
    }

    /// Elements of `selector` that exist and can be written on this device.
    private static func settableInputElements(_ id: AudioDeviceID,
                                              _ selector: AudioObjectPropertySelector) -> [AudioObjectPropertyElement] {
        inputElements.filter { element in
            var address = inputAddress(selector, element)
            var settable: DarwinBoolean = false
            return AudioObjectHasProperty(id, &address)
                && AudioObjectIsPropertySettable(id, &address, &settable) == noErr
                && settable.boolValue
        }
    }

    /// True when the device has a real mute switch; otherwise muting falls
    /// back to input volume 0.
    static func hasInputMute(_ id: AudioDeviceID) -> Bool {
        !settableInputElements(id, kAudioDevicePropertyMute).isEmpty
    }

    static func canMuteInput(_ id: AudioDeviceID) -> Bool {
        hasInputMute(id) || !settableInputElements(id, kAudioDevicePropertyVolumeScalar).isEmpty
    }

    static func isInputMuted(_ id: AudioDeviceID) -> Bool {
        if let element = settableInputElements(id, kAudioDevicePropertyMute).first {
            var address = inputAddress(kAudioDevicePropertyMute, element)
            var muted: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(id, &address, 0, nil, &size, &muted) == noErr { return muted != 0 }
        }
        return (inputVolume(id) ?? 1) <= 0.001
    }

    /// Mutes / unmutes via the mute property on every element that has one.
    @discardableResult
    static func setInputMute(_ id: AudioDeviceID, _ muted: Bool) -> Bool {
        let elements = settableInputElements(id, kAudioDevicePropertyMute)
        guard !elements.isEmpty else { return false }
        var ok = true
        for element in elements {
            var address = inputAddress(kAudioDevicePropertyMute, element)
            var value: UInt32 = muted ? 1 : 0
            ok = AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr && ok
        }
        return ok
    }

    /// Input volume 0…1 (first element that reports one).
    static func inputVolume(_ id: AudioDeviceID) -> Float? {
        for element in inputElements {
            var address = inputAddress(kAudioDevicePropertyVolumeScalar, element)
            guard AudioObjectHasProperty(id, &address) else { continue }
            var volume: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(id, &address, 0, nil, &size, &volume) == noErr { return volume }
        }
        return nil
    }

    @discardableResult
    static func setInputVolume(_ id: AudioDeviceID, _ volume: Float) -> Bool {
        let elements = settableInputElements(id, kAudioDevicePropertyVolumeScalar)
        guard !elements.isEmpty else { return false }
        var ok = true
        for element in elements {
            var address = inputAddress(kAudioDevicePropertyVolumeScalar, element)
            var value = Float32(volume)
            ok = AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr && ok
        }
        return ok
    }

    /// Calls `handler` on the main queue whenever devices appear / disappear
    /// or the default input/output changes.
    static func observeChanges(_ handler: @escaping () -> Void) {
        let selectors = [kAudioHardwarePropertyDevices,
                         kAudioHardwarePropertyDefaultOutputDevice,
                         kAudioHardwarePropertyDefaultInputDevice]
        for selector in selectors {
            var address = AudioObjectPropertyAddress(mSelector: selector,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { _, _ in
                handler()
            }
        }
    }

    private static func defaultAddress(_ direction: Direction) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: direction == .output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func hasStreams(_ id: AudioDeviceID, _ direction: Direction) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: direction == .output ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }
}

/// One-click system toggles for the System tab: appearance, Finder hidden
/// files, microphone mute, and default audio devices.
@MainActor
final class QuickTogglesService: ObservableObject {
    @Published private(set) var darkMode = false
    @Published private(set) var showHiddenFiles = false
    @Published private(set) var outputs: [AudioDevice] = []
    @Published private(set) var inputs: [AudioDevice] = []
    @Published private(set) var defaultOutput: AudioDeviceID?
    @Published private(set) var defaultInput: AudioDeviceID?
    @Published private(set) var micMuted = false
    @Published private(set) var canMuteMic = false
    @Published private(set) var isBusy = false
    @Published var lastError: String?

    private var observing = false
    /// Input volume before a volume-based mute, per device, so unmuting
    /// restores the user's level instead of jumping to 100 %.
    private var savedInputVolumes: [AudioDeviceID: Float] = [:]

    func start() {
        refresh()
        guard !observing else { return }
        observing = true
        AudioDevices.observeChanges { [weak self] in
            Task { @MainActor in self?.refreshAudio() }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshAppearance() }
        }
    }

    func refresh() {
        refreshAppearance()
        showHiddenFiles = Self.finderBool("AppleShowAllFiles") ?? false
        refreshAudio()
    }

    // MARK: - Appearance

    private func refreshAppearance() {
        darkMode = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleInterfaceStyle"] as? String == "Dark"
    }

    /// Goes through System Events (same Automation permission as Lock Screen).
    func setDarkMode(_ on: Bool) {
        runBackground {
            let r = try ProcessRunner.run("/usr/bin/osascript", arguments: [
                "-e", "tell application \"System Events\" to tell appearance preferences to set dark mode to \(on)"
            ])
            guard r.exitCode == 0 else { throw ToggleError(r.stderr) }
        } then: { [weak self] in
            self?.refreshAppearance()
        }
    }

    // MARK: - Finder

    /// The Finder switch needs a Finder relaunch to take effect; open
    /// windows come back on their own.
    func setShowHiddenFiles(_ on: Bool) {
        writeFinderDefault("AppleShowAllFiles", on) { [weak self] in self?.showHiddenFiles = on }
    }

    private func writeFinderDefault(_ key: String, _ value: Bool, onSuccess: @escaping () -> Void) {
        runBackground {
            let w = try ProcessRunner.run("/usr/bin/defaults", arguments: ["write", "com.apple.finder", key, "-bool", value ? "true" : "false"])
            guard w.exitCode == 0 else { throw ToggleError(w.stderr) }
            _ = try ProcessRunner.run("/usr/bin/killall", arguments: ["Finder"])
        } then: {
            onSuccess()
        }
    }

    nonisolated private static func finderBool(_ key: String) -> Bool? {
        CFPreferencesAppSynchronize("com.apple.finder" as CFString)
        let value = CFPreferencesCopyAppValue(key as CFString, "com.apple.finder" as CFString)
        if let b = value as? Bool { return b }
        if let s = value as? String { return ["1", "yes", "true"].contains(s.lowercased()) }
        return nil
    }

    // MARK: - Audio

    private func refreshAudio() {
        outputs = AudioDevices.list(.output)
        inputs = AudioDevices.list(.input)
        defaultOutput = AudioDevices.defaultDevice(.output)
        defaultInput = AudioDevices.defaultDevice(.input)
        refreshMic()
    }

    private func refreshMic() {
        guard let input = defaultInput else {
            canMuteMic = false
            micMuted = false
            return
        }
        canMuteMic = AudioDevices.canMuteInput(input)
        micMuted = canMuteMic && AudioDevices.isInputMuted(input)
    }

    /// Mutes the default input device — through its mute switch when it has
    /// one, otherwise by dropping input volume to 0 (and restoring it after).
    func setMicMuted(_ muted: Bool) {
        guard let input = defaultInput else { return }
        lastError = nil
        let ok: Bool
        if AudioDevices.hasInputMute(input) {
            ok = AudioDevices.setInputMute(input, muted)
        } else if muted {
            if let current = AudioDevices.inputVolume(input), current > 0.001 {
                savedInputVolumes[input] = current
            }
            ok = AudioDevices.setInputVolume(input, 0)
        } else {
            ok = AudioDevices.setInputVolume(input, savedInputVolumes.removeValue(forKey: input) ?? 0.75)
        }
        if !ok {
            lastError = String(localized: "This microphone doesn't allow muting from other apps")
        }
        refreshMic()
    }

    func setOutput(_ id: AudioDeviceID) {
        AudioDevices.setDefault(id, .output)
        refreshAudio()
    }

    func setInput(_ id: AudioDeviceID) {
        AudioDevices.setDefault(id, .input)
        refreshAudio()
    }

    // MARK: - Helpers

    private struct ToggleError: LocalizedError {
        let message: String
        init(_ stderr: String) { message = stderr.trimmingCharacters(in: .whitespacesAndNewlines) }
        var errorDescription: String? { message.isEmpty ? String(localized: "Command failed") : message }
    }

    private func runBackground(_ work: @escaping () throws -> Void, then: @escaping () -> Void) {
        guard !isBusy else { return }
        isBusy = true
        lastError = nil
        Task.detached(priority: .userInitiated) {
            let message: String?
            do { try work(); message = nil } catch { message = error.localizedDescription }
            await MainActor.run { [weak self] in
                self?.isBusy = false
                if let message { self?.lastError = message } else { then() }
            }
        }
    }
}
