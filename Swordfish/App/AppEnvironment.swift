import Foundation
import SwiftUI

/// Shared application state / service container. Additional services are
/// plugged in by their respective feature branches.
@MainActor
final class AppEnvironment: ObservableObject {
    let systemMonitor: SystemMonitor
    let displayController: DisplayController
    let caffeine: CaffeineService
    let clipboard: ClipboardService
    let devTools: DevToolsState
    let loginItem: LoginItemManager

    @Published var selectedTab: PopoverTab = .systemHub

    init(
        systemMonitor: SystemMonitor,
        displayController: DisplayController,
        caffeine: CaffeineService,
        clipboard: ClipboardService,
        devTools: DevToolsState,
        loginItem: LoginItemManager
    ) {
        self.systemMonitor = systemMonitor
        self.displayController = displayController
        self.caffeine = caffeine
        self.clipboard = clipboard
        self.devTools = devTools
        self.loginItem = loginItem
    }

    static func makeDefault() -> AppEnvironment {
        let forceMock = ProcessInfo.processInfo.environment["SWORDFISH_MOCK_SENSORS"] == "1"
        let sensors: HardwareSensorService = forceMock
            ? MockHardwareSensorService()
            : IOKitHardwareSensorService()

        let monitor = SystemMonitor(sensors: sensors)
        let displays = DisplayController()
        let caffeine = CaffeineService()
        let clipboard = ClipboardService()
        let devTools = DevToolsState()
        let loginItem = LoginItemManager()

        monitor.start()
        clipboard.start()

        return AppEnvironment(
            systemMonitor: monitor,
            displayController: displays,
            caffeine: caffeine,
            clipboard: clipboard,
            devTools: devTools,
            loginItem: loginItem
        )
    }
}
