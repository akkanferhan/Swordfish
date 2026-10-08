import Foundation
import SwiftUI

@MainActor
final class DevToolsState: ObservableObject {
    // JSON Formatter
    @Published var jsonInput: String = ""

    // Color Picker — last sampled
    @Published var pickedColor: NSColor? = nil

    // Dev Utilities — a tool + input handed over from elsewhere (e.g. a
    // clipboard smart action). The window consumes and clears it.
    @Published var utilityRequest: UtilityRequest? = nil

    struct UtilityRequest: Equatable {
        enum Tool: Equatable { case jwt, timestamp, base64 }
        let tool: Tool
        let input: String
    }
}
