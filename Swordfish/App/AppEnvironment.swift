import Foundation
import SwiftUI

/// Shared application state / service container. Additional services are
/// plugged in by their respective feature branches.
@MainActor
final class AppEnvironment: ObservableObject {
    let loginItem: LoginItemManager

    @Published var selectedTab: PopoverTab = .systemHub

    init(loginItem: LoginItemManager) {
        self.loginItem = loginItem
    }

    static func makeDefault() -> AppEnvironment {
        AppEnvironment(loginItem: LoginItemManager())
    }
}
