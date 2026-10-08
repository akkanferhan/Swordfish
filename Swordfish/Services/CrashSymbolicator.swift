import Foundation

/// Symbolicates crash reports locally: finds each binary's dSYM by UUID via
/// Spotlight (DerivedData, Archives, anywhere indexed) and resolves frame
/// addresses with `atos`. Handles the JSON `.ips` format (iOS 15+ / macOS
/// 12+) and classic text `.crash` reports.
enum CrashSymbolicator {
    struct Output {
        let text: String
        let symbolicatedFrames: Int
        let missingDSYMs: [String]   // "App (UUID)"
    }

    struct Image {
        let name: String
        let uuid: String          // uppercase, dashed
        let base: UInt64
        let arch: String
    }

    // MARK: - Entry point

    static func symbolicate(_ url: URL, extraDSYMs: [URL] = []) throws -> Output {
        let raw = try String(contentsOf: url, encoding: .utf8)
        if url.pathExtension.lowercased() == "ips" || raw.hasPrefix("{") {
            return try symbolicateIPS(raw, extraDSYMs: extraDSYMs)
        }
        return symbolicateText(raw, extraDSYMs: extraDSYMs)
    }

    // MARK: - dSYM lookup

    /// Spotlight indexes dSYM UUIDs as `com_apple_xcode_dsym_uuids`.
    static func findDSYM(uuid: String) -> URL? {
        let formatted = dashed(uuid)
        guard let r = try? ProcessRunner.run("/usr/bin/mdfind", arguments: ["com_apple_xcode_dsym_uuids == \(formatted)"]) else { return nil }
        return r.stdout.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }.first
    }

    /// The DWARF binary inside a .dSYM bundle that matches `uuid`.
    static func dwarfBinary(in dsym: URL, uuid: String) -> URL? {
        let dir = dsym.appendingPathComponent("Contents/Resources/DWARF")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        guard files.count > 1 else { return files.first }
        let wanted = dashed(uuid)
        return files.first { file in
            let r = try? ProcessRunner.run("/usr/bin/dwarfdump", arguments: ["--uuid", file.path])
            return r?.stdout.uppercased().contains(wanted) == true
        } ?? files.first
    }

    static func dashed(_ uuid: String) -> String {
        let hex = uuid.uppercased().filter(\.isHexDigit)
        guard hex.count == 32 else { return uuid.uppercased() }
        let c = Array(hex)
        return [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(c[$0]) }.joined(separator: "-")
    }

    private static func dsymFor(_ image: Image, extra: [URL]) -> URL? {
        for dsym in extra {
            if let r = try? ProcessRunner.run("/usr/bin/dwarfdump", arguments: ["--uuid", dsym.path]),
               r.stdout.uppercased().contains(image.uuid) {
                return dsym
            }
        }
        return findDSYM(uuid: image.uuid)
    }

    /// Resolves `addresses` (absolute, already slid by `image.base`) to
    /// "symbol (in Module) (File.swift:42)" strings — nil where atos had nothing.
    private static func atos(_ image: Image, dwarf: URL, addresses: [UInt64]) -> [String?] {
        guard !addresses.isEmpty else { return [] }
        let args = ["-arch", image.arch, "-o", dwarf.path, "-l", String(format: "0x%llx", image.base)]
            + addresses.map { String(format: "0x%llx", $0) }
        guard let r = try? ProcessRunner.run("/usr/bin/atos", arguments: args), r.exitCode == 0 else {
            return addresses.map { _ in nil }
        }
        let lines = r.stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return addresses.indices.map { i in
            guard i < lines.count else { return nil }
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            // Unresolved addresses come back as the bare hex address.
            return line.isEmpty || line.hasPrefix("0x") ? nil : line
        }
    }

    // MARK: - .ips (JSON)

    private static func symbolicateIPS(_ raw: String, extraDSYMs: [URL]) throws -> Output {
        // Line 1 is a small JSON header; the rest is the report body.
        let parts = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let header = (try? JSONSerialization.jsonObject(with: Data(parts[0].utf8))) as? [String: Any] ?? [:]
        guard parts.count == 2,
              let body = (try? JSONSerialization.jsonObject(with: Data(parts[1].utf8))) as? [String: Any] else {
            throw SimulatorToolbox.CommandError(message: String(localized: "Not a valid .ips crash report"))
        }

        let usedImages = body["usedImages"] as? [[String: Any]] ?? []
        let images: [Image?] = usedImages.map { img in
            guard let uuid = img["uuid"] as? String,
                  let base = (img["base"] as? NSNumber)?.uint64Value else { return nil }
            return Image(name: img["name"] as? String ?? "?", uuid: dashed(uuid), base: base,
                         arch: img["arch"] as? String ?? "arm64")
        }
        let threads = body["threads"] as? [[String: Any]] ?? []

        // Collect unsymbolicated frames per image, resolve them in one atos call each.
        var wanted: [Int: Set<UInt64>] = [:]
        for thread in threads {
            for frame in thread["frames"] as? [[String: Any]] ?? [] where frame["symbol"] == nil {
                guard let index = frame["imageIndex"] as? Int, index < images.count, let image = images[index],
                      let offset = (frame["imageOffset"] as? NSNumber)?.uint64Value else { continue }
                wanted[index, default: []].insert(image.base + offset)
            }
        }
        var resolved: [UInt64: String] = [:]
        var missing: [String] = []
        for (index, addresses) in wanted {
            guard let image = images[index] else { continue }
            guard let dsym = dsymFor(image, extra: extraDSYMs), let dwarf = dwarfBinary(in: dsym, uuid: image.uuid) else {
                missing.append("\(image.name) (\(image.uuid))")
                continue
            }
            let list = Array(addresses)
            for (address, symbol) in zip(list, atos(image, dwarf: dwarf, addresses: list)) {
                if let symbol { resolved[address] = symbol }
            }
        }

        // Render.
        var out: [String] = []
        let process = body["procName"] as? String ?? header["app_name"] as? String ?? "?"
        let version = (body["bundleInfo"] as? [String: Any])?["CFBundleShortVersionString"] as? String
            ?? header["app_version"] as? String ?? ""
        out.append("\(process) \(version)")
        if let os = body["osVersion"] as? [String: Any] {
            out.append("OS: \(os["train"] as? String ?? "") (\(os["build"] as? String ?? ""))")
        }
        if let exception = body["exception"] as? [String: Any] {
            out.append("Exception: \(exception["type"] as? String ?? "") \(exception["signal"] as? String ?? "") \(exception["subtype"] as? String ?? "")")
        }
        if let reason = (body["asi"] as? [String: [String]])?.values.flatMap({ $0 }).first {
            out.append("Reason: \(reason)")
        }
        out.append("")

        var symbolicated = 0
        let ordered = threads.enumerated().sorted { a, b in
            (a.element["triggered"] as? Bool == true ? 0 : 1, a.offset) < (b.element["triggered"] as? Bool == true ? 0 : 1, b.offset)
        }
        for (number, thread) in ordered {
            let crashed = thread["triggered"] as? Bool == true
            let name = (thread["name"] as? String) ?? (thread["queue"] as? String) ?? ""
            out.append("Thread \(number)\(crashed ? " Crashed" : "")\(name.isEmpty ? "" : ": \(name)")")
            for (i, frame) in (thread["frames"] as? [[String: Any]] ?? []).enumerated() {
                let index = frame["imageIndex"] as? Int ?? -1
                let image = index >= 0 && index < images.count ? images[index] : nil
                let imageName = image?.name ?? "???"
                let offset = (frame["imageOffset"] as? NSNumber)?.uint64Value ?? 0
                let address = (image?.base ?? 0) + offset
                var symbol: String
                if let existing = frame["symbol"] as? String {
                    let location = (frame["symbolLocation"] as? NSNumber)?.intValue ?? 0
                    symbol = "\(existing) + \(location)"
                    if let file = frame["sourceFile"] as? String, let line = frame["sourceLine"] as? Int {
                        symbol += " (\(file):\(line))"
                    }
                } else if let found = resolved[address] {
                    symbol = found
                    symbolicated += 1
                } else {
                    symbol = String(format: "0x%llx + %llu", image?.base ?? 0, offset)
                }
                let frameNo = String(i).padding(toLength: 4, withPad: " ", startingAt: 0)
                let module = imageName.count >= 30 ? String(imageName.prefix(29)) + " " : imageName.padding(toLength: 30, withPad: " ", startingAt: 0)
                out.append(frameNo + module + String(format: "0x%016llx ", address) + symbol)
            }
            out.append("")
        }
        return Output(text: out.joined(separator: "\n"), symbolicatedFrames: symbolicated, missingDSYMs: missing.sorted())
    }

    // MARK: - Classic text .crash

    private static let framePattern = try! NSRegularExpression(
        pattern: #"^(\d+\s+)(\S+)(\s+)(0x[0-9a-fA-F]+)(\s+.*)$"#, options: [.anchorsMatchLines])
    private static let imagePattern = try! NSRegularExpression(
        pattern: #"^\s*(0x[0-9a-fA-F]+)\s+-\s+\S+\s+\+?(\S+)\s+(\S+)\s+<([0-9a-fA-F-]+)>"#, options: [.anchorsMatchLines])

    private static func symbolicateText(_ raw: String, extraDSYMs: [URL]) -> Output {
        let ns = raw as NSString
        var images: [String: Image] = [:]
        for m in imagePattern.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
            let base = UInt64(ns.substring(with: m.range(at: 1)).dropFirst(2), radix: 16) ?? 0
            let name = ns.substring(with: m.range(at: 2))
            images[name] = Image(name: name, uuid: dashed(ns.substring(with: m.range(at: 4))), base: base,
                                 arch: ns.substring(with: m.range(at: 3)))
        }

        let frameMatches = framePattern.matches(in: raw, range: NSRange(location: 0, length: ns.length))
        var wanted: [String: Set<UInt64>] = [:]
        for m in frameMatches {
            let name = ns.substring(with: m.range(at: 2))
            let rest = ns.substring(with: m.range(at: 5))
            // Already symbolicated frames read "symbol + offset", unsymbolicated "0xBASE + offset".
            guard images[name] != nil, rest.trimmingCharacters(in: .whitespaces).hasPrefix("0x"),
                  let address = UInt64(ns.substring(with: m.range(at: 4)).dropFirst(2), radix: 16) else { continue }
            wanted[name, default: []].insert(address)
        }

        var resolved: [UInt64: String] = [:]
        var missing: [String] = []
        for (name, addresses) in wanted {
            guard let image = images[name] else { continue }
            guard let dsym = dsymFor(image, extra: extraDSYMs), let dwarf = dwarfBinary(in: dsym, uuid: image.uuid) else {
                missing.append("\(name) (\(image.uuid))")
                continue
            }
            let list = Array(addresses)
            for (address, symbol) in zip(list, atos(image, dwarf: dwarf, addresses: list)) {
                if let symbol { resolved[address] = symbol }
            }
        }

        var symbolicated = 0
        var output = raw
        // Replace from the end so earlier ranges stay valid.
        for m in frameMatches.reversed() {
            guard let address = UInt64(ns.substring(with: m.range(at: 4)).dropFirst(2), radix: 16),
                  let symbol = resolved[address],
                  let range = Range(m.range(at: 5), in: output) else { continue }
            output.replaceSubrange(range, with: " " + symbol)
            symbolicated += 1
        }
        return Output(text: output, symbolicatedFrames: symbolicated, missingDSYMs: missing.sorted())
    }
}
