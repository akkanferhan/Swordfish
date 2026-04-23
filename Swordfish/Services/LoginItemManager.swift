import Foundation
import ServiceManagement

@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var lastError: String?

    init() {
        refresh()
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// Toggle login-at-startup. macOS may show a confirmation dialog
    /// or prompt the user to approve in System Settings on first call.
    func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            refresh()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
