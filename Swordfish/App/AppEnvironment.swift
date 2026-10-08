import Foundation
import SwiftUI

/// Shared application state / service container. Additional services are
/// plugged in by their respective feature branches.
@MainActor
final class AppEnvironment: ObservableObject {
    let systemMonitor: SystemMonitor
    let displayController: DisplayController
    let caffeine: CaffeineService
    let lidSleep: LidSleepService
    let clipboard: ClipboardService
    let devTools: DevToolsState
    let loginItem: LoginItemManager
    let alerts: AlertService
    let builds: BuildMonitor
    let appStoreConnect: AppStoreConnectMonitor

    @Published var selectedTab: PopoverTab = .systemHub

    init(
        systemMonitor: SystemMonitor,
        displayController: DisplayController,
        caffeine: CaffeineService,
        lidSleep: LidSleepService,
        clipboard: ClipboardService,
        devTools: DevToolsState,
        loginItem: LoginItemManager,
        alerts: AlertService,
        builds: BuildMonitor,
        appStoreConnect: AppStoreConnectMonitor
    ) {
        self.systemMonitor = systemMonitor
        self.displayController = displayController
        self.caffeine = caffeine
        self.lidSleep = lidSleep
        self.clipboard = clipboard
        self.devTools = devTools
        self.loginItem = loginItem
        self.alerts = alerts
        self.builds = builds
        self.appStoreConnect = appStoreConnect
    }

    static func makeDefault() -> AppEnvironment {
        let forceMock = ProcessInfo.processInfo.environment["SWORDFISH_MOCK_SENSORS"] == "1"
        let sensors: HardwareSensorService = forceMock
            ? MockHardwareSensorService()
            : IOKitHardwareSensorService()

        let monitor = SystemMonitor(sensors: sensors)
        let displays = DisplayController()
        let caffeine = CaffeineService()
        let lidSleep = LidSleepService()
        let clipboard = ClipboardService()
        let devTools = DevToolsState()
        let loginItem = LoginItemManager()
        let alerts = AlertService(monitor: monitor)
        let builds = BuildMonitor()
        builds.onFinished = { [weak alerts] record, slower in
            alerts?.announceBuild(record, slowerThanUsual: slower)
        }
        let appStoreConnect = AppStoreConnectMonitor()
        appStoreConnect.onStateChange = { [weak alerts] build, previous in
            alerts?.announceASC(build, previous: previous)
        }

        monitor.start()
        clipboard.start()
        alerts.start()
        builds.start()
        appStoreConnect.start()

        return AppEnvironment(
            systemMonitor: monitor,
            displayController: displays,
            caffeine: caffeine,
            lidSleep: lidSleep,
            clipboard: clipboard,
            devTools: devTools,
            loginItem: loginItem,
            alerts: alerts,
            builds: builds,
            appStoreConnect: appStoreConnect
        )
    }
}
