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
    /// 用于区分旧版 GCloud OAuth 凭证与 Antigravity 专用凭证。
    let authorizationProfile: String?

    var isExpired: Bool {
        expiresAt.timeIntervalSinceNow < 60
    }

    var usesAntigravityAuthorization: Bool {
        authorizationProfile == "antigravity"
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
    case configurationMissing
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
        case .configurationMissing:
            return "Gemini OAuth 尚未配置，请在构建时注入客户端配置"
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

struct GeminiOAuthConfiguration: Equatable, Sendable {
    static let clientIDEnvironmentKey = "CODEXLING_GEMINI_OAUTH_CLIENT_ID"
    static let clientSecretEnvironmentKey = "CODEXLING_GEMINI_OAUTH_CLIENT_SECRET"
    static let resourceName = "GeminiOAuthConfig"

    let clientID: String
    let clientSecret: String?

    var isConfigured: Bool { !clientID.isEmpty }

    static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) -> Self {
        let plist: [String: String]
        if let url = bundle.url(forResource: resourceName, withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let decoded = try? PropertyListSerialization.propertyList(from: data, format: nil),
           let dictionary = decoded as? [String: String] {
            plist = dictionary
        } else {
            plist = [:]
        }
        return resolve(environment: environment, plist: plist)
    }

    static func resolve(environment: [String: String], plist: [String: String]) -> Self {
        let clientID = normalized(environment[clientIDEnvironmentKey])
            ?? normalized(plist["clientID"])
            ?? ""
        let clientSecret = normalized(environment[clientSecretEnvironmentKey])
            ?? normalized(plist["clientSecret"])
        return Self(clientID: clientID, clientSecret: clientSecret)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
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
    var quotaFetchState: String = "normal"
    var accountEligibilityMessage: String? = nil
    var accountValidationURL: String? = nil
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
    private let redirectURI = "http://localhost:51121/oauth-callback"
    private let authorizationURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    private let userInfoURL = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!
    private let cloudCodeBaseURL = URL(string: "https://cloudcode-pa.googleapis.com")!

    private let scopes = [
        "https://www.googleapis.com/auth/cloud-platform",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
        "https://www.googleapis.com/auth/cclog",
        "https://www.googleapis.com/auth/experimentsandconfigs"
    ]

    private let session: URLSession
    private var activeCallbackServer: GoogleOAuthCallbackServer?
    private var cancellationRequested = false

    init(
        configuration: GeminiOAuthConfiguration = .load(),
        session: URLSession = .shared
    ) {
        clientID = configuration.clientID
        clientSecret = configuration.clientSecret
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
        guard !clientID.isEmpty else {
            throw GeminiOAuthError.configurationMissing
        }
        if cancellationRequested {
            cancellationRequested = false
            throw GeminiOAuthError.oauthCancelled
        }

        let state = randomBase64URL(byteCount: 24)
        let verifier = randomBase64URL(byteCount: 32)
        let challenge = sha256Base64URL(verifier)

        let server = GoogleOAuthCallbackServer(expectedState: state, port: 51121, callbackPath: "/oauth-callback")
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
            avatarURL: userInfo?.picture,
            authorizationProfile: "antigravity"
        )
    }

    func refreshToken(_ token: GeminiOAuthToken) async throws -> GeminiOAuthToken {
        guard !clientID.isEmpty else {
            throw GeminiOAuthError.configurationMissing
        }
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
            avatarURL: userInfo?.picture ?? token.avatarURL,
            authorizationProfile: token.authorizationProfile ?? "antigravity"
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
        let account = try await loadAntigravityAccount(accessToken: accessToken)
        guard let projectID = account.projectID else { throw GeminiOAuthError.unavailable }
        return try await fetchAntigravityModels(accessToken: accessToken, project: projectID)
    }

    func fetchQuotaSnapshot(accessToken: String) async -> GeminiQuotaSnapshot {
        do {
            let account = try await loadAntigravityAccount(accessToken: accessToken)
            guard let projectID = account.projectID else {
                return GeminiQuotaSnapshot(
                    projectId: nil,
                    projectName: nil,
                    tier: account.planName,
                    isBillingEnabled: false,
                    dailyRequestsLimit: 0,
                    minuteRequestsLimit: 0,
                    minuteTokensLimit: 0,
                    planName: account.planName,
                    geminiWeeklyRemaining: nil,
                    geminiWeeklyResetDesc: nil,
                    geminiFiveHourRemaining: nil,
                    geminiFiveHourResetDesc: nil,
                    claudeGptWeeklyRemaining: nil,
                    claudeGptFiveHourRemaining: nil,
                    availableModels: [],
                    availableModelCount: 0,
                    quotaFetchState: account.eligibilityState,
                    accountEligibilityMessage: account.eligibilityMessage,
                    accountValidationURL: account.validationURL
                )
            }
            async let quotaTask = fetchAntigravityQuota(accessToken: accessToken, project: projectID)
            async let modelsTask = try? fetchAntigravityModels(accessToken: accessToken, project: projectID)
            let quota = try await quotaTask
            let models = await modelsTask ?? []
            let hasQuota = quota.geminiWeekly != nil || quota.geminiFiveHour != nil
                || quota.claudeGptWeekly != nil || quota.claudeGptFiveHour != nil

            return GeminiQuotaSnapshot(
                projectId: projectID,
                projectName: "Cloud AI Companion",
                tier: account.planName,
                isBillingEnabled: account.isPaid,
                dailyRequestsLimit: 0,
                minuteRequestsLimit: 0,
                minuteTokensLimit: 0,
                planName: account.planName,
                geminiWeeklyRemaining: quota.geminiWeekly,
                geminiWeeklyResetDesc: quota.geminiWeeklyReset,
                geminiFiveHourRemaining: quota.geminiFiveHour,
                geminiFiveHourResetDesc: quota.geminiFiveHourReset,
                claudeGptWeeklyRemaining: quota.claudeGptWeekly,
                claudeGptFiveHourRemaining: quota.claudeGptFiveHour,
                availableModels: models,
                availableModelCount: models.count,
                quotaFetchState: hasQuota ? "normal" : "quota_unavailable"
            )
        } catch let error as GeminiOAuthError {
            return unavailableQuotaSnapshot(state: quotaState(for: error))
        } catch {
            return unavailableQuotaSnapshot(state: "quota_unavailable")
        }
    }

    private func loadAntigravityAccount(accessToken: String) async throws -> AntigravityRemoteAccount {
        let data = try await postCloudCode(
            method: "loadCodeAssist",
            accessToken: accessToken,
            body: ["metadata": ["ideType": "ANTIGRAVITY"]]
        )
        let decoded = try JSONDecoder().decode(AntigravityLoadCodeAssistResponse.self, from: data)
        let rawProjectID = decoded.cloudaicompanionProject?.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectID = rawProjectID?.isEmpty == false ? rawProjectID : nil
        let tier = decoded.paidTier ?? decoded.currentTier
        let ineligible = decoded.ineligibleTiers?.first
        let eligibilityState = ineligible?.reasonCode == "VALIDATION_REQUIRED"
            ? "account_validation_required"
            : (projectID == nil ? "quota_unavailable" : "normal")
        let planName = displayPlanName(tier: tier, eligibilityState: eligibilityState)
        return AntigravityRemoteAccount(
            projectID: projectID,
            planName: planName,
            isPaid: decoded.paidTier != nil,
            eligibilityState: eligibilityState,
            eligibilityMessage: ineligible?.reasonCode == "VALIDATION_REQUIRED"
                ? "Google 要求验证此账号后才能使用 Antigravity。"
                : ineligible?.reasonMessage,
            validationURL: ineligible?.validationURL
        )
    }

    private func displayPlanName(
        tier: AntigravityLoadCodeAssistResponse.Tier?,
        eligibilityState: String
    ) -> String {
        if eligibilityState == "account_validation_required" { return "无 Antigravity 权限" }
        switch tier?.id {
        case "g1-pro-tier": return "Google AI Pro"
        case "g1-ultra-tier": return "Google AI Ultra"
        case "free-tier": return "Antigravity Free"
        case "standard-tier": return "Antigravity"
        default: return tier?.name ?? tier?.id ?? "套餐状态未知"
        }
    }

    private func fetchAntigravityModels(accessToken: String, project: String) async throws -> [String] {
        let data = try await postCloudCode(
            method: "fetchAvailableModels",
            accessToken: accessToken,
            body: ["project": project]
        )
        let decoded = try JSONDecoder().decode(AntigravityAvailableModelsResponse.self, from: data)
        return decoded.models.compactMap { id, model in
            guard model.isInternal != true, !(model.displayName ?? "").isEmpty else { return nil }
            return model.model ?? id
        }.sorted()
    }

    private func fetchAntigravityQuota(accessToken: String, project: String) async throws -> AntigravityRemoteQuota {
        let data = try await postCloudCode(
            method: "retrieveUserQuotaSummary",
            accessToken: accessToken,
            body: ["project": project]
        )
        return try AntigravityRemoteQuota.parse(data: data)
    }

    private func postCloudCode(
        method: String,
        accessToken: String,
        body: [String: Any]
    ) async throws -> Data {
        let url = cloudCodeBaseURL.appendingPathComponent("v1internal:\(method)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("antigravity", forHTTPHeaderField: "User-Agent")
        request.setValue(#"{"ideType":"ANTIGRAVITY"}"#, forHTTPHeaderField: "Client-Metadata")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GeminiOAuthError.unavailable }
        switch http.statusCode {
        case 200...299:
            return data
        case 401:
            throw GeminiOAuthError.unauthorized
        case 403:
            // 有效登录也可能因账号方案、地区或私有接口授权返回 403；不要误导用户反复登录。
            throw GeminiOAuthError.unavailable
        case 429:
            throw GeminiOAuthError.rateLimited(http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init))
        default:
            throw GeminiOAuthError.unavailable
        }
    }

    private func unavailableQuotaSnapshot(state: String) -> GeminiQuotaSnapshot {
        GeminiQuotaSnapshot(
            projectId: nil,
            projectName: nil,
            tier: "额度暂不可用",
            isBillingEnabled: false,
            dailyRequestsLimit: 0,
            minuteRequestsLimit: 0,
            minuteTokensLimit: 0,
            planName: nil,
            geminiWeeklyRemaining: nil,
            geminiWeeklyResetDesc: nil,
            geminiFiveHourRemaining: nil,
            geminiFiveHourResetDesc: nil,
            claudeGptWeeklyRemaining: nil,
            claudeGptFiveHourRemaining: nil,
            availableModels: [],
            availableModelCount: 0,
            quotaFetchState: state
        )
    }

    private func quotaState(for error: GeminiOAuthError) -> String {
        switch error {
        case .unauthorized: "unauthorized"
        case .rateLimited: "rate_limited"
        default: "quota_unavailable"
        }
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

private struct AntigravityRemoteAccount {
    let projectID: String?
    let planName: String
    let isPaid: Bool
    let eligibilityState: String
    let eligibilityMessage: String?
    let validationURL: String?
}

private struct AntigravityLoadCodeAssistResponse: Decodable {
    let cloudaicompanionProject: String?
    let currentTier: Tier?
    let paidTier: Tier?
    let allowedTiers: [Tier]?
    let ineligibleTiers: [IneligibleTier]?

    struct Tier: Decodable {
        let id: String?
        let name: String?
    }

    struct IneligibleTier: Decodable {
        let reasonCode: String?
        let reasonMessage: String?
        let tierId: String?
        let tierName: String?
        let validationErrorMessage: String?
        let validationUrl: String?

        var validationURL: String? { validationUrl }
    }
}

private struct AntigravityAvailableModelsResponse: Decodable {
    let models: [String: Model]

    struct Model: Decodable {
        let displayName: String?
        let model: String?
        let isInternal: Bool?
    }
}

private struct AntigravityRemoteQuota {
    var geminiWeekly: Double?
    var geminiWeeklyReset: String?
    var geminiFiveHour: Double?
    var geminiFiveHourReset: String?
    var claudeGptWeekly: Double?
    var claudeGptFiveHour: Double?

    static func parse(data: Data) throws -> Self {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiOAuthError.unavailable
        }
        let payload = (root["response"] as? [String: Any]) ?? root
        guard let groups = payload["groups"] as? [[String: Any]] else {
            throw GeminiOAuthError.unavailable
        }

        var result = Self()
        for group in groups {
            let groupName = string(group, keys: ["displayName", "display_name", "description"])
                .lowercased()
            guard let buckets = group["buckets"] as? [[String: Any]] else { continue }
            for bucket in buckets {
                let identity = [
                    groupName,
                    string(bucket, keys: ["bucketId", "bucket_id"]),
                    string(bucket, keys: ["displayName", "display_name"]),
                    string(bucket, keys: ["window"])
                ].joined(separator: " ").lowercased()
                guard let remaining = remainingFraction(bucket) else { continue }
                let reset = string(bucket, keys: ["description", "resetTime", "reset_time"])
                let isWeekly = identity.contains("weekly") || identity.contains("week") || identity.contains("周")
                let isFiveHour = identity.contains("5h") || identity.contains("5 hour")
                    || identity.contains("session") || identity.contains("5小时")
                let isThirdParty = identity.contains("3p") || identity.contains("claude")
                    || identity.contains("gpt") || identity.contains("third party")

                if isThirdParty && isWeekly {
                    result.claudeGptWeekly = remaining
                } else if isThirdParty && isFiveHour {
                    result.claudeGptFiveHour = remaining
                } else if isWeekly {
                    result.geminiWeekly = remaining
                    result.geminiWeeklyReset = reset.isEmpty ? nil : reset
                } else if isFiveHour {
                    result.geminiFiveHour = remaining
                    result.geminiFiveHourReset = reset.isEmpty ? nil : reset
                }
            }
        }
        return result
    }

    private static func remainingFraction(_ bucket: [String: Any]) -> Double? {
        let nested = (bucket["remaining"] as? [String: Any]) ?? [:]
        let value = bucket["remainingFraction"] ?? bucket["remaining_fraction"]
            ?? nested["remainingFraction"] ?? nested["remaining_fraction"]
        let fraction: Double?
        if let number = value as? NSNumber {
            fraction = number.doubleValue
        } else if let text = value as? String {
            fraction = Double(text)
        } else {
            fraction = nil
        }
        guard let fraction, (0...1).contains(fraction) else { return nil }
        return fraction
    }

    private static func string(_ dictionary: [String: Any], keys: [String]) -> String {
        for key in keys {
            if let value = dictionary[key] as? String { return value }
        }
        return ""
    }
}

private final class GoogleOAuthCallbackServer: @unchecked Sendable {
    private let expectedState: String
    private let port: UInt16
    private let callbackPath: String
    private let stateLock = NSLock()
    private var listener: NWListener?
    private var continuation: CheckedContinuation<String, Error>?

    init(expectedState: String, port: UInt16, callbackPath: String) {
        self.expectedState = expectedState
        self.port = port
        self.callbackPath = callbackPath
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
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
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
            let components = URLComponents(string: "http://127.0.0.1:\(port)\(path)")

            guard components?.path == callbackPath else {
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
                return OAuthCallbackHTML.success(provider: .gemini)
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
