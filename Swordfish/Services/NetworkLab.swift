import Foundation
import Network
import SystemConfiguration

// MARK: - Minimal HTTP/1.1 parsing

struct HTTPRequestHead {
    let method: String
    let target: String          // "/path?q" or "http://host/path" (proxy) or "host:443" (CONNECT)
    let version: String
    let headers: [(String, String)]

    func header(_ name: String) -> String? {
        headers.first { $0.0.caseInsensitiveCompare(name) == .orderedSame }?.1
    }

    var path: String {
        let noQuery = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? target
        return noQuery.isEmpty ? "/" : noQuery
    }

    /// Parses the bytes up to (not including) the blank line.
    static func parse(_ data: Data) -> HTTPRequestHead? {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        var lines = text.components(separatedBy: "\r\n")
        let first = lines.removeFirst().split(separator: " ", maxSplits: 2).map(String.init)
        guard first.count == 3 else { return nil }
        let headers = lines.compactMap { line -> (String, String)? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            return (String(line[..<colon]).trimmingCharacters(in: .whitespaces),
                    String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
        }
        return HTTPRequestHead(method: first[0].uppercased(), target: first[1], version: first[2], headers: headers)
    }
}

private let headerTerminator = Data("\r\n\r\n".utf8)

/// Reads from `connection` until a full header block has arrived (plus the
/// body when Content-Length says so), then hands everything over.
private func readRequest(_ connection: NWConnection, buffer: Data = Data(),
                         completion: @escaping (HTTPRequestHead?, Data, Data) -> Void) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { chunk, _, isComplete, error in
        var data = buffer
        if let chunk { data.append(chunk) }
        if let range = data.range(of: headerTerminator) {
            let headData = data[..<range.lowerBound]
            let rest = data[range.upperBound...]
            let head = HTTPRequestHead.parse(Data(headData))
            let length = Int(head?.header("Content-Length") ?? "") ?? 0
            if rest.count >= length || isComplete || error != nil || head?.method == "CONNECT" {
                completion(head, Data(headData), Data(rest))
            } else {
                readRequest(connection, buffer: data, completion: completion)
            }
        } else if isComplete || error != nil || data.count > 1_000_000 {
            completion(nil, data, Data())
        } else {
            readRequest(connection, buffer: data, completion: completion)
        }
    }
}

private func statusText(_ code: Int) -> String {
    HTTPURLResponse.localizedString(forStatusCode: code).capitalized
}

// MARK: - Traffic proxy

struct ProxyEntry: Identifiable, Equatable {
    let id = UUID()
    let started: Date
    var method: String
    var host: String
    var path: String
    var status: Int?          // nil for HTTPS tunnels
    var bytesUp = 0
    var bytesDown = 0
    var duration: TimeInterval?
    var isTunnel: Bool { method == "CONNECT" }
}

/// A small forward proxy: plain HTTP is relayed and logged in full;
/// HTTPS (CONNECT) is tunnelled untouched and logged as host + byte counts.
final class TrafficProxy: ObservableObject {
    @Published private(set) var entries: [ProxyEntry] = []
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "dev.swordfish.proxy")

    func start(port: UInt16) {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.requiredInterfaceType = .loopback   // localhost only — never exposed to the network
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready: self?.isRunning = true; self?.lastError = nil
                    case .failed(let error): self?.isRunning = false; self?.lastError = error.localizedDescription; self?.listener = nil
                    case .cancelled: self?.isRunning = false
                    default: break
                    }
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    func clear() { entries.removeAll() }

    // MARK: Connection handling (proxy queue)

    private func handle(_ client: NWConnection) {
        client.start(queue: queue)
        readRequest(client) { [weak self] head, headData, rest in
            guard let self, let head else { client.cancel(); return }
            if head.method == "CONNECT" {
                self.tunnel(client, head: head, initial: rest)
            } else {
                self.relay(client, head: head, headData: headData, body: rest)
            }
        }
    }

    private func tunnel(_ client: NWConnection, head: HTTPRequestHead, initial: Data) {
        let parts = head.target.split(separator: ":")
        let host = String(parts.first ?? "")
        let port = UInt16(parts.count > 1 ? String(parts[1]) : "443") ?? 443
        let entryID = log(ProxyEntry(started: Date(), method: "CONNECT", host: host, path: ""))
        let upstream = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        upstream.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                client.send(content: Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8), completion: .contentProcessed { _ in })
                if !initial.isEmpty { upstream.send(content: initial, completion: .contentProcessed { _ in }) }
                self?.pipe(from: client, to: upstream, entryID: entryID, upstreamDirection: true)
                self?.pipe(from: upstream, to: client, entryID: entryID, upstreamDirection: false)
            case .failed, .cancelled:
                client.cancel()
                self?.finish(entryID, status: nil)
            default: break
            }
        }
        upstream.start(queue: queue)
    }

    private func relay(_ client: NWConnection, head: HTTPRequestHead, headData: Data, body: Data) {
        guard let url = URL(string: head.target), let host = url.host else {
            client.send(content: Data("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n".utf8),
                        completion: .contentProcessed { _ in client.cancel() })
            return
        }
        let port = UInt16(url.port ?? 80)
        var path = url.path.isEmpty ? "/" : url.path
        if let query = url.query { path += "?\(query)" }
        let entryID = log(ProxyEntry(started: Date(), method: head.method, host: host, path: path, bytesUp: body.count))

        // Rewrite to origin form and force one request per connection.
        var lines = ["\(head.method) \(path) \(head.version)"]
        for (name, value) in head.headers where !["proxy-connection", "connection", "keep-alive"].contains(name.lowercased()) {
            lines.append("\(name): \(value)")
        }
        lines.append("Connection: close")
        let request = Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8) + body

        let upstream = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        upstream.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                upstream.send(content: request, completion: .contentProcessed { _ in })
                self?.pipe(from: upstream, to: client, entryID: entryID, upstreamDirection: false, parseStatus: true)
                self?.pipe(from: client, to: upstream, entryID: entryID, upstreamDirection: true)
            case .failed(let error):
                let message = "HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\nContent-Type: text/plain\r\n\r\n\(error.localizedDescription)"
                client.send(content: Data(message.utf8), completion: .contentProcessed { _ in client.cancel() })
                self?.finish(entryID, status: 502)
            default: break
            }
        }
        upstream.start(queue: queue)
    }

    /// Copies bytes one way until EOF, counting them into the log entry.
    private func pipe(from source: NWConnection, to destination: NWConnection, entryID: UUID,
                      upstreamDirection: Bool, parseStatus: Bool = false) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                var status: Int?
                if parseStatus, let line = String(data: data.prefix(64), encoding: .ascii)?.split(separator: " "),
                   line.count >= 2, line[0].hasPrefix("HTTP/") {
                    status = Int(line[1])
                }
                self?.count(entryID, bytes: data.count, up: upstreamDirection, status: status)
                destination.send(content: data, completion: .contentProcessed { _ in })
            }
            if isComplete || error != nil {
                destination.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                    destination.cancel()
                })
                source.cancel()
                self?.finish(entryID, status: nil)
                return
            }
            self?.pipe(from: source, to: destination, entryID: entryID, upstreamDirection: upstreamDirection)
        }
    }

    // MARK: Log updates (hop to main)

    private func log(_ entry: ProxyEntry) -> UUID {
        DispatchQueue.main.async {
            self.entries.insert(entry, at: 0)
            if self.entries.count > 1_000 { self.entries.removeLast(self.entries.count - 1_000) }
        }
        return entry.id
    }

    private func count(_ id: UUID, bytes: Int, up: Bool, status: Int?) {
        DispatchQueue.main.async {
            guard let i = self.entries.firstIndex(where: { $0.id == id }) else { return }
            if up { self.entries[i].bytesUp += bytes } else { self.entries[i].bytesDown += bytes }
            if let status, self.entries[i].status == nil { self.entries[i].status = status }
        }
    }

    private func finish(_ id: UUID, status: Int?) {
        DispatchQueue.main.async {
            guard let i = self.entries.firstIndex(where: { $0.id == id }), self.entries[i].duration == nil else { return }
            self.entries[i].duration = Date().timeIntervalSince(self.entries[i].started)
            if let status { self.entries[i].status = status }
        }
    }
}

// MARK: - System proxy switch

/// Points the Mac's primary network service at the local proxy (the iOS
/// Simulator uses the Mac's proxy settings). Needs the admin prompt.
enum SystemProxy {
    /// Network service name ("Wi-Fi", "USB 10/100/1000 LAN"…) of the primary interface.
    static func primaryService() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "Swordfish" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let device = global["PrimaryInterface"] as? String,
              let r = try? ProcessRunner.run("/usr/sbin/networksetup", arguments: ["-listnetworkserviceorder"]) else { return nil }
        // "(1) Wi-Fi\n(Hardware Port: Wi-Fi, Device: en0)"
        let lines = r.stdout.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() where line.contains("Device: \(device))") && i > 0 {
            let nameLine = lines[i - 1]
            if let close = nameLine.firstIndex(of: ")") {
                return String(nameLine[nameLine.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    static func isEnabled(port: UInt16) -> Bool {
        guard let service = primaryService(),
              let r = try? ProcessRunner.run("/usr/sbin/networksetup", arguments: ["-getwebproxy", service]) else { return false }
        return r.stdout.contains("Enabled: Yes") && r.stdout.contains("Port: \(port)")
    }

    /// nil on success, otherwise an error message.
    static func set(enabled: Bool, port: UInt16) -> String? {
        guard let service = primaryService() else { return String(localized: "Couldn't find the active network service") }
        let s = service.replacingOccurrences(of: "'", with: "'\\''")
        let script = enabled
            ? "/usr/sbin/networksetup -setwebproxy '\(s)' 127.0.0.1 \(port) && /usr/sbin/networksetup -setsecurewebproxy '\(s)' 127.0.0.1 \(port)"
            : "/usr/sbin/networksetup -setwebproxystate '\(s)' off && /usr/sbin/networksetup -setsecurewebproxystate '\(s)' off"
        return AdminShell.runScript(script, prompt: enabled
            ? String(localized: "Swordfish needs your password to route this Mac's traffic through its proxy.")
            : String(localized: "Swordfish needs your password to turn its proxy off."))
    }
}

// MARK: - Mock server

struct MockRoute: Identifiable, Codable, Equatable {
    var id = UUID()
    var enabled = true
    var method = "GET"          // or "ANY"
    var path = "/api/items"     // `*` and `:param` segments allowed
    var status = 200
    var delayMs = 0
    var headers = "Content-Type: application/json"
    var body = "{\n  \"items\": []\n}"

    func matches(method m: String, path p: String) -> Bool {
        guard enabled, method == "ANY" || method == m else { return false }
        let want = path.split(separator: "/", omittingEmptySubsequences: true)
        let have = p.split(separator: "/", omittingEmptySubsequences: true)
        for (i, segment) in want.enumerated() {
            if segment == "**" { return true }
            guard i < have.count else { return false }
            if segment == "*" || segment.hasPrefix(":") { continue }
            if !UniversalLinkValidator.wildcard(String(segment), matches: String(have[i])) { return false }
        }
        return want.count == have.count
    }
}

struct MockLogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let method: String
    let path: String
    let status: Int
    let routePath: String?
}

final class MockServer: ObservableObject {
    @Published var routes: [MockRoute] = MockServer.loadRoutes() { didSet { saveRoutes() } }
    @Published private(set) var log: [MockLogEntry] = []
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "dev.swordfish.mock")
    /// Snapshot read from the network queue.
    private var routesSnapshot: [MockRoute] = []
    private let lock = NSLock()

    func start(port: UInt16) {
        guard listener == nil else { return }
        updateSnapshot()
        do {
            let params = NWParameters.tcp
            params.requiredInterfaceType = .loopback   // localhost only — never exposed to the network
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready: self?.isRunning = true; self?.lastError = nil
                    case .failed(let error): self?.isRunning = false; self?.lastError = error.localizedDescription; self?.listener = nil
                    case .cancelled: self?.isRunning = false
                    default: break
                    }
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    func clearLog() { log.removeAll() }

    private func updateSnapshot() {
        lock.lock(); routesSnapshot = routes; lock.unlock()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        readRequest(connection) { [weak self] head, _, _ in
            guard let self, let head else { connection.cancel(); return }
            self.lock.lock()
            let route = self.routesSnapshot.first { $0.matches(method: head.method, path: head.path) }
            self.lock.unlock()

            var status = 404
            var headerLines = ["Content-Type: application/json"]
            var body = Data("{\"error\":\"No mock route for \(head.method) \(head.path)\"}".utf8)
            var delay = 0
            if head.method == "OPTIONS" {
                status = 204
                body = Data()
            } else if let route {
                status = route.status
                headerLines = route.headers.split(separator: "\n").map(String.init).filter { $0.contains(":") }
                body = Data(route.body.utf8)
                delay = route.delayMs
            }
            var response = "HTTP/1.1 \(status) \(statusText(status))\r\n"
            for line in headerLines { response += line.trimmingCharacters(in: .whitespaces) + "\r\n" }
            response += "Access-Control-Allow-Origin: *\r\n"
            response += "Access-Control-Allow-Headers: *\r\n"
            response += "Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS\r\n"
            response += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            let payload = Data(response.utf8) + body

            let entry = MockLogEntry(method: head.method, path: head.target, status: status, routePath: route?.path)
            DispatchQueue.main.async {
                self.log.insert(entry, at: 0)
                if self.log.count > 500 { self.log.removeLast() }
            }
            self.queue.asyncAfter(deadline: .now() + .milliseconds(delay)) {
                connection.send(content: payload, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }

    // MARK: Persistence

    private static var routesFile: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Swordfish/mock-routes.json")
    }

    private static func loadRoutes() -> [MockRoute] {
        guard let data = try? Data(contentsOf: routesFile),
              let routes = try? JSONDecoder().decode([MockRoute].self, from: data) else { return [MockRoute()] }
        return routes
    }

    private func saveRoutes() {
        updateSnapshot()
        try? FileManager.default.createDirectory(at: Self.routesFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(routes).write(to: Self.routesFile, options: .atomic)
    }
}
