import Foundation

enum PopoverTab: String, CaseIterable, Identifiable {
    case systemHub = "System"
    case devKit = "Dev Kit"
    case productivity = "Clipboard"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .systemHub:    return "gauge.medium"
        case .devKit:       return "curlybraces"
        case .productivity: return "list.clipboard"
        }
    }
}
