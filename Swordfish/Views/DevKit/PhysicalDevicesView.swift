import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Paired iPhones / iPads (via `devicectl`): install a build, launch an app,
/// grab a screenshot or the crash logs.
struct PhysicalDevicesView: View {
    @StateObject private var service = PhysicalDeviceService()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(service.isLoading ? String(localized: "Looking for devices…")
                                       : String(localized: "\(service.devices.count) paired device(s)"))
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                Spacer()
                ToolboxIconButton(symbol: "arrow.clockwise", help: "Refresh devices") { service.refresh() }
            }
            if service.devices.isEmpty && !service.isLoading {
                Text("Connect a device with a cable or pair it over Wi-Fi in Xcode → Devices and Simulators.")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, Spacing.sm)
            }
            ForEach(service.devices) { device in
                PhysicalDeviceRow(device: device, service: service)
            }
            if let status = service.status {
                ToolboxStatusLine(status: status)
            }
        }
        .task { service.refresh() }
    }
}

private struct PhysicalDeviceRow: View {
    let device: PhysicalDevice
    @ObservedObject var service: PhysicalDeviceService
    @State private var bundleID = ""
    @State private var deepLink = ""
    @State private var isTargeted = false

    private var busy: Bool { service.busyDeviceID == device.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: device.platform == "iOS" && (device.model ?? "").contains("iPad") ? "ipad" : "iphone")
                    .font(.system(size: 14))
                    .foregroundStyle(device.isConnected ? Theme.Semantic.ok : Theme.TextColor.tertiary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Theme.TextColor.primary)
                    Text(verbatim: [device.model, device.osVersion.map { "\(device.platform ?? "OS") \($0)" }, device.transport]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                if let udid = device.udid {
                    CopyButton(text: udid).help("Copy UDID")
                }
            }
            HStack(spacing: 4) {
                PillButton(title: "Install…", symbol: "square.and.arrow.down") { chooseBuild() }
                PillButton(title: "Screenshot", symbol: "camera") {
                    service.run(on: device) {
                        let url = try PhysicalDeviceTool.screenshot(device: device)
                        return .ok(String(localized: "Saved \(url.lastPathComponent)"), url)
                    }
                }
                PillButton(title: "Crash Logs", symbol: "ant") {
                    service.run(on: device) {
                        let url = try PhysicalDeviceTool.copyCrashLogs(device: device)
                        return .ok(String(localized: "Crash logs copied to \(url.lastPathComponent)"), url)
                    }
                }
            }
            HStack(spacing: 4) {
                TextField("Bundle ID to launch", text: $bundleID)
                    .textFieldStyle(.plain)
                    .font(Typography.mono)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            .fill(Theme.Surface.codeBg)
                    )
                PillButton(title: "Launch", symbol: "play") {
                    let id = bundleID.trimmingCharacters(in: .whitespaces)
                    guard !id.isEmpty else { return }
                    service.run(on: device) {
                        try PhysicalDeviceTool.launch(device: device.identifier, bundleID: id)
                        return .ok(String(localized: "Launched \(id)"), nil)
                    }
                }
            }
            HStack(spacing: 4) {
                TextField("Deep link (myapp://… or https://…)", text: $deepLink)
                    .textFieldStyle(.plain)
                    .font(Typography.mono)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            .fill(Theme.Surface.codeBg)
                    )
                PillButton(title: "Open URL", symbol: "link") {
                    let id = bundleID.trimmingCharacters(in: .whitespaces)
                    let link = deepLink.trimmingCharacters(in: .whitespaces)
                    guard !id.isEmpty, URL(string: link)?.scheme != nil else { return }
                    service.run(on: device) {
                        try PhysicalDeviceTool.openURL(device: device.identifier, bundleID: id, url: link)
                        return .ok(String(localized: "Opened \(link) in \(id)"), nil)
                    }
                }
                .help("Uses the bundle ID above — the app receives the URL as if it was tapped")
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.08) : Theme.Surface.surface1)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                        .strokeBorder(isTargeted ? Color.accentColor : Theme.Border.subtle, lineWidth: 1)
                )
        )
        .disabled(busy)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
        .help("Drop an .app or .ipa to install it")
    }

    private func chooseBuild() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle, UTType(filenameExtension: "ipa") ?? .data]
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            install(url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL? = (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) } ?? (item as? URL)
            guard let url, ["app", "ipa"].contains(url.pathExtension.lowercased()) else { return }
            DispatchQueue.main.async { install(url) }
        }
        return true
    }

    private func install(_ url: URL) {
        service.run(on: device) {
            try PhysicalDeviceTool.install(device: device.identifier, app: url)
            return .ok(String(localized: "Installed \(url.deletingPathExtension().lastPathComponent) on \(device.name)"), nil)
        }
    }
}
