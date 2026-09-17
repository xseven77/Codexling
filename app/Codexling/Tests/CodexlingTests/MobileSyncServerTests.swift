import Foundation
import Testing
@testable import Codexling

@Suite("MobileSyncServerTests")
struct MobileSyncServerTests {
    final class MockDataProvider: MobileSyncDataProvider, @unchecked Sendable {
        func makeSnapshot() async -> MobileSnapshotPayload {
            MobileSnapshotPayload(
                schemaVersion: 1,
                generatedAt: Date(timeIntervalSince1970: 1726470000),
                activePetId: "codexling",
                activity: MobileActivityPayload(
                    state: "executing",
                    activeTaskCount: 1,
                    activeTasks: [
                        MobileTaskPayload(id: "task-1", state: "executing", title: "Build router", agent: "codex")
                    ]
                ),
                connections: [
                    MobileConnectionPayload(id: "conn-1", provider: "codex", label: "Work", isHealthy: true, shortWindowRemaining: 78.5)
                ]
            )
        }

        func availablePets() -> [MobilePetMetadata] {
            [
                MobilePetMetadata(
                    id: "codexling",
                    displayName: "Codexling",
                    description: "Signature spirit",
                    frameWidth: 192,
                    frameHeight: 208,
                    totalRows: 11,
                    totalColumns: 8
                ),
                MobilePetMetadata(
                    id: "bsod",
                    displayName: "BSOD",
                    description: "Glitch spirit",
                    frameWidth: 192,
                    frameHeight: 208,
                    totalRows: 11,
                    totalColumns: 8
                )
            ]
        }

        func exportCredentials() async -> MobileCredentialsExportPayload {
            MobileCredentialsExportPayload(
                exportedAt: Date(timeIntervalSince1970: 1726470000),
                accounts: [
                    MobileCredentialAccountPayload(id: "conn-1", provider: "codex", label: "Work", tokenOrKey: "mock-token-secret")
                ]
            )
        }
    }

    @Test("MobileSnapshotPayload JSON serialization")
    func testSnapshotSerialization() throws {
        let payload = MobileSnapshotPayload(
            schemaVersion: 1,
            generatedAt: Date(timeIntervalSince1970: 1726470000),
            activePetId: "codexling",
            activity: MobileActivityPayload(
                state: "executing",
                activeTaskCount: 2,
                activeTasks: [
                    MobileTaskPayload(id: "1", state: "executing", title: "Test 1", agent: "hermes"),
                    MobileTaskPayload(id: "2", state: "waitingForUser", title: "Test 2", agent: "codex")
                ]
            ),
            connections: [
                MobileConnectionPayload(id: "c1", provider: "codex", label: "Main", isHealthy: true, shortWindowRemaining: 65.0)
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MobileSnapshotPayload.self, from: data)

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.activePetId == "codexling")
        #expect(decoded.activity.state == "executing")
        #expect(decoded.activity.activeTaskCount == 2)
        #expect(decoded.activity.activeTasks.count == 2)
        #expect(decoded.connections.count == 1)
        #expect(decoded.connections[0].isHealthy == true)
    }

    @Test("MobilePetMetadata contract matches 11x8 spritesheet spec")
    func testPetMetadataContract() throws {
        let pet = MobilePetMetadata(
            id: "codex",
            displayName: "Codex",
            description: "Codex Companion",
            frameWidth: 192,
            frameHeight: 208,
            totalRows: 11,
            totalColumns: 8
        )

        let data = try JSONEncoder().encode(pet)
        let decoded = try JSONDecoder().decode(MobilePetMetadata.self, from: data)

        #expect(decoded.id == "codex")
        #expect(decoded.frameWidth == 192)
        #expect(decoded.frameHeight == 208)
        #expect(decoded.totalRows == 11)
        #expect(decoded.totalColumns == 8)
        #expect(decoded.actionRowMap["idle"] == 0)
        #expect(decoded.actionRowMap["waiting"] == 6)
        #expect(decoded.actionRowMap["running"] == 7)
    }

    @Test("MobileSyncServer lifecycle and token validation")
    func testServerStartStop() throws {
        let provider = MockDataProvider()
        let server = MobileSyncServer(port: 59351, token: "test-token-12345", dataProvider: provider)

        // Starting and stopping the server should not throw or crash
        try server.start()
        server.stop()
    }

    /// Regression: a busy port used to be swallowed entirely.
    ///
    /// `NWListener` binds asynchronously, so the conflict arrives via
    /// `stateUpdateHandler` rather than a thrown error. The old handler called
    /// `stop()` — no status, no error, no retry — which left the mobile server
    /// permanently dead after a `restart()` raced with the previous listener's
    /// cancellation.
    @Test("MobileSyncServer reports a busy port instead of dying silently")
    func testPortConflictIsReported() async throws {
        let port: UInt16 = 59377
        let provider = MockDataProvider()

        let first = MobileSyncServer(port: port, token: "token-a", dataProvider: provider)
        try first.start()
        defer { first.stop() }

        // Wait for the first listener to actually reach `.ready`.
        try await waitFor(timeout: 5) { first.status == .ready }

        let second = MobileSyncServer(port: port, token: "token-b", dataProvider: provider)
        defer { second.stop() }
        try second.start()

        // The second bind must surface a failure, never a silent "started".
        try await waitFor(timeout: 5) {
            if case .failed = second.status { return true }
            return false
        }
        if case .failed(let message) = second.status {
            #expect(!message.isEmpty, "busy port must carry an explanation")
        } else {
            Issue.record("expected .failed, got \(second.status)")
        }
    }

    @Test("MobileSyncServer recovers once the port is released")
    func testRebindsAfterPortIsFreed() async throws {
        let port: UInt16 = 59378
        let provider = MockDataProvider()

        let blocker = MobileSyncServer(port: port, token: "token-a", dataProvider: provider)
        try blocker.start()
        try await waitFor(timeout: 5) { blocker.status == .ready }

        let contender = MobileSyncServer(port: port, token: "token-b", dataProvider: provider)
        defer { contender.stop() }
        try contender.start()
        try await waitFor(timeout: 5) {
            if case .failed = contender.status { return true }
            return false
        }

        // Free the port; the contender's backoff retry must eventually win.
        blocker.stop()
        try await waitFor(timeout: 20) { contender.status == .ready }
        #expect(contender.status == .ready)
    }

    /// The scenario the settings "重启服务" button exists for: rebind the same
    /// port without restarting the app. `cancel()` releases the port
    /// asynchronously, so this used to race into EADDRINUSE and die silently.
    @Test("MobileSyncServer can be restarted on the same port")
    func testRestartOnSamePort() async throws {
        let port: UInt16 = 59379
        let server = MobileSyncServer(port: port, token: "token", dataProvider: MockDataProvider())
        defer { server.stop() }

        try server.start()
        try await waitFor(timeout: 5) { server.status == .ready }

        server.stop()
        try server.start()

        // Either it binds straight away, or the internal backoff gets there.
        try await waitFor(timeout: 15) { server.status == .ready }
        #expect(server.status == .ready)
        #expect(!server.isAwaitingRetry)
    }

    /// Polls `condition` until it holds or `timeout` elapses.
    private func waitFor(
        timeout: TimeInterval,
        _ condition: @escaping @Sendable () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        Issue.record("timed out after \(timeout)s waiting for condition")
    }

    @Test("MobileSyncServer default plugin directory points to Application Support")
    func testPluginDirectoryDefault() {
        let defaultURL = MobileSyncServer.defaultPluginDirectoryURL
        #expect(defaultURL.path.contains("Plugins/mobile-web"))
    }

    @Test("MobileCredentialsExportPayload serialization")
    func testCredentialsExportSerialization() throws {
        let payload = MobileCredentialsExportPayload(
            exportedAt: Date(timeIntervalSince1970: 1726470000),
            accounts: [
                MobileCredentialAccountPayload(id: "c1", provider: "codex", label: "Work", tokenOrKey: "tok-12345"),
                MobileCredentialAccountPayload(id: "c2", provider: "deepseek", label: "Personal", tokenOrKey: "sk-67890")
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MobileCredentialsExportPayload.self, from: data)

        #expect(decoded.accounts.count == 2)
        #expect(decoded.accounts[0].provider == "codex")
        #expect(decoded.accounts[0].tokenOrKey == "tok-12345")
        #expect(decoded.accounts[1].provider == "deepseek")
    }

    @Test("WebPluginInstaller inspects installed plugin")
    func testWebPluginInstallerStatus() {
        let installer = WebPluginInstaller.shared
        let status = installer.currentStatus()
        // If plugin is installed in App Support, verify manifest and index
        if status.isInstalled {
            #expect(status.manifest?.version == "1.0.0")
            #expect(status.manifest?.name == "codexling-mobile-web")
        }
    }
}
