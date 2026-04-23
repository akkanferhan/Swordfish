import Foundation
import SwiftUI

@MainActor
final class DevToolsState: ObservableObject {
    // JSON Formatter
    @Published var jsonInput: String = ""

    // Color Picker — last sampled
    @Published var pickedColor: NSColor? = nil
}
