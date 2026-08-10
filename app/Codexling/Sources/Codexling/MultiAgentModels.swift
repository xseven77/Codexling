import Foundation

/// Stable identifiers used by the multi-agent registry. An agent identifies a
/// runtime family; a surface identifies where that runtime is presented.
struct AgentID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    static let codex = Self(rawValue: "agent.codex")
    static let hermes = Self(rawValue: "agent.hermes")
    static let claudeCode = Self(rawValue: "agent.claude-code")
    static let reasonix = Self(rawValue: "agent.reasonix")
}

enum AgentSurfaceID: String, Hashable, Codable, Sendable {
    case codexCLI = "surface.codex-cli"
    case codexDesktop = "surface.codex-desktop"
    case hermesCLI = "surface.hermes-cli"
    case claudeCodeCLI = "surface.claude-code-cli"
    case claudeCodeDesktop = "surface.claude-code-desktop"
    case reasonixCLI = "surface.reasonix-cli"
    case reasonixDesktop = "surface.reasonix-desktop"
}

struct AgentDescriptor: Hashable, Codable, Sendable {
    let id: AgentID
    let displayName: String
    let priority: Int
    let surfaces: Set<AgentSurfaceID>
}

enum BuiltInAgentCatalog {
    static let prioritized: [AgentDescriptor] = [
        AgentDescriptor(
            id: .codex,
            displayName: "Codex",
            priority: 0,
            surfaces: [.codexCLI, .codexDesktop]
        ),
        AgentDescriptor(
            id: .hermes,
            displayName: "Hermes",
            priority: 1,
            surfaces: [.hermesCLI]
        ),
        AgentDescriptor(
            id: .claudeCode,
            displayName: "Claude Code",
            priority: 2,
            surfaces: [.claudeCodeCLI, .claudeCodeDesktop]
        ),
        AgentDescriptor(
            id: .reasonix,
            displayName: "Reasonix",
            priority: 3,
            surfaces: [.reasonixCLI, .reasonixDesktop]
        )
    ]

    struct DevelopmentTarget: Equatable, Sendable {
        let agentID: AgentID
        let surface: AgentSurfaceID?
    }

    /// Product delivery order. A nil surface means the shared agent core and
    /// all currently supported Codex surfaces are handled together.
    static let developmentPriority: [DevelopmentTarget] = [
        DevelopmentTarget(agentID: .codex, surface: nil),
        DevelopmentTarget(agentID: .hermes, surface: .hermesCLI),
        DevelopmentTarget(agentID: .claudeCode, surface: .claudeCodeCLI),
        DevelopmentTarget(agentID: .claudeCode, surface: .claudeCodeDesktop),
        DevelopmentTarget(agentID: .reasonix, surface: nil),
    ]
}

struct ConnectionID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: UUID
}

enum ConnectionIsolation: Hashable, Codable, Sendable {
    /// Each Codex account owns a separate CODEX_HOME and app-server process.
    case codexHome(relativeDirectory: String)
    /// The secret itself lives in Keychain; only this opaque handle is modeled.
    case keychain(credentialHandle: String)
    /// Authentication is owned by the vendor CLI and is never copied.
    case vendorManaged
}

struct AgentConnection: Identifiable, Hashable, Codable, Sendable {
    let id: ConnectionID
    let agentID: AgentID
    var label: String
    let isolation: ConnectionIsolation
}

/// Session IDs are only unique inside one vendor/account namespace.
struct AgentSessionID: Hashable, Codable, Sendable {
    let agentID: AgentID
    let connectionID: ConnectionID
    let vendorSessionID: String
}

struct ProviderID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    static let deepSeek = Self(rawValue: "provider.deepseek")
}

struct ProviderConnection: Identifiable, Hashable, Codable, Sendable {
    let id: ConnectionID
    let providerID: ProviderID
    var label: String
    let credentialHandle: String
    var keySuffix: String
}

enum QuotaScope: String, Hashable, Codable, Sendable {
    case account
    case apiKey
    case subscription
    case session
}

/// DeepSeek's `/user/balance` is an account balance queried with an API key;
/// it is not a per-key spend or remaining-quota measurement.
struct ProviderBalanceSnapshot: Equatable, Codable, Sendable {
    let connectionID: ConnectionID
    let providerID: ProviderID
    let scope: QuotaScope
    let currency: String
    let total: Decimal
    let granted: Decimal
    let toppedUp: Decimal
    let fetchedAt: Date
}
