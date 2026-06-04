// MARK: - EmbeddedServer.swift
// Minimal HTTP + WebSocket server that runs directly inside the iOS app.
// The iPhone becomes the server — open http://<iphone-wifi-ip>:8080 in any browser.
//
// Routes:
//   GET  /                     → single-page web UI (served from WebUI.swift)
//   GET  /ip                   → returns this device's WiFi IP (for the UI to display)
//   GET  /api/logs             → paginated NDJSON query (source, search, limit, offset)
//   GET  /api/logs/summary     → aggregate counts by source + device list
//   GET  /api/status           → collector states, screen stream state, settings
//   POST /api/collector        → toggle a named collector {name, on}
//   POST /api/screen           → start/stop screen capture {streaming}
//   POST /api/settings         → update FPS/quality {fps, quality}
//   GET  /api/export           → download all logs as NDJSON attachment
//   GET  /api/integrity        → verify hash chain across all log files
//   WS   /live                 → pushes every new LogEntry as JSON text to browser clients
//   WS   /screen               → receives JPEG frames from ScreenStreamManager,
//                                fans them out as binary messages to browser clients

import Network
import Foundation
import CommonCrypto
import UIKit
import Darwin

public final class EmbeddedServer {

    public static let shared = EmbeddedServer()

    public var port: UInt16 = 8080
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.selfsurveillance.server", qos: .utility)

    // Active WebSocket connections
    private var liveClients:   [UUID: ClientConn] = [:]
    private var screenClients: [UUID: ClientConn] = [:]
    private let lock = NSLock()

    private init() {}

    // MARK: - Start

    public func start() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        guard let p = NWEndpoint.Port(rawValue: port) else { return }
        listener = try? NWListener(using: params, on: p)

        listener?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            if case .ready = state {
                let ip = self.wifiIPAddress() ?? "iPhone-IP"
                print("[EmbeddedServer] Ready — open http://\(ip):\(self.port) in any browser")
            }
        }

        listener?.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }

        listener?.start(queue: queue)

        ImmutableLogStore.onNewEntry = { [weak self] entry in
            self?.broadcastLiveEntry(entry)
        }
    }

    public func wifiIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            let family = current.pointee.ifa_addr.pointee.sa_family
            guard family == UInt8(AF_INET) else { continue }
            let name = String(cString: current.pointee.ifa_name)
            guard name == "en0" else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(current.pointee.ifa_addr,
                        socklen_t(current.pointee.ifa_addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count),
                        nil, socklen_t(0), NI_NUMERICHOST)
            address = String(cString: hostname)
        }
        return address
    }

    // MARK: - Accept + read request (header + optional body)

    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: queue)
        readRequest(conn, buffer: Data())
    }

    private func readRequest(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, error in
            guard let self = self else { return }
            guard let chunk = data, !chunk.isEmpty, error == nil else { return }
            var buf = buffer + chunk
            guard let termRange = buf.range(of: Data("\r\n\r\n".utf8)) else {
                self.readRequest(conn, buffer: buf)
                return
            }
            let headerBlock = String(data: buf[..<termRange.lowerBound], encoding: .utf8) ?? ""
            let afterHeaders = Data(buf[termRange.upperBound...])

            let lines = headerBlock.components(separatedBy: "\r\n")
            let parts = (lines.first ?? "").components(separatedBy: " ")
            guard parts.count >= 2 else { return }
            let method   = parts[0]
            let fullPath = parts[1]
            let path     = fullPath.components(separatedBy: "?")[0]
            let query    = fullPath.contains("?") ? String(fullPath.dropFirst(path.count + 1)) : ""

            var hdr = [String: String]()
            for line in lines.dropFirst() {
                if let idx = line.firstIndex(of: ":") {
                    let k = String(line[..<idx]).trimmingCharacters(in: .whitespaces).lowercased()
                    let v = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                    hdr[k] = v
                }
            }

            // WebSocket upgrade — no body needed
            if hdr["upgrade"]?.lowercased() == "websocket", let key = hdr["sec-websocket-key"] {
                self.upgradeWebSocket(conn: conn, path: path, key: key)
                return
            }

            let contentLength = Int(hdr["content-length"] ?? "0") ?? 0
            if afterHeaders.count >= contentLength {
                self.route(conn: conn, method: method, path: path, query: query,
                           body: Data(afterHeaders.prefix(contentLength)))
            } else {
                self.continueBody(conn: conn, method: method, path: path, query: query,
                                  body: afterHeaders, needed: contentLength)
            }
        }
    }

    private func continueBody(_ conn: NWConnection,
                              method: String, path: String, query: String,
                              body: Data, needed: Int) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, error in
            guard let self = self else { return }
            guard let chunk = data, !chunk.isEmpty, error == nil else { return }
            let accumulated = body + chunk
            if accumulated.count >= needed {
                self.route(conn: conn, method: method, path: path, query: query,
                           body: Data(accumulated.prefix(needed)))
            } else {
                self.continueBody(conn: conn, method: method, path: path, query: query,
                                  body: accumulated, needed: needed)
            }
        }
    }

    // MARK: - Routing

    private func route(conn: NWConnection, method: String, path: String, query: String, body: Data) {
        let json = body.isEmpty ? [:] :
            ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:])

        switch path {

        case "/":
            send(conn, status: 200, contentType: "text/html; charset=utf-8",
                 body: WebUI.html.data(using: .utf8) ?? Data())

        case "/ip":
            let ip = wifiIPAddress() ?? "unknown"
            send(conn, status: 200, contentType: "text/plain", body: Data((ip + ":\(port)").utf8))

        // ── Logs ──────────────────────────────────────────────────────────────

        case "/api/logs":
            let params   = parseQuery(query)
            let source   = params["source"]
            let search   = params["search"]
            let limit    = Int(params["limit"]  ?? "50")  ?? 50
            let offset   = Int(params["offset"] ?? "0")   ?? 0
            let entries  = ImmutableLogStore.shared.queryEntries(
                source: source, search: search, limit: limit, offset: offset)
            let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
            let data = (try? enc.encode(entries)) ?? Data("[]".utf8)
            send(conn, status: 200, contentType: "application/json", body: data)

        case "/api/logs/summary":
            let params   = parseQuery(query)
            let summary  = ImmutableLogStore.shared.querySummary(deviceID: params["deviceID"])
            let data     = (try? JSONSerialization.data(withJSONObject: summary)) ?? Data("{}".utf8)
            send(conn, status: 200, contentType: "application/json", body: data)

        // ── Controls ──────────────────────────────────────────────────────────

        case "/api/status":
            let s    = CollectorOrchestrator.shared.status()
            let data = (try? JSONSerialization.data(withJSONObject: s)) ?? Data("{}".utf8)
            send(conn, status: 200, contentType: "application/json", body: data)

        case "/api/collector":
            if let name = json["name"] as? String, let on = json["on"] as? Bool {
                DispatchQueue.main.async {
                    CollectorOrchestrator.shared.toggle(name: name, on: on)
                }
            }
            send(conn, status: 200, contentType: "application/json", body: Data(#"{"ok":true}"#.utf8))

        case "/api/screen":
            let streaming = json["streaming"] as? Bool ?? false
            DispatchQueue.main.async {
                if streaming { ScreenStreamManager.shared.start() }
                else         { ScreenStreamManager.shared.stop()  }
            }
            send(conn, status: 200, contentType: "application/json", body: Data(#"{"ok":true}"#.utf8))

        case "/api/settings":
            if let fps = json["fps"] as? Double {
                ScreenStreamManager.shared.maxFPS = fps
            }
            if let q = json["quality"] as? Double {
                ScreenStreamManager.shared.jpegQuality = CGFloat(q)
            }
            if let url = json["syncURL"] as? String {
                SyncEngine.shared.serverBaseURL = url
            }
            send(conn, status: 200, contentType: "application/json", body: Data(#"{"ok":true}"#.utf8))

        // ── Data ──────────────────────────────────────────────────────────────

        case "/api/export":
            let ndjson = ImmutableLogStore.shared.exportAllLogs()
            let ts = Int(Date().timeIntervalSince1970)
            send(conn, status: 200, contentType: "application/x-ndjson", body: ndjson,
                 extra: ["Content-Disposition": "attachment; filename=\"logs_\(ts).ndjson\""])

        case "/api/integrity":
            let (checked, issues) = ImmutableLogStore.shared.verifyAllIntegrity()
            let issueList = issues.map { ["seq": $0.sequenceNumber, "desc": $0.description] as [String: Any] }
            let obj: [String: Any] = ["checked": checked, "issues": issueList]
            let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
            send(conn, status: 200, contentType: "application/json", body: data)

        default:
            send(conn, status: 404, contentType: "text/plain", body: Data("Not found".utf8))
        }
    }

    // MARK: - HTTP response

    private func send(_ conn: NWConnection, status: Int, contentType: String,
                      body: Data, extra: [String: String] = [:]) {
        var header = "HTTP/1.1 \(status) OK\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\n"
        for (k, v) in extra { header += "\(k): \(v)\r\n" }
        header += "\r\n"
        var response = Data(header.utf8)
        response.append(body)
        conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
    }

    // MARK: - WebSocket handshake

    private func upgradeWebSocket(conn: NWConnection, path: String, key: String) {
        let magic  = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let raw    = Data((key + magic).utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        raw.withUnsafeBytes { CC_SHA1($0.baseAddress, CC_LONG(raw.count), &digest) }
        let accept = Data(digest).base64EncodedString()

        let response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n"
        conn.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] _ in
            guard let self = self else { return }
            let client = ClientConn(id: UUID(), conn: conn)
            self.lock.lock()
            switch path {
            case "/live":   self.liveClients[client.id]   = client
            case "/screen": self.screenClients[client.id] = client
            default: break
            }
            self.lock.unlock()
            self.readWebSocketFrames(client: client, path: path)
        })
    }

    // MARK: - WebSocket frame reading (browser → server)

    private func readWebSocketFrames(client: ClientConn, path: String) {
        client.conn.receive(minimumIncompleteLength: 2, maximumLength: 131_072) { [weak self] data, _, _, error in
            guard let self = self, let data = data, data.count >= 2, error == nil else {
                self?.removeClient(id: client.id, path: path)
                return
            }
            let opcode = data[0] & 0x0F
            if opcode == 0x8 { self.removeClient(id: client.id, path: path); return }
            self.readWebSocketFrames(client: client, path: path)
        }
    }

    private func removeClient(id: UUID, path: String) {
        lock.lock()
        switch path {
        case "/live":   liveClients.removeValue(forKey: id)
        case "/screen": screenClients.removeValue(forKey: id)
        default: break
        }
        lock.unlock()
    }

    // MARK: - WebSocket frame sending (server → browser)

    private func wsFrame(data: Data, opcode: UInt8) -> Data {
        var frame = Data()
        frame.append(0x80 | opcode)
        let len = data.count
        if len < 126 {
            frame.append(UInt8(len))
        } else if len < 65536 {
            frame.append(126)
            frame.append(UInt8((len >> 8) & 0xFF))
            frame.append(UInt8(len & 0xFF))
        } else {
            frame.append(127)
            for i in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((len >> i) & 0xFF))
            }
        }
        frame.append(contentsOf: data)
        return frame
    }

    // MARK: - Broadcast

    public func broadcastLiveEntry(_ entry: LogEntry) {
        guard let json = try? JSONEncoder().encode(entry) else { return }
        let frame = wsFrame(data: json, opcode: 0x1)
        lock.lock()
        let clients = Array(liveClients.values)
        lock.unlock()
        for client in clients {
            client.conn.send(content: frame, completion: .contentProcessed { _ in })
        }
    }

    public func broadcastScreenFrame(_ jpeg: Data) {
        let frame = wsFrame(data: jpeg, opcode: 0x2)
        lock.lock()
        let clients = Array(screenClients.values)
        lock.unlock()
        for client in clients {
            client.conn.send(content: frame, completion: .contentProcessed { _ in })
        }
    }

    // MARK: - Helpers

    private func parseQuery(_ query: String) -> [String: String] {
        var result = [String: String]()
        for part in query.components(separatedBy: "&") {
            let kv = part.components(separatedBy: "=")
            if kv.count == 2 {
                result[kv[0].removingPercentEncoding ?? kv[0]] =
                       kv[1].removingPercentEncoding ?? kv[1]
            }
        }
        return result
    }
}

// MARK: - Supporting types

private final class ClientConn {
    let id: UUID
    let conn: NWConnection
    init(id: UUID, conn: NWConnection) { self.id = id; self.conn = conn }
}
