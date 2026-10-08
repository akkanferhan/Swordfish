import Foundation

struct ASCBuild: Identifiable, Equatable {
    enum State: String {
        case processing = "PROCESSING", valid = "VALID", failed = "FAILED", invalid = "INVALID", unknown

        var label: String {
            switch self {
            case .processing: return String(localized: "Processing")
            case .valid:      return String(localized: "Ready")
            case .failed:     return String(localized: "Failed")
            case .invalid:    return String(localized: "Invalid")
            case .unknown:    return "—"
            }
        }
    }

    let id: String
    let appID: String
    let appName: String
    let bundleID: String
    let marketingVersion: String
    let buildNumber: String
    let platform: String
    let uploaded: Date?
    let state: State
    let expired: Bool

    var title: String { "\(marketingVersion) (\(buildNumber))" }
    var testFlightURL: URL? {
        URL(string: "https://appstoreconnect.apple.com/apps/\(appID)/testflight/\(platform == "MAC_OS" ? "macos" : "ios")")
    }
}

enum ASCSettings {
    static let notifyKey = "asc.notifyProcessing"
    static func register() {
        UserDefaults.standard.register(defaults: [notifyKey: true])
    }
}

/// Polls the App Store Connect API for recent builds and reports when one
/// finishes processing (the "is it in TestFlight yet?" loop).
@MainActor
final class AppStoreConnectMonitor: ObservableObject {
    @Published private(set) var builds: [ASCBuild] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastUpdated: Date?

    var onStateChange: ((ASCBuild, ASCBuild.State) -> Void)?

    private var timer: Timer?
    private var knownStates: [String: ASCBuild.State] = [:]

    var hasKey: Bool { AppleKeys.hasKey(.appStoreConnect) }

    func start() {
        ASCSettings.register()
        refresh()
        let t = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        guard hasKey, !isLoading else { return }
        isLoading = true
        Task {
            do {
                let fresh = try await Self.fetchBuilds()
                for build in fresh {
                    if let previous = knownStates[build.id], previous != build.state {
                        onStateChange?(build, previous)
                    }
                    knownStates[build.id] = build.state
                }
                builds = fresh
                lastError = nil
                lastUpdated = Date()
            } catch {
                lastError = error.localizedDescription
            }
            isLoading = false
        }
    }

    // MARK: - API

    nonisolated private static func token() throws -> String {
        let d = UserDefaults.standard
        guard let issuer = d.string(forKey: AppleKeys.ascIssuerIDKey), !issuer.isEmpty,
              let keyID = d.string(forKey: AppleKeys.ascKeyIDKey), !keyID.isEmpty,
              let pem = AppleKeys.privateKey(.appStoreConnect) else {
            throw AppleAPIError(message: String(localized: "Add your App Store Connect API key in Settings → Developer Keys"))
        }
        let now = Int(Date().timeIntervalSince1970)
        return try AppleJWT.make(keyID: keyID, issuer: issuer, privateKeyPEM: pem,
                                 extraHeader: ["typ": "JWT"],
                                 extraClaims: ["iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"])
    }

    nonisolated static func fetchBuilds() async throws -> [ASCBuild] {
        var components = URLComponents(string: "https://api.appstoreconnect.apple.com/v1/builds")!
        components.queryItems = [
            URLQueryItem(name: "sort", value: "-uploadedDate"),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "include", value: "app,preReleaseVersion"),
            URLQueryItem(name: "fields[builds]", value: "version,uploadedDate,processingState,expired,app,preReleaseVersion"),
            URLQueryItem(name: "fields[apps]", value: "name,bundleId"),
            URLQueryItem(name: "fields[preReleaseVersions]", value: "version,platform"),
        ]
        let bearer = try token()
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status == 200 else {
            let detail = (json["errors"] as? [[String: Any]])?.first?["detail"] as? String
            throw AppleAPIError(message: "App Store Connect: HTTP \(status)" + (detail.map { " — \($0)" } ?? ""))
        }

        var apps: [String: (name: String, bundleID: String)] = [:]
        var versions: [String: (version: String, platform: String)] = [:]
        for item in json["included"] as? [[String: Any]] ?? [] {
            guard let id = item["id"] as? String, let attributes = item["attributes"] as? [String: Any] else { continue }
            switch item["type"] as? String {
            case "apps":
                apps[id] = (attributes["name"] as? String ?? "?", attributes["bundleId"] as? String ?? "")
            case "preReleaseVersions":
                versions[id] = (attributes["version"] as? String ?? "?", attributes["platform"] as? String ?? "IOS")
            default:
                break
            }
        }

        let iso = ISO8601DateFormatter()
        return (json["data"] as? [[String: Any]] ?? []).compactMap { item -> ASCBuild? in
            guard let id = item["id"] as? String, let attributes = item["attributes"] as? [String: Any] else { return nil }
            let relationships = item["relationships"] as? [String: Any] ?? [:]
            func relatedID(_ key: String) -> String? {
                ((relationships[key] as? [String: Any])?["data"] as? [String: Any])?["id"] as? String
            }
            let appID = relatedID("app") ?? ""
            let version = relatedID("preReleaseVersion").flatMap { versions[$0] }
            return ASCBuild(
                id: id,
                appID: appID,
                appName: apps[appID]?.name ?? "?",
                bundleID: apps[appID]?.bundleID ?? "",
                marketingVersion: version?.version ?? "?",
                buildNumber: attributes["version"] as? String ?? "?",
                platform: version?.platform ?? "IOS",
                uploaded: (attributes["uploadedDate"] as? String).flatMap { iso.date(from: $0) },
                state: ASCBuild.State(rawValue: attributes["processingState"] as? String ?? "") ?? .unknown,
                expired: attributes["expired"] as? Bool ?? false
            )
        }
    }
}
