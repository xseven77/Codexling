import AppKit
import XCTest
@testable import Codexling

@MainActor
final class GatewayTests: XCTestCase {
    func testAgentCompatibleModelIDUsesGatewayAccountSyntaxWithoutSpaces() {
        XCTAssertEqual(
            GatewayStore.agentCompatibleModelID("gemini-3.7-flash (Seven X)"),
            "gemini-3.7-flash@seven-x"
        )
        XCTAssertEqual(
            GatewayStore.agentCompatibleModelID("deepseek-chat"),
            "deepseek-chat"
        )
        XCTAssertEqual(
            GatewayStore.hermesPickerModelID(
                provider: "Google Gemini",
                modelName: "gemini-3.7-flash",
                accountName: "X Seven"
            ),
            "Google-Gemini·gemini-3.7-flash·X-Seven"
        )
    }

    func testHermesGatewayConfigurationUsesOfficialCustomProviderContractAndVerifiesWrites() throws {
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hermes-config-\(UUID().uuidString).yaml")
        try Data("model:\n  provider: opencode-free\n".utf8).write(to: configURL)
        defer { try? FileManager.default.removeItem(at: configURL) }

        let runner = TestHermesCommandRunner()
        let configurator = HermesGatewayConfigurator(runner: runner, configURL: configURL)
        try configurator.configure(
            baseURL: "http://127.0.0.1:58349/v1",
            apiKey: "local-test-token",
            models: ["deepseek-chat", "gemini-3.1-pro-preview"],
            defaultModel: "gemini-3.1-pro-preview"
        )

        XCTAssertEqual(runner.values["providers.codexling.name"], "Codexling")
        XCTAssertEqual(runner.values["providers.codexling.api"], "http://127.0.0.1:58349/v1")
        XCTAssertEqual(runner.values["providers.codexling.api_key"], "local-test-token")
        XCTAssertEqual(runner.values["providers.codexling.transport"], "chat_completions")
        XCTAssertEqual(runner.values["providers.codexling.default_model"], "gemini-3.1-pro-preview")
        XCTAssertEqual(runner.values["providers.codexling.discover_models"], "false")
        XCTAssertEqual(runner.values["providers.codexling.models"], "[\"deepseek-chat\",\"gemini-3.1-pro-preview\"]")
        XCTAssertEqual(runner.values["providers.codexling.extra_headers.X-Codexling-Catalog-Version"], "2")
        XCTAssertEqual(runner.values["model.provider"], "custom:codexling")
        XCTAssertEqual(runner.values["model.default"], "gemini-3.1-pro-preview")
        XCTAssertEqual(runner.commands.filter { $0.starts(with: ["config", "set"]) }.count, 10)
        XCTAssertEqual(runner.commands.filter { $0.starts(with: ["config", "unset"]) }.count, 2)
        XCTAssertEqual(runner.commands.filter { $0.starts(with: ["config", "get"]) }.count, 9)
    }

    func testHermesGatewayConfigurationRejectsFalseSuccessWhenReadbackDiffers() throws {
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hermes-config-\(UUID().uuidString).yaml")
        let original = Data("model:\n  provider: opencode-free\n".utf8)
        try original.write(to: configURL)
        defer { try? FileManager.default.removeItem(at: configURL) }

        let runner = TestHermesCommandRunner(forcedReadback: ["model.provider": "opencode-free"])
        let configurator = HermesGatewayConfigurator(runner: runner, configURL: configURL)

        XCTAssertThrowsError(
            try configurator.configure(
                baseURL: "http://127.0.0.1:58349/v1",
                apiKey: "local-test-token",
                models: ["deepseek-chat"],
                defaultModel: "deepseek-chat"
            )
        )
        XCTAssertEqual(try Data(contentsOf: configURL), original)
    }

    func testPiGatewayConfigurationWritesModelsContractAndPreservesSettings() throws {
        let agentDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-agent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: agentDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: agentDirectory) }

        let modelsURL = agentDirectory.appendingPathComponent("models.json")
        let settingsURL = agentDirectory.appendingPathComponent("settings.json")
        try Data(#"{"providers":{"existing":{"baseUrl":"http://example.test","api":"openai-completions","apiKey":"x","models":[{"id":"old"}]}}}"#.utf8).write(to: modelsURL)
        try Data(#"{"theme":"dark","provider":"stale","baseURL":"stale","apiKey":"stale"}"#.utf8).write(to: settingsURL)

        let runner = TestPiCommandRunner(discoveredModel: "deepseek-chat")
        let configurator = PiGatewayConfigurator(runner: runner, agentDirectory: agentDirectory)
        try configurator.configure(
            baseURL: "http://127.0.0.1:58349/v1",
            apiKey: "local-test-token",
            models: ["deepseek-chat", "gemini-3.1-pro-preview", "deepseek-chat"],
            defaultModel: "deepseek-chat"
        )

        let modelsRoot = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: modelsURL)) as? [String: Any]
        )
        let providers = try XCTUnwrap(modelsRoot["providers"] as? [String: Any])
        XCTAssertNotNil(providers["existing"])
        let codexling = try XCTUnwrap(providers["codexling"] as? [String: Any])
        XCTAssertEqual(codexling["baseUrl"] as? String, "http://127.0.0.1:58349/v1")
        XCTAssertEqual(codexling["api"] as? String, "openai-completions")
        XCTAssertEqual(codexling["apiKey"] as? String, "local-test-token")
        XCTAssertEqual((codexling["models"] as? [[String: Any]])?.count, 2)

        let settings = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any]
        )
        XCTAssertEqual(settings["theme"] as? String, "dark")
        XCTAssertEqual(settings["defaultProvider"] as? String, "codexling")
        XCTAssertEqual(settings["defaultModel"] as? String, "deepseek-chat")
        XCTAssertNil(settings["provider"])
        XCTAssertNil(settings["baseURL"])
        XCTAssertNil(settings["apiKey"])
        XCTAssertEqual(runner.commands, [["--offline", "--list-models", "codexling"]])
    }

    func testGatewaySupervisorStateAndToggle() {
        let supervisor = GatewaySupervisor.shared
        XCTAssertTrue(supervisor.isRunning)
        XCTAssertEqual(supervisor.port, 58349)
        XCTAssertEqual(supervisor.endpoint?.absoluteString, "http://127.0.0.1:58349")
        XCTAssertFalse(supervisor.localToken.isEmpty)
        XCTAssertEqual(supervisor.statusText, "运行中")

        supervisor.stop()
        XCTAssertFalse(supervisor.isRunning)
        XCTAssertEqual(supervisor.statusText, "已停止")

        supervisor.start()
        XCTAssertTrue(supervisor.isRunning)
        XCTAssertEqual(supervisor.statusText, "运行中")
    }

    func testGatewayStoreTelemetryAndChecks() {
        let store = GatewayStore.shared
        XCTAssertEqual(store.telemetryItems.count, 9)
        XCTAssertEqual(store.doctorChecks.count, 5)
        XCTAssertTrue(store.doctorChecks.contains { $0.id == "sec" && $0.isSuccess })
        XCTAssertTrue(store.doctorChecks.contains { !$0.isSuccess })
        XCTAssertGreaterThanOrEqual(store.accountModelGroups.count, 4)
        XCTAssertGreaterThanOrEqual(store.allExportedModels.count, 2)
        XCTAssertEqual(store.openAIBaseURL, "http://127.0.0.1:58349/v1")
        XCTAssertEqual(store.anthropicBaseURL, "http://127.0.0.1:58349")
        XCTAssertFalse(store.localToken.isEmpty)
        XCTAssertEqual(store.agentRows.count, 4)
        XCTAssertTrue(store.requestsList.isEmpty)

        // Test Codex group has GPT-5 models
        let codexGroup = store.accountModelGroups.first { $0.id.hasPrefix("codex") }
        XCTAssertTrue(codexGroup?.models.contains(where: { $0.modelName.contains("gpt-5") }) ?? false)

        // Custom entries are explicitly user-added and are exported alongside
        // the account's discovered model catalog.
        let geminiGroupId = store.accountModelGroups.first { $0.id.hasPrefix("google_gemini") }?.id ?? "google_gemini"
        store.addCustomModel("custom-gemini-test", toGroupId: geminiGroupId)
        let geminiGroup = store.accountModelGroups.first { $0.id == geminiGroupId }
        XCTAssertTrue(geminiGroup?.models.contains(where: { $0.modelName.contains("custom-gemini-test") }) ?? false)

        store.removeCustomModel("custom-gemini-test", fromGroupId: geminiGroupId)
        let geminiGroupAfter = store.accountModelGroups.first { $0.id == geminiGroupId }
        XCTAssertFalse(geminiGroupAfter?.models.contains(where: { $0.modelName.contains("custom-gemini-test") }) ?? true)

        // Test Tab Switching
        store.selectedTab = .connect
        XCTAssertEqual(store.selectedTab.rawValue, "接入与模型")
        XCTAssertEqual(store.selectedTab.symbolName, "network")

        // Test metric updates
        store.updateGatewayMetrics(totalRequests: 10, inputTokens: 5000, outputTokens: 2000, toolCalls: 4)
        XCTAssertEqual(store.totalRequests, 10)
        XCTAssertEqual(store.totalInputTokens, 5000)
        XCTAssertEqual(store.totalOutputTokens, 2000)
        XCTAssertEqual(store.totalToolCalls, 4)
        XCTAssertFalse(store.todayDurationText.isEmpty)
    }

    func testGatewayStorePerAgentDurationAttribution() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("companion-stats-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let now = Date()
        let statsStore = CompanionStatsStore(fileURL: fileURL, now: now)
        statsStore.setActivityState(.executing, agentID: "antigravity", now: now)
        statsStore.tick(now: now.addingTimeInterval(60))
        statsStore.tick(now: now.addingTimeInterval(120))
        statsStore.setActivityState(.idle, agentID: nil, now: now.addingTimeInterval(120))

        let store = GatewayStore(companionStatsStore: statsStore)
        let rows = store.agentRows
        let codexRow = rows.first { $0.id == "codex" }
        let agRow = rows.first { $0.id == "antigravity" }

        XCTAssertEqual(codexRow?.durationText, "0 分钟")
        XCTAssertEqual(agRow?.durationText, "2 分钟")
    }

    func testGatewayWindowControllerProperties() {
        let controller = GatewayWindowController.shared
        controller.show()
        
        // Window should not release on close, and windowShouldClose must return false
        // to keep supervisor process alive
        let window = NSApp.windows.first { $0.title == "Codexling Gateway" }
        XCTAssertNotNil(window)
        if let window {
            XCTAssertFalse(window.isReleasedWhenClosed)
            XCTAssertFalse(controller.windowShouldClose(window))
        }
        controller.close()
    }

    func testGatewaySecretBrokerSaveAndRetrieve() throws {
        let broker = GatewaySecretBroker.shared
        let testAccount = "test-provider-key-\(UUID().uuidString)"
        let secret = "sk-test-secret-value-12345"

        try broker.saveSecret(secret, for: testAccount)
        let retrieved = broker.retrieveSecret(for: testAccount)
        XCTAssertEqual(retrieved, secret)

        try broker.deleteSecret(for: testAccount)
        let afterDelete = broker.retrieveSecret(for: testAccount)
        XCTAssertNil(afterDelete)
    }
}

private final class TestHermesCommandRunner: HermesCommandRunning, @unchecked Sendable {
    let isAvailable = true
    private let forcedReadback: [String: String]
    private(set) var values: [String: String] = [:]
    private(set) var commands: [[String]] = []

    init(forcedReadback: [String: String] = [:]) {
        self.forcedReadback = forcedReadback
    }

    func run(arguments: [String]) throws -> HermesCommandResult {
        commands.append(arguments)
        if arguments.count == 4, arguments[0] == "config", arguments[1] == "set" {
            values[arguments[2]] = arguments[3]
            return HermesCommandResult(output: "saved\n", errorOutput: "", terminationStatus: 0)
        }
        if arguments.count == 3, arguments[0] == "config", arguments[1] == "unset" {
            values.removeValue(forKey: arguments[2])
            return HermesCommandResult(output: "removed\n", errorOutput: "", terminationStatus: 0)
        }
        if arguments.count == 3, arguments[0] == "config", arguments[1] == "get" {
            let key = arguments[2]
            return HermesCommandResult(
                output: "\(forcedReadback[key] ?? values[key] ?? "")\n",
                errorOutput: "",
                terminationStatus: 0
            )
        }
        return HermesCommandResult(output: "", errorOutput: "unexpected command", terminationStatus: 1)
    }
}

private final class TestPiCommandRunner: PiCommandRunning, @unchecked Sendable {
    let isAvailable = true
    private let discoveredModel: String
    private(set) var commands: [[String]] = []

    init(discoveredModel: String) {
        self.discoveredModel = discoveredModel
    }

    func run(arguments: [String], agentDirectory: URL) throws -> PiCommandResult {
        commands.append(arguments)
        return PiCommandResult(
            output: "provider   model\ncodexling  \(discoveredModel)\n",
            errorOutput: "",
            terminationStatus: 0
        )
    }
}
