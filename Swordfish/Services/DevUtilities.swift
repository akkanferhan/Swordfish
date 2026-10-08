import Foundation
import CryptoKit

/// Pure, side-effect-free converters behind the Dev Utilities window. Kept
/// out of the views so they stay trivially testable.
enum DevUtilities {
    struct ConversionError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - JWT

    struct DecodedJWT {
        let header: String
        let payload: String
        let claims: [String: Any]
        let signature: String

        var expiresAt: Date? { (claims["exp"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } }
        var issuedAt: Date? { (claims["iat"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } }
        var notBefore: Date? { (claims["nbf"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } }
        var isExpired: Bool { expiresAt.map { $0 < Date() } ?? false }
    }

    /// Decodes header + payload. The signature is shown but **not** verified —
    /// that needs the issuer's key, which a debugging tool shouldn't hold.
    static func decodeJWT(_ token: String) throws -> DecodedJWT {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "Bearer ", with: "")
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 || parts.count == 5 else {
            throw ConversionError(message: String(localized: "A JWT has three dot-separated parts"))
        }
        guard let headerData = base64URLDecode(parts[0]),
              let payloadData = base64URLDecode(parts[1]) else {
            throw ConversionError(message: String(localized: "Header or payload is not valid base64url"))
        }
        let header = try prettyJSON(headerData)
        let payload = try prettyJSON(payloadData)
        let claims = (try? JSONSerialization.jsonObject(with: payloadData)) as? [String: Any] ?? [:]
        return DecodedJWT(header: header, payload: payload, claims: claims, signature: parts[2])
    }

    static func base64URLDecode(_ s: String) -> Data? {
        var b64 = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        return Data(base64Encoded: b64)
    }

    // MARK: - JSON

    static func prettyJSON(_ data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let out = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
        )
        return String(decoding: out, as: UTF8.self)
    }

    // MARK: - Timestamps

    struct TimestampResult {
        let date: Date
        /// How the input was read ("seconds", "milliseconds", "ISO 8601"…).
        let interpretation: String
    }

    /// Accepts Unix seconds / milliseconds / microseconds (picked by digit
    /// count) or an ISO 8601 date string.
    static func parseTimestamp(_ input: String) -> TimestampResult? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let value = Double(s) {
            let digits = s.split(separator: ".").first.map { $0.filter(\.isNumber).count } ?? 0
            switch digits {
            case ...11:   return TimestampResult(date: Date(timeIntervalSince1970: value), interpretation: String(localized: "Unix seconds"))
            case 12...14: return TimestampResult(date: Date(timeIntervalSince1970: value / 1_000), interpretation: String(localized: "Unix milliseconds"))
            default:      return TimestampResult(date: Date(timeIntervalSince1970: value / 1_000_000), interpretation: String(localized: "Unix microseconds"))
            }
        }
        let iso = ISO8601DateFormatter()
        for options: ISO8601DateFormatter.Options in [
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime],
            [.withFullDate],
        ] {
            iso.formatOptions = options
            if let date = iso.date(from: s) {
                return TimestampResult(date: date, interpretation: String(localized: "ISO 8601"))
            }
        }
        return nil
    }

    /// Label / value rows for every common representation of `date`.
    static func timestampRows(_ date: Date) -> [(label: String, value: String)] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoLocal = ISO8601DateFormatter()
        isoLocal.formatOptions = [.withInternetDateTime]
        isoLocal.timeZone = .current
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        return [
            (String(localized: "Unix seconds"), String(Int64(date.timeIntervalSince1970.rounded(.down)))),
            (String(localized: "Unix milliseconds"), String(Int64((date.timeIntervalSince1970 * 1_000).rounded(.down)))),
            (String(localized: "ISO 8601 (UTC)"), iso.string(from: date)),
            (String(localized: "ISO 8601 (local)"), isoLocal.string(from: date)),
            (String(localized: "Local"), date.formatted(date: .complete, time: .standard)),
            (String(localized: "Relative"), relative.localizedString(for: date, relativeTo: Date())),
        ]
    }

    // MARK: - Base64

    static func base64Encode(_ text: String, urlSafe: Bool) -> String {
        let encoded = Data(text.utf8).base64EncodedString()
        guard urlSafe else { return encoded }
        return encoded
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64Decode(_ text: String) throws -> String {
        let compact = text.filter { !$0.isWhitespace }
        guard let data = base64URLDecode(compact) else {
            throw ConversionError(message: String(localized: "Not valid base64"))
        }
        guard let string = String(data: data, encoding: .utf8) else {
            throw ConversionError(message: String(localized: "Decoded \(data.count) bytes, but they aren't UTF-8 text"))
        }
        return string
    }

    // MARK: - URL encoding

    /// RFC 3986 unreserved characters — safe for any URL component.
    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func urlEncode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }

    static func urlDecode(_ text: String) throws -> String {
        guard let decoded = text.replacingOccurrences(of: "+", with: " ").removingPercentEncoding else {
            throw ConversionError(message: String(localized: "Malformed percent-encoding"))
        }
        return decoded
    }

    /// Breaks a URL into scheme / host / path / query items — handy for
    /// inspecting deep links and OAuth redirects.
    static func urlComponents(_ text: String) -> [(label: String, value: String)]? {
        guard let c = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              c.scheme != nil else { return nil }
        var rows: [(String, String)] = []
        if let v = c.scheme { rows.append(("scheme", v)) }
        if let v = c.user { rows.append(("user", v)) }
        if let v = c.host { rows.append(("host", v)) }
        if let v = c.port { rows.append(("port", String(v))) }
        if !c.path.isEmpty { rows.append(("path", c.path)) }
        for item in c.queryItems ?? [] { rows.append(("?\(item.name)", item.value ?? "")) }
        if let v = c.fragment { rows.append(("#fragment", v)) }
        return rows
    }

    // MARK: - UUID

    static func uuids(count: Int, lowercase: Bool) -> String {
        (0..<max(1, count))
            .map { _ in lowercase ? UUID().uuidString.lowercased() : UUID().uuidString }
            .joined(separator: "\n")
    }

    // MARK: - Hashes

    static func hashes(_ text: String) -> [(label: String, value: String)] {
        let data = Data(text.utf8)
        func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
            digest.map { String(format: "%02x", $0) }.joined()
        }
        return [
            ("MD5", hex(Insecure.MD5.hash(data: data))),
            ("SHA-1", hex(Insecure.SHA1.hash(data: data))),
            ("SHA-256", hex(SHA256.hash(data: data))),
            ("SHA-512", hex(SHA512.hash(data: data))),
        ]
    }
}

/// Property list ↔ JSON. Plist types JSON can't express are mapped on the
/// way out (Data → base64 string, Date → ISO 8601 string).
enum PlistJSON {
    static func jsonString(fromPlistObject object: Any) throws -> String {
        let safe = jsonSafe(object)
        let data = try JSONSerialization.data(
            withJSONObject: safe,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
        )
        return String(decoding: data, as: UTF8.self)
    }

    /// Parses XML, binary or old-style plist text and returns pretty JSON.
    static func json(fromPlist text: String) throws -> String {
        let object = try PropertyListSerialization.propertyList(from: Data(text.utf8), format: nil)
        return try jsonString(fromPlistObject: object)
    }

    static func xmlPlist(fromJSON text: String) throws -> String {
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
        if containsNull(object) {
            throw DevUtilities.ConversionError(message: String(localized: "Property lists can't contain null values"))
        }
        let data = try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
        return String(decoding: data, as: UTF8.self)
    }

    private static func jsonSafe(_ value: Any) -> Any {
        switch value {
        case let dict as [String: Any]:
            return dict.mapValues(jsonSafe)
        case let array as [Any]:
            return array.map(jsonSafe)
        case let data as Data:
            return data.base64EncodedString()
        case let date as Date:
            return ISO8601DateFormatter().string(from: date)
        default:
            return value
        }
    }

    private static func containsNull(_ value: Any) -> Bool {
        switch value {
        case is NSNull: return true
        case let dict as [String: Any]: return dict.values.contains(where: containsNull)
        case let array as [Any]: return array.contains(where: containsNull)
        default: return false
        }
    }
}
