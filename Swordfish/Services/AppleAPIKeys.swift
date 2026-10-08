import Foundation
import Security
import CryptoKit

// MARK: - Keychain

/// Small wrapper around generic-password items for the .p8 private keys —
/// they never go to UserDefaults or disk in plain text.
enum KeychainStore {
    private static let service = "dev.swordfish.apple-keys"

    static func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AppleAPIError(message: SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)")
        }
    }

    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct AppleAPIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Key settings

/// IDs live in UserDefaults; the .p8 contents live in the Keychain.
enum AppleKeys {
    enum Kind: String {
        case apns, appStoreConnect = "asc"
        var keychainAccount: String { "\(rawValue).p8" }
    }

    static let apnsTeamIDKey = "keys.apns.teamID"
    static let apnsKeyIDKey = "keys.apns.keyID"
    static let ascIssuerIDKey = "keys.asc.issuerID"
    static let ascKeyIDKey = "keys.asc.keyID"

    static func privateKey(_ kind: Kind) -> String? { KeychainStore.load(account: kind.keychainAccount) }

    static func hasKey(_ kind: Kind) -> Bool {
        let d = UserDefaults.standard
        switch kind {
        case .apns:
            return !(d.string(forKey: apnsTeamIDKey) ?? "").isEmpty
                && !(d.string(forKey: apnsKeyIDKey) ?? "").isEmpty
                && privateKey(.apns) != nil
        case .appStoreConnect:
            return !(d.string(forKey: ascIssuerIDKey) ?? "").isEmpty
                && !(d.string(forKey: ascKeyIDKey) ?? "").isEmpty
                && privateKey(.appStoreConnect) != nil
        }
    }

    /// Validates that the text is a P-256 private key before storing it.
    static func storePrivateKey(_ pem: String, for kind: Kind) throws {
        _ = try signingKey(pem)
        try KeychainStore.save(pem, account: kind.keychainAccount)
    }

    static func signingKey(_ pem: String) throws -> P256.Signing.PrivateKey {
        do {
            return try P256.Signing.PrivateKey(pemRepresentation: pem.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            throw AppleAPIError(message: String(localized: "Not a valid .p8 (P-256) private key"))
        }
    }
}

// MARK: - JWT

/// ES256 JSON Web Tokens as APNs and the App Store Connect API expect them.
enum AppleJWT {
    static func make(keyID: String, issuer: String, privateKeyPEM: String,
                     extraHeader: [String: Any] = [:], extraClaims: [String: Any] = [:]) throws -> String {
        let key = try AppleKeys.signingKey(privateKeyPEM)
        var header: [String: Any] = ["alg": "ES256", "kid": keyID]
        header.merge(extraHeader) { $1 }
        var claims: [String: Any] = ["iss": issuer, "iat": Int(Date().timeIntervalSince1970)]
        claims.merge(extraClaims) { $1 }

        let headerPart = try base64URL(JSONSerialization.data(withJSONObject: header, options: [.sortedKeys]))
        let claimsPart = try base64URL(JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys]))
        let signingInput = "\(headerPart).\(claimsPart)"
        // JWS ES256 wants the raw 64-byte r‖s signature, not DER.
        let signature = try key.signature(for: Data(signingInput.utf8)).rawRepresentation
        return "\(signingInput).\(base64URL(signature))"
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - APNs

enum APNsClient {
    enum Environment: String, CaseIterable, Identifiable {
        case sandbox, production
        var id: String { rawValue }
        var host: String { self == .sandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com" }
        var label: String { self == .sandbox ? String(localized: "Sandbox (debug builds)") : String(localized: "Production (TestFlight / App Store)") }
    }

    struct Result {
        let status: Int
        let apnsID: String?
        let reason: String?
        var ok: Bool { status == 200 }
    }

    /// APNs accepts a provider token for up to an hour; refresh well before.
    private static var cachedToken: (value: String, keyID: String, created: Date)?

    static func send(deviceToken: String, topic: String, payload: Data,
                     environment: Environment) async throws -> Result {
        let defaults = UserDefaults.standard
        guard let teamID = defaults.string(forKey: AppleKeys.apnsTeamIDKey), !teamID.isEmpty,
              let keyID = defaults.string(forKey: AppleKeys.apnsKeyIDKey), !keyID.isEmpty,
              let pem = AppleKeys.privateKey(.apns) else {
            throw AppleAPIError(message: String(localized: "Add your APNs key in Settings → Developer Keys"))
        }
        let token: String
        if let cached = cachedToken, cached.keyID == keyID, Date().timeIntervalSince(cached.created) < 40 * 60 {
            token = cached.value
        } else {
            token = try AppleJWT.make(keyID: keyID, issuer: teamID, privateKeyPEM: pem)
            cachedToken = (token, keyID, Date())
        }

        let cleanToken = deviceToken.filter(\.isHexDigit).lowercased()
        guard cleanToken.count >= 64 else {
            throw AppleAPIError(message: String(localized: "Device token should be at least 64 hex characters"))
        }
        guard let url = URL(string: "https://\(environment.host)/3/device/\(cleanToken)") else {
            throw AppleAPIError(message: "Bad URL")
        }

        // Background pushes (content-available only) must use type background + priority 5.
        let object = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any]
        let aps = object?["aps"] as? [String: Any] ?? [:]
        let isBackground = aps["alert"] == nil && aps["sound"] == nil && aps["badge"] == nil
            && (aps["content-available"] as? Int) == 1

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("bearer \(token)", forHTTPHeaderField: "authorization")
        request.setValue(topic, forHTTPHeaderField: "apns-topic")
        request.setValue(isBackground ? "background" : "alert", forHTTPHeaderField: "apns-push-type")
        request.setValue(isBackground ? "5" : "10", forHTTPHeaderField: "apns-priority")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let reason = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["reason"] as? String
        return Result(status: http?.statusCode ?? 0,
                      apnsID: http?.value(forHTTPHeaderField: "apns-id"),
                      reason: reason)
    }

    /// APNs' terse reason codes, explained.
    static func explain(_ reason: String) -> String {
        switch reason {
        case "BadDeviceToken":         return String(localized: "BadDeviceToken — wrong token, or sandbox/production mismatch")
        case "DeviceTokenNotForTopic": return String(localized: "DeviceTokenNotForTopic — token belongs to another bundle ID")
        case "TopicDisallowed":        return String(localized: "TopicDisallowed — the key's team can't push to this bundle ID")
        case "InvalidProviderToken":   return String(localized: "InvalidProviderToken — check Team ID, Key ID and the .p8")
        case "ExpiredProviderToken":   return String(localized: "ExpiredProviderToken — Mac clock is off, or token older than 1 h")
        case "Unregistered":           return String(localized: "Unregistered — the app was uninstalled or the token is stale")
        case "PayloadTooLarge":        return String(localized: "PayloadTooLarge — payload is over 4 KB")
        case "TooManyProviderTokenUpdates": return String(localized: "TooManyProviderTokenUpdates — wait a few minutes")
        default:                       return reason
        }
    }
}
