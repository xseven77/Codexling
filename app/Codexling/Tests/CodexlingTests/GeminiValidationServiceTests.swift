import Foundation
import XCTest
@testable import Codexling

final class GeminiValidationServiceTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GeminiOAuthTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    func testGeminiOAuthTokenStoreRoundTripAndPermissions() throws {
        let store = GeminiOAuthTokenStore(directoryURL: tempDir)
        let handle = "test-handle"
        let token = GeminiOAuthToken(
            accessToken: "ya29.test-access-token",
            refreshToken: "1//test-refresh-token",
            expiresAt: Date().addingTimeInterval(3600),
            email: "developer@gmail.com",
            displayName: "Test Developer",
            avatarURL: "https://example.com/avatar.png",
            authorizationProfile: "antigravity"
        )

        try store.save(token, handle: handle)
        let loaded = try XCTUnwrap(store.load(handle: handle))
        XCTAssertEqual(loaded.accessToken, token.accessToken)
        XCTAssertEqual(loaded.refreshToken, token.refreshToken)
        XCTAssertEqual(loaded.email, token.email)
        XCTAssertEqual(loaded.displayName, token.displayName)

        let fileURL = tempDir.appendingPathComponent("\(handle).json")
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let posixPermissions = attributes[.posixPermissions] as? NSNumber {
            XCTAssertEqual(posixPermissions.intValue, 0o600)
        }

        try store.delete(handle: handle)
        XCTAssertNil(store.load(handle: handle))
    }

    func testLegacyGCloudTokenDecodesAndRequiresAntigravityRelogin() throws {
        let data = #"{"accessToken":"old-token","expiresAt":"2026-08-25T00:00:00Z","email":"old@example.com"}"#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let token = try decoder.decode(GeminiOAuthToken.self, from: data)

        XCTAssertNil(token.authorizationProfile)
        XCTAssertFalse(token.usesAntigravityAuthorization)
    }

    func testGeminiOAuthConfigurationUsesInjectedValuesWithoutSourceDefaults() {
        let configuration = GeminiOAuthConfiguration.resolve(
            environment: [
                GeminiOAuthConfiguration.clientIDEnvironmentKey: " injected-client ",
                GeminiOAuthConfiguration.clientSecretEnvironmentKey: " injected-secret ",
            ],
            plist: [
                "clientID": "plist-client",
                "clientSecret": "plist-secret",
            ]
        )

        XCTAssertEqual(configuration.clientID, "injected-client")
        XCTAssertEqual(configuration.clientSecret, "injected-secret")
        XCTAssertTrue(configuration.isConfigured)
    }

    func testGeminiOAuthConfigurationFallsBackToPrivatePlistAndAllowsMissingSecret() {
        let plistConfiguration = GeminiOAuthConfiguration.resolve(
            environment: [:],
            plist: ["clientID": "plist-client"]
        )
        let missingConfiguration = GeminiOAuthConfiguration.resolve(environment: [:], plist: [:])

        XCTAssertEqual(plistConfiguration.clientID, "plist-client")
        XCTAssertNil(plistConfiguration.clientSecret)
        XCTAssertTrue(plistConfiguration.isConfigured)
        XCTAssertFalse(missingConfiguration.isConfigured)
    }

    func testOAuthSuccessPagesShareCodexLayoutAndUseProviderCopy() {
        let codexHTML = OAuthCallbackHTML.success(provider: .codex)
        let geminiHTML = OAuthCallbackHTML.success(provider: .gemini)

        XCTAssertTrue(codexHTML.contains("Codex 连接成功 · Codexling"))
        XCTAssertTrue(codexHTML.contains("OpenAI Codex 账号"))
        XCTAssertTrue(geminiHTML.contains("Gemini 连接成功 · Codexling"))
        XCTAssertTrue(geminiHTML.contains("Google Gemini 账号"))
        XCTAssertTrue(codexHTML.contains("class=\"brand-badge\""))
        XCTAssertTrue(geminiHTML.contains("class=\"brand-badge\""))
        XCTAssertTrue(codexHTML.contains("data:image/"))
        XCTAssertTrue(geminiHTML.contains("data:image/"))
        XCTAssertFalse(codexHTML.contains("<button"))
        XCTAssertFalse(geminiHTML.contains("<button"))
        XCTAssertFalse(codexHTML.contains("关闭页面</button>"))
    }

    func testRemoteAntigravityQuotaUsesOAuthProjectAndParsesIndependentBuckets() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GeminiMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        GeminiMockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer account-a-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "antigravity")
            switch request.url?.path {
            case "/v1internal:loadCodeAssist":
                return (200, #"{"cloudaicompanionProject":"project-account-a","paidTier":{"id":"pro","name":"Google AI Pro"}}"#)
            case "/v1internal:retrieveUserQuotaSummary":
                let body = try XCTUnwrap(Self.requestBody(request))
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
                XCTAssertEqual(json["project"], "project-account-a")
                return (200, Self.quotaSummaryFixture)
            case "/v1internal:fetchAvailableModels":
                return (200, #"{"models":{"gemini-pro":{"displayName":"Gemini Pro","model":"gemini-pro"},"claude-sonnet":{"displayName":"Claude Sonnet","model":"claude-sonnet"},"internal":{"displayName":"Internal","isInternal":true}}}"#)
            default:
                XCTFail("出现了未预期的请求：\(request.url?.absoluteString ?? "nil")")
                return (404, "{}")
            }
        }
        defer { GeminiMockURLProtocol.handler = nil }

        let snapshot = await GeminiOAuthService(session: session)
            .fetchQuotaSnapshot(accessToken: "account-a-token")

        XCTAssertEqual(snapshot.projectId, "project-account-a")
        XCTAssertEqual(snapshot.planName, "Google AI Pro")
        XCTAssertEqual(snapshot.geminiFiveHourRemaining, 0.10)
        XCTAssertEqual(snapshot.geminiWeeklyRemaining, 0.70)
        XCTAssertEqual(snapshot.claudeGptFiveHourRemaining, 0.35)
        XCTAssertEqual(snapshot.claudeGptWeeklyRemaining, 0.90)
        XCTAssertEqual(snapshot.availableModels, ["claude-sonnet", "gemini-pro"])
        XCTAssertEqual(snapshot.quotaFetchState, "normal")
    }

    func testRemoteAntigravityUnauthorizedNeverInventsQuota() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GeminiMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        GeminiMockURLProtocol.handler = { _ in (401, #"{"error":{"status":"UNAUTHENTICATED"}}"#) }
        defer { GeminiMockURLProtocol.handler = nil }

        let snapshot = await GeminiOAuthService(session: session)
            .fetchQuotaSnapshot(accessToken: "rejected-token")

        XCTAssertEqual(snapshot.quotaFetchState, "unauthorized")
        XCTAssertNil(snapshot.geminiFiveHourRemaining)
        XCTAssertNil(snapshot.geminiWeeklyRemaining)
        XCTAssertNil(snapshot.claudeGptFiveHourRemaining)
        XCTAssertNil(snapshot.claudeGptWeeklyRemaining)
        XCTAssertTrue(snapshot.availableModels.isEmpty)
    }

    func testRemoteAntigravityValidationRequiredIsNotMislabelledAsPro() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GeminiMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        GeminiMockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1internal:loadCodeAssist")
            return (200, #"{"allowedTiers":[{"id":"standard-tier","name":"Antigravity","isDefault":true}],"ineligibleTiers":[{"reasonCode":"VALIDATION_REQUIRED","reasonMessage":"Your current account is not eligible for Antigravity.","validationErrorMessage":"Verify your account to continue.","validationUrl":"https://accounts.google.com/verify"}]}"#)
        }
        defer { GeminiMockURLProtocol.handler = nil }

        let snapshot = await GeminiOAuthService(session: session)
            .fetchQuotaSnapshot(accessToken: "unverified-account-token")

        XCTAssertEqual(snapshot.quotaFetchState, "account_validation_required")
        XCTAssertEqual(snapshot.planName, "无 Antigravity 权限")
        XCTAssertEqual(snapshot.accountEligibilityMessage, "Google 要求验证此账号后才能使用 Antigravity。")
        XCTAssertEqual(snapshot.accountValidationURL, "https://accounts.google.com/verify")
        XCTAssertFalse(snapshot.isBillingEnabled)
        XCTAssertNil(snapshot.geminiFiveHourRemaining)
        XCTAssertNil(snapshot.geminiWeeklyRemaining)
    }

    func testRemoteAntigravityEligibleFreeTierUsesFreeLabel() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GeminiMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        GeminiMockURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1internal:loadCodeAssist":
                return (200, #"{"cloudaicompanionProject":"free-project","currentTier":{"id":"free-tier","name":"Antigravity"}}"#)
            case "/v1internal:retrieveUserQuotaSummary":
                return (200, Self.quotaSummaryFixture)
            case "/v1internal:fetchAvailableModels":
                return (200, #"{"models":{}}"#)
            default:
                return (404, "{}")
            }
        }
        defer { GeminiMockURLProtocol.handler = nil }

        let snapshot = await GeminiOAuthService(session: session)
            .fetchQuotaSnapshot(accessToken: "free-account-token")

        XCTAssertEqual(snapshot.planName, "Antigravity Free")
        XCTAssertFalse(snapshot.isBillingEnabled)
        XCTAssertEqual(snapshot.quotaFetchState, "normal")
    }

    func testRemoteAntigravityUltraTierUsesUltraLabel() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GeminiMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        GeminiMockURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1internal:loadCodeAssist":
                return (200, #"{"cloudaicompanionProject":"ultra-project","paidTier":{"id":"g1-ultra-tier","name":"Google AI Ultra"}}"#)
            case "/v1internal:retrieveUserQuotaSummary":
                return (200, Self.quotaSummaryFixture)
            case "/v1internal:fetchAvailableModels":
                return (200, #"{"models":{}}"#)
            default:
                return (404, "{}")
            }
        }
        defer { GeminiMockURLProtocol.handler = nil }

        let snapshot = await GeminiOAuthService(session: session)
            .fetchQuotaSnapshot(accessToken: "ultra-account-token")

        XCTAssertEqual(snapshot.planName, "Google AI Ultra")
        XCTAssertTrue(snapshot.isBillingEnabled)
    }

    func testRemoteAntigravityMissingTierNeverFallsBackToPro() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GeminiMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        GeminiMockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1internal:loadCodeAssist")
            return (200, "{}")
        }
        defer { GeminiMockURLProtocol.handler = nil }

        let snapshot = await GeminiOAuthService(session: session)
            .fetchQuotaSnapshot(accessToken: "unknown-tier-token")

        XCTAssertEqual(snapshot.planName, "套餐状态未知")
        XCTAssertEqual(snapshot.quotaFetchState, "quota_unavailable")
        XCTAssertFalse(snapshot.isBillingEnabled)
    }

    func testRemoteAntigravityPermissionDeniedIsUnavailableInsteadOfReloginLoop() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GeminiMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        GeminiMockURLProtocol.handler = { _ in (403, #"{"error":{"status":"PERMISSION_DENIED"}}"#) }
        defer { GeminiMockURLProtocol.handler = nil }

        let snapshot = await GeminiOAuthService(session: session)
            .fetchQuotaSnapshot(accessToken: "valid-but-ineligible-token")

        XCTAssertEqual(snapshot.quotaFetchState, "quota_unavailable")
        XCTAssertNil(snapshot.geminiFiveHourRemaining)
        XCTAssertNil(snapshot.geminiWeeklyRemaining)
    }

    func testGeminiQuotaResetFormatterConvertsISOTimeToAdaptiveCountdown() throws {
        let formatter = ISO8601DateFormatter()
        let now = try XCTUnwrap(formatter.date(from: "2026-08-24T20:00:00Z"))
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        XCTAssertEqual(
            GeminiQuotaResetFormatter.displayText("2026-08-31T09:13:00Z", now: now),
            "6天13小时后刷新"
        )
        XCTAssertEqual(
            GeminiQuotaResetFormatter.displayText("2026-08-24T22:33:00Z", now: now),
            "2小时33分后刷新"
        )
        XCTAssertEqual(
            GeminiQuotaResetFormatter.absoluteText(
                "2026-08-31T09:13:00Z",
                now: now,
                timeZone: utc
            ),
            "2026年08月31日 09:13:00"
        )
    }

    func testGeminiQuotaResetFormatterAdaptsEnglishAndChineseDurations() {
        let now = Date(timeIntervalSince1970: 0)
        let utc = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(
            GeminiQuotaResetFormatter.displayText("6 days, 13 hours, 8 minutes remaining"),
            "6天13小时后刷新"
        )
        XCTAssertEqual(
            GeminiQuotaResetFormatter.displayText("18 分钟后完全刷新"),
            "18分后刷新"
        )
        XCTAssertEqual(GeminiQuotaResetFormatter.displayText("0 minutes"), "即将刷新")
        XCTAssertEqual(
            GeminiQuotaResetFormatter.displayText("1 day, 0 hours, 8 minutes, 12 seconds"),
            "1天8分后刷新"
        )
        XCTAssertEqual(
            GeminiQuotaResetFormatter.displayText("0 days, 0 hours, 3 minutes, 12 seconds"),
            "3分12秒后刷新"
        )
        XCTAssertEqual(
            GeminiQuotaResetFormatter.absoluteText("2 hours, 33 minutes", now: now, timeZone: utc),
            "1970年01月01日 02:33:00"
        )
    }

    private static let quotaSummaryFixture = #"""
    {
      "response": {
        "groups": [
          {
            "displayName": "Gemini Models",
            "buckets": [
              {"bucketId":"gemini-5h","remaining":{"remainingFraction":0.10},"description":"2 hours remaining"},
              {"bucketId":"gemini-weekly","remainingFraction":0.70,"description":"6 days remaining"}
            ]
          },
          {
            "displayName": "Claude and GPT models",
            "buckets": [
              {"bucket_id":"3p-5h","remaining_fraction":"0.35"},
              {"bucketId":"3p-weekly","remainingFraction":0.90}
            ]
          }
        ]
      }
    }
    """#

    private static func requestBody(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    @MainActor
    func testMultiAgentSettingsStoreAddAndRefreshGeminiOAuthAccount() async throws {
        let tokenStore = GeminiOAuthTokenStore(directoryURL: tempDir)
        let mockOAuth = MockGeminiOAuthService(
            token: GeminiOAuthToken(
                accessToken: "ya29.mock-token",
                refreshToken: "1//mock-refresh",
                expiresAt: Date().addingTimeInterval(3600),
                email: "gemini-user@google.com",
                displayName: "Gemini User",
                avatarURL: nil,
                authorizationProfile: "antigravity"
            ),
            modelIDs: [
                "models/gemini-2.5-pro",
                "models/gemini-2.5-flash",
                "models/gemini-2.0-flash"
            ]
        )
        let registryStorage = ConnectionRegistryStorage(
            fileURL: tempDir.appendingPathComponent("connections.json")
        )

        let store = MultiAgentSettingsStore(
            registryStorage: registryStorage,
            geminiOAuthTokenStore: tokenStore,
            geminiOAuthService: mockOAuth,
            startsAutomaticRefresh: false,
            migratesLegacyAccount: false
        )

        let added = await store.addGeminiAccount()
        XCTAssertTrue(added)
        XCTAssertEqual(store.geminiConnections.count, 1)

        let connection: GeminiAccountConnection = try XCTUnwrap(store.geminiConnections.first)
        XCTAssertEqual(connection.email, "gemini-user@google.com")
        XCTAssertEqual(connection.label, "gemini-user@google.com")
        XCTAssertEqual(connection.availableModelCount, 3)
        XCTAssertEqual(connection.availableModelIDs.first, "models/gemini-2.5-pro")
        XCTAssertEqual(connection.authenticationState, ConnectionAuthenticationState.connected)

        // Test refresh
        await store.refreshGeminiConnection(connection)
        XCTAssertEqual(store.geminiConnections.first?.availableModelCount, 3)

        // Test remove
        store.removeGeminiConnection(connection)
        XCTAssertTrue(store.geminiConnections.isEmpty)
    }
}

private final class GeminiMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, String))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (status, body) = try handler(request)
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private struct MockGeminiOAuthService: GeminiOAuthServicing {
    let token: GeminiOAuthToken
    let modelIDs: [String]

    func startOAuth(forceLogin: Bool) async throws -> GeminiOAuthToken {
        token
    }

    func refreshToken(_ token: GeminiOAuthToken) async throws -> GeminiOAuthToken {
        self.token
    }

    func validateModels(accessToken: String) async throws -> [String] {
        modelIDs
    }

    func fetchQuotaSnapshot(accessToken: String) async -> GeminiQuotaSnapshot {
        GeminiQuotaSnapshot(
            projectId: "mock-project-123",
            projectName: "Mock Gemini Project",
            tier: "Google AI Pro",
            isBillingEnabled: true,
            dailyRequestsLimit: 0,
            minuteRequestsLimit: 1500,
            minuteTokensLimit: 4000000,
            planName: "Google AI Pro",
            geminiWeeklyRemaining: 0.92,
            geminiWeeklyResetDesc: "6 天 21 小时后完全刷新",
            geminiFiveHourRemaining: 0.55,
            geminiFiveHourResetDesc: "2 小时 33 分钟后完全刷新",
            claudeGptWeeklyRemaining: 1.0,
            claudeGptFiveHourRemaining: 1.0,
            availableModels: modelIDs,
            availableModelCount: modelIDs.count
        )
    }

    func cancelOAuthAuthorization() {}
}
