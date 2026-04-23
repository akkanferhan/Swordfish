import Foundation

/// Converts a parsed JSON value into a Swift type declaration string.
/// Produces one struct per discovered object type, with Codable conformance
/// and CodingKeys when property names are renamed (snake_case → camelCase).
enum JSONToSwift {

    struct Options {
        var rootName: String = "Root"
        var codable: Bool = true
        var snakeToCamel: Bool = true
    }

    enum GenerationError: LocalizedError {
        case invalidJSON(String)
        var errorDescription: String? {
            switch self {
            case .invalidJSON(let msg): return "Invalid JSON: \(msg)"
            }
        }
    }

    /// Parse + generate. `input` is the raw JSON text.
    static func generate(from input: String, options: Options) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = input.data(using: .utf8) else {
            return "// Paste JSON to see the generated Swift.\n"
        }
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data, options: [.allowFragments])
        } catch {
            throw GenerationError.invalidJSON((error as NSError).localizedDescription)
        }
        var generator = Generator(options: options)
        _ = generator.infer(parsed, suggestedName: options.rootName)
        return generator.render()
    }
}

// MARK: - Generator

private struct Generator {
    let options: JSONToSwift.Options
    var structs: [StructDef] = []

    struct StructDef {
        var name: String
        var properties: [Property]
    }

    struct Property {
        var jsonKey: String
        var swiftName: String
        var type: String
    }

    mutating func infer(_ value: Any, suggestedName: String) -> String {
        if value is NSNull { return "String?" }
        if value is String { return "String" }
        if let num = value as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() { return "Bool" }
            let type = String(cString: num.objCType)
            if ["q", "i", "l", "s", "c", "Q", "I", "L", "S", "C"].contains(type) { return "Int" }
            return "Double"
        }
        if let arr = value as? [Any] {
            if arr.isEmpty { return "[String]" }
            let elementName = Self.singularize(suggestedName)
            let elementType = infer(arr[0], suggestedName: elementName)
            return "[\(elementType)]"
        }
        if let dict = value as? [String: Any] {
            let typeName = uniqueTypeName(Self.pascalCase(suggestedName))
            var props: [Property] = []
            for key in dict.keys.sorted() {
                guard let propValue = dict[key] else { continue }
                let childSuggestion = Self.pascalCase(key)
                let propType = infer(propValue, suggestedName: childSuggestion)
                let swiftName = options.snakeToCamel ? Self.camelCase(key) : key
                props.append(Property(
                    jsonKey: key,
                    swiftName: Self.escapeKeyword(swiftName),
                    type: propType
                ))
            }
            structs.append(StructDef(name: typeName, properties: props))
            return typeName
        }
        return "String?"
    }

    mutating func uniqueTypeName(_ base: String) -> String {
        let sanitized = base.isEmpty ? "Item" : base
        if !structs.contains(where: { $0.name == sanitized }) { return sanitized }
        var i = 2
        while structs.contains(where: { $0.name == "\(sanitized)\(i)" }) { i += 1 }
        return "\(sanitized)\(i)"
    }

    func render() -> String {
        // structs are appended post-order (children first). Reverse so root is on top.
        let rendered = structs.reversed().map(renderStruct).joined(separator: "\n")
        return "import Foundation\n\n" + rendered
    }

    private func renderStruct(_ def: StructDef) -> String {
        var out = ""
        let conformance = options.codable ? ": Codable" : ""
        out += "struct \(def.name)\(conformance) {\n"
        for prop in def.properties {
            out += "    let \(prop.swiftName): \(prop.type)\n"
        }
        let renamed = def.properties.filter { unescape($0.swiftName) != $0.jsonKey }
        if options.codable, !renamed.isEmpty {
            out += "\n    enum CodingKeys: String, CodingKey {\n"
            for prop in def.properties {
                let swiftBare = unescape(prop.swiftName)
                if swiftBare == prop.jsonKey {
                    out += "        case \(prop.swiftName)\n"
                } else {
                    out += "        case \(prop.swiftName) = \"\(prop.jsonKey)\"\n"
                }
            }
            out += "    }\n"
        }
        out += "}\n"
        return out
    }

    private func unescape(_ s: String) -> String {
        s.hasPrefix("`") && s.hasSuffix("`") ? String(s.dropFirst().dropLast()) : s
    }

    // MARK: - String helpers

    static func camelCase(_ s: String) -> String {
        let parts = splitIdentifier(s)
        guard let first = parts.first else { return s }
        let head = first.lowercasedPreservingAcronym()
        let tail = parts.dropFirst().map { $0.capitalizedFirst }
        let joined = head + tail.joined()
        return joined.isEmpty ? s : joined
    }

    static func pascalCase(_ s: String) -> String {
        let parts = splitIdentifier(s)
        let joined = parts.map { $0.capitalizedFirst }.joined()
        return joined.isEmpty ? s : joined
    }

    private static func splitIdentifier(_ s: String) -> [String] {
        // split on non-alphanumeric and on case transitions
        var parts: [String] = []
        var current = ""
        for ch in s {
            if ch.isLetter || ch.isNumber {
                if ch.isUppercase, !current.isEmpty, current.last!.isLowercase {
                    parts.append(current); current = String(ch); continue
                }
                current.append(ch)
            } else {
                if !current.isEmpty { parts.append(current); current = "" }
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    static func singularize(_ s: String) -> String {
        if s.lowercased().hasSuffix("ies"), s.count > 3 {
            return String(s.dropLast(3)) + "y"
        }
        if s.lowercased().hasSuffix("s"), s.count > 1 {
            return String(s.dropLast())
        }
        return s + "Item"
    }

    private static let swiftKeywords: Set<String> = [
        "associatedtype","class","deinit","enum","extension","fileprivate","func","import",
        "init","inout","internal","let","open","operator","private","precedencegroup",
        "protocol","public","rethrows","static","struct","subscript","typealias","var",
        "break","case","catch","continue","default","defer","do","else","fallthrough","for",
        "guard","if","in","repeat","return","throw","switch","where","while","Any","as",
        "false","is","nil","self","Self","super","throws","true","try","Type","Protocol"
    ]

    static func escapeKeyword(_ name: String) -> String {
        if swiftKeywords.contains(name) { return "`\(name)`" }
        if let first = name.first, first.isNumber { return "_\(name)" }
        if name.isEmpty { return "_" }
        return name
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst()
    }
    func lowercasedPreservingAcronym() -> String {
        // If all uppercase (ACRONYM), keep lowercase. Otherwise lowercase first char only.
        if self == self.uppercased(), count > 1 { return lowercased() }
        guard let first = first else { return self }
        return String(first).lowercased() + dropFirst()
    }
}
