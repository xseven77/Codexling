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
            avatarURL: "https://example.com/avatar.png"
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
                avatarURL: nil
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
