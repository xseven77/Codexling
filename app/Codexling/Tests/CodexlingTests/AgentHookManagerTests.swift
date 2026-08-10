import Foundation
import XCTest
@testable import Codexling

final class AgentHookManagerTests: XCTestCase {
    func testCodexInstallAndUninstallPreserveExistingHooks() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let config = fixture.home.appendingPathComponent(".codex/hooks.json")
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"existing-hook"}]}]}}"#
            .data(using: .utf8)!
            .write(to: config)

        try fixture.manager.installHook(for: .codex)
        let installed = try String(contentsOf: config, encoding: .utf8)
        XCTAssertTrue(installed.contains("existing-hook"))
        XCTAssertTrue(installed.contains(AgentHookManager.commandMarker))

        try fixture.manager.uninstallHook(for: .codex)
        let uninstalled = try String(contentsOf: config, encoding: .utf8)
        XCTAssertTrue(uninstalled.contains("existing-hook"))
        XCTAssertFalse(uninstalled.contains(AgentHookManager.commandMarker))
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

        try fixture.manager.uninstallHook(for: .hermes)
        let uninstalled = try String(contentsOf: config, encoding: .utf8)
        XCTAssertTrue(uninstalled.contains("existing-hook"))
        XCTAssertTrue(uninstalled.contains("ui:"))
        XCTAssertFalse(uninstalled.contains(AgentHookManager.commandMarker))
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
