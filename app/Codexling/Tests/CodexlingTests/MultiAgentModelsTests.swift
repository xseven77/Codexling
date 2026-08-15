import XCTest
@testable import Codexling

final class MultiAgentModelsTests: XCTestCase {
    func testPriorityOrderMatchesCommittedRoadmap() {
        XCTAssertEqual(
            BuiltInAgentCatalog.developmentPriority,
            [
                .init(agentID: .codex, surface: nil),
                .init(agentID: .hermes, surface: .hermesCLI),
                .init(agentID: .claudeCode, surface: .claudeCodeCLI),
                .init(agentID: .claudeCode, surface: .claudeCodeDesktop),
                .init(agentID: .reasonix, surface: nil),
            ]
        )
    }

    func testClaudeCodeDesktopIsASurfaceNotASecondIdentityDomain() throws {
        let claude = try XCTUnwrap(
            BuiltInAgentCatalog.prioritized.first(where: { $0.id == .claudeCode })
        )

        XCTAssertTrue(claude.surfaces.contains(.claudeCodeCLI))
        XCTAssertTrue(claude.surfaces.contains(.claudeCodeDesktop))
    }

    func testSameVendorSessionIDDoesNotCollideAcrossCodexAccounts() {
        let personal = ConnectionID(rawValue: UUID())
        let work = ConnectionID(rawValue: UUID())

        let first = AgentSessionID(
            agentID: .codex,
            connectionID: personal,
            vendorSessionID: "thread-1"
        )
        let second = AgentSessionID(
            agentID: .codex,
            connectionID: work,
            vendorSessionID: "thread-1"
        )

        XCTAssertNotEqual(first, second)
    }

    func testCodexAccountsUseSeparateHomes() {
        let personal = AgentConnection(
            id: ConnectionID(rawValue: UUID()),
            agentID: .codex,
            label: "Personal",
            isolation: .codexHome(relativeDirectory: "codex/personal")
        )
        let work = AgentConnection(
            id: ConnectionID(rawValue: UUID()),
            agentID: .codex,
            label: "Work",
            isolation: .codexHome(relativeDirectory: "codex/work")
        )

        XCTAssertNotEqual(personal.isolation, work.isolation)
    }

    func testDeepSeekBalancesRemainConnectionScopedButAccountLevel() {
        let firstConnection = ConnectionID(rawValue: UUID())
        let secondConnection = ConnectionID(rawValue: UUID())
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let first = ProviderBalanceSnapshot(
            connectionID: firstConnection,
            providerID: .deepSeek,
            scope: .account,
            currency: "CNY",
            total: 110,
            granted: 10,
            toppedUp: 100,
            fetchedAt: timestamp
        )
        let second = ProviderBalanceSnapshot(
            connectionID: secondConnection,
            providerID: .deepSeek,
            scope: .account,
            currency: "CNY",
            total: 110,
            granted: 10,
            toppedUp: 100,
            fetchedAt: timestamp
        )

        XCTAssertNotEqual(first.connectionID, second.connectionID)
        XCTAssertEqual(first.scope, .account)
        XCTAssertEqual(second.scope, .account)
    }

    func testProviderBalanceIndicatorUsesRequestedThresholds() {
        XCTAssertEqual(ProviderBalanceIndicator.resolve(total: 42.80, authenticationState: .connected), .healthy)
        XCTAssertEqual(ProviderBalanceIndicator.resolve(total: 10, authenticationState: .connected), .low)
        XCTAssertEqual(ProviderBalanceIndicator.resolve(total: 0.01, authenticationState: .connected), .low)
        XCTAssertEqual(ProviderBalanceIndicator.resolve(total: 0, authenticationState: .connected), .depleted)
        XCTAssertEqual(ProviderBalanceIndicator.resolve(total: -1, authenticationState: .connected), .depleted)
        XCTAssertEqual(ProviderBalanceIndicator.resolve(total: nil, authenticationState: .invalid), .depleted)
    }

    func testDeepSeekCredentialFilesArePrivateAndRoundTripWithoutAuthenticationUI() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexling-deepseek-credentials-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DeepSeekCredentialStore(credentialsDir: root)

        try store.save(apiKey: "sk-test", handle: "test-handle")

        XCTAssertEqual(try store.read(handle: "test-handle"), "sk-test")
        let attributes = try FileManager.default.attributesOfItem(
            atPath: root.appendingPathComponent("test-handle.json").path
        )
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, NSNumber(value: 0o600))
    }

    @MainActor
    func testUnifiedRefreshUpdatesEveryDeepSeekConnection() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexling-unified-refresh-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let firstID = ConnectionID(rawValue: UUID())
        let secondID = ConnectionID(rawValue: UUID())
        let registry = ConnectionRegistryStorage(fileURL: root.appendingPathComponent("connections.json"))
        try registry.save(ConnectionRegistrySnapshot(
            codexAccounts: [],
            deepSeekConnections: [
                DeepSeekAPIConnection(
                    id: firstID,
                    label: "First",
                    credentialHandle: "first",
                    keySuffix: "1111",
                    authenticationState: .checking,
                    createdAt: Date()
                ),
                DeepSeekAPIConnection(
                    id: secondID,
                    label: "Second",
                    credentialHandle: "second",
                    keySuffix: "2222",
                    authenticationState: .checking,
                    createdAt: Date()
                ),
            ]
        ))
        let credentialStore = TestDeepSeekCredentialStore(values: [
            "first": "first-key",
            "second": "second-key",
        ])
        let balanceService = TestDeepSeekBalanceService()
        let store = MultiAgentSettingsStore(
            hookManager: AgentHookManager(
                homeDirectory: root.appendingPathComponent("home", isDirectory: true),
                applicationSupportDirectory: root.appendingPathComponent("support", isDirectory: true)
            ),
            registryStorage: registry,
            codexRuntimeManager: CodexAccountRuntimeManager(
                runtimesRoot: root.appendingPathComponent("runtimes", isDirectory: true)
            ),
            credentialStore: credentialStore,
            deepSeekBalanceService: balanceService,
            startsAutomaticRefresh: false
        )

        let outcome = await store.refreshAllConnections()
        let refreshedConnectionIDs = await balanceService.recordedConnectionIDs()

        XCTAssertFalse(store.isRefreshingConnections)
        XCTAssertEqual(outcome.successCount, 2)
        XCTAssertTrue(outcome.failures.isEmpty)
        XCTAssertEqual(store.deepSeekConnections.map(\.authenticationState), [.connected, .connected])
        XCTAssertEqual(store.deepSeekConnections.map { $0.balance?.total }, [11, 22])
        XCTAssertEqual(Set(refreshedConnectionIDs), Set([firstID, secondID]))
    }

    @MainActor
    func testLastSelectedProviderConnectionPersistsAndReloads() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexling-selected-connection-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let defaultsKey = "dashboard.selectedConnection"
        let previousSelection = UserDefaults.standard.object(forKey: defaultsKey)
        defer {
            if let previousSelection {
                UserDefaults.standard.set(previousSelection, forKey: defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
            }
        }
        UserDefaults.standard.set(MultiAgentSettingsStore.currentCodexConnectionKey, forKey: defaultsKey)

        let firstID = ConnectionID(rawValue: UUID())
        let secondID = ConnectionID(rawValue: UUID())
        let registry = ConnectionRegistryStorage(fileURL: root.appendingPathComponent("connections.json"))
        try registry.save(ConnectionRegistrySnapshot(
            deepSeekConnections: [
                DeepSeekAPIConnection(
                    id: firstID,
                    label: "First",
                    credentialHandle: "first",
                    keySuffix: "1111",
                    authenticationState: .connected,
                    createdAt: Date()
                ),
                DeepSeekAPIConnection(
                    id: secondID,
                    label: "Second",
                    credentialHandle: "second",
                    keySuffix: "2222",
                    authenticationState: .connected,
                    createdAt: Date()
                ),
            ]
        ))

        func makeStore() -> MultiAgentSettingsStore {
            MultiAgentSettingsStore(
                hookManager: AgentHookManager(
                    homeDirectory: root.appendingPathComponent("home", isDirectory: true),
                    applicationSupportDirectory: root.appendingPathComponent("support", isDirectory: true)
                ),
                registryStorage: registry,
                codexRuntimeManager: CodexAccountRuntimeManager(
                    runtimesRoot: root.appendingPathComponent("runtimes", isDirectory: true)
                ),
                credentialStore: TestDeepSeekCredentialStore(values: [:]),
                deepSeekBalanceService: TestDeepSeekBalanceService(),
                startsAutomaticRefresh: false
            )
        }

        let store = makeStore()
        let selectedConnection = store.deepSeekConnections[1]
        let selectedKey = store.connectionKey(for: selectedConnection)
        store.selectDeepSeekConnection(selectedConnection)

        XCTAssertEqual(store.selectedConnectionKey, selectedKey)
        XCTAssertEqual(makeStore().selectedConnectionKey, selectedKey)
        XCTAssertEqual(makeStore().selectedDeepSeekConnection?.id, selectedConnection.id)
    }

    func testManualRefreshToastSummarizesSuccessPartialFailureAndFailure() {
        let success = RefreshToast(outcome: RefreshOutcome(successCount: 3))
        XCTAssertTrue(success.isSuccess)
        XCTAssertEqual(success.message, "刷新成功 · 已更新 3 个连接")

        let partial = RefreshToast(outcome: RefreshOutcome(
            successCount: 2,
            failures: ["Hermes 未能刷新"]
        ))
        XCTAssertFalse(partial.isSuccess)
        XCTAssertEqual(partial.message, "部分刷新失败 · 1 个连接")

        let failure = RefreshToast(outcome: RefreshOutcome(failures: ["DeepSeek：网络不可用"]))
        XCTAssertFalse(failure.isSuccess)
        XCTAssertEqual(failure.message, "刷新失败 · DeepSeek：网络不可用")
    }
}

private final class TestDeepSeekCredentialStore: DeepSeekCredentialStoring, @unchecked Sendable {
    private let values: [String: String]

    init(values: [String: String]) {
        self.values = values
    }

    func save(apiKey: String, handle: String) throws {}

    func read(handle: String) throws -> String {
        guard let value = values[handle] else { throw DeepSeekCredentialError.missing }
        return value
    }

    func delete(handle: String) throws {}
}

private actor TestDeepSeekBalanceService: DeepSeekBalanceFetching {
    private var connectionIDs: [ConnectionID] = []

    func recordedConnectionIDs() -> [ConnectionID] {
        connectionIDs
    }

    func fetch(apiKey: String, connectionID: ConnectionID) async throws -> ProviderBalanceSnapshot {
        connectionIDs.append(connectionID)
        let total: Decimal = apiKey == "first-key" ? 11 : 22
        return ProviderBalanceSnapshot(
            connectionID: connectionID,
            providerID: .deepSeek,
            scope: .account,
            currency: "CNY",
            total: total,
            granted: 0,
            toppedUp: total,
            fetchedAt: Date()
        )
    }
}
