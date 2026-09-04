import Foundation

public struct GatewaySettings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var modelConsolidationEnabled: Bool
    public var consolidatedProviders: [String]
    public var allowFailover: Bool
    public var cooldownSeconds: Int
    public var maxFailoverRetries: Int

    public enum CodingKeys: String, CodingKey {
        case schemaVersion = "$schemaVersion"
        case modelConsolidationEnabled
        case consolidatedProviders
        case allowFailover
        case cooldownSeconds
        case maxFailoverRetries
    }

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        modelConsolidationEnabled: Bool = false,
        consolidatedProviders: [String] = [],
        allowFailover: Bool = true,
        cooldownSeconds: Int = 300,
        maxFailoverRetries: Int = 2
    ) {
        self.schemaVersion = schemaVersion
        self.modelConsolidationEnabled = modelConsolidationEnabled
        self.consolidatedProviders = consolidatedProviders
        self.allowFailover = allowFailover
        self.cooldownSeconds = cooldownSeconds
        self.maxFailoverRetries = maxFailoverRetries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        modelConsolidationEnabled = try container.decodeIfPresent(Bool.self, forKey: .modelConsolidationEnabled) ?? false
        consolidatedProviders = try container.decodeIfPresent([String].self, forKey: .consolidatedProviders) ?? []
        allowFailover = try container.decodeIfPresent(Bool.self, forKey: .allowFailover) ?? true
        cooldownSeconds = try container.decodeIfPresent(Int.self, forKey: .cooldownSeconds) ?? 300
        maxFailoverRetries = try container.decodeIfPresent(Int.self, forKey: .maxFailoverRetries) ?? 2
    }

    public func isProviderConsolidated(_ providerID: String) -> Bool {
        let normalized = providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if consolidatedProviders.contains(where: { $0.lowercased() == normalized }) {
            return true
        }
        // Aliases check (e.g. codex/openai, gemini/google)
        if (normalized == "openai" || normalized == "codex") &&
            consolidatedProviders.contains(where: { $0.lowercased() == "openai" || $0.lowercased() == "codex" }) {
            return true
        }
        if (normalized == "google" || normalized == "gemini") &&
            consolidatedProviders.contains(where: { $0.lowercased() == "google" || $0.lowercased() == "gemini" }) {
            return true
        }
        // Backwards compatibility: if consolidatedProviders is empty, fallback to modelConsolidationEnabled
        if consolidatedProviders.isEmpty && modelConsolidationEnabled {
            return true
        }
        return false
    }

    public mutating func setProviderConsolidated(_ providerID: String, enabled: Bool) {
        let normalized = providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var current = Set(consolidatedProviders.map { $0.lowercased() })
        // If it was fallbacking to legacy modelConsolidationEnabled, populate current set first
        if consolidatedProviders.isEmpty && modelConsolidationEnabled {
            current = ["openai", "google", "deepseek", "opencode"]
        }
        if enabled {
            current.insert(normalized)
        } else {
            current.remove(normalized)
            if normalized == "openai" { current.remove("codex") }
            if normalized == "codex" { current.remove("openai") }
            if normalized == "google" { current.remove("gemini") }
            if normalized == "gemini" { current.remove("google") }
        }
        self.consolidatedProviders = Array(current).sorted()
        // Synchronize modelConsolidationEnabled as true if any provider is enabled
        self.modelConsolidationEnabled = !self.consolidatedProviders.isEmpty
    }
}

public struct GatewaySettingsStorage: @unchecked Sendable {
    public let fileManager: FileManager
    public let fileURL: URL

    public init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Codexling/gateway-settings.json")
    }

    public func load() -> GatewaySettings {
        let decoder = JSONDecoder()
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? decoder.decode(GatewaySettings.self, from: data) else {
            return GatewaySettings()
        }
        return settings
    }

    public func save(_ settings: GatewaySettings) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(settings)
        data.append(0x0A)
        try data.write(to: fileURL, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
