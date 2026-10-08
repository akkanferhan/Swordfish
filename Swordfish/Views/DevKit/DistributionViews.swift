import SwiftUI
import AppKit

// MARK: - App Store Connect

struct AppStoreConnectView: View {
    @EnvironmentObject var monitor: AppStoreConnectMonitor
    @Environment(\.popoverController) private var popoverController
    @AppStorage(ASCSettings.notifyKey) private var notify = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if !monitor.hasKey {
                HStack(spacing: Spacing.sm) {
                    Text("Add an App Store Connect API key (Users and Access → Integrations) to see builds here.")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    PillButton(title: "Add Key…", symbol: "key") { popoverController?.openSettings() }
                }
            } else {
                HStack(spacing: Spacing.sm) {
                    Toggle("Notify when processing finishes", isOn: $notify)
                        .toggleStyle(.checkbox)
                        .font(Typography.monoSmall)
                    Spacer()
                    if let updated = monitor.lastUpdated {
                        Text(updated.formatted(date: .omitted, time: .shortened))
                            .font(Typography.monoSmall)
                            .foregroundStyle(Theme.TextColor.quaternary)
                    }
                    ToolboxIconButton(symbol: monitor.isLoading ? "hourglass" : "arrow.clockwise", help: "Refresh") {
                        monitor.refresh()
                    }
                }
                if let error = monitor.lastError {
                    Text(error)
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.Semantic.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 3) {
                    ForEach(monitor.builds.prefix(10)) { build in
                        buildRow(build)
                    }
                }
                if monitor.builds.isEmpty && !monitor.isLoading && monitor.lastError == nil {
                    Text("No builds yet")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                }
            }
        }
        .onAppear { monitor.refresh() }
    }

    private func buildRow(_ build: ASCBuild) -> some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(build.appName) \(build.title)")
                    .font(Typography.bodyMedium)
                    .foregroundStyle(Theme.TextColor.primary)
                    .lineLimit(1)
                Text(verbatim: [build.bundleID, build.uploaded.map { RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date()) }]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            if build.expired {
                Badge(label: String(localized: "Expired"), tint: Theme.TextColor.tertiary)
            }
            Badge(label: build.state.label, tint: tint(build.state))
            if let url = build.testFlightURL {
                ToolboxIconButton(symbol: "arrow.up.right.square", help: "Open in App Store Connect") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: Radius.row).fill(Theme.Surface.surface1))
    }

    private func tint(_ state: ASCBuild.State) -> Color {
        switch state {
        case .processing:        return Theme.Semantic.warn
        case .valid:             return Theme.Semantic.ok
        case .failed, .invalid:  return Theme.Semantic.danger
        case .unknown:           return Theme.TextColor.tertiary
        }
    }
}

// MARK: - Apple Developer system status

struct AppleServiceStatus: Identifiable {
    let name: String
    let url: URL?
    let issues: [String]       // messages of ongoing events
    let resolvedToday: Int
    var id: String { name }
    var isHealthy: Bool { issues.isEmpty }
}

enum AppleStatusFeed {
    /// The JSONP feed behind developer.apple.com/system-status.
    static func fetch() async throws -> [AppleServiceStatus] {
        let url = URL(string: "https://www.apple.com/support/systemstatus/data/developer/system_status_en_US.js")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let text = String(decoding: data, as: UTF8.self)
        guard let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")"), open < close,
              let json = try JSONSerialization.jsonObject(with: Data(text[text.index(after: open)..<close].utf8)) as? [String: Any],
              let services = json["services"] as? [[String: Any]] else {
            throw AppleAPIError(message: String(localized: "Unexpected status feed format"))
        }
        let dayAgo = Date().addingTimeInterval(-24 * 3600).timeIntervalSince1970 * 1000
        return services.compactMap { service in
            guard let name = service["serviceName"] as? String else { return nil }
            let events = service["events"] as? [[String: Any]] ?? []
            let ongoing = events.filter { ($0["eventStatus"] as? String) != "resolved" && ($0["eventStatus"] as? String) != "completed" }
            let resolved = events.filter {
                ($0["eventStatus"] as? String) == "resolved" && (($0["epochEndDate"] as? Double) ?? 0) > dayAgo
            }
            return AppleServiceStatus(
                name: name.trimmingCharacters(in: .whitespaces),
                url: (service["redirectUrl"] as? String).flatMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) },
                issues: ongoing.compactMap { $0["message"] as? String },
                resolvedToday: resolved.count
            )
        }
    }
}

struct AppleStatusView: View {
    @State private var services: [AppleServiceStatus] = []
    @State private var error: String?
    @State private var showAll = false

    /// The services iOS developers hit most.
    private static let highlighted = ["APNS", "APNS Sandbox", "App Store Connect", "App Store Connect - TestFlight",
                                      "App Store Connect - App Processing", "App Store Connect - App Upload",
                                      "App Store Connect API", "Certificates, Identifiers & Profiles",
                                      "Developer ID Notary Service", "Xcode Cloud", "CloudKit Database", "Sign in with Apple"]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            let problems = services.filter { !$0.isHealthy }
            HStack(spacing: Spacing.sm) {
                Image(systemName: problems.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(problems.isEmpty ? Theme.Semantic.ok : Theme.Semantic.warn)
                Text(services.isEmpty ? String(localized: "Loading…")
                     : problems.isEmpty ? String(localized: "All developer services operational")
                     : String(localized: "\(problems.count) service(s) with issues"))
                    .font(Typography.bodyMedium)
                Spacer()
                Toggle("All", isOn: $showAll)
                    .toggleStyle(.checkbox)
                    .font(Typography.monoSmall)
                ToolboxIconButton(symbol: "arrow.clockwise", help: "Refresh") { Task { await load() } }
            }
            if let error {
                Text(error).font(Typography.monoSmall).foregroundStyle(Theme.Semantic.danger)
            }
            let shown = showAll ? services
                : services.filter { !$0.isHealthy || Self.highlighted.contains($0.name) }
            VStack(spacing: 2) {
                ForEach(shown) { service in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(service.isHealthy ? Theme.Semantic.ok : Theme.Semantic.warn)
                                .frame(width: 7, height: 7)
                            Text(service.name)
                                .font(Typography.monoSmall)
                                .foregroundStyle(Theme.TextColor.secondary)
                            if service.resolvedToday > 0 {
                                Text("resolved issue today")
                                    .font(Typography.monoSmall)
                                    .foregroundStyle(Theme.TextColor.quaternary)
                            }
                            Spacer()
                        }
                        ForEach(service.issues, id: \.self) { issue in
                            Text(issue)
                                .font(Typography.monoSmall)
                                .foregroundStyle(Theme.Semantic.warn)
                                .padding(.leading, 13)
                        }
                    }
                }
            }
            Button("developer.apple.com/system-status") {
                NSWorkspace.shared.open(URL(string: "https://developer.apple.com/system-status/")!)
            }
            .buttonStyle(.plain)
            .font(Typography.monoSmall)
            .foregroundStyle(Color.accentColor)
        }
        .task { await load() }
    }

    private func load() async {
        do {
            services = try await AppleStatusFeed.fetch()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
