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

    func testConnectionShortIDAndCompositeModelFormatting() {
        let uuid = UUID(uuidString: "12345678-ABCD-EF01-2345-6789ABCDEF01")!
        let connID = ConnectionID(rawValue: uuid)
        let shortID = GatewayStore.connectionShortID(id: connID)
        XCTAssertEqual(shortID, "12345678")

        let slug = "\(GatewayStore.accountSlug(name: "Work"))-google-\(shortID)"
        XCTAssertEqual(slug, "work-google-12345678")

        let agentModelID = GatewayStore.agentCompatibleModelID("gemini-2.5-flash (\(slug))")
        XCTAssertEqual(agentModelID, "gemini-2.5-flash@work-google-12345678")
    }

    func testCodexServableSlugsReadsCliauthoritativeCacheAndExcludesHidden() throws {
        let fm = FileManager.default
        let runtimesRoot = fm.temporaryDirectory.appendingPathComponent("codex-runtimes-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: runtimesRoot) }
        let relative = "abc123-def456"
        let home = runtimesRoot.appendingPathComponent(relative, isDirectory: true)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        try """
        {"models":[
          {"slug":"gpt-reserve","visibility":"hide","display_name":"Reserve"},
          {"slug":"codex-auto-review","visibility":"hide","display_name":"Review"},
          {"slug":"gpt-5.6-sol","visibility":"list","display_name":"GPT-5.6 Sol"},
          {"slug":"gpt-brand-new","visibility":"list"}
        ]}
        """.data(using: .utf8)!.write(to: home.appendingPathComponent("models_cache.json"))

        // availableModelIDs (the OpenAI/ChatGPT API catalog) is now the source
        // of truth, exactly matching how Gemini/OpenCode/DeepSeek operate — the
        // requirement is to run on the OpenAI API, not a local codex CLI.
        let connection = CodexAccountConnection(
            id: ConnectionID(rawValue: UUID()),
            label: "Seven X",
            relativeHomeDirectory: relative,
            authenticationState: .connected,
            isEnabled: true,
            usage: nil,
            availableModelIDs: [
                "gpt-5.6-sol-wm",
                "gpt-5.6-terra-wm",
                "gpt-5.5-wm",
                "gpt-5-6",
                "research",
            ],
            createdAt: Date()
        )
        let slugs = GatewayStore.codexServableSlugs(from: connection, runtimesRoot: runtimesRoot)
        // -wm watermark suffix is stripped, `research` is dropped, flagship order is applied.
        XCTAssertEqual(slugs, ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5-6", "gpt-5.5"])
        XCTAssertFalse(slugs.contains("research"), "research is an internal entry")

        // When availableModelIDs is empty, fall back to the CLI cache and still
        // exclude hidden/internal entries.
        let cacheConnection = CodexAccountConnection(
            id: ConnectionID(rawValue: UUID()),
            label: "Cache Only",
            relativeHomeDirectory: relative,
            authenticationState: .connected,
            isEnabled: true,
            usage: nil,
            availableModelIDs: [],
            createdAt: Date()
        )
        let cacheSlugs = GatewayStore.codexServableSlugs(from: cacheConnection, runtimesRoot: runtimesRoot)
        XCTAssertEqual(cacheSlugs, ["gpt-5.6-sol", "gpt-brand-new"])
        XCTAssertFalse(cacheSlugs.contains("gpt-reserve"))
        XCTAssertFalse(cacheSlugs.contains("codex-auto-review"))
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
        XCTAssertEqual(runner.values["providers.codexling.extra_headers.X-Agent-Name"], "Hermes")
        XCTAssertEqual(runner.values["model.provider"], "custom:codexling")
        XCTAssertEqual(runner.values["model.default"], "gemini-3.1-pro-preview")
        XCTAssertEqual(runner.commands.filter { $0.starts(with: ["config", "set"]) }.count, 11)
        XCTAssertEqual(runner.commands.filter { $0.starts(with: ["config", "unset"]) }.count, 2)
        XCTAssertEqual(runner.commands.filter { $0.starts(with: ["config", "get"]) }.count, 10)
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

    func testHermesGatewayUnconfigurationRemovesProviderAndResetsModel() throws {
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hermes-config-\(UUID().uuidString).yaml")
        try Data("providers:\n  codexling:\n    name: Codexling\n".utf8).write(to: configURL)
        defer { try? FileManager.default.removeItem(at: configURL) }

        let runner = TestHermesCommandRunner()
        let configurator = HermesGatewayConfigurator(runner: runner, configURL: configURL)

        // First configure
        try configurator.configure(
            baseURL: "http://127.0.0.1:58349/v1",
            apiKey: "local-test-token",
            models: ["deepseek-chat"],
            defaultModel: "deepseek-chat"
        )
        XCTAssertTrue(configurator.isConfigured)

        // Now unconfigure
        try configurator.unconfigure()
        XCTAssertFalse(configurator.isConfigured)
        XCTAssertNil(runner.values["providers.codexling.name"])
        XCTAssertNil(runner.values["providers.codexling.api"])
        XCTAssertNil(runner.values["providers.codexling.api_key"])
        XCTAssertNil(runner.values["providers.codexling.models"])
        XCTAssertNil(runner.values["model.provider"])
        XCTAssertNil(runner.values["model.default"])
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

    func testPiGatewayUnconfigurationRemovesProviderAndResetsDefaults() throws {
        let agentDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-agent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: agentDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: agentDirectory) }

        let modelsURL = agentDirectory.appendingPathComponent("models.json")
        let settingsURL = agentDirectory.appendingPathComponent("settings.json")
        try Data(#"{"providers":{"codexling":{"baseUrl":"http://example.test"},"other":{"baseUrl":"http://other.test"}}}"#.utf8).write(to: modelsURL)
        try Data(#"{"defaultProvider":"codexling","defaultModel":"gemini-3.7-flash","otherSetting":"keep"}"#.utf8).write(to: settingsURL)

        let runner = TestPiCommandRunner(discoveredModel: "gemini-3.7-flash")
        let configurator = PiGatewayConfigurator(runner: runner, agentDirectory: agentDirectory)

        XCTAssertTrue(configurator.isConfigured)

        try configurator.unconfigure()

        XCTAssertFalse(configurator.isConfigured)

        let modelsRoot = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: modelsURL)) as? [String: Any]
        )
        let providers = try XCTUnwrap(modelsRoot["providers"] as? [String: Any])
        XCTAssertNil(providers["codexling"])
        XCTAssertNotNil(providers["other"])

        let settings = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any]
        )
        XCTAssertNil(settings["defaultProvider"])
        XCTAssertNil(settings["defaultModel"])
        XCTAssertEqual(settings["otherSetting"] as? String, "keep")
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
        XCTAssertEqual(store.telemetryItems.count, 7)
        XCTAssertEqual(store.doctorChecks.count, 5)
        XCTAssertTrue(store.doctorChecks.contains { $0.id == "sec" && $0.isSuccess })
        XCTAssertTrue(store.doctorChecks.contains { !$0.isSuccess })
        XCTAssertGreaterThanOrEqual(store.accountModelGroups.count, 4)
        XCTAssertGreaterThanOrEqual(store.allExportedModels.count, 2)
        XCTAssertEqual(store.openAIBaseURL, "http://127.0.0.1:58349/v1")
        XCTAssertEqual(store.anthropicBaseURL, "http://127.0.0.1:58349")
        XCTAssertFalse(store.localToken.isEmpty)
        XCTAssertEqual(store.agentRows.count, 5)
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

        statsStore.setActivityState(.executing, agentID: "hermes", now: now.addingTimeInterval(120))
        statsStore.tick(now: now.addingTimeInterval(180))
        statsStore.tick(now: now.addingTimeInterval(240))
        statsStore.setActivityState(.idle, agentID: nil, now: now.addingTimeInterval(240))

        let store = GatewayStore(companionStatsStore: statsStore)
        let rows = store.agentRows
        let codexRow = rows.first { $0.id == "codex" }
        let agRow = rows.first { $0.id == "antigravity" }
        let hermesRow = rows.first { $0.id == "hermes" }
        let dshRow = rows.first { $0.id == "dsh" }
        let piRow = rows.first { $0.id == "pi" }

        XCTAssertEqual(codexRow?.durationText, "0 分钟")
        XCTAssertEqual(agRow?.durationText, "2 分钟")
        XCTAssertEqual(hermesRow?.durationText, "2 分钟")
        XCTAssertEqual(dshRow?.durationText, "0 分钟")
        XCTAssertEqual(piRow?.durationText, "0 分钟")
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

    func testGatewaySettingsStorageDefaultAndRoundtrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gateway-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let settingsURL = tempDir.appendingPathComponent("gateway-settings.json")
        let storage = GatewaySettingsStorage(fileURL: settingsURL)

        // Initial load when file does not exist should yield default settings
        let defaultSettings = storage.load()
        XCTAssertEqual(defaultSettings.schemaVersion, 1)
        XCTAssertFalse(defaultSettings.modelConsolidationEnabled)
        XCTAssertTrue(defaultSettings.allowFailover)
        XCTAssertEqual(defaultSettings.cooldownSeconds, 300)
        XCTAssertEqual(defaultSettings.maxFailoverRetries, 2)

        // Save customized settings
        let custom = GatewaySettings(
            modelConsolidationEnabled: true,
            allowFailover: false,
            cooldownSeconds: 600,
            maxFailoverRetries: 3
        )
        try storage.save(custom)

        // Verify file permissions 0600
        let attrs = try FileManager.default.attributesOfItem(atPath: settingsURL.path)
        let perms = attrs[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.intValue, 0o600)

        // Readback check
        let loaded = storage.load()
        XCTAssertEqual(loaded, custom)
    }

    func testGatewayStoreModelConsolidationTogglePersists() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gateway-store-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let settingsURL = tempDir.appendingPathComponent("gateway-settings.json")
        let storage = GatewaySettingsStorage(fileURL: settingsURL)
        let store = GatewayStore(settingsStorage: storage)

        XCTAssertFalse(store.isModelConsolidationEnabled)
        store.isModelConsolidationEnabled = true
        XCTAssertTrue(store.isModelConsolidationEnabled)

        // Verify storage on disk was updated
        let reloaded = storage.load()
        XCTAssertTrue(reloaded.modelConsolidationEnabled)
    }

    func testHermesTwoSegmentPickerModelID() {
        // Test 2-segment picker formatting for consolidated pool routing
        let pickerID1 = GatewayStore.hermesPickerModelID(
            provider: "Google Gemini",
            modelName: "gemini-3.7-flash"
        )
        XCTAssertEqual(pickerID1, "Google-Gemini·gemini-3.7-flash")

        let pickerID2 = GatewayStore.hermesPickerModelID(
            provider: "OpenAI",
            modelName: "gpt-5.6-sol"
        )
        XCTAssertEqual(pickerID2, "OpenAI·gpt-5.6-sol")

        let pickerID3 = GatewayStore.hermesPickerModelID(
            provider: "Google",
            modelName: "gemini-2.5-pro-tiered"
        )
        // Ensure `-tiered` implementation suffix is removed
        XCTAssertEqual(pickerID3, "Google·gemini-2.5-pro")
    }

    func testConsolidatedExportedModelsSwitching() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gateway-store-consolidation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let settingsURL = tempDir.appendingPathComponent("gateway-settings.json")
        let storage = GatewaySettingsStorage(fileURL: settingsURL)
        let store = GatewayStore(settingsStorage: storage)

        // When consolidation is disabled, allExportedModels reflects account-scoped models
        XCTAssertFalse(store.isModelConsolidationEnabled)
        let unconsolidatedCount = store.allExportedModels.count

        // Enable consolidation
        store.isModelConsolidationEnabled = true
        XCTAssertTrue(store.isModelConsolidationEnabled)

        // All exported models should now be deduplicated by (provider, baseModel)
        let consolidated = store.allExportedModels
        XCTAssertEqual(consolidated, store.consolidatedExportedModels)

        // Ensure no scoped account suffixes "(...)" exist in consolidated model names
        for model in consolidated {
            XCTAssertFalse(model.modelName.contains(" ("), "Consolidated model should not contain account scope: \(model.modelName)")
            XCTAssertTrue(model.sourceBadge.contains("聚合"))
        }

        // Toggle back
        store.isModelConsolidationEnabled = false
        XCTAssertEqual(store.allExportedModels.count, unconsolidatedCount)
    }

    func testPerProviderConsolidationSwitchingAndPersistence() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gateway-store-per-provider-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let settingsURL = tempDir.appendingPathComponent("gateway-settings.json")
        let storage = GatewaySettingsStorage(fileURL: settingsURL)
        var store = GatewayStore(settingsStorage: storage)

        // Initially no providers are consolidated
        XCTAssertFalse(store.isProviderConsolidated("openai"))
        XCTAssertFalse(store.isProviderConsolidated("google"))
        XCTAssertFalse(store.isProviderConsolidated("deepseek"))
        XCTAssertFalse(store.isProviderConsolidated("opencode"))

        // Enable only OpenAI consolidation
        store.setProviderConsolidated("openai", enabled: true)
        XCTAssertTrue(store.isProviderConsolidated("openai"))
        XCTAssertTrue(store.isProviderConsolidated("codex"))
        XCTAssertFalse(store.isProviderConsolidated("google"))
        XCTAssertFalse(store.isProviderConsolidated("deepseek"))
        XCTAssertFalse(store.isProviderConsolidated("opencode"))
        XCTAssertTrue(store.isModelConsolidationEnabled)

        // Reload from disk into a fresh store to verify persistence
        let storeReloaded = GatewayStore(settingsStorage: storage)
        XCTAssertTrue(storeReloaded.isProviderConsolidated("openai"))
        XCTAssertFalse(storeReloaded.isProviderConsolidated("google"))

        // Enable Google as well
        store.setProviderConsolidated("google", enabled: true)
        XCTAssertTrue(store.isProviderConsolidated("google"))
        XCTAssertTrue(store.isProviderConsolidated("gemini"))

        // Disable OpenAI
        store.setProviderConsolidated("openai", enabled: false)
        XCTAssertFalse(store.isProviderConsolidated("openai"))
        XCTAssertTrue(store.isProviderConsolidated("google"))

        // Disable Google
        store.setProviderConsolidated("google", enabled: false)
        XCTAssertFalse(store.isProviderConsolidated("google"))
        XCTAssertFalse(store.isModelConsolidationEnabled)
    }

    func testGeminiProxyEnabledDoesNotDependOnEmptyModels() {
        let store = GatewayStore()
        let googleGroups = store.accountModelGroups.filter { $0.id.hasPrefix("google_gemini_") }
        for group in googleGroups {
            XCTAssertTrue(group.isProxyAllowed)
            XCTAssertEqual(group.isProxyEnabled, true)
        }
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
