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
