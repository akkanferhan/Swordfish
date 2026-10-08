import Foundation

/// One key of an app's standard UserDefaults domain inside a simulator.
struct DefaultsEntry: Identifiable, Equatable {
    enum ValueType: String, CaseIterable, Identifiable {
        case string, integer, float, boolean, date, data, array, dictionary
        var id: String { rawValue }
        var isEditable: Bool { [.string, .integer, .float, .boolean, .date].contains(self) }
        var label: String {
            switch self {
            case .string:     return "String"
            case .integer:    return "Integer"
            case .float:      return "Float"
            case .boolean:    return "Boolean"
            case .date:       return "Date"
            case .data:       return "Data"
            case .array:      return "Array"
            case .dictionary: return "Dictionary"
            }
        }
        /// `defaults write` type flag.
        var flag: String? {
            switch self {
            case .string:  return "-string"
            case .integer: return "-int"
            case .float:   return "-float"
            case .boolean: return "-bool"
            case .date:    return "-date"
            default:       return nil
            }
        }
    }

    let key: String
    let type: ValueType
    /// Editable text form (dates as ISO 8601, collections as JSON).
    let display: String

    var id: String { key }
}

/// Reads and edits an app's UserDefaults inside a booted simulator through
/// `simctl spawn <udid> defaults …`, which goes through the simulator's
/// cfprefsd — so a terminated app sees the change on next launch.
enum SimulatorDefaults {
    static func read(udid: String, bundleID: String) throws -> [DefaultsEntry] {
        let r = try ProcessRunner.run("/usr/bin/xcrun", arguments: ["simctl", "spawn", udid, "defaults", "export", bundleID, "-"])
        guard r.exitCode == 0 else {
            throw SimulatorToolbox.CommandError(message: r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let dict = (try? PropertyListSerialization.propertyList(from: Data(r.stdout.utf8), format: nil)) as? [String: Any] else {
            return []
        }
        return dict.map { key, value in entry(key: key, value: value) }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }

    static func write(udid: String, bundleID: String, key: String, type: DefaultsEntry.ValueType, value: String) throws {
        guard let flag = type.flag else {
            throw SimulatorToolbox.CommandError(message: String(localized: "\(type.label) values can't be edited here"))
        }
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch type {
        case .integer:
            guard Int(text) != nil else { throw SimulatorToolbox.CommandError(message: String(localized: "Not an integer")) }
        case .float:
            guard Double(text) != nil else { throw SimulatorToolbox.CommandError(message: String(localized: "Not a number")) }
        case .boolean:
            guard ["true", "false", "yes", "no", "1", "0"].contains(text.lowercased()) else {
                throw SimulatorToolbox.CommandError(message: String(localized: "Use true or false"))
            }
        case .date:
            // `defaults write -date` takes "yyyy-MM-dd HH:mm:ss +0000".
            guard let date = ISO8601DateFormatter().date(from: text) else {
                throw SimulatorToolbox.CommandError(message: String(localized: "Use an ISO 8601 date, e.g. 2026-01-31T12:00:00Z"))
            }
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.timeZone = TimeZone(identifier: "UTC")
            fmt.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
            text = fmt.string(from: date)
        default:
            break
        }
        try SimulatorToolbox.simctl(["spawn", udid, "defaults", "write", bundleID, key, flag, text])
    }

    static func delete(udid: String, bundleID: String, key: String) throws {
        try SimulatorToolbox.simctl(["spawn", udid, "defaults", "delete", bundleID, key])
    }

    private static func entry(key: String, value: Any) -> DefaultsEntry {
        switch value {
        case let b as Bool where CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID():
            return DefaultsEntry(key: key, type: .boolean, display: b ? "true" : "false")
        case let n as NSNumber:
            let isFloat = CFNumberIsFloatType(n as CFNumber)
            return DefaultsEntry(key: key, type: isFloat ? .float : .integer, display: n.stringValue)
        case let s as String:
            return DefaultsEntry(key: key, type: .string, display: s)
        case let d as Date:
            return DefaultsEntry(key: key, type: .date, display: ISO8601DateFormatter().string(from: d))
        case let data as Data:
            return DefaultsEntry(key: key, type: .data, display: String(localized: "\(data.count) bytes"))
        case is [Any]:
            return DefaultsEntry(key: key, type: .array, display: (try? PlistJSON.jsonString(fromPlistObject: value)) ?? "[…]")
        default:
            return DefaultsEntry(key: key, type: .dictionary, display: (try? PlistJSON.jsonString(fromPlistObject: value)) ?? "{…}")
        }
    }
}
