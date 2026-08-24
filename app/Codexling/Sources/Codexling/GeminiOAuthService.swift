import AppKit
import CryptoKit
import Foundation
import Network

struct GeminiOAuthToken: Codable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
    let email: String?
    let displayName: String?
    let avatarURL: String?

    var isExpired: Bool {
        expiresAt.timeIntervalSinceNow < 60
    }
}

protocol GeminiOAuthTokenStoring: Sendable {
    func load(handle: String) -> GeminiOAuthToken?
    func save(_ token: GeminiOAuthToken, handle: String) throws
    func delete(handle: String) throws
}

struct GeminiOAuthTokenStore: GeminiOAuthTokenStoring {
    private let directoryURL: URL

    init(directoryURL: URL? = nil) {
        self.directoryURL = directoryURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Codexling/gemini_oauth", isDirectory: true)
    }

    private func fileURL(for handle: String) -> URL {
        directoryURL.appendingPathComponent("\(handle).json")
    }

    func load(handle: String) -> GeminiOAuthToken? {
        let url = fileURL(for: handle)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GeminiOAuthToken.self, from: data)
    }

    func save(_ token: GeminiOAuthToken, handle: String) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let url = fileURL(for: handle)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(token)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func delete(handle: String) throws {
        let url = fileURL(for: handle)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

enum GeminiOAuthError: LocalizedError, Sendable {
    case oauthCancelled
    case oauthTimedOut
    case oauthCallbackInvalid
    case tokenExchangeFailed(String)
    case tokenRefreshFailed(String)
    case unauthorized
    case rateLimited(Int?)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .oauthCancelled:
            return "Google 账号授权已取消"
        case .oauthTimedOut:
            return "Google 账号授权超时，请重试"
        case .oauthCallbackInvalid:
            return "Google 授权回调数据无效"
        case .tokenExchangeFailed(let message):
            return "Token 获取失败：\(message)"
        case .tokenRefreshFailed(let message):
            return "Token 续期失败：\(message)"
        case .unauthorized:
            return "Google 账号授权已过期，请重新登录"
        case .rateLimited(let seconds):
            if let seconds {
                return "Google Gemini API 限流中，请在 \(seconds) 秒后重试"
            }
            return "Google Gemini API 限流中，请稍后重试"
        case .unavailable:
            return "Google 服务暂时不可用"
        }
    }
}

struct GeminiQuotaSnapshot: Equatable, Codable, Sendable {
    var projectId: String?
    var projectName: String?
    var userName: String?
    var userEmail: String?
    var tier: String
    var isBillingEnabled: Bool
    var dailyRequestsLimit: Int
    var minuteRequestsLimit: Int
    var minuteTokensLimit: Int
    var planName: String?
    var geminiWeeklyRemaining: Double?
    var geminiWeeklyResetDesc: String?
    var geminiFiveHourRemaining: Double?
    var geminiFiveHourResetDesc: String?
    var claudeGptWeeklyRemaining: Double?
    var claudeGptFiveHourRemaining: Double?
    var availableModels: [String]
    var availableModelCount: Int
}

protocol GeminiOAuthServicing: Sendable {
    func startOAuth(forceLogin: Bool) async throws -> GeminiOAuthToken
    func refreshToken(_ token: GeminiOAuthToken) async throws -> GeminiOAuthToken
    func validateModels(accessToken: String) async throws -> [String]
    func fetchQuotaSnapshot(accessToken: String) async -> GeminiQuotaSnapshot
    func cancelOAuthAuthorization()
}

final class GeminiOAuthService: GeminiOAuthServicing, @unchecked Sendable {
    private let clientID: String
    private let clientSecret: String?
    private let redirectURI = "http://127.0.0.1:1456/oauth/callback"
    private let authorizationURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    private let userInfoURL = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!
    private let modelsURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!

    private let scopes = [
        "openid",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/cloud-platform"
    ]

    private let session: URLSession
    private var activeCallbackServer: GoogleOAuthCallbackServer?
    private var cancellationRequested = false

    init(
        clientID: String = "32555940559.apps.googleusercontent.com",
        clientSecret: String? = "ZmssLNjJy2998hD4CTg2ejr2",
        session: URLSession = .shared
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.session = session
    }

    func cancelOAuthAuthorization() {
        if let activeCallbackServer {
            activeCallbackServer.cancel()
        } else {
            cancellationRequested = true
        }
    }

    func startOAuth(forceLogin: Bool = false) async throws -> GeminiOAuthToken {
        if cancellationRequested {
            cancellationRequested = false
            throw GeminiOAuthError.oauthCancelled
        }

        let state = randomBase64URL(byteCount: 24)
        let verifier = randomBase64URL(byteCount: 32)
        let challenge = sha256Base64URL(verifier)

        let server = GoogleOAuthCallbackServer(expectedState: state)
        activeCallbackServer = server
        defer {
            if activeCallbackServer === server {
                activeCallbackServer = nil
            }
            cancellationRequested = false
        }

        var components = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)!
        let queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: forceLogin ? "select_account consent" : "consent")
        ]
        components.queryItems = queryItems

        guard let authURL = components.url else {
            throw GeminiOAuthError.oauthCallbackInvalid
        }

        NSWorkspace.shared.open(authURL)

        let code = try await server.waitForCode(timeoutSeconds: 300)
        let tokenData = try await exchangeCode(code, verifier: verifier)
        let userInfo = try? await fetchUserInfo(accessToken: tokenData.accessToken)

        return GeminiOAuthToken(
            accessToken: tokenData.accessToken,
            refreshToken: tokenData.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenData.expiresIn ?? 3600)),
            email: userInfo?.email,
            displayName: userInfo?.name,
            avatarURL: userInfo?.picture
        )
    }

    func refreshToken(_ token: GeminiOAuthToken) async throws -> GeminiOAuthToken {
        guard let refreshToken = token.refreshToken else {
            throw GeminiOAuthError.unauthorized
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyParams = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID
        ]
        if let clientSecret, !clientSecret.isEmpty {
            bodyParams["client_secret"] = clientSecret
        }
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GeminiOAuthError.unavailable
        }

        guard http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw GeminiOAuthError.tokenRefreshFailed(message)
        }

        let tokenResponse = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        let userInfo = try? await fetchUserInfo(accessToken: tokenResponse.accessToken)

        return GeminiOAuthToken(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken ?? token.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn ?? 3600)),
            email: userInfo?.email ?? token.email,
            displayName: userInfo?.name ?? token.displayName,
            avatarURL: userInfo?.picture ?? token.avatarURL
        )
    }

    private func exchangeCode(_ code: String, verifier: String) async throws -> GoogleTokenResponse {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyParams = [
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
            "client_id": clientID,
            "redirect_uri": redirectURI
        ]
        if let clientSecret, !clientSecret.isEmpty {
            bodyParams["client_secret"] = clientSecret
        }
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GeminiOAuthError.unavailable
        }

        guard http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw GeminiOAuthError.tokenExchangeFailed(message)
        }

        return try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
    }

    private func fetchUserInfo(accessToken: String) async throws -> GoogleUserInfo {
        var request = URLRequest(url: userInfoURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GeminiOAuthError.unauthorized
        }

        return try JSONDecoder().decode(GoogleUserInfo.self, from: data)
    }

    func validateModels(accessToken: String) async throws -> [String] {
        var request = URLRequest(url: modelsURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GeminiOAuthError.unavailable
        }

        switch http.statusCode {
        case 200:
            let decoded = try JSONDecoder().decode(GeminiModelsListResponse.self, from: data)
            return (decoded.models ?? [])
                .map(\.name)
                .filter { $0.contains("gemini") }
                .sorted()
        case 401, 403:
            throw GeminiOAuthError.unauthorized
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw GeminiOAuthError.rateLimited(retryAfter)
        case 500...599:
            throw GeminiOAuthError.unavailable
        default:
            throw GeminiOAuthError.oauthCallbackInvalid
        }
    }

    func fetchQuotaSnapshot(accessToken: String) async -> GeminiQuotaSnapshot {
        var projectId: String?
        var projectName: String?
        if let projects = try? await fetchProjects(accessToken: accessToken),
           let active = projects.first(where: { $0.lifecycleState == "ACTIVE" }) ?? projects.first {
            projectId = active.projectId
            projectName = active.name
        }

        var isBillingEnabled = false
        if let pid = projectId, let billing = try? await fetchBillingInfo(accessToken: accessToken, projectId: pid) {
            isBillingEnabled = billing.billingEnabled == true
        }

        var discoveredModels: [String] = []
        if let pid = projectId, let quotas = try? await fetchQuotas(accessToken: accessToken, projectId: pid) {
            var modelSet = Set<String>()
            for info in quotas.quotaInfos ?? [] {
                for dim in info.dimensionsInfos ?? [] {
                    if let model = dim.dimensions?["model"], (model.contains("gemini") || model.contains("gemma")) {
                        modelSet.insert(model)
                    }
                }
            }
            discoveredModels = modelSet.sorted()
        }

        if let agQuota = await fetchAntigravityLocalQuota() {
            return GeminiQuotaSnapshot(
                projectId: projectId ?? "Antigravity",
                projectName: projectName ?? "Google AI",
                userName: agQuota.userName,
                userEmail: agQuota.userEmail,
                tier: agQuota.plan,
                isBillingEnabled: true,
                dailyRequestsLimit: 0,
                minuteRequestsLimit: 1500,
                minuteTokensLimit: 4000000,
                planName: agQuota.plan,
                geminiWeeklyRemaining: agQuota.weekly,
                geminiWeeklyResetDesc: agQuota.weeklyDesc,
                geminiFiveHourRemaining: agQuota.fiveHour,
                geminiFiveHourResetDesc: agQuota.fiveHourDesc,
                claudeGptWeeklyRemaining: agQuota.claudeWeekly,
                claudeGptFiveHourRemaining: agQuota.claudeFiveHour,
                availableModels: agQuota.models.isEmpty ? discoveredModels : agQuota.models,
                availableModelCount: agQuota.models.isEmpty ? discoveredModels.count : agQuota.models.count
            )
        }

        if discoveredModels.isEmpty {
            discoveredModels = [
                "gemini-2.0-flash",
                "gemini-2.5-flash",
                "gemini-2.5-pro",
                "gemini-3.7-flash"
            ]
        }

        let tier = isBillingEnabled ? "Pay-as-you-go" : "Free Tier"
        let dailyLimit = isBillingEnabled ? 0 : 1500
        let minuteLimit = isBillingEnabled ? 1000 : 15
        let tokenLimit = isBillingEnabled ? 4000000 : 1000000

        return GeminiQuotaSnapshot(
            projectId: projectId,
            projectName: projectName,
            tier: tier,
            isBillingEnabled: isBillingEnabled,
            dailyRequestsLimit: dailyLimit,
            minuteRequestsLimit: minuteLimit,
            minuteTokensLimit: tokenLimit,
            planName: tier,
            geminiWeeklyRemaining: nil,
            geminiWeeklyResetDesc: nil,
            geminiFiveHourRemaining: nil,
            geminiFiveHourResetDesc: nil,
            claudeGptWeeklyRemaining: nil,
            claudeGptFiveHourRemaining: nil,
            availableModels: discoveredModels,
            availableModelCount: discoveredModels.count
        )
    }

    private func fetchAntigravityLocalQuota() async -> (plan: String, userName: String?, userEmail: String?, weekly: Double, weeklyDesc: String?, fiveHour: Double, fiveHourDesc: String?, claudeWeekly: Double?, claudeFiveHour: Double?, models: [String])? {
        let home = FileManager.default.homeDirectoryForCurrentUser

        // 1. Extract CSRF token from ~/Library/Logs/Antigravity/main.log
        let mainLogURL = home.appendingPathComponent("Library/Logs/Antigravity/main.log")
        guard let mainLogContent = try? String(contentsOf: mainLogURL, encoding: .utf8) else { return nil }

        let csrfPattern = #"--csrf_token\s+([a-zA-Z0-9-]+)"#
        guard let csrfRegex = try? NSRegularExpression(pattern: csrfPattern) else { return nil }
        let csrfMatches = csrfRegex.matches(in: mainLogContent, range: NSRange(mainLogContent.startIndex..., in: mainLogContent))
        guard let lastCsrfMatch = csrfMatches.last, let csrfRange = Range(lastCsrfMatch.range(at: 1), in: mainLogContent) else {
            return nil
        }
        let csrf = String(mainLogContent[csrfRange])
        guard !csrf.isEmpty else { return nil }

        // 2. Extract port from ~/Library/Logs/Antigravity/language_server.log
        let lsLogURL = home.appendingPathComponent("Library/Logs/Antigravity/language_server.log")
        guard let lsLogContent = try? String(contentsOf: lsLogURL, encoding: .utf8) else { return nil }

        let portPattern = #"Language server listening on random port at (\d+) for HTTP\b"#
        guard let portRegex = try? NSRegularExpression(pattern: portPattern) else { return nil }
        let portMatches = portRegex.matches(in: lsLogContent, range: NSRange(lsLogContent.startIndex..., in: lsLogContent))
        guard let lastPortMatch = portMatches.last, let portRange = Range(lastPortMatch.range(at: 1), in: lsLogContent) else {
            return nil
        }
        let port = String(lsLogContent[portRange])
        guard let portInt = Int(port), portInt > 0 else { return nil }

        // 3. Call GetUserStatus
        guard let statusURL = URL(string: "http://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/GetUserStatus") else { return nil }
        var statusReq = URLRequest(url: statusURL)
        statusReq.httpMethod = "POST"
        statusReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        statusReq.setValue(csrf, forHTTPHeaderField: "x-codeium-csrf-token")
        statusReq.httpBody = "{}".data(using: .utf8)

        var planName = "Google AI Pro"
        var userName: String?
        var userEmail: String?
        var models: [String] = []
        if let (statusData, statusResp) = try? await session.data(for: statusReq),
           (statusResp as? HTTPURLResponse)?.statusCode == 200,
           let statusDecoded = try? JSONDecoder().decode(AntigravityUserStatusResponse.self, from: statusData) {
            if let name = statusDecoded.resolvedUserTier?.name, !name.isEmpty {
                planName = name
            }
            userName = statusDecoded.resolvedName
            userEmail = statusDecoded.resolvedEmail
            models = statusDecoded.resolvedModels.compactMap { $0.label ?? $0.modelId }
        }

        // 4. Call RetrieveUserQuotaSummary
        guard let quotaURL = URL(string: "http://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary") else { return nil }
        var quotaReq = URLRequest(url: quotaURL)
        quotaReq.httpMethod = "POST"
        quotaReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        quotaReq.setValue(csrf, forHTTPHeaderField: "x-codeium-csrf-token")
        quotaReq.httpBody = #"{"force_refresh": true}"#.data(using: .utf8)

        guard let (quotaData, quotaResp) = try? await session.data(for: quotaReq),
              (quotaResp as? HTTPURLResponse)?.statusCode == 200,
              let quotaDecoded = try? JSONDecoder().decode(AntigravityQuotaSummaryResponse.self, from: quotaData),
              let groups = quotaDecoded.response?.groups else {
            return nil
        }

        var weeklyRemaining: Double = 1.0
        var weeklyDesc: String?
        var fiveHourRemaining: Double = 1.0
        var fiveHourDesc: String?
        var claudeWeekly: Double?
        var claudeFiveHour: Double?

        for group in groups {
            let name = group.displayName ?? ""
            if name.contains("Gemini") {
                for bucket in group.buckets ?? [] {
                    let bId = bucket.bucketId ?? ""
                    let w = bucket.window ?? ""
                    if bId.contains("weekly") || w == "weekly" {
                        weeklyRemaining = bucket.remainingFraction ?? 1.0
                        weeklyDesc = bucket.description
                    } else if bId.contains("5h") || w == "5h" {
                        fiveHourRemaining = bucket.remainingFraction ?? 1.0
                        fiveHourDesc = bucket.description
                    }
                }
            } else if name.contains("Claude") || name.contains("GPT") {
                for bucket in group.buckets ?? [] {
                    let bId = bucket.bucketId ?? ""
                    let w = bucket.window ?? ""
                    if bId.contains("weekly") || w == "weekly" {
                        claudeWeekly = bucket.remainingFraction ?? 1.0
                    } else if bId.contains("5h") || w == "5h" {
                        claudeFiveHour = bucket.remainingFraction ?? 1.0
                    }
                }
            }
        }

        return (
            plan: planName,
            userName: userName,
            userEmail: userEmail,
            weekly: weeklyRemaining,
            weeklyDesc: weeklyDesc,
            fiveHour: fiveHourRemaining,
            fiveHourDesc: fiveHourDesc,
            claudeWeekly: claudeWeekly,
            claudeFiveHour: claudeFiveHour,
            models: models
        )
    }

    private func fetchProjects(accessToken: String) async throws -> [GCPProjectItem] {
        var request = URLRequest(url: URL(string: "https://cloudresourcemanager.googleapis.com/v1/projects")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
        return (try? JSONDecoder().decode(GCPProjectsResponse.self, from: data))?.projects ?? []
    }

    private func fetchBillingInfo(accessToken: String, projectId: String) async throws -> GCPBillingInfoResponse? {
        var request = URLRequest(url: URL(string: "https://cloudbilling.googleapis.com/v1/projects/\(projectId)/billingInfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(GCPBillingInfoResponse.self, from: data)
    }

    private func fetchQuotas(accessToken: String, projectId: String) async throws -> GCPQuotaInfosResponse? {
        var request = URLRequest(url: URL(string: "https://cloudquotas.googleapis.com/v1/projects/\(projectId)/locations/global/services/generativelanguage.googleapis.com/quotaInfos")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(GCPQuotaInfosResponse.self, from: data)
    }

    private func randomBase64URL(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func sha256Base64URL(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct GeminiModelsListResponse: Decodable, Sendable {
    let models: [Model]?

    struct Model: Decodable, Sendable {
        let name: String
        let displayName: String?
        let supportedGenerationMethods: [String]?
    }
}

private struct GoogleTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct GoogleUserInfo: Decodable {
    let email: String?
    let name: String?
    let picture: String?
}

private struct GCPProjectsResponse: Decodable {
    let projects: [GCPProjectItem]?
}

private struct GCPProjectItem: Decodable {
    let projectId: String?
    let projectNumber: String?
    let name: String?
    let lifecycleState: String?
}

private struct GCPBillingInfoResponse: Decodable {
    let projectId: String?
    let billingAccountName: String?
    let billingEnabled: Bool?
}

private struct GCPQuotaInfosResponse: Decodable {
    let quotaInfos: [GCPQuotaInfoItem]?
}

private struct GCPQuotaInfoItem: Decodable {
    let quotaId: String?
    let dimensionsInfos: [GCPDimensionInfo]?
}

private struct GCPDimensionInfo: Decodable {
    let dimensions: [String: String]?
}

private final class GoogleOAuthCallbackServer: @unchecked Sendable {
    private let expectedState: String
    private let stateLock = NSLock()
    private var listener: NWListener?
    private var continuation: CheckedContinuation<String, Error>?

    init(expectedState: String) {
        self.expectedState = expectedState
    }

    func waitForCode(timeoutSeconds: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            stateLock.lock()
            self.continuation = continuation
            stateLock.unlock()
            startListener()

            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
                self?.finish(.failure(GeminiOAuthError.oauthTimedOut))
            }
        }
    }

    func cancel() {
        finish(.failure(GeminiOAuthError.oauthCancelled))
    }

    private func startListener() {
        do {
            let port = NWEndpoint.Port(rawValue: 1456)!
            let listener = try NWListener(using: .tcp, on: port)
            stateLock.lock()
            guard continuation != nil else {
                stateLock.unlock()
                listener.cancel()
                return
            }
            self.listener = listener
            stateLock.unlock()
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    self?.finish(.failure(error))
                }
            }
            listener.start(queue: .global())
        } catch {
            finish(.failure(error))
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                self?.send("Bad request", status: 400, on: connection)
                self?.finish(.failure(GeminiOAuthError.oauthCallbackInvalid))
                return
            }

            let firstLine = request.components(separatedBy: "\r\n").first ?? ""
            let path = firstLine.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let components = URLComponents(string: "http://127.0.0.1:1456\(path)")

            guard components?.path == "/oauth/callback" else {
                self.send("Not found", status: 404, on: connection)
                return
            }

            let code = components?.queryItems?.first { $0.name == "code" }?.value
            let state = components?.queryItems?.first { $0.name == "state" }?.value
            let error = components?.queryItems?.first { $0.name == "error" }?.value

            if let error {
                self.sendPage(.error("授权失败：\(error)"), status: 400, on: connection)
                self.finish(.failure(GeminiOAuthError.tokenExchangeFailed(error)))
            } else if let code, state == self.expectedState {
                self.sendPage(.success, status: 200, on: connection)
                self.finish(.success(code))
            } else {
                self.sendPage(.error("OAuth 回调无效，请返回应用重新登录。"), status: 400, on: connection)
                self.finish(.failure(GeminiOAuthError.oauthCallbackInvalid))
            }
        }
    }

    private enum Page {
        case success
        case error(String)

        var html: String {
            switch self {
            case .success:
                return """
                <!doctype html>
                <html lang="zh-CN">
                <head>
                  <meta charset="utf-8" />
                  <title>Google 账号连接成功 · Codexling</title>
                  <style>
                    body { font-family: -apple-system, sans-serif; background: #f3f5f8; text-align: center; padding: 80px 20px; }
                    .card { max-width: 400px; margin: 0 auto; background: white; padding: 30px; border-radius: 16px; box-shadow: 0 10px 30px rgba(0,0,0,0.08); }
                    h2 { color: #1f6d4a; margin-bottom: 8px; }
                    p { color: #555; font-size: 14px; }
                  </style>
                </head>
                <body>
                  <div class="card">
                    <h2>Google 账号连接成功</h2>
                    <p>已完成 Google Gemini 授权，你现在可以关闭此标签页并返回 Codexling。</p>
                  </div>
                </body>
                </html>
                """
            case .error(let msg):
                return """
                <!doctype html>
                <html lang="zh-CN">
                <head>
                  <meta charset="utf-8" />
                  <title>授权失败 · Codexling</title>
                  <style>
                    body { font-family: -apple-system, sans-serif; background: #f3f5f8; text-align: center; padding: 80px 20px; }
                    .card { max-width: 400px; margin: 0 auto; background: white; padding: 30px; border-radius: 16px; box-shadow: 0 10px 30px rgba(0,0,0,0.08); }
                    h2 { color: #e1382b; margin-bottom: 8px; }
                    p { color: #555; font-size: 14px; }
                  </style>
                </head>
                <body>
                  <div class="card">
                    <h2>Google 授权未完成</h2>
                    <p>\(msg)</p>
                  </div>
                </body>
                </html>
                """
            }
        }
    }

    private func sendPage(_ page: Page, status: Int, on connection: NWConnection) {
        let html = page.html
        let statusText = status == 200 ? "OK" : "Error"
        let response = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        \r
        \(html)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func send(_ body: String, status: Int, on connection: NWConnection) {
        sendPage(.error(body), status: status, on: connection)
    }

    private func finish(_ result: Result<String, Error>) {
        stateLock.lock()
        guard let continuation else {
            stateLock.unlock()
            return
        }
        self.continuation = nil
        let listener = listener
        self.listener = nil
        stateLock.unlock()
        listener?.cancel()

        switch result {
        case .success(let code):
            continuation.resume(returning: code)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private struct AntigravityUserStatusResponse: Decodable {
    let name: String?
    let email: String?
    let userStatus: UserStatusPayload?
    let userTier: AntigravityUserTier?
    let clientModelConfigs: AntigravityClientModelConfigs?

    struct UserStatusPayload: Decodable {
        let name: String?
        let email: String?
        let userTier: AntigravityUserTier?
        let clientModelConfigs: AntigravityClientModelConfigs?
    }

    struct AntigravityUserTier: Decodable {
        let id: String?
        let name: String?
        let description: String?
        let upgradeSubscriptionUri: String?
        let upgradeSubscriptionText: String?
    }

    struct AntigravityClientModelConfigs: Decodable {
        let models: [AntigravityModelItem]?
    }

    struct AntigravityModelItem: Decodable {
        let label: String?
        let modelId: String?
    }

    var resolvedName: String? {
        userStatus?.name ?? name
    }

    var resolvedEmail: String? {
        userStatus?.email ?? email
    }

    var resolvedUserTier: AntigravityUserTier? {
        userStatus?.userTier ?? userTier
    }

    var resolvedModels: [AntigravityModelItem] {
        userStatus?.clientModelConfigs?.models ?? clientModelConfigs?.models ?? []
    }
}

private struct AntigravityQuotaSummaryResponse: Decodable {
    let response: QuotaPayload?

    struct QuotaPayload: Decodable {
        let groups: [QuotaGroup]?
        let description: String?
    }

    struct QuotaGroup: Decodable {
        let displayName: String?
        let description: String?
        let buckets: [QuotaBucket]?
    }

    struct QuotaBucket: Decodable {
        let bucketId: String?
        let displayName: String?
        let description: String?
        let window: String?
        let remainingFraction: Double?
        let resetTime: String?
    }
}
