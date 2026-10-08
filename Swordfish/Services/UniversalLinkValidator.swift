import Foundation

/// Fetches and checks a domain's apple-app-site-association (AASA) file —
/// from the origin *and* Apple's CDN, which is what devices actually read —
/// and evaluates which app (if any) a given URL would open.
enum UniversalLinkValidator {
    struct Check: Identifiable {
        enum Level { case pass, warn, fail }
        let id = UUID()
        let level: Level
        let message: String
    }

    struct AppEntry: Identifiable {
        let id = UUID()
        let appIDs: [String]
        /// Human-readable rules in file order ("/products/*", "NOT /admin/*", "? ref=*"…).
        let rules: [String]
    }

    struct Report {
        let host: String
        let source: URL?
        var checks: [Check] = []
        var apps: [AppEntry] = []
        var webCredentials: [String] = []
        var appClips: [String] = []
        /// Result for the test URL's path: matching app IDs, or nil when no URL path was given.
        var match: MatchResult?
        var rawJSON: String?
    }

    enum MatchResult {
        case opens([String], rule: String)
        case excluded(rule: String)
        case noMatch
    }

    // MARK: - Entry point

    static func validate(_ input: String) async -> Report {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: withScheme), let host = components.host, !host.isEmpty else {
            var report = Report(host: trimmed, source: nil)
            report.checks.append(Check(level: .fail, message: String(localized: "Enter a domain or an https:// URL")))
            return report
        }

        var report = Report(host: host, source: nil)
        if components.scheme != "https" {
            report.checks.append(Check(level: .fail, message: String(localized: "Universal Links only work over https")))
        }

        // Origin: /.well-known first, root path as the legacy fallback.
        var originData: Data?
        for path in ["/.well-known/apple-app-site-association", "/apple-app-site-association"] {
            guard let url = URL(string: "https://\(host)\(path)") else { continue }
            let result = await fetch(url)
            switch result {
            case .success(let response):
                originData = response.data
                report = Report(host: host, source: url, checks: report.checks)
                report.checks.append(Check(level: .pass, message: String(localized: "Served at \(path) (HTTP 200)")))
                if path != "/.well-known/apple-app-site-association" {
                    report.checks.append(Check(level: .warn, message: String(localized: "Only found at the root path — move it to /.well-known/")))
                }
                if !response.contentType.lowercased().contains("json") {
                    report.checks.append(Check(level: .warn, message: String(localized: "Content-Type is \(response.contentType.isEmpty ? "missing" : response.contentType), expected application/json")))
                }
                if response.data.count > 128 * 1024 {
                    report.checks.append(Check(level: .fail, message: String(localized: "File is \(response.data.count / 1024) KB — Apple's limit is 128 KB")))
                }
            case .redirected(let target):
                report.checks.append(Check(level: .fail, message: String(localized: "\(path) redirects to \(target) — Apple does not follow redirects")))
            case .failed(let message):
                report.checks.append(Check(level: path.hasPrefix("/.well-known") ? .warn : .fail, message: "\(path): \(message)"))
            }
            if originData != nil { break }
        }

        // Apple's CDN copy — devices fetch this, not the origin.
        var cdnData: Data?
        if let cdnURL = URL(string: "https://app-site-association.cdn-apple.com/a/v1/\(host)") {
            switch await fetch(cdnURL) {
            case .success(let response):
                cdnData = response.data
                report.checks.append(Check(level: .pass, message: String(localized: "Apple CDN has a copy")))
            case .redirected, .failed:
                report.checks.append(Check(level: .warn, message: String(localized: "Apple CDN has no copy yet — devices can't use the links until it does")))
            }
        }

        guard let data = originData ?? cdnData else { return report }
        if let origin = originData, let cdn = cdnData, normalized(origin) != normalized(cdn) {
            report.checks.append(Check(level: .warn, message: String(localized: "Apple CDN copy differs from your server (CDN refreshes within ~24 h)")))
        }

        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            report.checks.append(Check(level: .fail, message: String(localized: "File is not valid JSON")))
            return report
        }
        report.checks.append(Check(level: .pass, message: String(localized: "Valid JSON")))
        report.rawJSON = (try? DevUtilities.prettyJSON(data))

        parse(json, into: &report)

        // Path to test, when the user gave more than a bare domain.
        let path = components.percentEncodedPath
        if !path.isEmpty && path != "/" || components.query != nil {
            report.match = match(path: path.isEmpty ? "/" : path,
                                 query: components.query,
                                 fragment: components.fragment,
                                 json: json)
        }
        return report
    }

    // MARK: - Parsing

    private static func parse(_ json: [String: Any], into report: inout Report) {
        guard let applinks = json["applinks"] as? [String: Any] else {
            report.checks.append(Check(level: .fail, message: String(localized: "No \"applinks\" section — Universal Links aren't configured")))
            return
        }
        let details = applinks["details"] as? [[String: Any]] ?? []
        if details.isEmpty {
            report.checks.append(Check(level: .fail, message: String(localized: "\"applinks.details\" is empty")))
        }
        for detail in details {
            let ids = (detail["appIDs"] as? [String]) ?? (detail["appID"] as? String).map { [$0] } ?? []
            if ids.isEmpty {
                report.checks.append(Check(level: .fail, message: String(localized: "A details entry has no appIDs")))
            }
            for id in ids where id.split(separator: ".").first?.count != 10 {
                report.checks.append(Check(level: .warn, message: String(localized: "\(id) doesn't start with a 10-character Team ID")))
            }
            var rules: [String] = []
            if let comps = detail["components"] as? [[String: Any]] {
                rules = comps.map(describe)
            } else if let paths = detail["paths"] as? [String] {
                rules = paths
                report.checks.append(Check(level: .warn, message: String(localized: "Uses legacy \"paths\" — \"components\" is the iOS 13+ format")))
            }
            report.apps.append(AppEntry(appIDs: ids, rules: rules))
        }
        report.webCredentials = (json["webcredentials"] as? [String: Any])?["apps"] as? [String] ?? []
        report.appClips = (json["appclips"] as? [String: Any])?["apps"] as? [String] ?? []
    }

    private static func describe(_ component: [String: Any]) -> String {
        var parts: [String] = []
        if component["exclude"] as? Bool == true { parts.append("NOT") }
        if let path = component["/"] as? String { parts.append(path) }
        if let query = component["?"] as? String {
            parts.append("?\(query)")
        } else if let query = component["?"] as? [String: String] {
            parts.append("?" + query.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&"))
        }
        if let fragment = component["#"] as? String { parts.append("#\(fragment)") }
        return parts.isEmpty ? "*" : parts.joined(separator: " ")
    }

    // MARK: - Matching (first matching rule wins, in file order)

    static func match(path: String, query: String?, fragment: String?, json: [String: Any]) -> MatchResult {
        let details = (json["applinks"] as? [String: Any])?["details"] as? [[String: Any]] ?? []
        let decodedPath = path.removingPercentEncoding ?? path
        for detail in details {
            let ids = (detail["appIDs"] as? [String]) ?? (detail["appID"] as? String).map { [$0] } ?? []
            if let comps = detail["components"] as? [[String: Any]] {
                for component in comps where matches(component, path: decodedPath, query: query, fragment: fragment) {
                    let rule = describe(component)
                    return component["exclude"] as? Bool == true ? .excluded(rule: rule) : .opens(ids, rule: rule)
                }
            } else if let paths = detail["paths"] as? [String] {
                for rule in paths {
                    let excluded = rule.hasPrefix("NOT ")
                    let pattern = excluded ? String(rule.dropFirst(4)) : rule
                    if wildcard(pattern, matches: decodedPath) {
                        return excluded ? .excluded(rule: rule) : .opens(ids, rule: rule)
                    }
                }
            }
        }
        return .noMatch
    }

    private static func matches(_ component: [String: Any], path: String, query: String?, fragment: String?) -> Bool {
        let caseSensitive = component["caseSensitive"] as? Bool ?? true
        if let pattern = component["/"] as? String, !wildcard(pattern, matches: path, caseSensitive: caseSensitive) {
            return false
        }
        if let pattern = component["?"] as? String {
            if !wildcard(pattern, matches: query ?? "", caseSensitive: caseSensitive) { return false }
        } else if let patterns = component["?"] as? [String: String] {
            let items = URLComponents(string: "?\(query ?? "")")?.queryItems ?? []
            for (name, pattern) in patterns {
                let value = items.first { $0.name == name }?.value ?? ""
                if !wildcard(pattern, matches: value, caseSensitive: caseSensitive) { return false }
            }
        }
        if let pattern = component["#"] as? String,
           !wildcard(pattern, matches: fragment ?? "", caseSensitive: caseSensitive) {
            return false
        }
        return true
    }

    /// AASA wildcards: `*` = any run of characters, `?` = exactly one.
    static func wildcard(_ pattern: String, matches text: String, caseSensitive: Bool = true) -> Bool {
        var regex = "^"
        for ch in pattern {
            switch ch {
            case "*": regex += ".*"
            case "?": regex += "."
            default:  regex += NSRegularExpression.escapedPattern(for: String(ch))
            }
        }
        regex += "$"
        let options: String.CompareOptions = caseSensitive ? [.regularExpression] : [.regularExpression, .caseInsensitive]
        return text.range(of: regex, options: options) != nil
    }

    // MARK: - Networking

    private struct Response {
        let data: Data
        let contentType: String
    }

    private enum FetchResult {
        case success(Response)
        case redirected(String)
        case failed(String)
    }

    /// Refuses redirects so they can be reported — Apple's fetcher doesn't follow them.
    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }()

    private static func fetch(_ url: URL) async -> FetchResult {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { return .failed("No HTTP response") }
            if (300..<400).contains(http.statusCode) {
                return .redirected(http.value(forHTTPHeaderField: "Location") ?? "?")
            }
            guard http.statusCode == 200 else { return .failed("HTTP \(http.statusCode)") }
            return .success(Response(data: data, contentType: http.value(forHTTPHeaderField: "Content-Type") ?? ""))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func normalized(_ data: Data) -> Data {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let out = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return data }
        return out
    }
}
