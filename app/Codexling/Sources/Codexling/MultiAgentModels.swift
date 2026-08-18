import Foundation

/// Stable identifiers used by the multi-agent registry. An agent identifies a
/// runtime family; a surface identifies where that runtime is presented.
struct AgentID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    static let codex = Self(rawValue: "agent.codex")
    static let hermes = Self(rawValue: "agent.hermes")
    static let deepseekHarness = Self(rawValue: "agent.deepseek-harness")
}

enum AgentSurfaceID: String, Hashable, Codable, Sendable {
    case codexCLI = "surface.codex-cli"
    case codexDesktop = "surface.codex-desktop"
    case hermesCLI = "surface.hermes-cli"
    case deepseekHarnessCLI = "surface.deepseek-harness-cli"
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
            id: .deepseekHarness,
            displayName: "Deepseek Harness",
            priority: 1,
            surfaces: [.deepseekHarnessCLI]
        ),
        AgentDescriptor(
            id: .hermes,
            displayName: "Hermes",
            priority: 2,
            surfaces: [.hermesCLI]
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
        DevelopmentTarget(agentID: .deepseekHarness, surface: .deepseekHarnessCLI),
        DevelopmentTarget(agentID: .hermes, surface: .hermesCLI),
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
    static let openCodeGo = Self(rawValue: "provider.opencode-go")
    static let openCodeZen = Self(rawValue: "provider.opencode-zen")
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

enum ConnectionAuthenticationState: String, Codable, Sendable {
    case needsLogin
    case checking
    case connected
    case invalid
}

enum ProviderBalanceIndicator: Equatable, Sendable {
    case healthy
    case low
    case depleted

    static func resolve(total: Decimal?, authenticationState: ConnectionAuthenticationState) -> Self {
        guard authenticationState == .connected else { return .depleted }
        guard let total else { return .low }
        if total <= 0 { return .depleted }
        if total <= 10 { return .low }
        return .healthy
    }
}

struct CodexAccountRateLimitWindow: Equatable, Codable, Sendable {
    let usedPercent: Int
    let resetsAt: Date?
    let windowDurationMinutes: Int?

    var remainingPercent: Int { 100 - usedPercent }
}

struct CodexAccountUsageSnapshot: Equatable, Codable, Sendable {
    let email: String?
    let planType: String?
    let primary: CodexAccountRateLimitWindow?
    let secondary: CodexAccountRateLimitWindow?
    let fetchedAt: Date
    /// 订阅到期时间（RFC3339）。OAuth 路径会回填，CLI 路径可能为空。
    let subscriptionActiveUntilISO: String?
    let subscriptionWillRenew: Bool?
    let resetCoupons: [ResetCoupon]

    init(
        email: String?,
        planType: String?,
        primary: CodexAccountRateLimitWindow?,
        secondary: CodexAccountRateLimitWindow?,
        fetchedAt: Date,
        subscriptionActiveUntilISO: String? = nil,
        subscriptionWillRenew: Bool? = nil,
        resetCoupons: [ResetCoupon] = []
    ) {
        self.email = email
        self.planType = planType
        self.primary = primary
        self.secondary = secondary
        self.fetchedAt = fetchedAt
        self.subscriptionActiveUntilISO = subscriptionActiveUntilISO
        self.subscriptionWillRenew = subscriptionWillRenew
        self.resetCoupons = resetCoupons
    }
}

struct CodexAccountConnection: Identifiable, Equatable, Codable, Sendable {
    let id: ConnectionID
    var label: String
    let relativeHomeDirectory: String
    var authenticationState: ConnectionAuthenticationState
    var isEnabled: Bool
    /// 该 Codex 连接的全量快照（额度/账单/重置券）。
    var usage: CodexUsageSnapshot? = nil
    let createdAt: Date
}

struct DeepSeekAPIConnection: Identifiable, Equatable, Codable, Sendable {
    let id: ConnectionID
    var label: String
    let credentialHandle: String
    let keySuffix: String
    var authenticationState: ConnectionAuthenticationState
    var balance: ProviderBalanceSnapshot?
    let createdAt: Date
}

/// OpenCode Go 与 Zen 使用相同的 API Key 凭据机制，但它们是两种不同的
/// 计费产品：Go 是订阅额度窗口，Zen 是按余额/消费计费。因此不能合并成
/// 单一的 "OpenCode" 连接或复用同一张额度卡片。
enum OpenCodePlan: String, CaseIterable, Hashable, Codable, Sendable {
    case go
    case zen

    var providerID: ProviderID {
        switch self {
        case .go: .openCodeGo
        case .zen: .openCodeZen
        }
    }

    var displayName: String {
        switch self {
        case .go: "OpenCode Go"
        case .zen: "OpenCode Zen"
        }
    }
}

/// A validated OpenCode API-key connection. `availableModelCount` is only a
/// capability check; neither OpenCode Go usage windows nor Zen account balance
/// currently have a stable public API, so this record deliberately stores no
/// inferred quota value.
struct OpenCodeAPIConnection: Identifiable, Equatable, Codable, Sendable {
    let id: ConnectionID
    var label: String
    let plan: OpenCodePlan
    let credentialHandle: String
    let keySuffix: String
    var authenticationState: ConnectionAuthenticationState
    var availableModelCount: Int?
    /// 可访问的模型 id 列表（用于「点击查看模型列表」弹窗）。
    var availableModelIDs: [String] = []
    var lastValidatedAt: Date?
    /// 用户账号的 OpenCode 工作间页面地址（例如 .../workspace/wrk_xxx/go）。
    /// 用于 footer「前往官方页面」深链到账号页面；为空时退回通用控制台。
    var workspaceURL: String?
    let createdAt: Date

    /// Custom Codable so `availableModelIDs` decodes as `[]` when absent
    /// (older saved registries), preventing a decode failure that would wipe
    /// the whole connection registry on load.
    enum CodingKeys: String, CodingKey {
        case id, label, plan, credentialHandle, keySuffix, authenticationState
        case availableModelCount, availableModelIDs, lastValidatedAt, workspaceURL, createdAt
    }

    init(
        id: ConnectionID,
        label: String,
        plan: OpenCodePlan,
        credentialHandle: String,
        keySuffix: String,
        authenticationState: ConnectionAuthenticationState,
        availableModelCount: Int? = nil,
        availableModelIDs: [String] = [],
        lastValidatedAt: Date? = nil,
        workspaceURL: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.label = label
        self.plan = plan
        self.credentialHandle = credentialHandle
        self.keySuffix = keySuffix
        self.authenticationState = authenticationState
        self.availableModelCount = availableModelCount
        self.availableModelIDs = availableModelIDs
        self.lastValidatedAt = lastValidatedAt
        self.workspaceURL = workspaceURL
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ConnectionID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        plan = try container.decode(OpenCodePlan.self, forKey: .plan)
        credentialHandle = try container.decode(String.self, forKey: .credentialHandle)
        keySuffix = try container.decode(String.self, forKey: .keySuffix)
        authenticationState = try container.decode(ConnectionAuthenticationState.self, forKey: .authenticationState)
        availableModelCount = try container.decodeIfPresent(Int.self, forKey: .availableModelCount)
        availableModelIDs = try container.decodeIfPresent([String].self, forKey: .availableModelIDs) ?? []
        lastValidatedAt = try container.decodeIfPresent(Date.self, forKey: .lastValidatedAt)
        workspaceURL = try container.decodeIfPresent(String.self, forKey: .workspaceURL)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(plan, forKey: .plan)
        try container.encode(credentialHandle, forKey: .credentialHandle)
        try container.encode(keySuffix, forKey: .keySuffix)
        try container.encode(authenticationState, forKey: .authenticationState)
        try container.encodeIfPresent(availableModelCount, forKey: .availableModelCount)
        try container.encode(availableModelIDs, forKey: .availableModelIDs)
        try container.encodeIfPresent(lastValidatedAt, forKey: .lastValidatedAt)
        try container.encodeIfPresent(workspaceURL, forKey: .workspaceURL)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

enum AgentActivityState: String, CaseIterable, Codable, Sendable {
    case offline
    case idle
    case thinking
    case executing
    case reviewing
    case waitingForUser
    case completed
    case interrupted
    case rateLimited
    case failed

    var arbitrationPriority: Int {
        switch self {
        case .waitingForUser: 60
        case .failed, .rateLimited: 50
        case .completed: 40
        case .reviewing, .executing, .thinking: 30
        case .interrupted: 20
        case .idle: 10
        case .offline: 0
        }
    }
}

enum NormalizedAgentEventName: String, Codable, Sendable {
    case sessionStarted = "session.started"
    case promptSubmitted = "prompt.submitted"
    case toolStarted = "tool.started"
    case permissionRequested = "permission.requested"
    case toolFinished = "tool.finished"
    case turnCompleted = "turn.completed"
    case sessionEnded = "session.ended"
    case failed
    case rateLimited = "rate_limited"
}

enum AgentToolCategory: String, Codable, Sendable {
    case reading
    case writing
    case shell
    case network
    case other
}

/// Privacy-preserving event emitted by the bundled bridge. Vendor payload
/// bodies, prompts, tool arguments, commands and full paths never enter here.
struct NormalizedAgentEvent: Codable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let agentID: AgentID
    let surfaceID: AgentSurfaceID
    let connectionID: ConnectionID?
    let sessionID: String?
    let turnID: String?
    let event: NormalizedAgentEventName
    let toolCategory: AgentToolCategory?
    let outcome: String?
    let timestamp: Date

    init(
        schemaVersion: Int = currentSchemaVersion,
        agentID: AgentID,
        surfaceID: AgentSurfaceID,
        connectionID: ConnectionID? = nil,
        sessionID: String? = nil,
        turnID: String? = nil,
        event: NormalizedAgentEventName,
        toolCategory: AgentToolCategory? = nil,
        outcome: String? = nil,
        timestamp: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.agentID = agentID
        self.surfaceID = surfaceID
        self.connectionID = connectionID
        self.sessionID = sessionID
        self.turnID = turnID
        self.event = event
        self.toolCategory = toolCategory
        self.outcome = outcome
        self.timestamp = timestamp
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case agentID
        case surfaceID
        case connectionID
        case sessionID
        case turnID
        case event
        case toolCategory
        case outcome
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        agentID = AgentID(rawValue: try container.decode(String.self, forKey: .agentID))
        surfaceID = try container.decode(AgentSurfaceID.self, forKey: .surfaceID)
        if let rawConnectionID = try container.decodeIfPresent(String.self, forKey: .connectionID),
           let uuid = UUID(uuidString: rawConnectionID) {
            connectionID = ConnectionID(rawValue: uuid)
        } else {
            connectionID = nil
        }
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        turnID = try container.decodeIfPresent(String.self, forKey: .turnID)
        event = try container.decode(NormalizedAgentEventName.self, forKey: .event)
        toolCategory = try container.decodeIfPresent(AgentToolCategory.self, forKey: .toolCategory)
        outcome = try container.decodeIfPresent(String.self, forKey: .outcome)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(agentID.rawValue, forKey: .agentID)
        try container.encode(surfaceID, forKey: .surfaceID)
        try container.encodeIfPresent(connectionID?.rawValue.uuidString.lowercased(), forKey: .connectionID)
        try container.encodeIfPresent(sessionID, forKey: .sessionID)
        try container.encodeIfPresent(turnID, forKey: .turnID)
        try container.encode(event, forKey: .event)
        try container.encodeIfPresent(toolCategory, forKey: .toolCategory)
        try container.encodeIfPresent(outcome, forKey: .outcome)
        try container.encode(timestamp, forKey: .timestamp)
    }
}

enum PetStateMapper {
    static func activity(for event: NormalizedAgentEvent) -> AgentActivityState {
        switch event.event {
        case .sessionStarted:
            .idle
        case .promptSubmitted:
            .thinking
        case .toolStarted:
            .executing
        case .permissionRequested:
            .waitingForUser
        case .toolFinished:
            .reviewing
        case .turnCompleted:
            .completed
        case .sessionEnded:
            .idle
        case .failed:
            .failed
        case .rateLimited:
            .rateLimited
        }
    }
}

struct AgentActivityCandidate: Equatable, Sendable {
    let state: AgentActivityState
    let updatedAt: Date
}

enum AgentActivityArbitrator {
    static func preferred(_ candidates: [AgentActivityCandidate]) -> AgentActivityCandidate? {
        candidates.max { lhs, rhs in
            if lhs.state.arbitrationPriority == rhs.state.arbitrationPriority {
                return lhs.updatedAt < rhs.updatedAt
            }
            return lhs.state.arbitrationPriority < rhs.state.arbitrationPriority
        }
    }
}
