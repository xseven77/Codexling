import Foundation
import Network

// MARK: - Mobile Sync Data Models

public struct MobileTaskPayload: Codable, Equatable, Sendable {
    public let id: String
    public let state: String
    public let title: String
    public let agent: String

    public init(id: String, state: String, title: String, agent: String) {
        self.id = id
        self.state = state
        self.title = title
        self.agent = agent
    }
}

public struct MobileActivityPayload: Codable, Equatable, Sendable {
    public let state: String
    public let activeTaskCount: Int
    public let activeTasks: [MobileTaskPayload]

    public init(state: String, activeTaskCount: Int, activeTasks: [MobileTaskPayload]) {
        self.state = state
        self.activeTaskCount = activeTaskCount
        self.activeTasks = activeTasks
    }
}

public struct MobileConnectionPayload: Codable, Equatable, Sendable {
    public let id: String
    public let provider: String
    public let label: String
    public let isHealthy: Bool
    public let shortWindowRemaining: Double?
    public let weeklyRemaining: Double?
    public let balance: String?

    public init(
        id: String,
        provider: String,
        label: String,
        isHealthy: Bool,
        shortWindowRemaining: Double? = nil,
        weeklyRemaining: Double? = nil,
        balance: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.label = label
        self.isHealthy = isHealthy
        self.shortWindowRemaining = shortWindowRemaining
        self.weeklyRemaining = weeklyRemaining
        self.balance = balance
    }
}

public struct MobileSnapshotPayload: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let activePetId: String
    public let activity: MobileActivityPayload
    public let connections: [MobileConnectionPayload]

    public init(
        schemaVersion: Int = 1,
        generatedAt: Date = Date(),
        activePetId: String,
        activity: MobileActivityPayload,
        connections: [MobileConnectionPayload]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.activePetId = activePetId
        self.activity = activity
        self.connections = connections
    }
}

public struct MobilePetMetadata: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let description: String
    public let frameWidth: Int
    public let frameHeight: Int
    public let totalRows: Int
    public let totalColumns: Int
    public let actionRowMap: [String: Int]

    public init(
        id: String,
        displayName: String,
        description: String,
        frameWidth: Int = 192,
        frameHeight: Int = 208,
        totalRows: Int = 11,
        totalColumns: Int = 8,
        actionRowMap: [String: Int] = [
            "idle": 0,
            "waving": 3,
            "jumping": 4,
            "failed": 5,
            "waiting": 6,
            "running": 7,
            "review": 8
        ]
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.totalRows = totalRows
        self.totalColumns = totalColumns
        self.actionRowMap = actionRowMap
    }
}

// MARK: - Mobile Sync Data Provider

public protocol MobileSyncDataProvider: AnyObject, Sendable {
    func makeSnapshot() async -> MobileSnapshotPayload
    func availablePets() -> [MobilePetMetadata]
}

// MARK: - Mobile Sync Server

public final class MobileSyncServer: @unchecked Sendable {
    public static let defaultPort: UInt16 = 58350

    public static var defaultPluginDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Codexling/Plugins/mobile-web")
    }

    public let port: NWEndpoint.Port
    public let token: String
    public let pluginDirectoryURL: URL
    private let dataProvider: any MobileSyncDataProvider
    private let queue = DispatchQueue(label: "com.qiizo.Codexling.mobile-sync", qos: .userInitiated)

    private var listener: NWListener?
    private var isRunning = false
    private let lock = NSLock()
    private var sseClients: [UUID: NWConnection] = [:]

    public init(
        port: UInt16 = MobileSyncServer.defaultPort,
        token: String,
        pluginDirectoryURL: URL = MobileSyncServer.defaultPluginDirectoryURL,
        dataProvider: any MobileSyncDataProvider
    ) {
        self.port = NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(rawValue: 58350)!
        self.token = token
        self.pluginDirectoryURL = pluginDirectoryURL
        self.dataProvider = dataProvider
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }

        guard !isRunning else { return }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: port)

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.stop()
            }
        }

        listener.start(queue: queue)
        self.listener = listener
        self.isRunning = true
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        guard isRunning else { return }
        isRunning = false

        for connection in sseClients.values {
            connection.cancel()
        }
        sseClients.removeAll()

        listener?.cancel()
        listener = nil
    }

    public func broadcast(event: String, data: String) {
        lock.lock()
        let clients = Array(sseClients.values)
        lock.unlock()

        guard !clients.isEmpty else { return }
        let payload = "event: \(event)\ndata: \(data)\n\n"
        guard let rawData = payload.data(using: .utf8) else { return }

        for client in clients {
            client.send(content: rawData, completion: .contentProcessed({ _ in }))
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection)
    }

    private func receiveRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil {
                connection.cancel()
                return
            }
            guard let data, let requestText = String(data: data, encoding: .utf8) else {
                if isComplete { connection.cancel() }
                return
            }

            self.processRequest(requestText, on: connection)
        }
    }

    private func processRequest(_ requestText: String, on connection: NWConnection) {
        let lines = requestText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            sendResponse(status: 400, headers: [:], body: "Bad Request", on: connection)
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendResponse(status: 400, headers: [:], body: "Bad Request", on: connection)
            return
        }

        let method = String(parts[0])
        let rawPath = String(parts[1])

        // Parse path and query parameters
        let pathComponents = rawPath.components(separatedBy: "?")
        let requestPath = pathComponents[0]
        let queryParams = parseQuery(pathComponents.count > 1 ? pathComponents[1] : nil)

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            let headerParts = line.split(separator: ":", maxSplits: 1)
            if headerParts.count == 2 {
                let name = headerParts[0].trimmingCharacters(in: .whitespaces).lowercased()
                let value = headerParts[1].trimmingCharacters(in: .whitespaces)
                headers[name] = value
            }
        }

        // 1. Public health check
        if requestPath == "/health" {
            sendJSONResponse(status: 200, object: ["status": "ok"], on: connection)
            return
        }

        // 2. Mobile API Endpoints (Bearer Token or Query Token)
        if requestPath.hasPrefix("/mobile/") {
            guard validateAuth(headers: headers, queryParams: queryParams) else {
                sendJSONResponse(status: 401, object: ["error": "unauthorized"], on: connection)
                return
            }

            switch (method, requestPath) {
            case ("GET", "/mobile/snapshot"):
                Task {
                    let snapshot = await self.dataProvider.makeSnapshot()
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    if let data = try? encoder.encode(snapshot),
                       let jsonString = String(data: data, encoding: .utf8) {
                        self.sendResponse(status: 200, headers: ["Content-Type": "application/json"], body: jsonString, on: connection)
                    } else {
                        self.sendResponse(status: 500, headers: [:], body: "Internal Server Error", on: connection)
                    }
                }

            case ("GET", "/mobile/pets"):
                let pets = self.dataProvider.availablePets()
                let encoder = JSONEncoder()
                if let data = try? encoder.encode(pets),
                   let jsonString = String(data: data, encoding: .utf8) {
                    self.sendResponse(status: 200, headers: ["Content-Type": "application/json"], body: jsonString, on: connection)
                } else {
                    self.sendResponse(status: 500, headers: [:], body: "Internal Server Error", on: connection)
                }

            case ("GET", "/mobile/events"):
                startSSEStream(on: connection)

            default:
                sendResponse(status: 404, headers: [:], body: "Not Found", on: connection)
            }
            return
        }

        // 3. Desktop Plugin Static Web Hosting (GET / or static files)
        if method == "GET" {
            servePluginStaticContent(path: requestPath, on: connection)
            return
        }

        sendResponse(status: 404, headers: [:], body: "Not Found", on: connection)
    }

    private func servePluginStaticContent(path: String, on connection: NWConnection) {
        let relativePath = (path == "/" || path.isEmpty) ? "index.html" : String(path.dropFirst())
        let fileURL = pluginDirectoryURL.appendingPathComponent(relativePath)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let fileData = try? Data(contentsOf: fileURL) {
                let mime = mimeType(for: fileURL.pathExtension)
                sendRawResponse(status: 200, headers: ["Content-Type": mime], data: fileData, on: connection)
                return
            }
        }

        // Fallback: If root is requested but plugin not installed, serve friendly status page
        if path == "/" || path == "/index.html" {
            let fallbackHTML = """
            <!DOCTYPE html>
            <html lang="zh-CN">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width,initial-scale=1">
              <title>Codexling Mobile Web</title>
              <style>
                body { background: #121214; color: #e4e4e7; font-family: system-ui, -apple-system, sans-serif; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 24px; box-sizing: border-box; }
                .card { max-width: 440px; background: #18181b; border: 1px solid rgba(255,255,255,0.08); border-radius: 16px; padding: 32px; text-align: center; box-shadow: 0 8px 32px rgba(0,0,0,0.4); }
                h1 { color: #f59e0b; font-size: 20px; margin-top: 0; letter-spacing: -0.02em; }
                p { color: #a1a1aa; font-size: 14px; line-height: 1.6; margin: 12px 0; }
                .badge { display: inline-block; background: rgba(16,185,129,0.15); color: #10b981; padding: 6px 14px; border-radius: 9999px; font-size: 12px; font-weight: 500; margin-top: 16px; }
                .path { font-family: ui-monospace, monospace; background: #27272a; padding: 3px 8px; border-radius: 6px; font-size: 12px; color: #e4e4e7; word-break: break-all; }
              </style>
            </head>
            <body>
              <div class="card">
                <h1>Codexling Mobile Web</h1>
                <p>Web 伴生前端插件尚未安装或尚未启用。</p>
                <p>请将 <span class="path">mobile-web</span> 插件包导入至桌面端插件目录。</p>
                <div class="badge">● 局域网 API 广播服务正常运行中 (端口: 58350)</div>
              </div>
            </body>
            </html>
            """
            sendResponse(status: 200, headers: ["Content-Type": "text/html; charset=utf-8"], body: fallbackHTML, on: connection)
            return
        }

        sendResponse(status: 404, headers: [:], body: "Not Found", on: connection)
    }

    private func parseQuery(_ query: String?) -> [String: String] {
        guard let query else { return [:] }
        var dict: [String: String] = [:]
        for item in query.components(separatedBy: "&") {
            let pair = item.components(separatedBy: "=")
            if pair.count == 2 {
                dict[pair[0]] = pair[1].removingPercentEncoding ?? pair[1]
            }
        }
        return dict
    }

    private func validateAuth(headers: [String: String], queryParams: [String: String]) -> Bool {
        if let auth = headers["authorization"] {
            let expected = "Bearer \(token)"
            if auth == expected { return true }
        }
        if let queryToken = queryParams["token"], queryToken == token {
            return true
        }
        return false
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": "text/html; charset=utf-8"
        case "js", "mjs": "application/javascript; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "json": "application/json; charset=utf-8"
        case "webp": "image/webp"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "svg": "image/svg+xml"
        case "ico": "image/x-icon"
        case "woff2": "font/woff2"
        default: "application/octet-stream"
        }
    }

    private func sendResponse(
        status: Int,
        headers: [String: String],
        body: String,
        on connection: NWConnection
    ) {
        let bodyData = body.data(using: .utf8) ?? Data()
        sendRawResponse(status: status, headers: headers, data: bodyData, on: connection)
    }

    private func sendRawResponse(
        status: Int,
        headers: [String: String],
        data: Data,
        on connection: NWConnection
    ) {
        var response = "HTTP/1.1 \(status) \(statusMessage(for: status))\r\n"
        var finalHeaders = headers
        finalHeaders["Content-Length"] = "\(data.count)"
        finalHeaders["Connection"] = "close"

        for (k, v) in finalHeaders {
            response += "\(k): \(v)\r\n"
        }
        response += "\r\n"

        var fullData = response.data(using: .utf8) ?? Data()
        fullData.append(data)

        connection.send(content: fullData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    private func sendJSONResponse(status: Int, object: Any, on connection: NWConnection) {
        if let data = try? JSONSerialization.data(withJSONObject: object),
           let string = String(data: data, encoding: .utf8) {
            sendResponse(status: status, headers: ["Content-Type": "application/json"], body: string, on: connection)
        } else {
            sendResponse(status: 500, headers: [:], body: "Internal Error", on: connection)
        }
    }

    private func startSSEStream(on connection: NWConnection) {
        let clientID = UUID()
        lock.lock()
        sseClients[clientID] = connection
        lock.unlock()

        let initialResponse = "HTTP/1.1 200 OK\r\n"
            + "Content-Type: text/event-stream\r\n"
            + "Cache-Control: no-cache\r\n"
            + "Connection: keep-alive\r\n\r\n"
            + ": keepalive\n\n"

        guard let initialData = initialResponse.data(using: .utf8) else {
            connection.cancel()
            return
        }

        connection.send(content: initialData, completion: .contentProcessed({ [weak self] error in
            if error != nil {
                self?.removeSSEClient(id: clientID)
                connection.cancel()
            }
        }))
    }

    private func removeSSEClient(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        sseClients.removeValue(forKey: id)
    }

    private func statusMessage(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 500: "Internal Server Error"
        default: "Status \(status)"
        }
    }
}
