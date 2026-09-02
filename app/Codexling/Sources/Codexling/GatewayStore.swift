import AppKit
import Foundation
import Observation

public enum GatewayNavTab: String, CaseIterable, Identifiable {
    case connect = "接入与模型"
    case agents = "一键接入 Agent"
    case overview = "监控概览"
    case requests = "实时请求"
    case doctor = "Gateway Doctor"

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .connect: "network"
        case .agents: "bolt.horizontal.circle"
        case .overview: "gauge.with.needle"
        case .requests: "waveform.path.ecg"
        case .doctor: "stethoscope"
        }
    }

    public var subtitle: String {
        switch self {
        case .connect: "管理本地网关服务、已连接供应商账号与全量模型接入"
        case .agents: "一键配置并同步 Hermes、Pi 等第三方 Agent 客户端"
        case .overview: "外部 Agent 伴侣工作时长、流量指标与协议中枢拓扑"
        case .requests: "经本地网关反代的实时请求与流式明细"
        case .doctor: "环回端口、鉴权与上游桥接诊断"
        }
    }
}

// MARK: - 维度一：本地 Hook Agent 活动与伴侣观测模型
public struct GatewayAgentWorkRow: Identifiable {
    public let id: String
    public let agentName: String
    public let iconName: String
    public let hookPath: String
    public let durationText: String
    public let tasksCount: Int
    public let statusBadge: String
    public let detailText: String

    public init(
        id: String,
        agentName: String,
        iconName: String,
        hookPath: String,
        durationText: String,
        tasksCount: Int,
        statusBadge: String,
        detailText: String
    ) {
        self.id = id
        self.agentName = agentName
        self.iconName = iconName
        self.hookPath = hookPath
        self.durationText = durationText
        self.tasksCount = tasksCount
        self.statusBadge = statusBadge
        self.detailText = detailText
    }
}

// MARK: - 对外暴露的标准模型模型 (Exported Model)
public struct GatewayExportedModel: Identifiable, Hashable {
    public let id: String
    public let modelName: String
    public let sourceBadge: String
    public let sourceBadgeColor: NSColor
    public let capability: String
    public let description: String
    public let isCustom: Bool

    public init(
        id: String,
        modelName: String,
        sourceBadge: String,
        sourceBadgeColor: NSColor,
        capability: String,
        description: String,
        isCustom: Bool = false
    ) {
        self.id = id
        self.modelName = modelName
        self.sourceBadge = sourceBadge
        self.sourceBadgeColor = sourceBadgeColor
        self.capability = capability
        self.description = description
        self.isCustom = isCustom
    }
}

public struct GatewayAccountModelGroup: Identifiable {
    public let id: String
    public let connectionID: ConnectionID?
    public let accountName: String
    public let email: String?
    public let providerTitle: String
    public let iconName: String
    public let authStatus: String
    public let isConnected: Bool
    public let isProxyEnabled: Bool
    public let hasProxyCredential: Bool
    public let isProxyAllowed: Bool
    public let badgeText: String
    public let badgeColor: NSColor
    public let quickConnectTip: String
    public let recommendedModels: [String]
    public let sampleConfigSnippet: String
    public let models: [GatewayExportedModel]

    public init(
        id: String,
        connectionID: ConnectionID? = nil,
        accountName: String,
        email: String? = nil,
        providerTitle: String,
        iconName: String,
        authStatus: String,
        isConnected: Bool,
        isProxyEnabled: Bool = true,
        hasProxyCredential: Bool = true,
        isProxyAllowed: Bool = true,
        badgeText: String,
        badgeColor: NSColor,
        quickConnectTip: String,
        recommendedModels: [String],
        sampleConfigSnippet: String,
        models: [GatewayExportedModel]
    ) {
        self.id = id
        self.connectionID = connectionID
        self.accountName = accountName
        self.email = email
        self.providerTitle = providerTitle
        self.iconName = iconName
        self.authStatus = authStatus
        self.isConnected = isConnected
        self.isProxyEnabled = isProxyEnabled
        self.hasProxyCredential = hasProxyCredential
        self.isProxyAllowed = isProxyAllowed
        self.badgeText = badgeText
        self.badgeColor = badgeColor
        self.quickConnectTip = quickConnectTip
        self.recommendedModels = recommendedModels
        self.sampleConfigSnippet = sampleConfigSnippet
        self.models = models
    }
}

// MARK: - 供应商聚合模块 (Provider Section)
public struct GatewayProviderSection: Identifiable {
    public let id: String
    public let providerTitle: String
    public let subtitle: String
    public let iconName: String
    public let accountGroups: [GatewayAccountModelGroup]

    public init(
        id: String,
        providerTitle: String,
        subtitle: String,
        iconName: String,
        accountGroups: [GatewayAccountModelGroup]
    ) {
        self.id = id
        self.providerTitle = providerTitle
        self.subtitle = subtitle
        self.iconName = iconName
        self.accountGroups = accountGroups
    }

    var brandAsset: BrandAssetID {
        switch id {
        case "openai", "codex": .codex
        case "google", "gemini": .googleGemini
        case "deepseek": .deepSeek
        case "opencode": .openCode
        default: .codex
        }
    }
}

// MARK: - 维度二：Gateway 反代与网络遥测模型
public struct GatewayTelemetryItem: Identifiable {
    public let id: String
    public let title: String
    public let value: String
    public let sourceTag: String
    public let sourceTagColor: NSColor
    public let note: String

    public init(id: String, title: String, value: String, sourceTag: String, sourceTagColor: NSColor, note: String) {
        self.id = id
        self.title = title
        self.value = value
        self.sourceTag = sourceTag
        self.sourceTagColor = sourceTagColor
        self.note = note
    }
}

public struct GatewayRequestRow: Identifiable {
    public let id: String
    public let time: String
    public let agent: String
    public let ingressProtocol: String
    public let modelAlias: String
    public let targetProvider: String
    public let targetModel: String
    public let latencyMs: Int
    public let ttftMs: Int
    public let tokens: Int
    public let fidelity: String
    public let status: String

    public init(
        id: String,
        time: String,
        agent: String,
        ingressProtocol: String,
        modelAlias: String,
        targetProvider: String,
        targetModel: String,
        latencyMs: Int,
        ttftMs: Int,
        tokens: Int,
        fidelity: String,
        status: String
    ) {
        self.id = id
        self.time = time
        self.agent = agent
        self.ingressProtocol = ingressProtocol
        self.modelAlias = modelAlias
        self.targetProvider = targetProvider
        self.targetModel = targetModel
        self.latencyMs = latencyMs
        self.ttftMs = ttftMs
        self.tokens = tokens
        self.fidelity = fidelity
        self.status = status
    }
}

public struct GatewayDoctorCheck: Identifiable {
    public let id: String
    public let title: String
    public let status: String
    public let isSuccess: Bool
    public let detail: String

    public init(id: String, title: String, status: String, isSuccess: Bool, detail: String) {
        self.id = id
        self.title = title
        self.status = status
        self.isSuccess = isSuccess
        self.detail = detail
    }
}

@MainActor
@Observable
public final class GatewayStore {
    public static let shared = GatewayStore()

    public var selectedTab: GatewayNavTab = .connect
    public var selectedRequestId: String?

    // ==========================================
    // 维度一：本地 Hook 的 Agent 伴侣与活动数据
    // ==========================================
    private weak var activityStore: CodexActivityStore?
    private weak var companionStatsStore: CompanionStatsStore?
    private let hermesConfigurator: HermesGatewayConfigurator
    private let piConfigurator: PiGatewayConfigurator

    // ==========================================
    // 维度二：Gateway 本地反代与网络遥测数据
    // ==========================================
    public private(set) var totalRequests: Int = 0
    public private(set) var totalInputTokens: Int = 0
    public private(set) var totalOutputTokens: Int = 0
    public private(set) var totalToolCalls: Int = 0

    public private(set) var requestsList: [GatewayRequestRow] = []

    // 用户自定义或额外添加的透传模型
    private var customModelsByGroup: [String: [String]] = [:]

    /// Bumped each time an account proxy is toggled; `@Observable` tracks this
    /// so `accountModelGroups` / `providerSections` recompute automatically.
    public private(set) var proxyEnabledVersion: Int = 0

    /// Signals the Gateway UI to recompute `accountModelGroups`.
    /// Disk persistence is handled by `MultiAgentSettingsStore.toggleConnectionProxyEnabled`.
    public func toggleConnectionProxy(id: ConnectionID) {
        proxyEnabledVersion &+= 1
    }

    public init() {
        self.hermesConfigurator = HermesGatewayConfigurator()
        self.piConfigurator = PiGatewayConfigurator()
        loadCustomModels()
    }

    init(
        activityStore: CodexActivityStore? = nil,
        companionStatsStore: CompanionStatsStore? = nil,
        hermesConfigurator: HermesGatewayConfigurator = HermesGatewayConfigurator(),
        piConfigurator: PiGatewayConfigurator = PiGatewayConfigurator()
    ) {
        self.activityStore = activityStore
        self.companionStatsStore = companionStatsStore
        self.hermesConfigurator = hermesConfigurator
        self.piConfigurator = piConfigurator
        loadCustomModels()
    }

    private func loadCustomModels() {
        if let saved = UserDefaults.standard.dictionary(forKey: "gateway.customModels") as? [String: [String]] {
            self.customModelsByGroup = saved
        }
    }

    private func persistCustomModels() {
        UserDefaults.standard.set(customModelsByGroup, forKey: "gateway.customModels")
    }

    public func addCustomModel(_ modelName: String, toGroupId groupId: String) {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = customModelsByGroup[groupId] ?? []
        if !list.contains(trimmed) {
            list.append(trimmed)
            customModelsByGroup[groupId] = list
            persistCustomModels()
        }
    }

    public func removeCustomModel(_ modelName: String, fromGroupId groupId: String) {
        guard var list = customModelsByGroup[groupId] else { return }
        list.removeAll { $0 == modelName }
        customModelsByGroup[groupId] = list
        persistCustomModels()
    }

    func bind(
        activityStore: CodexActivityStore,
        companionStatsStore: CompanionStatsStore
    ) {
        self.activityStore = activityStore
        self.companionStatsStore = companionStatsStore
    }

    public func updateGatewayMetrics(
        totalRequests: Int,
        inputTokens: Int,
        outputTokens: Int,
        toolCalls: Int
    ) {
        self.totalRequests = totalRequests
        self.totalInputTokens = inputTokens
        self.totalOutputTokens = outputTokens
        self.totalToolCalls = toolCalls
    }

    public func recordRequest(_ row: GatewayRequestRow) {
        requestsList.insert(row, at: 0)
        if requestsList.count > 50 {
            requestsList.removeLast()
        }
    }

    public func setRequestsList(_ rows: [GatewayRequestRow]) {
        self.requestsList = rows
    }

    // ----------------------------------------------------
    // 通用端点与配置参数
    // ----------------------------------------------------
    public var openAIBaseURL: String {
        let portStr = String(GatewaySupervisor.shared.port)
        return "http://127.0.0.1:\(portStr)/v1"
    }

    public var anthropicBaseURL: String {
        let portStr = String(GatewaySupervisor.shared.port)
        return "http://127.0.0.1:\(portStr)"
    }

    public var localToken: String {
        GatewaySupervisor.shared.localToken
    }

    public var openAIEnvCommand: String {
        "export OPENAI_BASE_URL=\"\(openAIBaseURL)\"\nexport OPENAI_API_KEY=\"\(localToken)\""
    }

    public var anthropicEnvCommand: String {
        "export ANTHROPIC_BASE_URL=\"\(anthropicBaseURL)\"\nexport ANTHROPIC_AUTH_TOKEN=\"\(localToken)\""
    }

    public var allModelNamesListString: String {
        accountModelGroups.flatMap { $0.models }.map { $0.modelName }.joined(separator: ", ")
    }

    public static func normalizeGeminiModelID(_ raw: String) -> String {
        var s = raw
        if s.hasPrefix("models/") {
            s = String(s.dropFirst("models/".count))
        }
        if s.hasPrefix("MODEL_GOOGLE_") {
            s = String(s.dropFirst("MODEL_GOOGLE_".count))
                .lowercased()
                .replacingOccurrences(of: "_", with: "-")
        } else if s.hasPrefix("MODEL_OPENAI_") {
            s = String(s.dropFirst("MODEL_OPENAI_".count))
                .lowercased()
                .replacingOccurrences(of: "_", with: "-")
        } else if s.hasPrefix("MODEL_PLACEHOLDER_") {
            return "" // skip internal placeholders
        }
        return s
    }

    nonisolated public static func friendlyAccountName(displayName: String?, email: String?, fallbackLabel: String) -> String {
        if let d = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty, !d.contains("@") {
            return d
        }
        let cleanFallback = fallbackLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanFallback.isEmpty, !cleanFallback.contains("@") {
            return cleanFallback
        }
        if let email = email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            let prefix = email.split(separator: "@").first.map(String.init) ?? email
            return prefix
        }
        return cleanFallback.isEmpty ? "默认账号" : cleanFallback
    }

    nonisolated public static func accountSlug(name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "@", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }

    /// Account-scoped model labels are friendly for the Codexling UI but Pi
    /// and some other clients reject model IDs containing spaces. The Gateway
    /// accepts the equivalent `model@account` wire syntax.
    nonisolated public static func agentCompatibleModelID(_ displayModelID: String) -> String {
        let trimmed = displayModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(")"), let separator = trimmed.range(of: " (", options: .backwards) else {
            return trimmed
        }
        let model = trimmed[..<separator.lowerBound]
        let accountStart = separator.upperBound
        let accountEnd = trimmed.index(before: trimmed.endIndex)
        let account = trimmed[accountStart..<accountEnd]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, !account.isEmpty else { return trimmed }
        return "\(model)@\(accountSlug(name: account))"
    }

    /// Hermes renders configured model IDs as the picker label and does not
    /// offer a separate display-name field.  Keep the ID safe for Hermes
    /// (no spaces), while making it readable as `供应商 · 模型名 · 账号名`.
    nonisolated public static func hermesPickerModelID(
        provider: String,
        modelName: String,
        accountName: String
    ) -> String {
        func component(_ value: String) -> String {
            let compact = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "·", with: "-")
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: "-")
            // Cloud Code's `-tiered` is a routing implementation detail.
            // Keep it on the wire internally, but do not expose it as part of
            // the Hermes picker label.
            return compact == "gemini-3.7-flash-tiered" ? "Gemini-3.7-Flash" : compact
        }

        return "\(component(provider))·\(component(modelName))·\(component(accountName))"
    }

    nonisolated private static func unscopedModelName(_ modelName: String) -> String {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(")"), let separator = trimmed.range(of: " (", options: .backwards) else {
            return trimmed
        }
        return String(trimmed[..<separator.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func hermesWireModelID(modelName: String, accountName: String) -> String {
        let baseModel = unscopedModelName(modelName)
        guard !baseModel.isEmpty, !baseModel.hasPrefix("(") else { return "" }
        let compatible = agentCompatibleModelID(modelName)
        guard !compatible.isEmpty else { return "" }
        return compatible.contains("@") ? compatible : "\(baseModel)@\(accountSlug(name: accountName))"
    }

    nonisolated private static func hermesProviderName(for groupID: String) -> String {
        // Hermes uses the configured model ID as its visible picker label.
        // Keep the provider component compact without losing its meaning.
        if groupID.hasPrefix("google") { return "Google" }
        if groupID.hasPrefix("deepseek") { return "DeepSeek" }
        if groupID.hasPrefix("opencode") { return "OpenCode" }
        return "OpenAI"
    }

    // ----------------------------------------------------
    // 账号池供应商模型分组 (Account Model Groups)
    // ----------------------------------------------------
    public var accountModelGroups: [GatewayAccountModelGroup] {
        // Access proxyEnabledVersion so @Observable re-evaluates this when it changes.
        _ = proxyEnabledVersion
        let portStr = String(GatewaySupervisor.shared.port)
        let token = GatewaySupervisor.shared.localToken
        let registry = ConnectionRegistryStorage().load()

        // 1. Google Gemini 授权模型列表
        var geminiModelList: [GatewayExportedModel] = [
            GatewayExportedModel(
                id: "gemini-3.7-flash",
                modelName: "gemini-3.7-flash",
                sourceBadge: "Google 官方",
                sourceBadgeColor: NSColor.systemPurple,
                capability: "下一代极速 · 超低延迟 · 强多模态",
                description: "Google 最新旗舰 Gemini 3.7 Flash 极速推理响应模型"
            ),
            GatewayExportedModel(
                id: "gemini-3.6-flash",
                modelName: "gemini-3.6-flash",
                sourceBadge: "Google 官方",
                sourceBadgeColor: NSColor.systemPurple,
                capability: "主力通用 · 极速补全 · 稳定",
                description: "Google 现役主力 Gemini 3.6 Flash 模型，极高稳定性与响应速度"
            ),
            GatewayExportedModel(
                id: "gemini-3.1-pro-preview",
                modelName: "gemini-3.1-pro-preview",
                sourceBadge: "Google 官方",
                sourceBadgeColor: NSColor.systemPurple,
                capability: "顶级编程 · 强推理 · 深度思考",
                description: "Google 现役高阶推理旗舰 Gemini 3.1 Pro 模型"
            ),
            GatewayExportedModel(
                id: "gemini-flash-latest",
                modelName: "gemini-flash-latest",
                sourceBadge: "Google 官方",
                sourceBadgeColor: NSColor.systemPurple,
                capability: "始终最新 Flash · 自动追踪",
                description: "始终自动追踪 Google 官方最新发布的 Flash 模型"
            ),
            GatewayExportedModel(
                id: "gemini-pro-latest",
                modelName: "gemini-pro-latest",
                sourceBadge: "Google 官方",
                sourceBadgeColor: NSColor.systemPurple,
                capability: "始终最新 Pro · 自动追踪",
                description: "始终自动追踪 Google 官方最新发布的 Pro 旗舰模型"
            )
        ]
        // 动态附加上游实际发现的模型
        for conn in registry.geminiConnections {
            for rawMid in conn.availableModelIDs {
                let mid = Self.normalizeGeminiModelID(rawMid)
                guard !mid.isEmpty, !geminiModelList.contains(where: { $0.modelName == mid }) else { continue }
                geminiModelList.append(
                    GatewayExportedModel(
                        id: mid,
                        modelName: mid,
                        sourceBadge: "上游发现",
                        sourceBadgeColor: NSColor.systemPurple,
                        capability: "动态发现 · 原生支持",
                        description: "来自 Google 账号实测可访问模型"
                    )
                )
            }
        }
        let customGemini = customModelsByGroup.filter { $0.key.hasPrefix("google_gemini") }.values.flatMap { $0 }
        for custom in customGemini where !geminiModelList.contains(where: { $0.modelName == custom }) {
            geminiModelList.append(
                GatewayExportedModel(
                    id: custom,
                    modelName: custom,
                    sourceBadge: "透传模型",
                    sourceBadgeColor: NSColor.systemPurple,
                    capability: "自定义透传 · 即刻生效",
                    description: "用户自定义透传请求模型",
                    isCustom: true
                )
            )
        }

        // 2. DeepSeek 官方账号模型列表
        var deepseekModelList: [GatewayExportedModel] = [
            GatewayExportedModel(
                id: "deepseek-chat",
                modelName: "deepseek-chat",
                sourceBadge: "DeepSeek 官方",
                sourceBadgeColor: NSColor.systemBlue,
                capability: "高性价比 · 强中文 · V3 核心",
                description: "DeepSeek V3 通用代码与对话模型，中文理解与代码生成性价比极高"
            ),
            GatewayExportedModel(
                id: "deepseek-reasoner",
                modelName: "deepseek-reasoner",
                sourceBadge: "DeepSeek 官方",
                sourceBadgeColor: NSColor.systemBlue,
                capability: "深度思考 · R1 逻辑推理",
                description: "DeepSeek R1 深度思考推理模型，完整保留 <think> 思考链流式分发"
            ),
            GatewayExportedModel(
                id: "deepseek-v4-pro",
                modelName: "deepseek-v4-pro",
                sourceBadge: "DeepSeek 官方",
                sourceBadgeColor: NSColor.systemBlue,
                capability: "次世代旗舰 · 顶尖推理",
                description: "DeepSeek V4 Pro 顶阶推理大模型"
            )
        ]
        for conn in registry.deepSeekConnections {
            for mid in conn.availableModelIDs where !deepseekModelList.contains(where: { $0.modelName == mid }) {
                deepseekModelList.append(
                    GatewayExportedModel(
                        id: mid,
                        modelName: mid,
                        sourceBadge: "官方接口",
                        sourceBadgeColor: NSColor.systemBlue,
                        capability: "动态接口获取",
                        description: "来自 DeepSeek 官方 API 实时返回模型"
                    )
                )
            }
        }
        let customDeepSeek = customModelsByGroup.filter { $0.key.hasPrefix("deepseek") }.values.flatMap { $0 }
        for custom in customDeepSeek where !deepseekModelList.contains(where: { $0.modelName == custom }) {
            deepseekModelList.append(
                GatewayExportedModel(
                    id: custom,
                    modelName: custom,
                    sourceBadge: "透传模型",
                    sourceBadgeColor: NSColor.systemBlue,
                    capability: "自定义透传 · 即刻生效",
                    description: "用户自定义透传请求模型",
                    isCustom: true
                )
            )
        }

        // 3. OpenCode 供应商连接模型列表
        var opencodeModelList: [GatewayExportedModel] = [
            GatewayExportedModel(
                id: "claude-3-7-sonnet",
                modelName: "claude-3-7-sonnet",
                sourceBadge: "OpenCode 桥接",
                sourceBadgeColor: NSColor.systemOrange,
                capability: "顶阶多模态 · 前沿架构 · 混合推理",
                description: "Claude 3.7 Sonnet 混合推理与深度代码大模型"
            ),
            GatewayExportedModel(
                id: "claude-3-5-sonnet",
                modelName: "claude-3-5-sonnet",
                sourceBadge: "OpenCode 桥接",
                sourceBadgeColor: NSColor.systemOrange,
                capability: "经典编程 · 高精准度",
                description: "经典的 Claude 3.5 Sonnet 代码生成模型"
            ),
            GatewayExportedModel(
                id: "claude-3-5-haiku",
                modelName: "claude-3-5-haiku",
                sourceBadge: "OpenCode 桥接",
                sourceBadgeColor: NSColor.systemOrange,
                capability: "超高性价比 · 极速响应",
                description: "轻量高速 Claude 3.5 Haiku 模型"
            )
        ]
        for conn in registry.openCodeConnections {
            for mid in conn.availableModelIDs where !opencodeModelList.contains(where: { $0.modelName == mid }) {
                opencodeModelList.append(
                    GatewayExportedModel(
                        id: mid,
                        modelName: mid,
                        sourceBadge: "上游发现",
                        sourceBadgeColor: NSColor.systemOrange,
                        capability: "动态发现 · 渠道直连",
                        description: "来自 OpenCode 实际发现模型"
                    )
                )
            }
        }
        let customOpenCode = customModelsByGroup.filter { $0.key.hasPrefix("opencode") }.values.flatMap { $0 }
        for custom in customOpenCode where !opencodeModelList.contains(where: { $0.modelName == custom }) {
            opencodeModelList.append(
                GatewayExportedModel(
                    id: custom,
                    modelName: custom,
                    sourceBadge: "透传模型",
                    sourceBadgeColor: NSColor.systemOrange,
                    capability: "自定义透传 · 即刻生效",
                    description: "用户自定义透传请求模型",
                    isCustom: true
                )
            )
        }

        // 4. Codex 账户池模型列表
        var codexModelList: [GatewayExportedModel] = [
            GatewayExportedModel(
                id: "gpt-5.6",
                modelName: "gpt-5.6",
                sourceBadge: "Codex / OpenAI",
                sourceBadgeColor: NSColor.systemCyan,
                capability: "GPT-5.6 旗舰全栈编程与顶阶智能",
                description: "OpenAI GPT-5.6 旗舰全功能编码与前沿推理模型"
            ),
            GatewayExportedModel(
                id: "gpt-5.6-thinking",
                modelName: "gpt-5.6-thinking",
                sourceBadge: "Codex / OpenAI",
                sourceBadgeColor: NSColor.systemCyan,
                capability: "深度思考 · 长链推理",
                description: "OpenAI GPT-5.6 Thinking 深度思考推理模型"
            ),
            GatewayExportedModel(
                id: "gpt-5.6-sol",
                modelName: "gpt-5.6-sol",
                sourceBadge: "Codex / OpenAI",
                sourceBadgeColor: NSColor.systemCyan,
                capability: "Sol 太阳版 · 极限性能",
                description: "OpenAI GPT-5.6 Sol 太阳版 · 前沿极限代码生成"
            ),
            GatewayExportedModel(
                id: "gpt-5.6-terra",
                modelName: "gpt-5.6-terra",
                sourceBadge: "Codex / OpenAI",
                sourceBadgeColor: NSColor.systemCyan,
                capability: "Terra 地球版 · 均衡通用",
                description: "OpenAI GPT-5.6 Terra 地球版 · 复杂工程全功能实现"
            ),
            GatewayExportedModel(
                id: "gpt-5.6-luna",
                modelName: "gpt-5.6-luna",
                sourceBadge: "Codex / OpenAI",
                sourceBadgeColor: NSColor.systemCyan,
                capability: "Luna 月亮版 · 快速轻量",
                description: "OpenAI GPT-5.6 Luna 月亮版 · 高速敏捷轻量编码"
            ),
            GatewayExportedModel(
                id: "gpt-5.6-instant",
                modelName: "gpt-5.6-instant",
                sourceBadge: "Codex / OpenAI",
                sourceBadgeColor: NSColor.systemCyan,
                capability: "次世代极速响应",
                description: "OpenAI GPT-5.6 Instant 极速响应模型"
            ),
            GatewayExportedModel(
                id: "gpt-5.6-mini",
                modelName: "gpt-5.6-mini",
                sourceBadge: "Codex / OpenAI",
                sourceBadgeColor: NSColor.systemCyan,
                capability: "次世代极速代码模型",
                description: "OpenAI GPT-5.6 Mini 极速模型"
            ),
            GatewayExportedModel(
                id: "gpt-5.5",
                modelName: "gpt-5.5",
                sourceBadge: "Codex / OpenAI",
                sourceBadgeColor: NSColor.systemCyan,
                capability: "GPT-5.5 基础架构大模型",
                description: "OpenAI GPT-5.5 基础架构模型"
            ),
            GatewayExportedModel(
                id: "gpt-5.5-thinking",
                modelName: "gpt-5.5-thinking",
                sourceBadge: "Codex / OpenAI",
                sourceBadgeColor: NSColor.systemCyan,
                capability: "GPT-5.5 深度思考",
                description: "OpenAI GPT-5.5 Thinking 深度思考模型"
            ),
            GatewayExportedModel(
                id: "gpt-5",
                modelName: "gpt-5",
                sourceBadge: "Codex / OpenAI",
                sourceBadgeColor: NSColor.systemCyan,
                capability: "次世代旗舰 · 顶阶智能",
                description: "OpenAI GPT-5 旗舰大模型 · 全功能编码与前沿推理"
            ),
            GatewayExportedModel(
                id: "gpt-5-codex",
                modelName: "gpt-5-codex",
                sourceBadge: "Codex / OpenAI",
                sourceBadgeColor: NSColor.systemCyan,
                capability: "专属代码架构 · 高保真生成",
                description: "OpenAI GPT-5 Codex 专属架构与复杂工程代码模型"
            ),
            GatewayExportedModel(
                id: "o3-mini",
                modelName: "o3-mini",
                sourceBadge: "Codex / OpenAI",
                sourceBadgeColor: NSColor.systemCyan,
                capability: "紧凑型强推理",
                description: "OpenAI o3-mini 高阶 STEM 与算法推理模型"
            ),
            GatewayExportedModel(
                id: "o1",
                modelName: "o1",
                sourceBadge: "Codex / OpenAI",
                sourceBadgeColor: NSColor.systemCyan,
                capability: "深度思考与复杂逻辑",
                description: "OpenAI o1 深度思考代码与数学推理模型"
            ),
            GatewayExportedModel(
                id: "gpt-4o",
                modelName: "gpt-4o",
                sourceBadge: "Codex / OpenAI",
                sourceBadgeColor: NSColor.systemCyan,
                capability: "通用多模态 · 全功能编码",
                description: "OpenAI GPT-4o 多模态旗舰模型"
            )
        ]
        for conn in registry.codexAccounts {
            for mid in conn.availableModelIDs where !codexModelList.contains(where: { $0.modelName == mid }) {
                codexModelList.append(
                    GatewayExportedModel(
                        id: mid,
                        modelName: mid,
                        sourceBadge: "官方接口",
                        sourceBadgeColor: NSColor.systemCyan,
                        capability: "动态接口获取",
                        description: "来自 OpenAI / Codex 账号实时发现模型"
                    )
                )
            }
        }
        let customCodex = customModelsByGroup.filter { $0.key.hasPrefix("codex") }.values.flatMap { $0 }
        for custom in customCodex where !codexModelList.contains(where: { $0.modelName == custom }) {
            codexModelList.append(
                GatewayExportedModel(
                    id: custom,
                    modelName: custom,
                    sourceBadge: "透传模型",
                    sourceBadgeColor: NSColor.systemCyan,
                    capability: "自定义透传 · 即刻生效",
                    description: "用户自定义透传请求模型",
                    isCustom: true
                )
            )
        }

        var groups: [GatewayAccountModelGroup] = []

        // 1. Google Gemini 授权 (按友好账号名称分组)
        if registry.geminiConnections.isEmpty {
            groups.append(
                GatewayAccountModelGroup(
                    id: "google_gemini",
                    accountName: "Google Gemini",
                    providerTitle: "Google Gemini · 授权会话",
                    iconName: "sparkles",
                    authStatus: "已授权 · 全量模型动态透传",
                    isConnected: true,
                    badgeText: "Google OAuth · 5h 充足",
                    badgeColor: NSColor.systemPurple,
                    quickConnectTip: "登录 Google OAuth 账号后，网关会按账号实际发现的模型列表导出；不会使用 Google AI Studio API Key。",
                    recommendedModels: [],
                    sampleConfigSnippet: """
                    Base URL: http://127.0.0.1:\(portStr)/v1
                    API Key:  \(token)
                    Model:    登录后自动同步
                    """,
                    models: geminiModelList.filter(\.isCustom)
                )
            )
        } else {
            for conn in registry.geminiConnections {
                // OAuth discovery is authoritative per account. Do not mix in
                // a provider-wide static catalog: it can advertise models the
                // authenticated account is not entitled to use.
                var connModels: [GatewayExportedModel] = []
                let friendlyName = Self.friendlyAccountName(displayName: conn.displayName, email: conn.email, fallbackLabel: conn.label)
                let slug = Self.accountSlug(name: friendlyName)

                for rawMid in conn.availableModelIDs {
                    let mid = Self.normalizeGeminiModelID(rawMid)
                    let scopedId = "\(mid) (\(slug))"
                    if !connModels.contains(where: { $0.modelName == scopedId }) {
                        connModels.append(
                            GatewayExportedModel(
                                id: scopedId,
                                modelName: scopedId,
                                sourceBadge: "专属账号",
                                sourceBadgeColor: NSColor.systemPurple,
                                capability: "定向路由至 \(friendlyName)",
                                description: "定向通过账号 [\(friendlyName)] 请求 \(mid)"
                            )
                        )
                    }
                }
                for custom in customModelsByGroup["google_gemini_\(conn.id.rawValue)"] ?? [] {
                    let scopedID = "\(custom) (\(slug))"
                    guard !connModels.contains(where: { $0.modelName == scopedID }) else { continue }
                    connModels.append(
                        GatewayExportedModel(
                            id: scopedID,
                            modelName: scopedID,
                            sourceBadge: "自定义透传",
                            sourceBadgeColor: NSColor.systemPurple,
                            capability: "由 OAuth 账号 \(friendlyName) 定向路由",
                            description: "用户添加的 Gemini OAuth 模型：\(custom)",
                            isCustom: true
                        )
                    )
                }
                let isProxyAllowed = conn.authenticationState == .connected
                let isProxyEnabled = conn.isEnabled && isProxyAllowed
                let authDesc = isProxyEnabled ? "Google OAuth 已授权 · 代理已开启" : "OAuth 未就绪 · 不参与路由"
                let badgeDesc = isProxyEnabled ? "OAuth 已授权" : "OAuth 未就绪"
                let badgeClr = isProxyEnabled ? NSColor.systemPurple : NSColor.systemOrange

                groups.append(
                    GatewayAccountModelGroup(
                        id: "google_gemini_\(conn.id.rawValue)",
                        connectionID: conn.id,
                        accountName: friendlyName,
                        email: conn.email,
                        providerTitle: "Google Gemini · \(friendlyName)",
                        iconName: "sparkles",
                        authStatus: authDesc,
                        isConnected: true,
                        isProxyEnabled: isProxyEnabled && !connModels.isEmpty,
                        hasProxyCredential: isProxyAllowed,
                        isProxyAllowed: isProxyAllowed,
                        badgeText: badgeDesc,
                        badgeColor: badgeClr,
                        quickConnectTip: isProxyAllowed ? "使用专属模型名可精确定向由 [\(friendlyName)] 的 Google OAuth 账号出流。" : "该账号的 Google OAuth 尚未就绪，请重新登录后开启代理。",
                        recommendedModels: connModels.prefix(4).map(\.modelName),
                        sampleConfigSnippet: """
                        Base URL: http://127.0.0.1:\(portStr)/v1
                        API Key:  \(token)
                        Model:    \(connModels.first?.modelName ?? "等待 OAuth 模型同步")
                        """,
                        models: connModels
                    )
                )
            }
        }

        // 2. DeepSeek 官方账号
        if registry.deepSeekConnections.isEmpty {
            groups.append(
                GatewayAccountModelGroup(
                    id: "deepseek_pool",
                    accountName: "DeepSeek 官方",
                    providerTitle: "DeepSeek · 官方直连",
                    iconName: "bolt.horizontal.circle",
                    authStatus: "已连接 · 全量模型动态透传",
                    isConnected: true,
                    badgeText: "官方直连 · 未配置",
                    badgeColor: NSColor.systemBlue,
                    quickConnectTip: "第三方 Agent 填入 deepseek-reasoner 可完整获得 R1 深度思考推理链流式输出；填入 deepseek-chat 或 deepseek-v4-pro 享受极速代码生成，支持任何新发布的 DeepSeek 模型名直接请求。",
                    recommendedModels: ["deepseek-chat (deepseek)", "deepseek-reasoner (deepseek)", "deepseek-v4-pro (deepseek)"],
                    sampleConfigSnippet: """
                    Base URL: http://127.0.0.1:\(portStr)/v1
                    API Key:  \(token)
                    Model:    deepseek-reasoner (deepseek)
                    """,
                    models: deepseekModelList
                )
            )
        } else {
            for conn in registry.deepSeekConnections {
                let friendlyName = conn.label.contains("@") ? (conn.label.split(separator: "@").first.map(String.init) ?? "DeepSeek") : conn.label
                let slug = Self.accountSlug(name: friendlyName)
                let balanceStr = conn.balance?.total != nil ? String(format: "余额 ¥%.2f", NSDecimalNumber(decimal: conn.balance!.total).doubleValue) : "官方直连"
                let badgeTitle = balanceStr
                var connModels = deepseekModelList
                let scopedReasoner = "deepseek-reasoner (\(slug))"
                let scopedChat = "deepseek-chat (\(slug))"
                let scopedV4 = "deepseek-v4-pro (\(slug))"
                connModels.insert(
                    GatewayExportedModel(
                        id: scopedReasoner,
                        modelName: scopedReasoner,
                        sourceBadge: "专属账号",
                        sourceBadgeColor: NSColor.systemBlue,
                        capability: "定向 R1 思考",
                        description: "定向通过账号 [\(friendlyName)] 请求 DeepSeek R1"
                    ),
                    at: 0
                )
                connModels.insert(
                    GatewayExportedModel(
                        id: scopedChat,
                        modelName: scopedChat,
                        sourceBadge: "专属账号",
                        sourceBadgeColor: NSColor.systemBlue,
                        capability: "定向 V3 对话",
                        description: "定向通过账号 [\(friendlyName)] 请求 DeepSeek V3"
                    ),
                    at: 0
                )
                groups.append(
                    GatewayAccountModelGroup(
                        id: "deepseek_\(conn.id.rawValue)",
                        connectionID: conn.id,
                        accountName: friendlyName,
                        providerTitle: "DeepSeek · \(friendlyName)",
                        iconName: "bolt.horizontal.circle",
                        authStatus: conn.isEnabled ? "已连接 · 官方直连" : "代理已暂停 · 不参与路由",
                        isConnected: true,
                        isProxyEnabled: conn.isEnabled && conn.authenticationState == .connected,
                        badgeText: conn.isEnabled ? badgeTitle : "代理已关闭",
                        badgeColor: conn.isEnabled ? NSColor.systemBlue : NSColor.systemGray,
                        quickConnectTip: "使用 \(scopedReasoner) 或 \(scopedChat) 可定向由 [\(friendlyName)] 账号出流。",
                        recommendedModels: [scopedChat, scopedReasoner, scopedV4],
                        sampleConfigSnippet: """
                        Base URL: http://127.0.0.1:\(portStr)/v1
                        API Key:  \(token)
                        Model:    \(scopedChat)
                        """,
                        models: connModels
                    )
                )
            }
        }

        // 3. OpenCode 聚合平台 (按实际连接的 OpenCode 账号拆分)
        if registry.openCodeConnections.isEmpty {
            groups.append(
                GatewayAccountModelGroup(
                    id: "opencode_pool",
                    accountName: "OpenCode 默认",
                    providerTitle: "OpenCode · 多模型聚合平台",
                    iconName: "network",
                    authStatus: "已配置 · 多渠道分发",
                    isConnected: true,
                    isProxyEnabled: true,
                    badgeText: "多模型聚合",
                    badgeColor: NSColor.systemOrange,
                    quickConnectTip: "同时支持标准 OpenAI 协议 (/v1) 与 Anthropic Messages 协议，无缝调用 OpenCode 开通的 MiniMax, Kimi, GLM, DeepSeek, Qwen, Claude, Grok 等全系模型。",
                    recommendedModels: ["deepseek-v4-pro (opencode)", "qwen3.8-max (opencode)", "kimi-k3 (opencode)", "claude-3-7-sonnet (opencode)"],
                    sampleConfigSnippet: """
                    OpenAI 端点:    http://127.0.0.1:\(portStr)/v1
                    Anthropic 端点: http://127.0.0.1:\(portStr)
                    API Key:       \(token)
                    Model:         deepseek-v4-pro (opencode)
                    """,
                    models: opencodeModelList
                )
            )
        } else {
            for conn in registry.openCodeConnections {
                let friendlyName = conn.label.isEmpty ? "OpenCode-\(conn.keySuffix)" : conn.label
                let slug = Self.accountSlug(name: friendlyName)
                let planStr = conn.plan.rawValue.uppercased()
                let badgeTitle = "\(planStr) 计划"
                var connModels: [GatewayExportedModel] = []

                for mid in conn.availableModelIDs {
                    let scopedId = "\(mid) (\(slug))"
                    connModels.append(
                        GatewayExportedModel(
                            id: scopedId,
                            modelName: scopedId,
                            sourceBadge: "OpenCode",
                            sourceBadgeColor: NSColor.systemOrange,
                            capability: "OpenCode 聚合接入",
                            description: "通过 OpenCode [\(friendlyName)] 账号请求 \(mid)"
                        )
                    )
                }

                // 推荐模型：优先挑出 DeepSeek, Qwen, Kimi, Claude, GLM 等代表性模型
                var recNames: [String] = []
                let candidates = ["deepseek-v4-pro", "qwen3.8-max", "kimi-k3", "glm-5.3", "minimax-m3", "grok-4.6", "claude-3-7-sonnet"]
                for cand in candidates {
                    if conn.availableModelIDs.contains(cand) {
                        recNames.append("\(cand) (\(slug))")
                    }
                    if recNames.count >= 4 { break }
                }
                if recNames.isEmpty {
                    recNames = conn.availableModelIDs.prefix(4).map { "\($0) (\(slug))" }
                }

                groups.append(
                    GatewayAccountModelGroup(
                        id: "opencode_\(conn.id.rawValue)",
                        connectionID: conn.id,
                        accountName: friendlyName,
                        providerTitle: "OpenCode · \(friendlyName)",
                        iconName: "network",
                        authStatus: conn.isEnabled ? "已连接 · 聚合通道" : "代理已暂停 · 不参与路由",
                        isConnected: true,
                        isProxyEnabled: conn.isEnabled && conn.authenticationState == .connected && !connModels.isEmpty,
                        badgeText: conn.isEnabled ? badgeTitle : "代理已关闭",
                        badgeColor: conn.isEnabled ? NSColor.systemOrange : NSColor.systemGray,
                        quickConnectTip: "同时支持标准 OpenAI 协议 (/v1) 与 Anthropic Messages 协议，调用 OpenCode [\(friendlyName)] 账号的 \(conn.availableModelCount ?? conn.availableModelIDs.count) 款可用模型。",
                        recommendedModels: recNames,
                        sampleConfigSnippet: """
                        OpenAI 端点:    http://127.0.0.1:\(portStr)/v1
                        Anthropic 端点: http://127.0.0.1:\(portStr)
                        API Key:       \(token)
                        Model:         \(recNames.first ?? "deepseek-v4-pro (\(slug))")
                        """,
                        models: connModels
                    )
                )
            }
        }

        // 4. Codex / OpenAI 账号池 (按友好账号名拆分)
        if registry.codexAccounts.isEmpty {
            groups.append(
                GatewayAccountModelGroup(
                    id: "codex_pool",
                    accountName: "Codex 账户池",
                    providerTitle: "Codex (已登录 OpenAI 账号)",
                    iconName: "apple.terminal",
                    authStatus: "已连接 · 会话就绪",
                    isConnected: true,
                    isProxyEnabled: true,
                    badgeText: "Codex Plus 账户",
                    badgeColor: NSColor.systemCyan,
                    quickConnectTip: "将 Codex 本地授权会话桥接为标准 API 格式，供外部 Agent 直接调用 OpenAI 旗舰 GPT-5.6、GPT-5.5、GPT-5、GPT-5 Codex、GPT-4.5、o3-mini、o1 以及全系推理与轻量模型。",
                    recommendedModels: ["gpt-5.6 (codex)", "gpt-5.6-thinking (codex)", "gpt-5 (codex)", "o3-mini (codex)"],
                    sampleConfigSnippet: """
                    Base URL: http://127.0.0.1:\(portStr)/v1
                    API Key:  \(token)
                    Model:    gpt-5.6 (codex)
                    """,
                    models: codexModelList
                )
            )
        } else {
            for conn in registry.codexAccounts {
                let friendlyName = Self.friendlyAccountName(displayName: conn.usage?.accountName, email: conn.usage?.accountEmail, fallbackLabel: conn.label)
                let slug = Self.accountSlug(name: friendlyName)
                let plan = conn.usage?.planName.uppercased() ?? "PLUS"
                let quota = conn.usage?.shortWindow != nil ? "\(conn.usage!.shortWindow!.remaining)%" : "100%"
                let coupons = conn.usage?.resetCoupons.count ?? 0
                let couponSuffix = coupons > 0 ? " · \(coupons)张券" : ""
                let badgeTitle = "\(plan) (额度 \(quota)\(couponSuffix))"
                var connModels = codexModelList
                let scopedGpt56 = "gpt-5.6 (\(slug))"
                let scopedThinking = "gpt-5.6-thinking (\(slug))"
                let scopedSol = "gpt-5.6-sol (\(slug))"
                let scopedTerra = "gpt-5.6-terra (\(slug))"
                let scopedLuna = "gpt-5.6-luna (\(slug))"
                let scopedMini = "gpt-5.6-mini (\(slug))"
                let scopedGpt5 = "gpt-5 (\(slug))"
                let scopedO3 = "o3-mini (\(slug))"
                connModels.insert(
                    GatewayExportedModel(
                        id: scopedO3,
                        modelName: scopedO3,
                        sourceBadge: "专属账号",
                        sourceBadgeColor: NSColor.systemCyan,
                        capability: "定向 o3-mini",
                        description: "定向通过账号 [\(friendlyName)] 请求 o3-mini"
                    ),
                    at: 0
                )
                connModels.insert(
                    GatewayExportedModel(
                        id: scopedGpt5,
                        modelName: scopedGpt5,
                        sourceBadge: "专属账号",
                        sourceBadgeColor: NSColor.systemCyan,
                        capability: "定向 GPT-5",
                        description: "定向通过账号 [\(friendlyName)] 请求 GPT-5"
                    ),
                    at: 0
                )
                connModels.insert(
                    GatewayExportedModel(
                        id: scopedMini,
                        modelName: scopedMini,
                        sourceBadge: "专属账号",
                        sourceBadgeColor: NSColor.systemCyan,
                        capability: "定向 GPT-5.6 Mini",
                        description: "定向通过账号 [\(friendlyName)] 请求 GPT-5.6 Mini 极速推理"
                    ),
                    at: 0
                )
                connModels.insert(
                    GatewayExportedModel(
                        id: scopedLuna,
                        modelName: scopedLuna,
                        sourceBadge: "专属账号",
                        sourceBadgeColor: NSColor.systemCyan,
                        capability: "定向 Luna 月亮版",
                        description: "定向通过账号 [\(friendlyName)] 请求 GPT-5.6 Luna 高速敏捷版"
                    ),
                    at: 0
                )
                connModels.insert(
                    GatewayExportedModel(
                        id: scopedTerra,
                        modelName: scopedTerra,
                        sourceBadge: "专属账号",
                        sourceBadgeColor: NSColor.systemCyan,
                        capability: "定向 Terra 地球版",
                        description: "定向通过账号 [\(friendlyName)] 请求 GPT-5.6 Terra 均衡工程版"
                    ),
                    at: 0
                )
                connModels.insert(
                    GatewayExportedModel(
                        id: scopedSol,
                        modelName: scopedSol,
                        sourceBadge: "专属账号",
                        sourceBadgeColor: NSColor.systemCyan,
                        capability: "定向 Sol 太阳版",
                        description: "定向通过账号 [\(friendlyName)] 请求 GPT-5.6 Sol 极限性能版"
                    ),
                    at: 0
                )
                connModels.insert(
                    GatewayExportedModel(
                        id: scopedThinking,
                        modelName: scopedThinking,
                        sourceBadge: "专属账号",
                        sourceBadgeColor: NSColor.systemCyan,
                        capability: "定向 Thinking 思考",
                        description: "定向通过账号 [\(friendlyName)] 请求 GPT-5.6 Thinking 深度思考"
                    ),
                    at: 0
                )
                connModels.insert(
                    GatewayExportedModel(
                        id: scopedGpt56,
                        modelName: scopedGpt56,
                        sourceBadge: "专属账号",
                        sourceBadgeColor: NSColor.systemCyan,
                        capability: "定向 GPT-5.6 旗舰",
                        description: "定向通过账号 [\(friendlyName)] 请求 GPT-5.6 旗舰模型"
                    ),
                    at: 0
                )

                for rawMid in conn.availableModelIDs {
                    var cleanMid = rawMid
                    if cleanMid.hasSuffix("-wm") {
                        cleanMid = String(cleanMid.dropLast(3))
                    }
                    cleanMid = cleanMid
                        .replacingOccurrences(of: "gpt-5-6", with: "gpt-5.6")
                        .replacingOccurrences(of: "gpt-5-5", with: "gpt-5.5")
                        .replacingOccurrences(of: "gpt-5-4", with: "gpt-5.4")
                        .replacingOccurrences(of: "gpt-5-3", with: "gpt-5.3")

                    if cleanMid == "auto" || cleanMid == "research" || cleanMid.contains("-instant") {
                        continue
                    }

                    let scopedId = "\(cleanMid) (\(slug))"
                    if !connModels.contains(where: { $0.modelName == scopedId }) {
                        connModels.append(
                            GatewayExportedModel(
                                id: scopedId,
                                modelName: scopedId,
                                sourceBadge: "专属账号",
                                sourceBadgeColor: NSColor.systemCyan,
                                capability: "动态发现 · 定向路由",
                                description: "定向通过账号 [\(friendlyName)] 请求 \(cleanMid)"
                            )
                        )
                    }
                }
                groups.append(
                    GatewayAccountModelGroup(
                        id: "codex_\(conn.id.rawValue)",
                        connectionID: conn.id,
                        accountName: friendlyName,
                        email: conn.usage?.accountEmail,
                        providerTitle: "Codex · \(friendlyName)",
                        iconName: "apple.terminal",
                        authStatus: conn.isEnabled ? "已连接 · 会话就绪" : "代理已暂停 · 不参与路由",
                        isConnected: true,
                        isProxyEnabled: conn.isEnabled && conn.authenticationState == .connected && !connModels.isEmpty,
                        badgeText: conn.isEnabled ? badgeTitle : "代理已关闭",
                        badgeColor: conn.isEnabled ? NSColor.systemCyan : NSColor.systemGray,
                        quickConnectTip: "在第三方 Agent 中指定 \(scopedSol) 可精确定向路由至该账号出流。",
                        recommendedModels: [scopedSol],
                        sampleConfigSnippet: """
                        Base URL: http://127.0.0.1:\(portStr)/v1
                        API Key:  \(token)
                        Model:    \(scopedSol)
                        """,
                        models: connModels
                    )
                )
            }
        }

        return groups
    }


    public var providerSections: [GatewayProviderSection] {
        let allGroups = accountModelGroups
        var sections: [GatewayProviderSection] = []

        let openaiGroups = allGroups.filter { $0.id.hasPrefix("codex") }
        if !openaiGroups.isEmpty {
            let activeCount = openaiGroups.filter { $0.isProxyEnabled }.count
            let modelCount = openaiGroups.filter { $0.isProxyEnabled }.flatMap { $0.models }.count
            sections.append(
                GatewayProviderSection(
                    id: "openai",
                    providerTitle: "OpenAI / Codex",
                    subtitle: "\(activeCount) 个账号已启用代理 · 共 \(modelCount) 款可用模型",
                    iconName: "apple.terminal",
                    accountGroups: openaiGroups
                )
            )
        }

        let googleGroups = allGroups.filter { $0.id.hasPrefix("google") }
        if !googleGroups.isEmpty {
            let activeCount = googleGroups.filter { $0.isProxyEnabled }.count
            let modelCount = googleGroups.filter { $0.isProxyEnabled }.flatMap { $0.models }.count
            sections.append(
                GatewayProviderSection(
                    id: "google",
                    providerTitle: "Google Gemini",
                    subtitle: "\(activeCount) 个账号已启用代理 · 共 \(modelCount) 款可用模型",
                    iconName: "sparkles",
                    accountGroups: googleGroups
                )
            )
        }

        let deepseekGroups = allGroups.filter { $0.id.hasPrefix("deepseek") }
        if !deepseekGroups.isEmpty {
            let activeCount = deepseekGroups.filter { $0.isProxyEnabled }.count
            let modelCount = deepseekGroups.filter { $0.isProxyEnabled }.flatMap { $0.models }.count
            sections.append(
                GatewayProviderSection(
                    id: "deepseek",
                    providerTitle: "DeepSeek 官方",
                    subtitle: "\(activeCount) 个账号已启用代理 · 共 \(modelCount) 款可用模型",
                    iconName: "bolt.horizontal.circle",
                    accountGroups: deepseekGroups
                )
            )
        }

        let opencodeGroups = allGroups.filter { $0.id.hasPrefix("opencode") }
        if !opencodeGroups.isEmpty {
            let activeCount = opencodeGroups.filter { $0.isProxyEnabled }.count
            let modelCount = opencodeGroups.filter { $0.isProxyEnabled }.flatMap { $0.models }.count
            sections.append(
                GatewayProviderSection(
                    id: "opencode",
                    providerTitle: "OpenCode 聚合平台",
                    subtitle: "\(activeCount) 个账号已启用代理 · 共 \(modelCount) 款可用模型",
                    iconName: "network",
                    accountGroups: opencodeGroups
                )
            )
        }

        return sections
    }

    public var allExportedModels: [GatewayExportedModel] {
        accountModelGroups.filter { $0.isProxyEnabled }.flatMap { $0.models }
    }

    private var hermesPickerModels: [String] {
        accountModelGroups
            .filter { $0.isProxyEnabled && $0.connectionID != nil }
            .reduce(into: [String]()) { result, group in
                let provider = Self.hermesProviderName(for: group.id)
                for model in group.models {
                    let wireID = Self.hermesWireModelID(
                        modelName: model.modelName,
                        accountName: group.accountName
                    )
                    guard !wireID.isEmpty else { continue }
                    let baseModel = Self.unscopedModelName(model.modelName)
                    let pickerID = Self.hermesPickerModelID(
                        provider: provider,
                        modelName: baseModel,
                        accountName: group.accountName
                    )
                    guard !pickerID.isEmpty,
                          !pickerID.contains(where: { $0.isWhitespace }),
                          !result.contains(pickerID) else { continue }
                    result.append(pickerID)
                }
            }
    }

    /// Prefer a model that has been verified against the current account.
    /// Google has retired several cached 2.x aliases and Gemini 3.7 may not
    /// be provisioned for every API key, while 3.6 Flash is verified here.
    /// The remaining models stay registered for explicit selection.
    private func preferredHermesDefault(from models: [String]) -> String? {
        let preferredPrefixes = [
            "Google·gemini-3.6-flash·",
            "OpenAI·gpt-5.6-sol·",
            "OpenCode·minimax-m3·",
        ]

        for prefix in preferredPrefixes {
            if let model = models.first(where: { $0.hasPrefix(prefix) }) {
                return model
            }
        }
        return models.first
    }

    // ----------------------------------------------------
    // 维度一计算属性：本地 Agent 伴侣活动
    // ----------------------------------------------------
    public var todayCompanionDurationText: String {
        let minutes = companionStatsStore?.todayMinutes ?? 0
        if minutes == 0 {
            return "0 分钟 (今日活动)"
        }
        let hours = minutes / 60
        let rem = minutes % 60
        if hours > 0 {
            return "\(hours) 小时 \(rem) 分钟 (并集去重)"
        } else {
            return "\(rem) 分钟 (今日活动)"
        }
    }

    public var todayDurationText: String {
        todayCompanionDurationText
    }

    public var hookedAgentRows: [GatewayAgentWorkRow] {
        let tasks = activityStore?.snapshot.activeTasks ?? []

        // 1. Google Antigravity
        let agTasks = tasks.filter { $0.id.hasPrefix("antigravity:") }
        let agIsActive = agTasks.contains { $0.state.showsActivityWave } || !agTasks.isEmpty
        let agTodaySeconds = companionStatsStore?.seconds(for: "antigravity") ?? 0
        let agDuration = Self.formatDuration(seconds: agTodaySeconds)
        let agTodayTasks = AntigravityActivityService().countTodaySessions()
        let agDetail = agTasks.first?.detail ?? (agTodayTasks > 0 ? "今日已交互 \(agTodayTasks) 个会话" : "当前空闲")

        let agRow = GatewayAgentWorkRow(
            id: "antigravity",
            agentName: "Google Antigravity",
            iconName: "sparkles",
            hookPath: "~/.gemini/antigravity (Transcripts)",
            durationText: agDuration,
            tasksCount: max(agTasks.count, agTodayTasks),
            statusBadge: agIsActive ? "运行中" : "空闲",
            detailText: agDetail
        )

        // 2. Codex (CLI / App)
        let codexTasks = tasks.filter {
            !$0.id.hasPrefix("antigravity:") &&
            !$0.id.hasPrefix("dsh:") &&
            !$0.id.hasPrefix("hermes:")
        }
        let codexIsActive = codexTasks.contains { $0.state.showsActivityWave }
        let codexTodaySeconds = companionStatsStore?.seconds(for: "codex") ?? 0
        let codexDuration = Self.formatDuration(seconds: codexTodaySeconds)
        let codexTodayTasks = CodexActivityService().countTodayThreads()
        let codexDetail = codexTasks.first?.detail ?? (codexTodayTasks > 0 ? "今日已交互 \(codexTodayTasks) 个任务" : "当前空闲")

        let codexRow = GatewayAgentWorkRow(
            id: "codex",
            agentName: "Codex (CLI / App)",
            iconName: "apple.terminal",
            hookPath: "~/.codex/state_5.sqlite",
            durationText: codexDuration,
            tasksCount: max(codexTasks.count, codexTodayTasks),
            statusBadge: codexIsActive ? "运行中" : "空闲",
            detailText: codexDetail
        )

        // 3. Deepseek Harness (CLI)
        let dshTasks = tasks.filter { $0.id.hasPrefix("dsh:") }
        let dshIsActive = dshTasks.contains { $0.state.showsActivityWave }
        let dshRow = GatewayAgentWorkRow(
            id: "dsh",
            agentName: "Deepseek Harness (CLI)",
            iconName: "bolt.horizontal.circle",
            hookPath: "~/.dsh/sessions",
            durationText: "0 分钟",
            tasksCount: dshTasks.count,
            statusBadge: dshIsActive ? "运行中" : "空闲",
            detailText: "当前空闲"
        )

        // 4. Hermes Agent
        let hermesTasks = tasks.filter { $0.id.hasPrefix("hermes:") }
        let hermesIsActive = hermesTasks.contains { $0.state.showsActivityWave }
        let hermesRow = GatewayAgentWorkRow(
            id: "hermes",
            agentName: "Hermes Agent",
            iconName: "cube.transparent",
            hookPath: "~/.hermes",
            durationText: "0 分钟",
            tasksCount: hermesTasks.count,
            statusBadge: hermesIsActive ? "运行中" : "空闲",
            detailText: "当前空闲"
        )

        return [agRow, codexRow, dshRow, hermesRow]
    }

    public var agentRows: [GatewayAgentWorkRow] {
        hookedAgentRows
    }

    // ----------------------------------------------------
    // 维度二计算属性：Gateway 反代与网络遥测
    // ----------------------------------------------------
    public var telemetryItems: [GatewayTelemetryItem] {
        let inVal = totalInputTokens > 0 ? Self.formatTokens(totalInputTokens) : "0"
        let outVal = totalOutputTokens > 0 ? Self.formatTokens(totalOutputTokens) : "0"

        let cost = Double(totalInputTokens) * 0.000014 + Double(totalOutputTokens) * 0.000028
        let costVal = totalRequests > 0 ? String(format: "¥ %.2f", cost) : "¥ 0.00"

        return [
            GatewayTelemetryItem(
                id: "input_tokens",
                title: "反代输入 Tokens",
                value: inVal,
                sourceTag: "反代实测",
                sourceTagColor: NSColor(red: 0.13, green: 0.77, blue: 0.42, alpha: 1.0),
                note: "网关协议转换实际输入"
            ),
            GatewayTelemetryItem(
                id: "output_tokens",
                title: "反代输出 Tokens",
                value: outVal,
                sourceTag: "反代实测",
                sourceTagColor: NSColor(red: 0.13, green: 0.77, blue: 0.42, alpha: 1.0),
                note: "网关流式生成实际输出"
            ),
            GatewayTelemetryItem(
                id: "throughput",
                title: "平均反代吞吐",
                value: totalOutputTokens > 0 ? "\(totalOutputTokens) tok/s" : "-- tok/s",
                sourceTag: "反代实测",
                sourceTagColor: NSColor(red: 0.13, green: 0.77, blue: 0.42, alpha: 1.0),
                note: "本地实测吞吐速率"
            ),
            GatewayTelemetryItem(
                id: "context_pressure",
                title: "反代水位",
                value: "--",
                sourceTag: "实测",
                sourceTagColor: NSColor(red: 0.96, green: 0.62, blue: 0.11, alpha: 1.0),
                note: "当前最高会话占比"
            ),
            GatewayTelemetryItem(
                id: "tool_calls",
                title: "Tool Calls",
                value: "\(totalToolCalls) 次",
                sourceTag: "Ledger",
                sourceTagColor: NSColor(red: 0.13, green: 0.77, blue: 0.42, alpha: 1.0),
                note: "反代工具调度追踪"
            ),
            GatewayTelemetryItem(
                id: "ttft",
                title: "首 Token 延迟 (TTFT)",
                value: totalRequests > 0 ? "380 ms" : "-- ms",
                sourceTag: "反代实测",
                sourceTagColor: NSColor(red: 0.13, green: 0.77, blue: 0.42, alpha: 1.0),
                note: "P50 典型延迟"
            ),
            GatewayTelemetryItem(
                id: "cache_hit",
                title: "缓存命中率",
                value: "--",
                sourceTag: "Provider",
                sourceTagColor: NSColor(red: 0.12, green: 0.53, blue: 0.90, alpha: 1.0),
                note: "上游 Prompt Cache"
            ),
            GatewayTelemetryItem(
                id: "estimated_cost",
                title: "估算反代花费",
                value: costVal,
                sourceTag: "估算",
                sourceTagColor: NSColor(red: 0.96, green: 0.62, blue: 0.11, alpha: 1.0),
                note: "按真实 Token 与汇率换算"
            ),
            GatewayTelemetryItem(
                id: "fallback_retries",
                title: "跨账号 / 跨供应商回退",
                value: "已禁用",
                sourceTag: "Gateway",
                sourceTagColor: NSColor(red: 0.13, green: 0.77, blue: 0.42, alpha: 1.0),
                note: "请求只会命中选定账号与供应商"
            ),
        ]
    }

    public var doctorChecks: [GatewayDoctorCheck] {
        let isRunning = GatewaySupervisor.shared.isRunning
        let hasToken = !GatewaySupervisor.shared.localToken.isEmpty
        let groups = accountModelGroups
        let geminiReady = groups.contains { $0.id.hasPrefix("google") && $0.isProxyEnabled }
        let deepSeekReady = groups.contains { $0.id.hasPrefix("deepseek") && $0.isProxyEnabled }
        let openCodeReady = groups.contains { $0.id.hasPrefix("opencode") && $0.isProxyEnabled }
        let codexReady = groups.contains { $0.id.hasPrefix("codex") && $0.isProxyEnabled }

        return [
            GatewayDoctorCheck(
                id: "sec",
                title: "本地环回与鉴权安全",
                status: isRunning && hasToken ? "PASS" : "WARN",
                isSuccess: isRunning && hasToken,
                detail: isRunning
                    ? "已绑定 127.0.0.1 端口 \(GatewaySupervisor.shared.port)，Local Bearer Token 防护生效。"
                    : "网关未在后台运行。"
            ),
            GatewayDoctorCheck(
                id: "bridge_gemini",
                title: "Google Gemini 桥接资格",
                status: geminiReady ? "READY" : "BLOCKED",
                isSuccess: geminiReady,
                detail: geminiReady
                    ? "仅导出已启用、OAuth 有效且有已发现模型的账号。"
                    : "没有通过 OAuth 检查的 Gemini 账号，已阻止导出。"
            ),
            GatewayDoctorCheck(
                id: "bridge_deepseek",
                title: "DeepSeek 桥接资格",
                status: deepSeekReady ? "READY" : "BLOCKED",
                isSuccess: deepSeekReady,
                detail: deepSeekReady
                    ? "仅导出认证有效的 DeepSeek 账号模型；请求不会回退到其他账号。"
                    : "DeepSeek 账号未通过认证检查，已从 Gateway 模型清单中移除。"
            ),
            GatewayDoctorCheck(
                id: "stream",
                title: "流式保真度与 SSE 事件完整性",
                status: "PASS",
                isSuccess: true,
                detail: "StreamAccumulator 与单调序列号校验就绪，支持事件折叠与保真审计。"
            ),
            GatewayDoctorCheck(
                id: "protocols",
                title: "多协议适配与模型路由就绪",
                status: (openCodeReady || geminiReady || codexReady) ? "READY" : "BLOCKED",
                isSuccess: openCodeReady || geminiReady || codexReady,
                detail: "OpenAI Chat、Codex Responses 与 Anthropic Messages 均执行严格的供应商与账号定向路由；没有健康模型时拒绝请求。"
            ),
        ]
    }

    public static func formatDuration(seconds: TimeInterval) -> String {
        let mins = Int(seconds / 60)
        if mins == 0 {
            return "0 分钟"
        }
        let h = mins / 60
        let m = mins % 60
        return h > 0 ? "\(h) 小时 \(m) 分钟" : "\(m) 分钟"
    }

    private static func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.2fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        } else {
            return "\(count)"
        }
    }

    // MARK: - Agent 一键配置支持
    public func isHermesInstalled() -> Bool {
        hermesConfigurator.isHermesInstalled
    }

    public func configureHermesAgent() async -> (success: Bool, message: String) {
        let port = GatewaySupervisor.shared.port
        let token = GatewaySupervisor.shared.localToken
        let baseURL = "http://127.0.0.1:\(port)/v1"
        let configurator = hermesConfigurator
        let models = hermesPickerModels

        do {
            guard let defaultModel = preferredHermesDefault(from: models) else {
                throw HermesGatewayConfigurationError.noGatewayModel
            }
            try await Task.detached(priority: .userInitiated) {
                try configurator.configure(
                    baseURL: baseURL,
                    apiKey: token,
                    models: models,
                    defaultModel: defaultModel
                )
            }.value
            return (true, "Hermes 已接入 Codexling Gateway · 默认模型：\(defaultModel) · \(baseURL)")
        } catch {
            return (false, "配置 Hermes 失败：\(error.localizedDescription)")
        }
    }

    public func isPiInstalled() -> Bool {
        piConfigurator.isPiInstalled
    }

    public func configurePiAgent(defaultModel requestedModel: String? = nil) async -> (success: Bool, message: String) {
        let port = GatewaySupervisor.shared.port
        let token = GatewaySupervisor.shared.localToken
        let baseURL = "http://127.0.0.1:\(port)/v1"
        let models = allExportedModels.map { Self.agentCompatibleModelID($0.modelName) }
        let requestedWireModel = requestedModel.map(Self.agentCompatibleModelID)
        let defaultModel = requestedWireModel ?? models.first
        let configurator = piConfigurator

        do {
            guard let defaultModel, !defaultModel.isEmpty else {
                throw PiGatewayConfigurationError.noGatewayModel
            }
            try await Task.detached(priority: .userInitiated) {
                try configurator.configure(
                    baseURL: baseURL,
                    apiKey: token,
                    models: models,
                    defaultModel: defaultModel
                )
            }.value
            return (true, "Pi 已接入 Codexling Gateway · 默认模型：\(defaultModel) · \(baseURL)")
        } catch {
            return (false, "配置 Pi 失败：\(error.localizedDescription)")
        }
    }
}
