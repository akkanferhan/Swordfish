import SwiftUI
import AppKit

struct NetworkLabView: View {
    enum Tab { case traffic, mock }

    @ObservedObject var proxy: TrafficProxy
    @ObservedObject var mock: MockServer
    @State private var tab: Tab = .traffic

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $tab) {
                    Text("Traffic").tag(Tab.traffic)
                    Text("Mock Server").tag(Tab.mock)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            Divider()
            switch tab {
            case .traffic: TrafficTab(proxy: proxy)
            case .mock:    MockTab(mock: mock)
            }
        }
        .background(Theme.Surface.popover)
    }
}

// MARK: - Traffic

private struct TrafficTab: View {
    @ObservedObject var proxy: TrafficProxy
    @AppStorage("networkLab.proxyPort") private var port = 9090
    @State private var systemProxyOn = false
    @State private var busy = false
    @State private var error: String?
    @State private var filter = ""

    private var rows: [ProxyEntry] {
        let q = filter.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return proxy.entries }
        return proxy.entries.filter { $0.host.localizedCaseInsensitiveContains(q) || $0.path.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.sm) {
                Circle().fill(proxy.isRunning ? Theme.Semantic.ok : Theme.TextColor.quaternary).frame(width: 8, height: 8)
                Text(proxy.isRunning ? "Proxy on 127.0.0.1:\(port)" : "Proxy stopped")
                    .font(Typography.monoSmall)
                Stepper("", value: $port, in: 1024...65535)
                    .labelsHidden()
                    .disabled(proxy.isRunning)
                if proxy.isRunning {
                    PillButton(title: "Stop", symbol: "stop") { stop() }
                } else {
                    AccentActionButton(title: "Start", symbol: "play.fill") { proxy.start(port: UInt16(port)) }
                }
                Divider().frame(height: 16)
                Toggle("Route this Mac (and Simulators) through it", isOn: Binding(
                    get: { systemProxyOn },
                    set: { setSystemProxy($0) }
                ))
                .toggleStyle(.checkbox)
                .font(Typography.monoSmall)
                .disabled(!proxy.isRunning || busy)
                Spacer()
                TextField("Filter host / path", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .font(Typography.mono)
                    .frame(width: 180)
                PillButton(title: "Clear", symbol: "xmark.circle") { proxy.clear() }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 6)

            if let message = error ?? proxy.lastError {
                Text(message)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.Semantic.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.md)
            }
            if systemProxyOn {
                Text("⚠︎ All of this Mac's HTTP/HTTPS traffic goes through Swordfish while this is on. It's turned off when you stop the proxy or quit.")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.Semantic.warn)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, 4)
            }
            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { entry in
                        TrafficRow(entry: entry)
                        Divider().opacity(0.4)
                    }
                }
            }
            .background(Theme.Surface.codeBg)
            .overlay {
                if rows.isEmpty {
                    Text(proxy.isRunning
                         ? "Waiting for traffic… HTTPS shows as host + bytes (it isn't decrypted)."
                         : "Start the proxy, then enable routing or point a client at 127.0.0.1:\(port).")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
        }
        .task {
            let p = UInt16(port)
            systemProxyOn = await Task.detached { SystemProxy.isEnabled(port: p) }.value
        }
    }

    private func stop() {
        if systemProxyOn { setSystemProxy(false) }
        proxy.stop()
    }

    private func setSystemProxy(_ on: Bool) {
        busy = true
        error = nil
        let p = UInt16(port)
        Task {
            let result = await Task.detached { SystemProxy.set(enabled: on, port: p) }.value
            busy = false
            if let result { error = result } else { systemProxyOn = on }
        }
    }
}

private struct TrafficRow: View {
    let entry: ProxyEntry

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(entry.started.formatted(date: .omitted, time: .standard))
                .foregroundStyle(Theme.TextColor.quaternary)
                .frame(width: 70, alignment: .leading)
            Text(entry.isTunnel ? "TLS" : entry.method)
                .foregroundStyle(entry.isTunnel ? Theme.TextColor.tertiary : Color.accentColor)
                .frame(width: 54, alignment: .leading)
            Text(statusLabel)
                .foregroundStyle(statusColor)
                .frame(width: 40, alignment: .leading)
            Text(entry.host + (entry.isTunnel ? "" : entry.path))
                .foregroundStyle(Theme.TextColor.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 4)
            Text("↑\(ByteCountFormatter.string(fromByteCount: Int64(entry.bytesUp), countStyle: .file)) ↓\(ByteCountFormatter.string(fromByteCount: Int64(entry.bytesDown), countStyle: .file))")
                .foregroundStyle(Theme.TextColor.tertiary)
            Text(entry.duration.map { String(format: "%.0f ms", $0 * 1000) } ?? "…")
                .foregroundStyle(Theme.TextColor.tertiary)
                .frame(width: 70, alignment: .trailing)
        }
        .font(Typography.monoSmall)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 4)
    }

    private var statusLabel: String {
        if entry.isTunnel { return "" }
        return entry.status.map(String.init) ?? "…"
    }

    private var statusColor: Color {
        guard let status = entry.status else { return Theme.TextColor.tertiary }
        switch status {
        case 200..<300: return Theme.Semantic.ok
        case 300..<400: return Theme.TextColor.secondary
        case 400..<500: return Theme.Semantic.warn
        default:        return Theme.Semantic.danger
        }
    }
}

// MARK: - Mock server

private struct MockTab: View {
    @ObservedObject var mock: MockServer
    @AppStorage("networkLab.mockPort") private var port = 8089
    @State private var selection: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.sm) {
                Circle().fill(mock.isRunning ? Theme.Semantic.ok : Theme.TextColor.quaternary).frame(width: 8, height: 8)
                Text(verbatim: "http://localhost:\(port)")
                    .font(Typography.mono)
                    .textSelection(.enabled)
                CopyButton(text: "http://localhost:\(port)")
                Stepper("", value: $port, in: 1024...65535)
                    .labelsHidden()
                    .disabled(mock.isRunning)
                if mock.isRunning {
                    PillButton(title: "Stop", symbol: "stop") { mock.stop() }
                } else {
                    AccentActionButton(title: "Start", symbol: "play.fill") { mock.start(port: UInt16(port)) }
                }
                Spacer()
                PillButton(title: "Add Route", symbol: "plus") {
                    let route = MockRoute()
                    mock.routes.append(route)
                    selection = route.id
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 6)
            if let error = mock.lastError {
                Text(error)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.Semantic.danger)
                    .padding(.horizontal, Spacing.md)
            }
            Divider()
            HSplitView {
                routeList.frame(minWidth: 260)
                editor.frame(minWidth: 320)
                requestLog.frame(minWidth: 220)
            }
            Text("Point your app's base URL at http://localhost:\(port). If iOS blocks plain HTTP, add NSAllowsLocalNetworking to the app's ATS settings.")
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.quaternary)
                .padding(6)
        }
    }

    private var routeList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach($mock.routes) { $route in
                    HStack(spacing: 6) {
                        Toggle("", isOn: $route.enabled).toggleStyle(.checkbox).labelsHidden()
                        Text(route.method)
                            .font(Typography.monoSmall)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 50, alignment: .leading)
                        Text(route.path)
                            .font(Typography.mono)
                            .lineLimit(1)
                        Spacer()
                        Text("\(route.status)")
                            .font(Typography.monoSmall)
                            .foregroundStyle(route.status < 400 ? Theme.Semantic.ok : Theme.Semantic.danger)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.button)
                            .fill(selection == route.id ? Color.accentColor.opacity(0.15) : Color.clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selection = route.id }
                }
            }
            .padding(Spacing.sm)
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let index = mock.routes.firstIndex(where: { $0.id == selection }) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        Picker("", selection: $mock.routes[index].method) {
                            ForEach(["ANY", "GET", "POST", "PUT", "PATCH", "DELETE"], id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                        TextField("/api/items/:id", text: $mock.routes[index].path)
                            .textFieldStyle(.roundedBorder)
                            .font(Typography.mono)
                    }
                    HStack(spacing: Spacing.sm) {
                        Text("Status").font(Typography.monoSmall)
                        TextField("200", value: $mock.routes[index].status, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text("Delay").font(Typography.monoSmall)
                        TextField("0", value: $mock.routes[index].delayMs, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        Text("ms").font(Typography.monoSmall)
                        Spacer()
                        PillButton(title: "Delete", symbol: "trash") {
                            let id = mock.routes[index].id
                            selection = nil
                            mock.routes.removeAll { $0.id == id }
                        }
                    }
                    Text("Headers").sectionTitleStyle()
                    CodeEditor(text: $mock.routes[index].headers, placeholder: "Content-Type: application/json", minHeight: 50)
                    Text("Body").sectionTitleStyle()
                    CodeEditor(text: $mock.routes[index].body, placeholder: "{ }", minHeight: 160)
                    Text("Paths: `*` matches one segment, `**` the rest, `:name` any value. First enabled match wins.")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                }
                .padding(Spacing.md)
            }
        } else {
            Text("Select or add a route")
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var requestLog: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Requests").sectionTitleStyle()
                Spacer()
                Button("Clear") { mock.clearLog() }
                    .buttonStyle(.plain)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(Spacing.sm)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(mock.log) { entry in
                        HStack(spacing: 6) {
                            Text("\(entry.status)")
                                .foregroundStyle(entry.routePath == nil ? Theme.Semantic.danger : Theme.Semantic.ok)
                            Text("\(entry.method) \(entry.path)")
                                .foregroundStyle(Theme.TextColor.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .font(Typography.monoSmall)
                    }
                }
                .padding(.horizontal, Spacing.sm)
            }
        }
    }
}

// MARK: - Window

@MainActor
final class NetworkLabWindowController: NSObject {
    private var window: NSWindow?
    let proxy = TrafficProxy()
    let mock = MockServer()

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: NetworkLabView(proxy: proxy, mock: mock)))
        window.title = String(localized: "Network Lab")
        window.setContentSize(NSSize(width: 1040, height: 620))
        window.contentMinSize = NSSize(width: 860, height: 400)
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Called at quit: never leave the Mac pointing at a proxy that's gone.
    func shutdown() {
        let stored = UserDefaults.standard.integer(forKey: "networkLab.proxyPort")
        let port = UInt16(stored == 0 ? 9090 : stored)   // @AppStorage default isn't persisted
        if proxy.isRunning, SystemProxy.isEnabled(port: port) {
            _ = SystemProxy.set(enabled: false, port: port)
        }
        proxy.stop()
        mock.stop()
    }
}
