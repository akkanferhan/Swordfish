import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - cURL ↔ Swift

struct CurlTool: View {
    @State private var toSwift = true
    @State private var curl = ""
    @State private var method = "GET"
    @State private var url = ""
    @State private var headers = ""
    @State private var requestBody = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ToolHeader(title: "cURL ↔ Swift", subtitle: "Turn a copied cURL into URLRequest code, or build a cURL from parts")
            Picker("", selection: $toSwift) {
                Text("cURL → Swift").tag(true)
                Text("Request → cURL").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
            if toSwift { curlToSwift } else { requestToCurl }
        }
    }

    @ViewBuilder
    private var curlToSwift: some View {
        CodeEditor(text: $curl, placeholder: "curl 'https://api.example.com/items' -H 'Authorization: Bearer …' --data-raw '{\"a\":1}'", minHeight: 110)
        if !curl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            switch Result(catching: { try CurlConverter.parse(curl) }) {
            case .success(let spec):
                VStack(alignment: .leading, spacing: 4) {
                    ValueRow(label: "Method", value: spec.method)
                    ValueRow(label: "URL", value: spec.url)
                    ForEach(Array(spec.headers.enumerated()), id: \.offset) { _, header in
                        ValueRow(label: header.name, value: header.value)
                    }
                }
                ResultBox(title: "Swift", text: CurlConverter.swiftCode(spec))
                PillButton(title: "Edit as Request", symbol: "pencil") {
                    method = spec.method
                    url = spec.url
                    headers = spec.headers.map { "\($0.name): \($0.value)" }.joined(separator: "\n")
                    requestBody = spec.body ?? ""
                    toSwift = false
                }
            case .failure(let error):
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.Semantic.danger)
            }
        }
    }

    @ViewBuilder
    private var requestToCurl: some View {
        HStack(spacing: Spacing.sm) {
            Picker("", selection: $method) {
                ForEach(["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD"], id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(width: 100)
            TextField("https://api.example.com/items", text: $url)
                .textFieldStyle(.roundedBorder)
                .font(Typography.mono)
        }
        CodeEditor(text: $headers, placeholder: "Header: value — one per line", minHeight: 70)
        CodeEditor(text: $requestBody, placeholder: "Body (optional)", minHeight: 70)
        if !url.isEmpty {
            let spec = HTTPRequestSpec(
                method: method,
                url: url,
                headers: headers.split(separator: "\n").compactMap { line -> (name: String, value: String)? in
                    guard let colon = line.firstIndex(of: ":") else { return nil }
                    return (String(line[..<colon]).trimmingCharacters(in: .whitespaces),
                            String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
                },
                body: requestBody.isEmpty ? nil : requestBody
            )
            ResultBox(title: "cURL", text: CurlConverter.curlCommand(spec))
            ResultBox(title: "Swift", text: CurlConverter.swiftCode(spec))
        }
    }
}

// MARK: - SF Symbols

struct SymbolsTool: View {
    @State private var names: [String] = []
    @State private var search = ""
    @State private var copied: String?
    @State private var rendering: Rendering = .monochrome

    enum Rendering: String, CaseIterable, Identifiable {
        case monochrome, hierarchical, multicolor
        var id: String { rawValue }
        var mode: SymbolRenderingMode {
            switch self {
            case .monochrome:   return .monochrome
            case .hierarchical: return .hierarchical
            case .multicolor:   return .multicolor
            }
        }
    }

    private var filtered: [String] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return names }
        let terms = q.split(separator: " ")
        return names.filter { name in terms.allSatisfy { name.contains($0) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ToolHeader(title: "SF Symbols", subtitle: "\(names.count) symbols on this Mac — click to copy the name, right-click for code")
            HStack(spacing: Spacing.sm) {
                TextField("Search (e.g. arrow circle fill)", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .font(Typography.mono)
                Picker("", selection: $rendering) {
                    ForEach(Rendering.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                .labelsHidden()
                .frame(width: 130)
            }
            if let copied {
                Text("Copied \(copied)")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.Semantic.ok)
            }
            let shown = Array(filtered.prefix(600))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
                ForEach(shown, id: \.self) { name in
                    VStack(spacing: 4) {
                        Image(systemName: name)
                            .symbolRenderingMode(rendering.mode)
                            .font(.system(size: 22))
                            .frame(height: 30)
                        Text(name)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Theme.TextColor.tertiary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 92, height: 72)
                    .background(RoundedRectangle(cornerRadius: Radius.row).fill(Theme.Surface.surface1))
                    .contentShape(Rectangle())
                    .onTapGesture { copy(name, label: name) }
                    .contextMenu {
                        Button("Copy Name") { copy(name, label: name) }
                        Button("Copy SwiftUI") { copy("Image(systemName: \"\(name)\")", label: "SwiftUI") }
                        Button("Copy UIKit") { copy("UIImage(systemName: \"\(name)\")", label: "UIKit") }
                    }
                }
            }
            if filtered.count > shown.count {
                Text("Showing \(shown.count) of \(filtered.count) — refine the search")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
            }
            if names.isEmpty {
                Text("The SF Symbols list wasn't found on this macOS version.")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
            }
        }
        .task {
            names = await Task.detached { SFSymbolsCatalog.names() }.value
        }
    }

    private func copy(_ text: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = label
    }
}

// MARK: - App Icon

struct AppIconTool: View {
    @State private var image: NSImage?
    @State private var imageName = ""
    @State private var platforms: Set<AppIconGenerator.Platform> = [.iOS]
    @State private var removeAlpha = true
    @State private var status: ToolboxStatus?
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ToolHeader(title: "App Icon", subtitle: "One 1024×1024 PNG → a ready AppIcon.appiconset for Xcode")
            HStack(alignment: .top, spacing: Spacing.lg) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(isTargeted ? Color.accentColor.opacity(0.1) : Theme.Surface.surface1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .strokeBorder(isTargeted ? Color.accentColor : Theme.Border.default,
                                              style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        )
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    } else {
                        Text("Drop PNG")
                            .font(Typography.monoSmall)
                            .foregroundStyle(Theme.TextColor.tertiary)
                    }
                }
                .frame(width: 128, height: 128)
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    providers.first?.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                        let url: URL? = (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) } ?? (item as? URL)
                        guard let url else { return }
                        DispatchQueue.main.async { load(url) }
                    }
                    return true
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    PillButton(title: "Choose Image…", symbol: "photo") { choose() }
                    if !imageName.isEmpty {
                        Text(imageName)
                            .font(Typography.monoSmall)
                            .foregroundStyle(Theme.TextColor.tertiary)
                    }
                    ForEach(AppIconGenerator.Platform.allCases) { platform in
                        Toggle(platform.rawValue, isOn: Binding(
                            get: { platforms.contains(platform) },
                            set: { on in if on { platforms.insert(platform) } else { platforms.remove(platform) } }
                        ))
                        .toggleStyle(.checkbox)
                    }
                    Toggle("Remove transparency (App Store requires it on iOS)", isOn: $removeAlpha)
                        .toggleStyle(.checkbox)
                    AccentActionButton(title: "Generate…", symbol: "square.and.arrow.down",
                                       enabled: image != nil && !platforms.isEmpty) { generate() }
                }
                .font(Typography.monoSmall)
            }
            if let status { ToolboxStatusLine(status: status) }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }

    private func load(_ url: URL) {
        guard let img = NSImage(contentsOf: url) else {
            status = .error(String(localized: "Couldn't read \(url.lastPathComponent)"))
            return
        }
        image = img
        let px = img.representations.first?.pixelsWide ?? 0
        imageName = "\(url.lastPathComponent) · \(px) px"
        status = px > 0 && px < 1024 ? .error(String(localized: "Image is \(px) px — use at least 1024 px to avoid blurry icons")) : nil
    }

    private func generate() {
        guard let image else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Generate Here")
        panel.message = String(localized: "Choose a folder, e.g. your Assets.xcassets")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            let set = try AppIconGenerator.generate(from: image, platforms: platforms, removeAlpha: removeAlpha, into: folder)
            status = .ok(String(localized: "Created \(set.lastPathComponent)"), set)
        } catch {
            status = .error(error.localizedDescription)
        }
    }
}

// MARK: - Localization check

struct LocalizationTool: View {
    @State private var report: LocalizationReport?
    @State private var folder: URL?
    @State private var isScanning = false
    @State private var selected: String?   // "catalogPath|language"

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ToolHeader(title: "Localization Check", subtitle: "Translation coverage of every String Catalog (.xcstrings) in a project")
            HStack(spacing: Spacing.sm) {
                PillButton(title: "Choose Project Folder…", symbol: "folder") { choose() }
                if let folder {
                    Text(folder.path)
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    ToolboxIconButton(symbol: "arrow.clockwise", help: "Rescan") { scan(folder) }
                }
                Spacer()
                if let report, !report.catalogs.isEmpty {
                    PillButton(title: "Copy Missing as CSV", symbol: "tablecells") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(report.csv(), forType: .string)
                    }
                }
            }
            if isScanning {
                Text("Scanning…").font(Typography.monoSmall).foregroundStyle(Theme.TextColor.tertiary)
            } else if let report {
                if report.catalogs.isEmpty {
                    Text("No .xcstrings files found")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                }
                ForEach(report.catalogs) { catalog in
                    catalogView(catalog)
                }
            }
        }
    }

    private func catalogView(_ catalog: LocalizationReport.Catalog) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(catalog.url.lastPathComponent)
                    .font(Typography.bodyMedium)
                Text("· \(catalog.keyCount) keys · source \(catalog.sourceLanguage)")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                if catalog.staleCount > 0 {
                    Badge(label: String(localized: "\(catalog.staleCount) stale"), tint: Theme.Semantic.warn)
                }
                Spacer()
            }
            ForEach(catalog.languages) { lang in
                let key = "\(catalog.id)|\(lang.language)"
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.sm) {
                        Text(lang.language)
                            .font(Typography.mono)
                            .frame(width: 70, alignment: .leading)
                        UsageBar(value: lang.percent, tint: lang.percent >= 1 ? Theme.Semantic.ok
                                 : (lang.percent >= 0.8 ? Theme.Semantic.warn : Theme.Semantic.danger))
                            .frame(height: 5)
                        Text(String(format: "%.0f%%", lang.percent * 100))
                            .font(Typography.monoSmall)
                            .frame(width: 40, alignment: .trailing)
                        Text(lang.missingKeys.isEmpty ? "" : String(localized: "\(lang.missingKeys.count) missing"))
                            .font(Typography.monoSmall)
                            .foregroundStyle(Theme.Semantic.danger)
                            .frame(width: 80, alignment: .trailing)
                        Text(lang.needsReview > 0 ? String(localized: "\(lang.needsReview) review") : "")
                            .font(Typography.monoSmall)
                            .foregroundStyle(Theme.Semantic.warn)
                            .frame(width: 70, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selected = selected == key ? nil : key }
                    if selected == key, !lang.missingKeys.isEmpty {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(lang.missingKeys.prefix(200), id: \.self) { missing in
                                Text(missing)
                                    .font(Typography.monoSmall)
                                    .foregroundStyle(Theme.TextColor.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.leading, 78)
                    }
                }
            }
        }
        .padding(Spacing.sm)
        .background(RoundedRectangle(cornerRadius: Radius.row).fill(Theme.Surface.surface1))
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            folder = url
            scan(url)
        }
    }

    private func scan(_ url: URL) {
        isScanning = true
        Task {
            report = await Task.detached(priority: .userInitiated) { LocalizationReport.scan(url) }.value
            isScanning = false
        }
    }
}

// MARK: - Shared

/// Title + subtitle used at the top of each Dev Utilities tool.
struct ToolHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Typography.title).foregroundStyle(Theme.TextColor.primary)
            Text(subtitle).font(Typography.monoSmall).foregroundStyle(Theme.TextColor.tertiary)
        }
    }
}

/// Read-only, selectable result with a copy button.
struct ResultBox: View {
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
                )
        }
    }
}
