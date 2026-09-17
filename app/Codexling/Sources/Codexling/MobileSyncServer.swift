import Foundation
import Network

// MARK: - Mobile Sync Data Models

public struct MobileTaskPayload: Codable, Equatable, Sendable {
    public let id: String
    public let state: String
    public let title: String
    public let agent: String
    public let detail: String?
    public let model: String?
    public let workspaceName: String?
    public let gitBranch: String?

    public init(
        id: String,
        state: String,
        title: String,
        agent: String,
        detail: String? = nil,
        model: String? = nil,
        workspaceName: String? = nil,
        gitBranch: String? = nil
    ) {
        self.id = id
        self.state = state
        self.title = title
        self.agent = agent
        self.detail = detail
        self.model = model
        self.workspaceName = workspaceName
        self.gitBranch = gitBranch
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

public struct MobileResetCouponPayload: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let description: String?
    public let source: String?
    public let grantedAt: String?
    public let expiresAt: String
    public let status: String?
    public let resetType: String?
    /// Avatar of the account that granted the coupon. Without this the client
    /// can only draw a generic placeholder, which is what the mobile web used to
    /// do while the desktop showed the real Codex avatar.
    public let profileImageURL: String?
    /// Preferred display name (`Codex Team`); `source` is only the fallback.
    public let profileUserID: String?

    public init(
        id: String,
        title: String,
        description: String? = nil,
        source: String? = nil,
        grantedAt: String? = nil,
        expiresAt: String,
        status: String? = nil,
        resetType: String? = nil,
        profileImageURL: String? = nil,
        profileUserID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.source = source
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
        self.status = status
        self.resetType = resetType
        self.profileImageURL = profileImageURL
        self.profileUserID = profileUserID
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
    public let accountName: String?
    public let email: String?
    public let planName: String?
    public let shortWindowLabel: String?
    public let shortWindowResetAt: String?
    public let weeklyWindowLabel: String?
    public let weeklyWindowResetAt: String?
    public let claudeGptFiveHourRemaining: Double?
    public let claudeGptWeeklyRemaining: Double?
    public let subscriptionActiveUntilISO: String?
    public let subscriptionWillRenew: Bool?
    public let subscriptionDaysRemaining: Int?
    public let subscriptionReminderMessage: String?
    public let subscriptionRenewalLine: String?
    public let resetCoupons: [MobileResetCouponPayload]?
    public let keySuffix: String?
    public let statusColor: String?
    public let toppedUp: String?
    public let granted: String?
    public let availableModelCount: Int?
    public let availableModelIDs: [String]?
    public let lastValidatedAt: String?

    public init(
        id: String,
        provider: String,
        label: String,
        isHealthy: Bool,
        shortWindowRemaining: Double? = nil,
        weeklyRemaining: Double? = nil,
        balance: String? = nil,
        accountName: String? = nil,
        email: String? = nil,
        planName: String? = nil,
        shortWindowLabel: String? = nil,
        shortWindowResetAt: String? = nil,
        weeklyWindowLabel: String? = nil,
        weeklyWindowResetAt: String? = nil,
        claudeGptFiveHourRemaining: Double? = nil,
        claudeGptWeeklyRemaining: Double? = nil,
        subscriptionActiveUntilISO: String? = nil,
        subscriptionWillRenew: Bool? = nil,
        subscriptionDaysRemaining: Int? = nil,
        subscriptionReminderMessage: String? = nil,
        subscriptionRenewalLine: String? = nil,
        resetCoupons: [MobileResetCouponPayload]? = nil,
        keySuffix: String? = nil,
        statusColor: String? = nil,
        toppedUp: String? = nil,
        granted: String? = nil,
        availableModelCount: Int? = nil,
        availableModelIDs: [String]? = nil,
        lastValidatedAt: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.label = label
        self.isHealthy = isHealthy
        self.shortWindowRemaining = shortWindowRemaining
        self.weeklyRemaining = weeklyRemaining
        self.balance = balance
        self.accountName = accountName
        self.email = email
        self.planName = planName
        self.shortWindowLabel = shortWindowLabel
        self.shortWindowResetAt = shortWindowResetAt
        self.weeklyWindowLabel = weeklyWindowLabel
        self.weeklyWindowResetAt = weeklyWindowResetAt
        self.claudeGptFiveHourRemaining = claudeGptFiveHourRemaining
        self.claudeGptWeeklyRemaining = claudeGptWeeklyRemaining
        self.subscriptionActiveUntilISO = subscriptionActiveUntilISO
        self.subscriptionWillRenew = subscriptionWillRenew
        self.subscriptionDaysRemaining = subscriptionDaysRemaining
        self.subscriptionReminderMessage = subscriptionReminderMessage
        self.subscriptionRenewalLine = subscriptionRenewalLine
        self.resetCoupons = resetCoupons
        self.keySuffix = keySuffix
        self.statusColor = statusColor
        self.toppedUp = toppedUp
        self.granted = granted
        self.availableModelCount = availableModelCount
        self.availableModelIDs = availableModelIDs
        self.lastValidatedAt = lastValidatedAt
    }
}

public struct MobileSnapshotPayload: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let activePetId: String
    public let todayMinutes: Int
    public let activity: MobileActivityPayload
    public let connections: [MobileConnectionPayload]

    public init(
        schemaVersion: Int = 1,
        generatedAt: Date = Date(),
        activePetId: String,
        todayMinutes: Int = 0,
        activity: MobileActivityPayload,
        connections: [MobileConnectionPayload]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.activePetId = activePetId
        self.todayMinutes = todayMinutes
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

// MARK: - Mobile Credentials Export Payload

public struct MobileCredentialAccountPayload: Codable, Equatable, Sendable {
    public let id: String
    public let provider: String
    public let label: String
    public let tokenOrKey: String

    public init(id: String, provider: String, label: String, tokenOrKey: String) {
        self.id = id
        self.provider = provider
        self.label = label
        self.tokenOrKey = tokenOrKey
    }
}

public struct MobileCredentialsExportPayload: Codable, Equatable, Sendable {
    public let exportedAt: Date
    public let accounts: [MobileCredentialAccountPayload]

    public init(exportedAt: Date = Date(), accounts: [MobileCredentialAccountPayload]) {
        self.exportedAt = exportedAt
        self.accounts = accounts
    }
}

// MARK: - Mobile Sync Data Provider

public protocol MobileSyncDataProvider: AnyObject, Sendable {
    func makeSnapshot() async -> MobileSnapshotPayload
    func availablePets() -> [MobilePetMetadata]
    func exportCredentials() async -> MobileCredentialsExportPayload
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
    /// Set by an intentional `stop()` so a scheduled rebind cannot resurrect a
    /// server the app asked to shut down.
    private var isShuttingDown = false
    private var rebindAttempt = 0
    private static let maxRebindAttempts = 6

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

    public enum Status: Equatable, Sendable {
        case idle
        case starting
        case ready
        case failed(String)
    }

    /// Observed by the manager so the UI reflects reality instead of an assumption.
    public var onStatusChange: (@Sendable (Status) -> Void)?

    public private(set) var status: Status = .idle {
        didSet { onStatusChange?(status) }
    }

    /// True while a backoff rebind is pending, so the UI can say "retrying"
    /// instead of just "failed".
    public private(set) var isAwaitingRetry = false

    /// Starts the listener.
    ///
    /// Note that `NWListener` binds **asynchronously**: `start(queue:)` only
    /// schedules the bind, and a busy port is reported later through
    /// `stateUpdateHandler` as `.failed` — not as a thrown error. Treating a
    /// non-throwing return as success is what previously let the server die
    /// silently (no status, no error, no retry) after a `restart()` raced with
    /// the cancellation of the previous listener.
    public func start() throws {
        lock.lock()
        isShuttingDown = false
        guard listener == nil else {
            lock.unlock()
            return
        }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: port)
        self.listener = listener
        status = .starting
        lock.unlock()

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        // `weak listener` keeps a stale listener's late state transitions from
        // clobbering the state of the one that replaced it.
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self, let listener else { return }
            self.lock.lock()
            let isCurrent = self.listener === listener
            self.lock.unlock()
            guard isCurrent else { return }
            self.handleListenerState(state)
        }

        listener.start(queue: queue)
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            lock.lock()
            isRunning = true
            rebindAttempt = 0
            isAwaitingRetry = false
            status = .ready
            lock.unlock()

        case .failed(let error):
            lock.lock()
            listener?.cancel()
            listener = nil
            isRunning = false
            let attempt = rebindAttempt
            rebindAttempt += 1
            status = .failed(Self.describe(error))
            isAwaitingRetry = attempt < Self.maxRebindAttempts
            lock.unlock()
            scheduleRebind(afterAttempt: attempt)

        case .cancelled:
            lock.lock()
            isRunning = false
            if case .ready = status { status = .idle }
            lock.unlock()

        default:
            break
        }
    }

    /// Bounded exponential backoff so a transient port conflict self-heals.
    private func scheduleRebind(afterAttempt attempt: Int) {
        guard attempt < Self.maxRebindAttempts else { return }
        let delay = min(pow(2.0, Double(attempt)), 8.0)

        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let shuttingDown = self.isShuttingDown
            let alreadyListening = self.listener != nil
            self.lock.unlock()
            guard !shuttingDown, !alreadyListening else { return }
            try? self.start()
        }
    }

    private static func describe(_ error: NWError) -> String {
        switch error {
        case .posix(let code):
            if code == .EADDRINUSE { return "端口 \(code) 已被占用" }
            return "网络错误 \(code.rawValue)"
        default:
            return "\(error)"
        }
    }

    public func stop() {
        lock.lock()
        isShuttingDown = true
        isRunning = false
        rebindAttempt = 0
        isAwaitingRetry = false

        let clients = Array(sseClients.values)
        sseClients.removeAll()

        listener?.cancel()
        listener = nil
        status = .idle
        lock.unlock()

        for connection in clients {
            connection.cancel()
        }
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
        var bodyStartIndex = lines.count
        for (idx, line) in lines.enumerated().dropFirst() {
            if line.isEmpty {
                bodyStartIndex = idx + 1
                break
            }
            let headerParts = line.split(separator: ":", maxSplits: 1)
            if headerParts.count == 2 {
                let name = headerParts[0].trimmingCharacters(in: .whitespaces).lowercased()
                let value = headerParts[1].trimmingCharacters(in: .whitespaces)
                headers[name] = value
            }
        }
        let requestBody = lines.dropFirst(bodyStartIndex).joined(separator: "\r\n")

        // 0. Handle CORS preflight
        if method == "OPTIONS" {
            sendResponse(status: 204, headers: [
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Headers": "*",
                "Access-Control-Allow-Methods": "GET, POST, OPTIONS"
            ], body: "", on: connection)
            return
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

            // Dynamic serving of pet spritesheets
            if requestPath.hasPrefix("/mobile/pets/") && requestPath.hasSuffix("/spritesheet.webp") {
                let petSub = String(requestPath.dropFirst("/mobile/pets/".count).dropLast("/spritesheet.webp".count))
                // Look in Application Support/Codexling/Pets/<petSub>/spritesheet.webp
                let customURL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/Codexling/Pets")
                    .appendingPathComponent(petSub)
                    .appendingPathComponent("spritesheet.webp")
                if FileManager.default.fileExists(atPath: customURL.path),
                   let data = try? Data(contentsOf: customURL) {
                    sendRawResponse(status: 200, headers: ["Content-Type": "image/webp"], data: data, on: connection)
                    return
                }
                // Fallback to plugin pets
                let pluginURL = pluginDirectoryURL.appendingPathComponent("pets").appendingPathComponent(petSub).appendingPathComponent("spritesheet.webp")
                if FileManager.default.fileExists(atPath: pluginURL.path),
                   let data = try? Data(contentsOf: pluginURL) {
                    sendRawResponse(status: 200, headers: ["Content-Type": "image/webp"], data: data, on: connection)
                    return
                }
            }

            switch (method, requestPath) {
            case ("GET", "/mobile/proxy"), ("POST", "/mobile/proxy"):
                guard let targetStr = queryParams["target"], let targetURL = URL(string: targetStr) else {
                    sendResponse(status: 400, headers: [:], body: "Missing target parameter", on: connection)
                    return
                }
                Task {
                    var req = URLRequest(url: targetURL)
                    req.httpMethod = method
                    req.timeoutInterval = 30
                    if !requestBody.isEmpty, let bodyData = requestBody.data(using: .utf8) {
                        req.httpBody = bodyData
                    }
                    if let auth = headers["x-target-authorization"] ?? headers["authorization"] {
                        req.setValue(auth, forHTTPHeaderField: "Authorization")
                    }
                    if let ct = headers["content-type"] {
                        req.setValue(ct, forHTTPHeaderField: "Content-Type")
                    } else if method == "POST" {
                        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    }
                    req.setValue("application/json", forHTTPHeaderField: "Accept")

                    // Domain-specific headers for OpenAI and Google Cloud Code
                    let host = targetURL.host?.lowercased() ?? ""
                    if host.contains("chatgpt.com") {
                        req.setValue("Codexling/0.1", forHTTPHeaderField: "User-Agent")
                        req.setValue("https://chatgpt.com/", forHTTPHeaderField: "Origin")
                        req.setValue("https://chatgpt.com/", forHTTPHeaderField: "Referer")
                        if targetURL.path.contains("/wham/") {
                            req.setValue("codex-1", forHTTPHeaderField: "OpenAI-Beta")
                            req.setValue("Codex Desktop", forHTTPHeaderField: "originator")
                        }
                        if let accountID = headers["chatgpt-account-id"] ?? queryParams["account_id"] {
                            req.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
                        }
                    } else if host.contains("googleapis.com") {
                        req.setValue("antigravity", forHTTPHeaderField: "User-Agent")
                        req.setValue(#"{"ideType":"ANTIGRAVITY"}"#, forHTTPHeaderField: "Client-Metadata")
                    } else {
                        req.setValue("CodexlingMobile/1.0", forHTTPHeaderField: "User-Agent")
                    }

                    do {
                        let (data, response) = try await URLSession.codexlingExternal.data(for: req)
                        let httpResponse = response as? HTTPURLResponse
                        let statusCode = httpResponse?.statusCode ?? 200
                        let responseText = String(data: data, encoding: .utf8) ?? "{}"
                        self.sendResponse(status: statusCode, headers: ["Content-Type": "application/json"], body: responseText, on: connection)
                    } catch {
                        self.sendResponse(status: 502, headers: [:], body: error.localizedDescription, on: connection)
                    }
                }
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

            case ("GET", "/mobile/credentials"):
                Task {
                    let credentials = await self.dataProvider.exportCredentials()
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    if let data = try? encoder.encode(credentials),
                       let jsonString = String(data: data, encoding: .utf8) {
                        self.sendResponse(status: 200, headers: ["Content-Type": "application/json"], body: jsonString, on: connection)
                    } else {
                        self.sendResponse(status: 500, headers: [:], body: "Internal Server Error", on: connection)
                    }
                }

            case ("GET", "/mobile/events"):
                startSSEStream(on: connection)

            default:
                sendResponse(status: 404, headers: [:], body: "Not Found", on: connection)
            }
            return
        }

        // 3. Desktop Plugin Static Web Hosting (GET / HEAD / or static files)
        if method == "GET" || method == "HEAD" {
            servePluginStaticContent(path: requestPath, on: connection)
            return
        }

        sendResponse(status: 404, headers: [:], body: "Not Found", on: connection)
    }

    private func servePluginStaticContent(path: String, on connection: NWConnection) {
        let relativePath = (path == "/" || path.isEmpty) ? "index.html" : String(path.dropFirst())
        let fileURL = pluginDirectoryURL.appendingPathComponent(relativePath)

        // Dynamic manifest: inject the live pairing token into `start_url` so a
        // home-screen shortcut added from any URL still launches authenticated.
        // An already-installed shortcut keeps whatever URL the OS captured; the
        // app surfaces that limitation to the user after re-pairing.
        if relativePath == "manifest.json" {
            if let data = try? Data(contentsOf: fileURL),
               var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                json["start_url"] = "./?token=\(token)"
                if let patched = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) {
                    sendRawResponse(
                        status: 200,
                        headers: [
                            "Content-Type": "application/manifest+json; charset=utf-8",
                            "Cache-Control": "no-cache, no-store, must-revalidate",
                        ],
                        data: patched,
                        on: connection
                    )
                    return
                }
            }
        }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let fileData = try? Data(contentsOf: fileURL) {
                let mime = mimeType(for: fileURL.pathExtension)
                // Hashed bundles are content-addressed and safe to cache forever;
                // the entry document must always be revalidated, otherwise a phone
                // keeps booting the previous build after a plugin update.
                let isHashedAsset = relativePath.hasPrefix("assets/")
                let cacheControl = isHashedAsset
                    ? "public, max-age=31536000, immutable"
                    : "no-cache, no-store, must-revalidate"
                sendRawResponse(
                    status: 200,
                    headers: ["Content-Type": mime, "Cache-Control": cacheControl],
                    data: fileData,
                    on: connection
                )
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
        finalHeaders["Access-Control-Allow-Origin"] = "*"
        finalHeaders["Access-Control-Allow-Headers"] = "*"
        finalHeaders["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
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
