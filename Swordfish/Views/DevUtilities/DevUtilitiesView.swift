import SwiftUI
import AppKit

/// Everyday converters that otherwise mean pasting tokens into random
/// websites: JWT, timestamps, Base64, URL encoding, UUIDs, plist ↔ JSON,
/// hashes. Everything runs locally.
struct DevUtilitiesView: View {
    enum Tool: String, CaseIterable, Identifiable {
        case jwt, timestamp, base64, url, curl, uuid, plist, hash, symbols, appIcon, localization
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .jwt:       return "JWT Decoder"
            case .timestamp: return "Timestamp"
            case .base64:    return "Base64"
            case .url:       return "URL Encode"
            case .curl:      return "cURL ↔ Swift"
            case .symbols:   return "SF Symbols"
            case .appIcon:   return "App Icon"
            case .localization: return "Localization Check"
            case .uuid:      return "UUID"
            case .plist:     return "Plist ↔ JSON"
            case .hash:      return "Hash"
            }
        }
        var symbol: String {
            switch self {
            case .jwt:       return "key.viewfinder"
            case .timestamp: return "clock"
            case .base64:    return "textformat.abc"
            case .url:       return "link"
            case .curl:      return "terminal"
            case .symbols:   return "star.square.on.square"
            case .appIcon:   return "app.dashed"
            case .localization: return "globe"
            case .uuid:      return "number"
            case .plist:     return "doc.badge.gearshape"
            case .hash:      return "number.square"
            }
        }
    }

    @EnvironmentObject var devTools: DevToolsState
    @State private var tool: Tool = .jwt
    // Inputs that can be pre-filled from outside live here, not in the tools.
    @State private var jwtInput = ""
    @State private var timestampInput = String(Int(Date().timeIntervalSince1970))
    @State private var base64Input = ""
    @State private var base64Decode = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                content
                    .padding(Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(Theme.Surface.popover)
        .onAppear { consume(devTools.utilityRequest) }
        .onChange(of: devTools.utilityRequest) { consume($0) }
    }

    private func consume(_ request: DevToolsState.UtilityRequest?) {
        guard let request else { return }
        switch request.tool {
        case .jwt:
            tool = .jwt
            jwtInput = request.input
        case .timestamp:
            tool = .timestamp
            timestampInput = request.input
        case .base64:
            tool = .base64
            base64Decode = true
            base64Input = request.input
        }
        devTools.utilityRequest = nil
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Tool.allCases) { t in
                Button {
                    tool = t
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: t.symbol)
                            .frame(width: 16)
                        Text(t.title)
                            .font(Typography.bodyMedium)
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 6)
                    .foregroundStyle(tool == t ? Color.white : Theme.TextColor.secondary)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            .fill(tool == t ? Color.accentColor : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(width: 170)
        .background(Theme.Surface.surface1)
    }

    @ViewBuilder
    private var content: some View {
        switch tool {
        case .jwt:       JWTTool(token: $jwtInput)
        case .timestamp: TimestampTool(input: $timestampInput)
        case .base64:    Base64Tool(input: $base64Input, decode: $base64Decode)
        case .url:       URLTool()
        case .curl:      CurlTool()
        case .symbols:   SymbolsTool()
        case .appIcon:   AppIconTool()
        case .localization: LocalizationTool()
        case .uuid:      UUIDTool()
        case .plist:     PlistTool()
        case .hash:      HashTool()
        }
    }
}

// MARK: - JWT

private struct JWTTool: View {
    @Binding var token: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            UtilityHeader(title: "JWT Decoder",
                          subtitle: "Decodes header and payload locally. The signature is not verified.")
            CodeEditor(text: $token, placeholder: "eyJhbGciOiJIUzI1NiIs…", minHeight: 90)
            if !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                switch Result(catching: { try DevUtilities.decodeJWT(token) }) {
                case .success(let jwt): decoded(jwt)
                case .failure(let error): UtilityError(message: error.localizedDescription)
                }
            }
        }
    }

    @ViewBuilder
    private func decoded(_ jwt: DevUtilities.DecodedJWT) -> some View {
        if let exp = jwt.expiresAt {
            HStack(spacing: 6) {
                Image(systemName: jwt.isExpired ? "xmark.seal.fill" : "checkmark.seal.fill")
                Text(jwt.isExpired
                     ? String(localized: "Expired \(exp.formatted(.relative(presentation: .named)))")
                     : String(localized: "Valid — expires \(exp.formatted(.relative(presentation: .named)))"))
            }
            .font(Typography.bodyMedium)
            .foregroundStyle(jwt.isExpired ? Theme.Semantic.danger : Theme.Semantic.ok)
        }
        VStack(alignment: .leading, spacing: 4) {
            if let d = jwt.issuedAt { ValueRow(label: "iat", value: d.formatted(date: .abbreviated, time: .standard)) }
            if let d = jwt.notBefore { ValueRow(label: "nbf", value: d.formatted(date: .abbreviated, time: .standard)) }
            if let d = jwt.expiresAt { ValueRow(label: "exp", value: d.formatted(date: .abbreviated, time: .standard)) }
        }
        HStack(alignment: .top, spacing: Spacing.md) {
            OutputBox(title: "Header", text: jwt.header)
            OutputBox(title: "Payload", text: jwt.payload)
        }
    }
}

// MARK: - Timestamp

private struct TimestampTool: View {
    @Binding var input: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            UtilityHeader(title: "Timestamp",
                          subtitle: "Unix seconds, milliseconds or microseconds, or an ISO 8601 date")
            HStack(spacing: Spacing.sm) {
                UtilityField(placeholder: "1700000000 or 2026-01-01T12:00:00Z", text: $input)
                PillButton(title: "Now", symbol: "clock.arrow.circlepath") {
                    input = String(Int(Date().timeIntervalSince1970))
                }
            }
            if let result = DevUtilities.parseTimestamp(input) {
                Text("Read as \(result.interpretation)")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(DevUtilities.timestampRows(result.date), id: \.label) { row in
                        ValueRow(label: row.label, value: row.value)
                    }
                }
            } else if !input.isEmpty {
                UtilityError(message: String(localized: "Not a recognised timestamp or date"))
            }
        }
    }
}

// MARK: - Base64

private struct Base64Tool: View {
    @Binding var input: String
    @Binding var decode: Bool
    @State private var urlSafe = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            UtilityHeader(title: "Base64", subtitle: "Encode text to Base64 or decode Base64 / base64url back to text")
            HStack(spacing: Spacing.md) {
                Picker("", selection: $decode) {
                    Text("Encode").tag(false)
                    Text("Decode").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                if !decode {
                    Toggle("URL-safe (base64url)", isOn: $urlSafe)
                        .toggleStyle(.checkbox)
                        .font(Typography.monoSmall)
                }
            }
            CodeEditor(text: $input, placeholder: decode ? "SGVsbG8=" : "Hello", minHeight: 110)
            if !input.isEmpty {
                if decode {
                    switch Result(catching: { try DevUtilities.base64Decode(input) }) {
                    case .success(let text): OutputBox(title: "Decoded", text: text)
                    case .failure(let error): UtilityError(message: error.localizedDescription)
                    }
                } else {
                    OutputBox(title: "Encoded", text: DevUtilities.base64Encode(input, urlSafe: urlSafe))
                }
            }
        }
    }
}

// MARK: - URL

private struct URLTool: View {
    @State private var input = ""
    @State private var decode = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            UtilityHeader(title: "URL Encode", subtitle: "Percent-encode / decode, and break a URL into its parts")
            Picker("", selection: $decode) {
                Text("Encode").tag(false)
                Text("Decode").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
            CodeEditor(text: $input, placeholder: "myapp://product?id=42&ref=push", minHeight: 80)
            if !input.isEmpty {
                if decode {
                    switch Result(catching: { try DevUtilities.urlDecode(input) }) {
                    case .success(let text): OutputBox(title: "Decoded", text: text)
                    case .failure(let error): UtilityError(message: error.localizedDescription)
                    }
                } else {
                    OutputBox(title: "Encoded", text: DevUtilities.urlEncode(input))
                }
                if let parts = DevUtilities.urlComponents(decode ? ((try? DevUtilities.urlDecode(input)) ?? input) : input) {
                    Text("Components")
                        .sectionTitleStyle()
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(parts.enumerated()), id: \.offset) { _, row in
                            ValueRow(label: row.label, value: row.value)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - UUID

private struct UUIDTool: View {
    @State private var count = 1
    @State private var lowercase = false
    @State private var output = DevUtilities.uuids(count: 1, lowercase: false)

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            UtilityHeader(title: "UUID", subtitle: "Random (v4) UUIDs")
            HStack(spacing: Spacing.md) {
                Stepper("Count: \(count)", value: $count, in: 1...100)
                    .font(Typography.monoSmall)
                Toggle("Lowercase", isOn: $lowercase)
                    .toggleStyle(.checkbox)
                    .font(Typography.monoSmall)
                AccentActionButton(title: "Generate", symbol: "arrow.triangle.2.circlepath") {
                    output = DevUtilities.uuids(count: count, lowercase: lowercase)
                }
            }
            OutputBox(title: "UUIDs", text: output)
        }
        .onChange(of: lowercase) { lower in
            output = lower ? output.lowercased() : output.uppercased()
        }
    }
}

// MARK: - Plist ↔ JSON

private struct PlistTool: View {
    @State private var input = ""
    @State private var toJSON = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            UtilityHeader(title: "Plist ↔ JSON",
                          subtitle: "Data becomes base64 and dates ISO 8601 when converting to JSON")
            HStack(spacing: Spacing.sm) {
                Picker("", selection: $toJSON) {
                    Text("Plist → JSON").tag(true)
                    Text("JSON → Plist").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
                PillButton(title: "Open File…", symbol: "folder") { openFile() }
            }
            CodeEditor(text: $input,
                       placeholder: toJSON ? "<?xml version=\"1.0\"…><plist>…</plist>" : "{ \"key\": \"value\" }",
                       minHeight: 160)
            if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                switch Result(catching: { toJSON ? try PlistJSON.json(fromPlist: input) : try PlistJSON.xmlPlist(fromJSON: input) }) {
                case .success(let text): OutputBox(title: toJSON ? "JSON" : "XML Plist", text: text)
                case .failure(let error): UtilityError(message: error.localizedDescription)
                }
            }
        }
    }

    /// Binary plists aren't text, so files are converted straight to JSON.
    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList, .json, .xml]
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        if url.pathExtension.lowercased() == "json" {
            toJSON = false
            input = String(decoding: data, as: UTF8.self)
        } else if let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let xml = try? PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0) {
            toJSON = true
            input = String(decoding: xml, as: UTF8.self)
        }
    }
}

// MARK: - Hash

private struct HashTool: View {
    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            UtilityHeader(title: "Hash", subtitle: "Digests of the UTF-8 bytes of the text")
            CodeEditor(text: $input, placeholder: "Text to hash", minHeight: 110)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(DevUtilities.hashes(input), id: \.label) { row in
                    ValueRow(label: row.label, value: row.value)
                }
            }
        }
    }
}

// MARK: - Shared pieces

private struct UtilityHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Typography.title).foregroundStyle(Theme.TextColor.primary)
            Text(subtitle).font(Typography.monoSmall).foregroundStyle(Theme.TextColor.tertiary)
        }
    }
}

private struct UtilityField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(Typography.mono)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .fill(Theme.Surface.codeBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            .strokeBorder(Theme.Border.subtle, lineWidth: 1)
                    )
            )
    }
}

private struct UtilityError: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(Typography.monoSmall)
            .foregroundStyle(Theme.Semantic.danger)
    }
}

/// Label + value + copy, used for timestamp / hash / URL component rows.
struct ValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(verbatim: label)
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.tertiary)
                .frame(width: 130, alignment: .leading)
            Text(verbatim: value)
                .font(Typography.mono)
                .foregroundStyle(Theme.TextColor.primary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            CopyButton(text: value)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                .fill(Theme.Surface.surface1)
        )
    }
}

/// Read-only, selectable result block with a copy button.
private struct OutputBox: View {
    let title: LocalizedStringKey
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).sectionTitleStyle()
                Spacer()
                CopyButton(text: text)
            }
            Text(verbatim: text)
                .font(Typography.code)
                .foregroundStyle(Theme.TextColor.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                        .fill(Theme.Surface.codeBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                                .strokeBorder(Theme.Border.subtle, lineWidth: 1)
                        )
                )
        }
    }
}
