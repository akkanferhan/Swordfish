import Foundation
import AppKit

// MARK: - cURL ↔ URLRequest

struct HTTPRequestSpec: Equatable {
    var method = "GET"
    var url = ""
    var headers: [(name: String, value: String)] = []
    var body: String?

    static func == (a: HTTPRequestSpec, b: HTTPRequestSpec) -> Bool {
        a.method == b.method && a.url == b.url && a.body == b.body
            && a.headers.map { "\($0.name):\($0.value)" } == b.headers.map { "\($0.name):\($0.value)" }
    }
}

enum CurlConverter {
    /// Parses a curl command (as copied from browser dev tools, Proxyman,
    /// Postman…) into method / URL / headers / body.
    static func parse(_ command: String) throws -> HTTPRequestSpec {
        let tokens = try tokenize(command)
        var spec = HTTPRequestSpec()
        var dataParts: [String] = []
        var explicitMethod: String?
        var getWithData = false
        var i = tokens.first == "curl" ? 1 : 0

        func next() throws -> String {
            i += 1
            guard i < tokens.count else { throw DevUtilities.ConversionError(message: "Missing value after \(tokens[i - 1])") }
            return tokens[i]
        }

        while i < tokens.count {
            let token = tokens[i]
            switch token {
            case "-X", "--request":
                explicitMethod = try next().uppercased()
            case "-H", "--header":
                let header = try next()
                if let colon = header.firstIndex(of: ":") {
                    spec.headers.append((String(header[..<colon]).trimmingCharacters(in: .whitespaces),
                                         String(header[header.index(after: colon)...]).trimmingCharacters(in: .whitespaces)))
                }
            case "-d", "--data", "--data-raw", "--data-binary", "--data-ascii", "--data-urlencode", "--json":
                dataParts.append(try next())
                if token == "--json" {
                    spec.headers.append(("Content-Type", "application/json"))
                    spec.headers.append(("Accept", "application/json"))
                }
            case "-u", "--user":
                let credentials = try next()
                spec.headers.append(("Authorization", "Basic " + Data(credentials.utf8).base64EncodedString()))
            case "-b", "--cookie":
                spec.headers.append(("Cookie", try next()))
            case "-A", "--user-agent":
                spec.headers.append(("User-Agent", try next()))
            case "-e", "--referer":
                spec.headers.append(("Referer", try next()))
            case "--url":
                spec.url = try next()
            case "-G", "--get":
                getWithData = true
            case "-o", "--output", "-w", "--write-out", "-m", "--max-time", "--connect-timeout", "-x", "--proxy":
                _ = try next()   // options with a value we don't need
            default:
                if token.hasPrefix("-") {
                    break   // flags like --compressed, -L, -k, -s, -i, -v
                } else if spec.url.isEmpty {
                    spec.url = token
                }
            }
            i += 1
        }
        guard !spec.url.isEmpty else { throw DevUtilities.ConversionError(message: String(localized: "No URL found in the command")) }

        let joined = dataParts.joined(separator: "&")
        if getWithData, !joined.isEmpty {
            spec.url += (spec.url.contains("?") ? "&" : "?") + joined
        } else if !joined.isEmpty {
            spec.body = joined
        }
        spec.method = explicitMethod ?? (spec.body == nil ? "GET" : "POST")
        return spec
    }

    /// Shell-style word splitting: '…', "…" (with \ escapes), $'…' (ANSI-C),
    /// backslash escapes and line continuations.
    static func tokenize(_ input: String) throws -> [String] {
        var tokens: [String] = []
        var current = ""
        var inToken = false
        var chars = Array(input)
        var i = 0
        chars.append(" ")
        while i < chars.count {
            let c = chars[i]
            switch c {
            case "\\":
                if i + 1 < chars.count {
                    let n = chars[i + 1]
                    if n == "\n" { i += 2; continue }        // line continuation
                    current.append(n); inToken = true; i += 2; continue
                }
            case "'":
                guard let end = chars[(i + 1)...].firstIndex(of: "'") else {
                    throw DevUtilities.ConversionError(message: String(localized: "Unclosed ' quote"))
                }
                current += String(chars[(i + 1)..<end]); inToken = true; i = end + 1; continue
            case "$" where i + 1 < chars.count && chars[i + 1] == "'":
                var j = i + 2
                while j < chars.count && chars[j] != "'" {
                    if chars[j] == "\\" && j + 1 < chars.count {
                        switch chars[j + 1] {
                        case "n": current.append("\n")
                        case "t": current.append("\t")
                        case "r": current.append("\r")
                        default:  current.append(chars[j + 1])
                        }
                        j += 2
                    } else {
                        current.append(chars[j]); j += 1
                    }
                }
                inToken = true; i = j + 1; continue
            case "\"":
                var j = i + 1
                while j < chars.count && chars[j] != "\"" {
                    if chars[j] == "\\" && j + 1 < chars.count && "\"\\$`".contains(chars[j + 1]) {
                        current.append(chars[j + 1]); j += 2
                    } else {
                        current.append(chars[j]); j += 1
                    }
                }
                guard j < chars.count else { throw DevUtilities.ConversionError(message: String(localized: "Unclosed \" quote")) }
                inToken = true; i = j + 1; continue
            case " ", "\t", "\n", "\r":
                if inToken { tokens.append(current); current = ""; inToken = false }
                i += 1; continue
            default:
                break
            }
            current.append(c); inToken = true; i += 1
        }
        return tokens
    }

    static func swiftCode(_ spec: HTTPRequestSpec) -> String {
        var lines = ["var request = URLRequest(url: URL(string: \(swiftLiteral(spec.url)))!)"]
        if spec.method != "GET" { lines.append("request.httpMethod = \"\(spec.method)\"") }
        for header in spec.headers {
            lines.append("request.setValue(\(swiftLiteral(header.value)), forHTTPHeaderField: \(swiftLiteral(header.name)))")
        }
        if let body = spec.body {
            if body.contains("\n") {
                lines.append("request.httpBody = Data(\(swiftMultiline(body)).utf8)")
            } else {
                lines.append("request.httpBody = Data(\(swiftLiteral(body)).utf8)")
            }
        }
        lines.append("")
        lines.append("let (data, response) = try await URLSession.shared.data(for: request)")
        return lines.joined(separator: "\n")
    }

    static func curlCommand(_ spec: HTTPRequestSpec) -> String {
        var parts = ["curl"]
        // curl implies GET without a body and POST with one.
        let implied = spec.body == nil ? "GET" : "POST"
        if spec.method != implied { parts.append("-X \(spec.method)") }
        parts.append(shellQuote(spec.url))
        for header in spec.headers where !header.name.isEmpty {
            parts.append("-H " + shellQuote("\(header.name): \(header.value)"))
        }
        if let body = spec.body, !body.isEmpty { parts.append("--data-raw " + shellQuote(body)) }
        return parts.joined(separator: " \\\n  ")
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Plain literal when safe; otherwise a raw string with enough #s that
    /// neither `"#…` (closing) nor `\#…` (escape) can occur in the content.
    private static func swiftLiteral(_ s: String) -> String {
        if !s.contains("\\") && !s.contains("\"") && !s.contains("\n") { return "\"\(s)\"" }
        var hashes = "#"
        while s.contains("\"" + hashes) || s.contains("\\" + hashes) { hashes += "#" }
        return "\(hashes)\"\(s)\"\(hashes)"
    }

    private static func swiftMultiline(_ s: String) -> String {
        var hashes = "#"
        while s.contains("\"\"\"" + hashes) || s.contains("\\" + hashes) { hashes += "#" }
        return "\(hashes)\"\"\"\n\(s)\n\"\"\"\(hashes)"
    }
}

// MARK: - SF Symbols

enum SFSymbolsCatalog {
    /// Every symbol name in display order, read from the system's CoreGlyphs
    /// bundle (the same list the SF Symbols app shows).
    static func names() -> [String] {
        let path = "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/symbol_order.plist"
        return (NSArray(contentsOfFile: path) as? [String]) ?? []
    }
}

// MARK: - App icon generator

enum AppIconGenerator {
    enum Platform: String, CaseIterable, Identifiable {
        case iOS, macOS, watchOS
        var id: String { rawValue }
    }

    /// Writes `AppIcon.appiconset` (PNGs + Contents.json) into `folder`.
    static func generate(from source: NSImage, platforms: Set<Platform>, removeAlpha: Bool, into folder: URL) throws -> URL {
        let set = folder.appendingPathComponent("AppIcon.appiconset")
        try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        var images: [[String: String]] = []

        func write(pixels: Int, name: String, flatten: Bool) throws {
            let data = try png(source, pixels: pixels, flatten: flatten)
            try data.write(to: set.appendingPathComponent(name))
        }

        if platforms.contains(.iOS) {
            try write(pixels: 1024, name: "AppIcon-iOS-1024.png", flatten: removeAlpha)
            images.append(["filename": "AppIcon-iOS-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"])
        }
        if platforms.contains(.watchOS) {
            try write(pixels: 1024, name: "AppIcon-watchOS-1024.png", flatten: true)
            images.append(["filename": "AppIcon-watchOS-1024.png", "idiom": "universal", "platform": "watchos", "size": "1024x1024"])
        }
        if platforms.contains(.macOS) {
            for points in [16, 32, 128, 256, 512] {
                for scale in [1, 2] {
                    let name = "AppIcon-mac-\(points)@\(scale)x.png"
                    try write(pixels: points * scale, name: name, flatten: false)
                    images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
                }
            }
        }
        let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
        let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: set.appendingPathComponent("Contents.json"))
        return set
    }

    private static func png(_ image: NSImage, pixels: Int, flatten: Bool) throws -> Data {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw DevUtilities.ConversionError(message: "Couldn't allocate bitmap")
        }
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        if flatten {
            NSColor.white.setFill()
            rect.fill()
        }
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw DevUtilities.ConversionError(message: "PNG encoding failed")
        }
        return data
    }
}

// MARK: - Localization coverage

struct LocalizationReport {
    struct LanguageStats: Identifiable {
        let language: String
        let total: Int
        let translated: Int
        let needsReview: Int
        let missingKeys: [String]
        var id: String { language }
        var percent: Double { total == 0 ? 1 : Double(translated) / Double(total) }
    }

    struct Catalog: Identifiable {
        let url: URL
        let sourceLanguage: String
        let keyCount: Int
        let staleCount: Int
        let languages: [LanguageStats]
        var id: String { url.path }
    }

    let catalogs: [Catalog]

    /// Finds every `.xcstrings` under `root` (skipping build output and
    /// dependency folders) and measures translation coverage per language.
    static func scan(_ root: URL) -> LocalizationReport {
        let skip: Set<String> = ["DerivedData", ".build", "build", "Pods", "Carthage", "node_modules", ".git", "SourcePackages"]
        var catalogs: [Catalog] = []
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                          options: [.skipsHiddenFiles]) else { return LocalizationReport(catalogs: []) }
        for case let url as URL in walker {
            if skip.contains(url.lastPathComponent) { walker.skipDescendants(); continue }
            guard url.pathExtension == "xcstrings", let catalog = parse(url) else { continue }
            catalogs.append(catalog)
        }
        return LocalizationReport(catalogs: catalogs.sorted { $0.url.path < $1.url.path })
    }

    private static func parse(_ url: URL) -> Catalog? {
        guard let data = try? Data(contentsOf: url),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let strings = json["strings"] as? [String: [String: Any]] else { return nil }
        let source = json["sourceLanguage"] as? String ?? "en"

        var languages = Set<String>()
        for entry in strings.values {
            (entry["localizations"] as? [String: Any])?.keys.forEach { languages.insert($0) }
        }
        languages.remove(source)

        let translatable = strings.filter { _, entry in
            entry["shouldTranslate"] as? Bool != false && entry["extractionState"] as? String != "stale"
        }
        let stale = strings.values.filter { $0["extractionState"] as? String == "stale" }.count

        let stats = languages.sorted().map { lang -> LanguageStats in
            var translated = 0
            var review = 0
            var missing: [String] = []
            for (key, entry) in translatable {
                let localization = (entry["localizations"] as? [String: Any])?[lang] as? [String: Any]
                let state = (localization?["stringUnit"] as? [String: Any])?["state"] as? String
                if localization?["variations"] != nil || state == "translated" {
                    translated += 1
                } else if state == "needs_review" {
                    review += 1
                    translated += 1
                } else {
                    missing.append(key)
                }
            }
            return LanguageStats(language: lang, total: translatable.count, translated: translated,
                                 needsReview: review, missingKeys: missing.sorted())
        }
        return Catalog(url: url, sourceLanguage: source, keyCount: translatable.count,
                       staleCount: stale, languages: stats)
    }

    /// key,language rows for every missing translation.
    func csv() -> String {
        var rows = ["catalog,language,key"]
        for catalog in catalogs {
            for lang in catalog.languages {
                for key in lang.missingKeys {
                    let escaped = "\"" + key.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                    rows.append("\(catalog.url.lastPathComponent),\(lang.language),\(escaped)")
                }
            }
        }
        return rows.joined(separator: "\n")
    }
}
