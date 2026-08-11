import Foundation
import XCTest
@testable import Codexling

final class AgentHookManagerTests: XCTestCase {
    func testCodexUsesBuiltInAdapterAndRejectsHookMutation() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let codex = try XCTUnwrap(fixture.manager.integrationStatuses().first { $0.id == .codex })
        XCTAssertEqual(codex.hookState, .builtIn)
        XCTAssertEqual(codex.detail, "App Server · 本地活动")
        XCTAssertThrowsError(try fixture.manager.installHook(for: .codex)) {
            XCTAssertEqual($0 as? AgentHookManagerError, .unsupportedAgent)
        }
        XCTAssertThrowsError(try fixture.manager.uninstallHook(for: .codex)) {
            XCTAssertEqual($0 as? AgentHookManagerError, .unsupportedAgent)
        }
    }

    func testReasonixUsesDirectHookEntriesAndRemovesOnlyCodexling() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        try fixture.manager.installHook(for: .reasonix)
        let config = fixture.home.appendingPathComponent(".reasonix/hooks/hooks.json")
        let installed = try String(contentsOf: config, encoding: .utf8)
        XCTAssertTrue(installed.contains("\"PreToolUse\""))
        XCTAssertTrue(installed.contains(AgentHookManager.commandMarker))
        XCTAssertFalse(installed.contains("\"hooks\" : ["))

        try fixture.manager.uninstallHook(for: .reasonix)
        XCTAssertFalse(try String(contentsOf: config, encoding: .utf8).contains(AgentHookManager.commandMarker))
    }

    func testHermesMergesIntoExistingHooksBlockAndUninstallsCleanly() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let config = fixture.home.appendingPathComponent(".hermes/config.yaml")
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "model: test\nhooks:\n  pre_tool_call:\n    - command: \"existing-hook\"\n      timeout: 2\nui:\n  theme: dark\n"
            .write(to: config, atomically: true, encoding: .utf8)

        try fixture.manager.installHook(for: .hermes)
        let installed = try String(contentsOf: config, encoding: .utf8)
        XCTAssertTrue(installed.contains("existing-hook"))
        XCTAssertTrue(installed.contains(AgentHookManager.commandMarker))
        XCTAssertEqual(installed.components(separatedBy: "hooks:").count - 1, 1)
        XCTAssertTrue(fixture.manager.areHermesHooksAuthorized())

        let allowlist = fixture.home.appendingPathComponent(".hermes/shell-hooks-allowlist.json")
        let allowlistRoot = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: allowlist)) as? [String: Any]
        )
        let approvals = try XCTUnwrap(allowlistRoot["approvals"] as? [[String: Any]])
        XCTAssertEqual(approvals.filter {
            ($0["command"] as? String)?.contains(AgentHookManager.commandMarker) == true
        }.count, 7)

        try fixture.manager.uninstallHook(for: .hermes)
        let uninstalled = try String(contentsOf: config, encoding: .utf8)
        XCTAssertTrue(uninstalled.contains("existing-hook"))
        XCTAssertTrue(uninstalled.contains("ui:"))
        XCTAssertFalse(uninstalled.contains(AgentHookManager.commandMarker))
        let updatedRoot = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: allowlist)) as? [String: Any]
        )
        let updatedApprovals = try XCTUnwrap(updatedRoot["approvals"] as? [[String: Any]])
        XCTAssertFalse(updatedApprovals.contains {
            ($0["command"] as? String)?.contains(AgentHookManager.commandMarker) == true
        })
    }

    func testHermesConfiguredWithoutApprovalReportsAuthorizationRequired() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let hermes = fixture.home.appendingPathComponent(".local/bin/hermes")
        try FileManager.default.createDirectory(at: hermes.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: hermes.path, contents: Data("hermes".utf8)))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hermes.path)

        try fixture.manager.installHook(for: .hermes)
        try FileManager.default.removeItem(
            at: fixture.home.appendingPathComponent(".hermes/shell-hooks-allowlist.json")
        )

        let status = try XCTUnwrap(
            fixture.manager.integrationStatuses().first { $0.id == .hermes }
        )
        XCTAssertEqual(status.hookState, .authorizationRequired)
    }

    func testActivityArbitrationPrefersWaitingThenFailureThenActivity() {
        let now = Date()
        let result = AgentActivityArbitrator.preferred([
            AgentActivityCandidate(state: .thinking, updatedAt: now.addingTimeInterval(20)),
            AgentActivityCandidate(state: .failed, updatedAt: now.addingTimeInterval(10)),
            AgentActivityCandidate(state: .waitingForUser, updatedAt: now),
        ])
        XCTAssertEqual(result?.state, .waitingForUser)
    }

    func testHookEventReducerLetsWaitingAgentWinAndKeepsAllActiveTasks() {
        let now = Date()
        var reducer = AgentEventActivityReducer()
        reducer.ingest(NormalizedAgentEvent(
            agentID: .hermes,
            surfaceID: .hermesCLI,
            sessionID: "hermes-session",
            event: .toolStarted,
            timestamp: now
        ))
        reducer.ingest(NormalizedAgentEvent(
            agentID: .claudeCode,
            surfaceID: .claudeCodeDesktop,
            sessionID: "claude-session",
            event: .permissionRequested,
            timestamp: now.addingTimeInterval(1)
        ))

        let snapshot = reducer.mergedSnapshot(base: .unavailable, now: now.addingTimeInterval(2))
        XCTAssertEqual(snapshot.state, .waitingForUser)
        XCTAssertEqual(snapshot.threadTitle, "Claude Code · Desktop")
        XCTAssertEqual(snapshot.activeTaskCount, 2)
        XCTAssertEqual(Set(snapshot.activeTasks.map(\.title)), ["Hermes · CLI", "Claude Code · Desktop"])
        XCTAssertEqual(Set(snapshot.localAgentTasks.map(\.title)), ["Hermes · CLI", "Claude Code · Desktop"])
    }

    func testHookEventReducerKeepsIdleAgentInPetLocalSummaryOnly() {
        let now = Date()
        var reducer = AgentEventActivityReducer()
        reducer.ingest(NormalizedAgentEvent(
            agentID: .hermes,
            surfaceID: .hermesCLI,
            sessionID: "hermes-session",
            event: .sessionStarted,
            timestamp: now
        ))

        let snapshot = reducer.mergedSnapshot(base: .unavailable, now: now.addingTimeInterval(1))
        XCTAssertTrue(snapshot.activeTasks.isEmpty)
        XCTAssertEqual(snapshot.activeTaskCount, 0)
        XCTAssertEqual(snapshot.localAgentTasks.map(\.title), ["Hermes · CLI"])
        XCTAssertEqual(snapshot.localAgentTasks.first?.state, .idle)
    }

    func testBridgeWireFormatDecodesStringIdentifiers() throws {
        let connectionID = UUID()
        let json = """
        {"schemaVersion":1,"agentID":"agent.hermes","surfaceID":"surface.hermes-cli","connectionID":"\(connectionID.uuidString)","sessionID":"session-1","event":"permission.requested","timestamp":"2026-08-10T12:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(NormalizedAgentEvent.self, from: Data(json.utf8))
        XCTAssertEqual(event.agentID, .hermes)
        XCTAssertEqual(event.surfaceID, .hermesCLI)
        XCTAssertEqual(event.connectionID?.rawValue, connectionID)
        XCTAssertEqual(event.event, .permissionRequested)
    }

    func testCodexAppServerCapabilityGateRequiresAllUsedMethods() {
        let probe = CodexAppServerCapabilityProbe()
        let supported = probe.inspect(schemaData: Data(
            #"{"methods":["initialize","account/read","account/rateLimits/read","thread/list"]}"#.utf8
        ))
        XCTAssertTrue(supported.supported)

        let unsupported = probe.inspect(schemaData: Data(#"{"methods":["initialize","account/read"]}"#.utf8))
        XCTAssertFalse(unsupported.supported)
        XCTAssertEqual(Set(unsupported.missingMethods), ["account/rateLimits/read", "thread/list"])
    }

    func testCodexAppServerParsesAccountAndRateLimitFixture() throws {
        let account: [String: Any] = [
            "id": 2,
            "result": [
                "account": ["type": "chatgpt", "email": "work@example.com", "planType": "team"],
                "requiresOpenaiAuth": true,
            ],
        ]
        let limits: [String: Any] = [
            "id": 3,
            "result": [
                "rateLimits": [
                    "primary": ["usedPercent": 18, "windowDurationMins": 300, "resetsAt": 1_800_000_000],
                    "secondary": ["usedPercent": 24, "windowDurationMins": 10_080, "resetsAt": 1_800_100_000],
                ],
            ],
        ]
        let snapshot = try CodexAppServerSnapshotParser().parse(
            accountResponse: account,
            rateLimitResponse: limits
        )
        XCTAssertEqual(snapshot.email, "work@example.com")
        XCTAssertEqual(snapshot.planType, "team")
        XCTAssertEqual(snapshot.primary?.remainingPercent, 82)
        XCTAssertEqual(snapshot.secondary?.remainingPercent, 76)
    }

    func testHookEventReducerExpiresCompletionAndRemovesEndedSession() {
        let now = Date()
        var reducer = AgentEventActivityReducer()
        let completed = NormalizedAgentEvent(
            agentID: .reasonix,
            surfaceID: .reasonixCLI,
            sessionID: "reasonix-session",
            event: .turnCompleted,
            timestamp: now
        )
        reducer.ingest(completed)
        XCTAssertEqual(reducer.mergedSnapshot(base: .unavailable, now: now).state, .completed)
        XCTAssertEqual(
            reducer.mergedSnapshot(base: .unavailable, now: now.addingTimeInterval(16)).state,
            .unavailable
        )

        reducer.ingest(NormalizedAgentEvent(
            agentID: .hermes,
            surfaceID: .hermesCLI,
            sessionID: "ended",
            event: .toolStarted,
            timestamp: now
        ))
        reducer.ingest(NormalizedAgentEvent(
            agentID: .hermes,
            surfaceID: .hermesCLI,
            sessionID: "ended",
            event: .sessionEnded,
            timestamp: now.addingTimeInterval(1)
        ))
        XCTAssertEqual(reducer.mergedSnapshot(base: .unavailable, now: now.addingTimeInterval(2)).state, .unavailable)
    }

    func testCodexRuntimeCreatesSeparateFileCredentialHomes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexling-runtime-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = CodexAccountRuntimeManager(runtimesRoot: root)
        let work = try manager.createAccount(label: "Work")
        let personal = try manager.createAccount(label: "Personal")

        XCTAssertNotEqual(work.id, personal.id)
        XCTAssertNotEqual(work.relativeHomeDirectory, personal.relativeHomeDirectory)
        let workConfig = try String(contentsOf: manager.homeURL(for: work).appendingPathComponent("config.toml"), encoding: .utf8)
        let personalConfig = try String(contentsOf: manager.homeURL(for: personal).appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertEqual(workConfig, "cli_auth_credentials_store = \"file\"\n")
        XCTAssertEqual(personalConfig, workConfig)

        let token = CodexOAuthToken(
            accessToken: "work-access",
            refreshToken: "work-refresh",
            idToken: "work-id",
            expiresAt: Date().addingTimeInterval(3_600),
            email: "work@example.com",
            displayName: "Work"
        )
        let workTokenStore = CodexOAuthTokenStore(fileURL: try manager.oauthTokenURL(for: work))
        let personalTokenStore = CodexOAuthTokenStore(fileURL: try manager.oauthTokenURL(for: personal))
        workTokenStore.save(token)

        let loadedToken = try XCTUnwrap(workTokenStore.load())
        XCTAssertEqual(loadedToken.accessToken, token.accessToken)
        XCTAssertEqual(loadedToken.refreshToken, token.refreshToken)
        XCTAssertEqual(loadedToken.idToken, token.idToken)
        XCTAssertEqual(loadedToken.email, token.email)
        XCTAssertEqual(loadedToken.displayName, token.displayName)
        XCTAssertEqual(loadedToken.expiresAt.timeIntervalSince1970, token.expiresAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertFalse(personalTokenStore.hasStoredToken())
    }

    func testConnectionRegistryRoundTripsDatesAndAccountScopedBalance() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexling-registry-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = ConnectionRegistryStorage(fileURL: root.appendingPathComponent("connections.json"))
        let id = ConnectionID(rawValue: UUID())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = ConnectionRegistrySnapshot(
            codexAccounts: [],
            deepSeekConnections: [
                DeepSeekAPIConnection(
                    id: id,
                    label: "Personal Key",
                    credentialHandle: "opaque-handle",
                    keySuffix: "7A2F",
                    authenticationState: .connected,
                    balance: ProviderBalanceSnapshot(
                        connectionID: id,
                        providerID: .deepSeek,
                        scope: .account,
                        currency: "CNY",
                        total: Decimal(string: "42.80")!,
                        granted: Decimal(string: "4.80")!,
                        toppedUp: Decimal(string: "38.00")!,
                        fetchedAt: now
                    ),
                    createdAt: now
                ),
            ]
        )
        try storage.save(snapshot)

        let loaded = storage.load()
        XCTAssertEqual(loaded.deepSeekConnections.count, 1)
        XCTAssertEqual(loaded.deepSeekConnections[0].balance?.scope, .account)
        XCTAssertEqual(loaded.deepSeekConnections[0].balance?.total, Decimal(string: "42.80"))
        XCTAssertEqual(loaded.deepSeekConnections[0].createdAt, now)
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexling-hook-tests-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let support = root.appendingPathComponent("support", isDirectory: true)
        let helper = root.appendingPathComponent("CodexlingAgentBridge")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: helper.path, contents: Data("bridge".utf8)))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        return Fixture(
            root: root,
            home: home,
            manager: AgentHookManager(
                homeDirectory: home,
                applicationSupportDirectory: support,
                helperSourceURL: helper
            )
        )
    }
}

private struct Fixture {
    let root: URL
    let home: URL
    let manager: AgentHookManager

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
