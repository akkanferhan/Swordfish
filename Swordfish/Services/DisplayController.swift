import Foundation
import AppKit

struct DisplayDevice: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let resolution: CGSize
    let isBuiltIn: Bool
    var brightness: Double   // 0...1
}

@MainActor
final class DisplayController: ObservableObject {
    @Published var displays: [DisplayDevice] = []

    private var debounceWorkItem: DispatchWorkItem?

    init() {
        refresh()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        var displayCount: UInt32 = 0
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: 16)
        CGGetActiveDisplayList(16, &activeDisplays, &displayCount)
        let ids = Array(activeDisplays.prefix(Int(displayCount)))

        let screens = NSScreen.screens
        displays = ids.map { id in
            let isBuiltIn = CGDisplayIsBuiltin(id) != 0
            let mode = CGDisplayCopyDisplayMode(id)
            let w = mode.map { CGFloat($0.pixelWidth) } ?? CGFloat(CGDisplayPixelsWide(id))
            let h = mode.map { CGFloat($0.pixelHeight) } ?? CGFloat(CGDisplayPixelsHigh(id))
            let name = screens.first { ($0.deviceDescription[.init("NSScreenNumber")] as? NSNumber)?.uint32Value == id }?.localizedName
                ?? (isBuiltIn ? "Built-in Display" : "External Display")
            let brightness = readBrightness(for: id, isBuiltIn: isBuiltIn) ?? 0.75
            return DisplayDevice(
                id: id,
                name: name,
                resolution: CGSize(width: w, height: h),
                isBuiltIn: isBuiltIn,
                brightness: brightness
            )
        }
    }

    func setBrightness(_ value: Double, for id: CGDirectDisplayID) {
        guard let idx = displays.firstIndex(where: { $0.id == id }) else { return }
        let clamped = max(0, min(1, value))
        displays[idx].brightness = clamped

        let isBuiltIn = displays[idx].isBuiltIn
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem {
            Task.detached(priority: .userInitiated) {
                if isBuiltIn {
                    _ = DisplayBrightness.setBuiltInBrightness(clamped, for: id)
                } else {
                    _ = DisplayBrightness.setExternalBrightness(clamped, for: id)
                }
            }
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func readBrightness(for id: CGDirectDisplayID, isBuiltIn: Bool) -> Double? {
        // Only built-in is readable with the private DisplayServices API we ship;
        // external DDC read would need a GET-VCP round-trip we haven't wired up.
        return isBuiltIn ? DisplayBrightness.builtInBrightness(for: id) : nil
    }
}
