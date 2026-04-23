import Foundation
import IOKit
import IOKit.pwr_mgt

@MainActor
final class CaffeineService: ObservableObject {
    enum Duration: Int, CaseIterable, Identifiable {
        case indefinite = 0, fifteenMin = 900, oneHour = 3600, twoHours = 7200, fiveHours = 18000
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .indefinite: return "∞"
            case .fifteenMin: return "15m"
            case .oneHour:    return "1h"
            case .twoHours:   return "2h"
            case .fiveHours:  return "5h"
            }
        }
    }

    @Published private(set) var isEnabled = false
    @Published var duration: Duration = .indefinite
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var expiresAt: Date?

    private var assertionID: IOPMAssertionID = IOPMAssertionID(0)
    private var timer: Timer?

    func toggle() {
        isEnabled ? disable() : enable()
    }

    func enable() {
        guard !isEnabled else { return }
        var id = IOPMAssertionID(0)
        let reason = "Swordfish — preventing sleep" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason, &id
        )
        guard result == kIOReturnSuccess else { return }
        assertionID = id
        isEnabled = true
        if duration != .indefinite {
            expiresAt = Date().addingTimeInterval(TimeInterval(duration.rawValue))
        } else {
            expiresAt = nil
        }
        scheduleTick()
    }

    func disable() {
        guard isEnabled else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = IOPMAssertionID(0)
        isEnabled = false
        expiresAt = nil
        remaining = 0
        timer?.invalidate()
        timer = nil
    }

    func setDuration(_ newValue: Duration) {
        duration = newValue
        if isEnabled {
            if newValue == .indefinite {
                expiresAt = nil
                remaining = 0
            } else {
                expiresAt = Date().addingTimeInterval(TimeInterval(newValue.rawValue))
                remaining = TimeInterval(newValue.rawValue)
            }
        }
    }

    private func scheduleTick() {
        timer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        self.timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    private func tick() {
        guard let expiresAt else { return }
        remaining = max(0, expiresAt.timeIntervalSinceNow)
        if remaining == 0 { disable() }
    }
}
