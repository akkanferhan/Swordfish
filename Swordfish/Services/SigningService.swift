import Foundation
import Security
import CryptoKit

struct ProvisioningProfile: Identifiable, Equatable {
    enum Kind: String {
        case development, adHoc, appStore, enterprise, developerID
        var label: String {
            switch self {
            case .development: return String(localized: "Development")
            case .adHoc:       return String(localized: "Ad Hoc")
            case .appStore:    return String(localized: "App Store")
            case .enterprise:  return String(localized: "Enterprise")
            case .developerID: return String(localized: "Developer ID")
            }
        }
    }

    let url: URL
    let uuid: String
    let name: String
    let appIDName: String?
    let bundleID: String
    let teamName: String?
    let teamID: String?
    let platforms: [String]
    let kind: Kind
    let created: Date?
    let expires: Date?
    let isXcodeManaged: Bool
    let devices: [String]
    let entitlementsJSON: String
    /// SHA-1 fingerprints of the certificates the profile allows to sign.
    let certificateFingerprints: Set<String>

    var id: String { url.path }
    var isExpired: Bool { expires.map { $0 < Date() } ?? false }
    var expiresSoon: Bool {
        guard let expires, !isExpired else { return false }
        return expires.timeIntervalSinceNow < 30 * 24 * 3600
    }
}

struct SigningIdentity: Identifiable, Equatable {
    let name: String
    let teamID: String?
    let expires: Date?
    let fingerprint: String

    var id: String { fingerprint }
    var isExpired: Bool { expires.map { $0 < Date() } ?? false }
    var expiresSoon: Bool {
        guard let expires, !isExpired else { return false }
        return expires.timeIntervalSinceNow < 30 * 24 * 3600
    }
}

/// Reads installed provisioning profiles (decoded in-process with
/// CMSDecoder, no `security cms -D` round trip) and the code-signing
/// identities in the login keychain, and cross-references the two so it's
/// obvious when a profile has no usable certificate on this Mac.
@MainActor
final class SigningService: ObservableObject {
    @Published private(set) var profiles: [ProvisioningProfile] = []
    @Published private(set) var identities: [SigningIdentity] = []
    @Published private(set) var isLoading = false
    @Published var lastError: String?

    nonisolated static let profileFolders: [URL] = {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return [
            home.appendingPathComponent("Library/MobileDevice/Provisioning Profiles"),
            home.appendingPathComponent("Library/Developer/Xcode/UserData/Provisioning Profiles"),
        ]
    }()

    var identityFingerprints: Set<String> { Set(identities.map(\.fingerprint)) }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let profiles = Self.loadProfiles()
            let identities = Self.loadIdentities()
            await MainActor.run { [weak self] in
                self?.profiles = profiles
                self?.identities = identities
                self?.isLoading = false
            }
        }
    }

    /// Moves profiles to the Trash rather than deleting — Xcode re-downloads
    /// managed ones anyway, and a manual one is easy to restore.
    func trash(_ targets: [ProvisioningProfile]) {
        lastError = nil
        var failures: [String] = []
        for profile in targets {
            do {
                try FileManager.default.trashItem(at: profile.url, resultingItemURL: nil)
            } catch {
                failures.append("\(profile.name): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty { lastError = failures.joined(separator: "\n") }
        refresh()
    }

    // MARK: - Profiles

    nonisolated private static func loadProfiles() -> [ProvisioningProfile] {
        var seen = Set<String>()
        var result: [ProvisioningProfile] = []
        for folder in profileFolders {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where ["mobileprovision", "provisionprofile"].contains(file.pathExtension) {
                guard let profile = parseProfile(at: file), seen.insert(profile.uuid).inserted else { continue }
                result.append(profile)
            }
        }
        return result.sorted { ($0.expires ?? .distantPast) > ($1.expires ?? .distantPast) }
    }

    nonisolated static func parseProfile(at url: URL) -> ProvisioningProfile? {
        guard let data = try? Data(contentsOf: url),
              let plistData = decodeCMS(data),
              let plist = (try? PropertyListSerialization.propertyList(from: plistData, format: nil)) as? [String: Any]
        else { return nil }

        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        let appID = (entitlements["application-identifier"] as? String)
            ?? (entitlements["com.apple.application-identifier"] as? String)
            ?? ""
        let teamID = (plist["TeamIdentifier"] as? [String])?.first
        // "TEAMID.com.acme.app" → "com.acme.app"
        let bundleID = teamID.flatMap { appID.hasPrefix($0 + ".") ? String(appID.dropFirst($0.count + 1)) : nil } ?? appID
        let devices = plist["ProvisionedDevices"] as? [String] ?? []
        let platforms = plist["Platform"] as? [String] ?? []
        let getTaskAllow = (entitlements["get-task-allow"] as? Bool)
            ?? (entitlements["com.apple.security.get-task-allow"] as? Bool)
            ?? false

        let kind: ProvisioningProfile.Kind
        if plist["ProvisionsAllDevices"] as? Bool == true {
            kind = platforms.contains("OSX") ? .developerID : .enterprise
        } else if !devices.isEmpty {
            kind = getTaskAllow ? .development : .adHoc
        } else {
            kind = getTaskAllow ? .development : .appStore
        }

        let certs = (plist["DeveloperCertificates"] as? [Data] ?? []).map(sha1)
        let entitlementsJSON = (try? PlistJSON.jsonString(fromPlistObject: entitlements)) ?? "{}"

        return ProvisioningProfile(
            url: url,
            uuid: plist["UUID"] as? String ?? url.deletingPathExtension().lastPathComponent,
            name: plist["Name"] as? String ?? url.lastPathComponent,
            appIDName: plist["AppIDName"] as? String,
            bundleID: bundleID,
            teamName: plist["TeamName"] as? String,
            teamID: teamID,
            platforms: platforms,
            kind: kind,
            created: plist["CreationDate"] as? Date,
            expires: plist["ExpirationDate"] as? Date,
            isXcodeManaged: plist["IsXcodeManaged"] as? Bool ?? false,
            devices: devices,
            entitlementsJSON: entitlementsJSON,
            certificateFingerprints: Set(certs)
        )
    }

    /// Strips the CMS (PKCS#7) signature wrapper and returns the embedded plist.
    nonisolated private static func decodeCMS(_ data: Data) -> Data? {
        var decoder: CMSDecoder?
        guard CMSDecoderCreate(&decoder) == errSecSuccess, let decoder else { return nil }
        let updated = data.withUnsafeBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return errSecParam }
            return CMSDecoderUpdateMessage(decoder, base, data.count)
        }
        guard updated == errSecSuccess, CMSDecoderFinalizeMessage(decoder) == errSecSuccess else { return nil }
        var content: CFData?
        guard CMSDecoderCopyContent(decoder, &content) == errSecSuccess, let content else { return nil }
        return content as Data
    }

    nonisolated private static func sha1(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02X", $0) }.joined()
    }

    // MARK: - Identities

    nonisolated private static let signingPrefixes = [
        "Apple Development", "Apple Distribution", "iPhone Developer", "iPhone Distribution",
        "Developer ID Application", "Developer ID Installer", "Mac Developer",
        "3rd Party Mac Developer", "Mac App Distribution", "Mac Installer Distribution",
    ]

    /// Code-signing identities (certificate + private key) in the keychains.
    /// Querying refs doesn't touch the private keys, so no access prompts.
    nonisolated static func loadIdentities() -> [SigningIdentity] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true,
        ]
        var items: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess,
              let identities = items as? [SecIdentity] else { return [] }

        var seen = Set<String>()
        var result: [SigningIdentity] = []
        for identity in identities {
            var cert: SecCertificate?
            guard SecIdentityCopyCertificate(identity, &cert) == errSecSuccess, let cert,
                  let name = SecCertificateCopySubjectSummary(cert) as String?,
                  signingPrefixes.contains(where: { name.hasPrefix($0) })
            else { continue }
            let fingerprint = sha1(SecCertificateCopyData(cert) as Data)
            guard seen.insert(fingerprint).inserted else { continue }
            result.append(SigningIdentity(
                name: name,
                teamID: organizationalUnit(of: cert),
                expires: notAfter(of: cert),
                fingerprint: fingerprint
            ))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    nonisolated private static func notAfter(of cert: SecCertificate) -> Date? {
        let keys = [kSecOIDX509V1ValidityNotAfter] as CFArray
        guard let values = SecCertificateCopyValues(cert, keys, nil) as? [String: Any],
              let entry = values[kSecOIDX509V1ValidityNotAfter as String] as? [String: Any],
              let seconds = entry[kSecPropertyKeyValue as String] as? NSNumber
        else { return nil }
        return Date(timeIntervalSinceReferenceDate: seconds.doubleValue)
    }

    /// Apple puts the Team ID in the subject's OU field.
    nonisolated private static func organizationalUnit(of cert: SecCertificate) -> String? {
        let keys = [kSecOIDX509V1SubjectName] as CFArray
        guard let values = SecCertificateCopyValues(cert, keys, nil) as? [String: Any],
              let subject = values[kSecOIDX509V1SubjectName as String] as? [String: Any],
              let fields = subject[kSecPropertyKeyValue as String] as? [[String: Any]]
        else { return nil }
        let ou = fields.first { ($0[kSecPropertyKeyLabel as String] as? String) == (kSecOIDOrganizationalUnitName as String) }
        return ou?[kSecPropertyKeyValue as String] as? String
    }
}
