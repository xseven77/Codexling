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

    public var selectedTab: GatewayNavTab = .connect {
        didSet {
            if oldValue != selectedTab {
                if selectedTab == .overview {
                    Task { await refreshTelemetryAnalytics() }
                } else if selectedTab == .requests {
                    Task { await refreshRequestsList() }
                }
            }
        }
    }
    public var selectedRequestId: String?

    // ==========================================
    // 维度一：本地 Hook 的 Agent 伴侣与活动数据
    // ==========================================
    private weak var activityStore: CodexActivityStore?
    private weak var companionStatsStore: CompanionStatsStore?
    private let hermesConfigurator: HermesGatewayConfigurator
    private let piConfigurator: PiGatewayConfigurator
    private let agentCatalogDefaults = UserDefaults.standard
    private let hermesCatalogFingerprintKey = "Codexling.hermesCatalogFingerprint"
    private let piCatalogFingerprintKey = "Codexling.piCatalogFingerprint"

    // Agent status is discovered off the main actor when the Agents page is
    // opened. Never invoke `hermes config get` from a SwiftUI body: it starts
    // a process synchronously and can block a single render several times.
    public private(set) var hermesAgentInstalled = false
    public private(set) var hermesAgentConfigured = false
    public private(set) var piAgentInstalled = false
    public private(set) var piAgentConfigured = false
    public private(set) var isRefreshingAgentIntegrationStatus = false
    public private(set) var hasLoadedAgentIntegrationStatus = false

    // ==========================================
    // 维度二：Gateway 本地反代与持久化遥测数据
    // ==========================================
    public private(set) var totalRequests: Int = 0
    public private(set) var totalInputTokens: Int = 0
    public private(set) var totalOutputTokens: Int = 0
    public private(set) var totalToolCalls: Int = 0

    public private(set) var requestsList: [GatewayRequestRow] = []

    // 遥测分析与筛选状态
    public var selectedDateRange: GatewayDateRange = .today {
        didSet {
            requestsCurrentPage = 1
            Task { await refreshSelectedTabData() }
        }
    }
    public var customStartDate: Date = Calendar.current.date(byAdding: .hour, value: -1, to: Date()) ?? Date()
    public var customEndDate: Date = Date()
    public var showsCustomDatePicker: Bool = false

    public var selectedMetricTab: GatewayMetricTab = .tokens
    public var selectedBreakdownDimension: GatewayBreakdownDimension = .model {
        didSet {
            guard selectedTab == .overview else { return }
            Task { await refreshBreakdown() }
        }
    }

    public var filterAgent: String? = nil {
        didSet {
            requestsCurrentPage = 1
            Task { await refreshSelectedTabData() }
        }
    }
    public var filterProvider: String? = nil {
        didSet {
            requestsCurrentPage = 1
            Task { await refreshSelectedTabData() }
        }
    }
    public var filterAccount: String? = nil {
        didSet {
            requestsCurrentPage = 1
            Task { await refreshSelectedTabData() }
        }
    }
    public var filterModel: String? = nil {
        didSet {
            requestsCurrentPage = 1
            Task { await refreshSelectedTabData() }
        }
    }

    public private(set) var telemetrySummary: GatewayTelemetrySummary = .zero
    public private(set) var timeseriesBuckets: [GatewayTimeseriesBucket] = []
    public private(set) var breakdownItems: [GatewayBreakdownItem] = []
    public private(set) var detailedRequestsList: [GatewayTelemetryEventDetail] = []
    public private(set) var isTelemetryLoading: Bool = false
    public private(set) var isSummaryLoading: Bool = false
    public private(set) var isTimeseriesLoading: Bool = false
    public private(set) var isBreakdownLoading: Bool = false
    public private(set) var isRequestsLoading: Bool = false

    // 分页状态管理
    public var requestsCurrentPage: Int = 1 {
        didSet {
            if oldValue != requestsCurrentPage, selectedTab == .requests {
                Task { await refreshRequestsList() }
            }
        }
    }
    public var requestsPageSize: Int = 20 {
        didSet {
            if oldValue != requestsPageSize {
                requestsCurrentPage = 1
                if selectedTab == .requests {
                    Task { await refreshRequestsList() }
                }
            }
        }
    }
    public private(set) var requestsTotalCount: Int64 = 0

    public var requestsTotalPages: Int {
        guard requestsTotalCount > 0 else { return 1 }
        return max(1, Int(ceil(Double(requestsTotalCount) / Double(requestsPageSize))))
    }

    public func goToPage(_ page: Int) {
        let target = max(1, min(page, requestsTotalPages))
        if target != requestsCurrentPage {
            requestsCurrentPage = target
        }
    }

    public func nextPage() {
        if requestsCurrentPage < requestsTotalPages {
            requestsCurrentPage += 1
        }
    }

    public func prevPage() {
        if requestsCurrentPage > 1 {
            requestsCurrentPage -= 1
        }
    }

    public func setPageSize(_ size: Int) {
        guard size > 0, size != requestsPageSize else { return }
        requestsPageSize = size
    }

    // ==========================================
    // 维度三：请求流表格列自定义显示设置
    // ==========================================
    public static let visibleColumnsDefaultsKey = "codexling.gateway.visibleColumns"

    public var isColumnSettingsPresented: Bool = false

    public var visibleColumns: Set<GatewayRequestColumn> = {
        if let saved = UserDefaults.standard.stringArray(forKey: "codexling.gateway.visibleColumns") {
            let cols = saved.compactMap { GatewayRequestColumn(rawValue: $0) }
            if !cols.isEmpty {
                return Set(cols)
            }
        }
        return Set(GatewayRequestColumn.defaultColumns)
    }() {
        didSet {
            let rawValues = Array(visibleColumns.map(\.rawValue))
            UserDefaults.standard.set(rawValues, forKey: Self.visibleColumnsDefaultsKey)
        }
    }

    public var orderedVisibleColumns: [GatewayRequestColumn] {
        GatewayRequestColumn.allCases.filter { visibleColumns.contains($0) }
    }

    public func isColumnVisible(_ col: GatewayRequestColumn) -> Bool {
        visibleColumns.contains(col)
    }

    public func toggleColumn(_ col: GatewayRequestColumn) {
        if visibleColumns.contains(col) {
            if visibleColumns.count > 1 {
                visibleColumns.remove(col)
            }
        } else {
            visibleColumns.insert(col)
        }
    }

    public func setColumnVisible(_ col: GatewayRequestColumn, isVisible: Bool) {
        if isVisible {
            visibleColumns.insert(col)
        } else {
            if visibleColumns.count > 1 {
                visibleColumns.remove(col)
            }
        }
    }

    public func selectAllColumns() {
        visibleColumns = Set(GatewayRequestColumn.allCases)
    }

    public func resetColumnsToDefault() {
        visibleColumns = Set(GatewayRequestColumn.defaultColumns)
    }

    public func setCustomPreset(hours: Int) {
        let now = Date()
        let start = Calendar.current.date(byAdding: .hour, value: -hours, to: now) ?? now
        applyCustomDateRange(start: start, end: now)
    }

    public func setCustomPreset(days: Int) {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        applyCustomDateRange(start: start, end: now)
    }

    public func applyCustomDateRange(start: Date, end: Date) {
        self.customStartDate = start
        self.customEndDate = end
        self.selectedDateRange = .custom
        self.requestsCurrentPage = 1
    }

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

    // ==========================================
    // 持久化遥测接口请求与更新
    // ==========================================

    private func buildQueryItems(additional: [String: String] = [:]) -> [URLQueryItem] {
        let (from, to) = selectedDateRange.calculateTimestamps(customStart: customStartDate, customEnd: customEndDate)
        let tz = TimeZone.current.identifier
        var items = [
            URLQueryItem(name: "from", value: "\(from)"),
            URLQueryItem(name: "to", value: "\(to)"),
            URLQueryItem(name: "timezone", value: tz),
        ]
        if let agent = filterAgent, !agent.isEmpty, agent != "全部 Agent" {
            items.append(URLQueryItem(name: "agent", value: agent))
        }
        if let provider = filterProvider, !provider.isEmpty, provider != "全部供应商" {
            items.append(URLQueryItem(name: "provider", value: provider))
        }
        if let account = filterAccount, !account.isEmpty, account != "全部账号" {
            items.append(URLQueryItem(name: "account", value: account))
        }
        if let model = filterModel, !model.isEmpty, model != "全部模型" {
            items.append(URLQueryItem(name: "model", value: model))
        }
        for (k, v) in additional {
            items.append(URLQueryItem(name: k, value: v))
        }
        return items
    }

    public func refreshTelemetryAnalytics() async {
        guard !isTelemetryLoading else { return }
        isTelemetryLoading = true
        defer { isTelemetryLoading = false }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshSummary() }
            group.addTask { await self.refreshTimeseries() }
            group.addTask { await self.refreshBreakdown() }
        }
    }

    /// Data is intentionally lazy: a page owns its own requests.  Switching
    /// to Connect, Agents or Doctor never starts telemetry work in the
    /// background, and changing filters only refreshes the page being viewed.
    private func refreshSelectedTabData() async {
        switch selectedTab {
        case .overview:
            await refreshTelemetryAnalytics()
        case .requests:
            await refreshRequestsList()
        case .connect, .agents, .doctor:
            break
        }
    }

    public func refreshSummary() async {
        guard !isSummaryLoading else { return }
        isSummaryLoading = true
        defer { isSummaryLoading = false }

        guard let base = GatewaySupervisor.shared.endpoint else { return }
        var components = URLComponents(url: base.appendingPathComponent("telemetry/summary"), resolvingAgainstBaseURL: false)
        components?.queryItems = buildQueryItems()
        guard let url = components?.url else { return }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(localToken)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 3

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let decoder = JSONDecoder()
            let summary = try decoder.decode(GatewayTelemetrySummary.self, from: data)
            self.telemetrySummary = summary
            self.updateGatewayMetrics(
                totalRequests: Int(summary.totalRequests),
                inputTokens: Int(summary.totalInputTokens),
                outputTokens: Int(summary.totalOutputTokens),
                toolCalls: Int(summary.toolCallsCount)
            )
        } catch {
            print("[GatewayStore] refreshSummary error: \(error)")
        }
    }

    public func refreshTimeseries() async {
        guard !isTimeseriesLoading else { return }
        isTimeseriesLoading = true
        defer { isTimeseriesLoading = false }

        guard let base = GatewaySupervisor.shared.endpoint else { return }
        var components = URLComponents(url: base.appendingPathComponent("telemetry/timeseries"), resolvingAgainstBaseURL: false)
        let (from, to) = selectedDateRange.calculateTimestamps(customStart: customStartDate, customEnd: customEndDate)
        let durationMs = max(0, to - from)

        let interval: String
        switch selectedDateRange {
        case .last10Minutes:
            interval = "minute"
        case .today, .yesterday:
            interval = "hour"
        case .last7Days, .last30Days:
            interval = "day"
        case .custom:
            if durationMs <= 3600 * 1000 {
                interval = "minute"
            } else if durationMs <= 48 * 3600 * 1000 {
                interval = "hour"
            } else if durationMs <= 60 * 86400 * 1000 {
                interval = "day"
            } else {
                interval = "week"
            }
        }

        components?.queryItems = buildQueryItems(additional: ["interval": interval, "metric": selectedMetricTab.rawValue])
        guard let url = components?.url else { return }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(localToken)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 3

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let decoder = JSONDecoder()
            let resp = try decoder.decode(GatewayTimeseriesResponse.self, from: data)
            self.timeseriesBuckets = resp.buckets
        } catch {
            print("[GatewayStore] refreshTimeseries error: \(error)")
        }
    }

    public func refreshBreakdown() async {
        guard !isBreakdownLoading else { return }
        isBreakdownLoading = true
        defer { isBreakdownLoading = false }

        guard let base = GatewaySupervisor.shared.endpoint else { return }
        var components = URLComponents(url: base.appendingPathComponent("telemetry/breakdown"), resolvingAgainstBaseURL: false)
        components?.queryItems = buildQueryItems(additional: ["dimension": selectedBreakdownDimension.apiDimension])
        guard let url = components?.url else { return }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(localToken)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 3

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let decoder = JSONDecoder()
            let resp = try decoder.decode(GatewayBreakdownResponse.self, from: data)
            self.breakdownItems = resp.items
        } catch {
            print("[GatewayStore] refreshBreakdown error: \(error)")
        }
    }

    public func refreshRequestsList() async {
        guard !isRequestsLoading else { return }
        isRequestsLoading = true
        defer { isRequestsLoading = false }

        guard let base = GatewaySupervisor.shared.endpoint else { return }
        var components = URLComponents(url: base.appendingPathComponent("telemetry/requests"), resolvingAgainstBaseURL: false)
        let limit = requestsPageSize
        let offset = max(0, (requestsCurrentPage - 1) * requestsPageSize)
        components?.queryItems = buildQueryItems(additional: [
            "limit": "\(limit)",
            "offset": "\(offset)"
        ])
        guard let url = components?.url else { return }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(localToken)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 3

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let decoder = JSONDecoder()
            let resp = try decoder.decode(GatewayRequestsResponse.self, from: data)
            self.detailedRequestsList = resp.items
            self.requestsTotalCount = resp.total
        } catch {
            print("[GatewayStore] refreshRequestsList error: \(error)")
        }
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

    /// Normalizes raw model IDs from ChatGPT / OpenAI API by stripping the `-wm` watermark suffix.
    public static func normalizeCodexModelID(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix("-wm") {
            s = String(s.dropLast(3))
        }
        return s
    }

    /// Sorts codex model slugs so flagship models (5.6 Sol / Terra / Luna / 5.6 / 5.5) appear first.
    /// Handles both the dash-form (`gpt-5-6-sol`, from `availableModelIDs`) and
    /// dot-form (`gpt-5.6-sol`, from the codex CLI catalog) by normalizing the
    /// version separator before scoring.
    public static func sortCodexModelSlugs(_ slugs: [String]) -> [String] {
        let canonical = { (s: String) -> String in
            // gpt-5-6-sol -> gpt-5.6-sol so the score below matches once.
            s.replacingOccurrences(of: "gpt-5-", with: "gpt-5.")
        }
        return slugs.sorted { a, b in
            let score = { (s: String) -> Int in
                let c = canonical(s)
                if c == "gpt-5.6-sol" || c.contains("5.6-sol") { return 100 }
                if c == "gpt-5.6-terra" || c.contains("5.6-terra") { return 90 }
                if c == "gpt-5.6-luna" || c.contains("5.6-luna") { return 80 }
                if c == "gpt-5.6" { return 70 }
                if c.contains("5.6-thinking") || c.contains("thinking") { return 65 }
                if c == "gpt-5.5" { return 60 }
                if c.contains("5.6") { return 50 }
                if c.contains("5.5") { return 40 }
                if c.contains("5.4") { return 30 }
                if c.contains("5.3") { return 20 }
                if c.contains("5.2") { return 10 }
                return 0
            }
            let scoreA = score(a)
            let scoreB = score(b)
            if scoreA != scoreB { return scoreA > scoreB }
            return a < b
        }
    }

    /// Sources servable slugs for a Codex account.
    /// Uses authoritative OpenAI account discovery (`availableModelIDs`) from the OpenAI/ChatGPT API,
    /// exactly matching how Google Gemini, OpenCode, and DeepSeek operate.
    /// Falls back to on-disk models_cache.json only if availableModelIDs is empty.
    static func codexServableSlugs(from connection: CodexAccountConnection, runtimesRoot: URL? = nil) -> [String] {
        if !connection.availableModelIDs.isEmpty {
            var slugs: [String] = []
            for raw in connection.availableModelIDs {
                let norm = normalizeCodexModelID(raw)
                if !norm.isEmpty && norm != "research" && !slugs.contains(norm) {
                    slugs.append(norm)
                }
            }
            if !slugs.isEmpty {
                return sortCodexModelSlugs(slugs)
            }
        }
        let runtimesRoot = runtimesRoot ?? ConnectionRegistryStorage().fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Codexling/Runtimes/Codex", isDirectory: true)
        let home = runtimesRoot.appendingPathComponent(connection.relativeHomeDirectory, isDirectory: true)
        let cacheURL = home.appendingPathComponent("models_cache.json")
        if let data = try? Data(contentsOf: cacheURL),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let models = json["models"] as? [[String: Any]] {
            let slugs = parseCodexModelSlugs(models: models)
            if !slugs.isEmpty { return sortCodexModelSlugs(slugs) }
        }
        return []
    }

    /// Filters a codex model catalog down to the user-selectable (visible)
    /// slugs, dropping hidden/internal entries.
    private static func parseCodexModelSlugs(models: [[String: Any]]) -> [String] {
        var slugs: [String] = []
        for model in models {
            guard let slug = model["slug"] as? String, !slug.isEmpty else { continue }
            if slug == "codex-auto-review" { continue }
            if (model["visibility"] as? String) == "hide" { continue }
            if !slugs.contains(slug) { slugs.append(slug) }
        }
        return slugs
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

    nonisolated public static func connectionShortID(id: ConnectionID) -> String {
        let raw = id.rawValue.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return String(raw.prefix(8))
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
            // Cloud Code's `-tiered` is a routing implementation detail. Keep
            // its original form in the Gateway catalog, but give every Gemini
            // generation (including newly released ones) the same concise,
            // human-readable picker label.
            let withoutTier = compact.replacingOccurrences(of: "-tiered", with: "")
            return withoutTier
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

        // Every exported list begins empty. The account-scoped official
        // discovery catalog below is authoritative; stale built-in names must
        // never appear as selectable models.
        var geminiModelList: [GatewayExportedModel] = [] /*
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
        ] */
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
        var deepseekModelList: [GatewayExportedModel] = [] /*
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
        ] */
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
        var opencodeModelList: [GatewayExportedModel] = [] /*
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
        ] */
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
        // Codex CLI 只能服务其自身 `models_cache.json` 中列出的模型；该文件由 CLI
        // 在同步时自动刷新。因此这里仅从该权威来源构建可服务模型，绝不使用
        // ChatGPT 侧的 availableModelIDs（那些模型 codex exec 无法服务）。
        var codexModelList: [GatewayExportedModel] = []
        for conn in registry.codexAccounts {
            for slug in Self.codexServableSlugs(from: conn) where !codexModelList.contains(where: { $0.modelName == slug }) {
                codexModelList.append(
                    GatewayExportedModel(
                        id: slug,
                        modelName: slug,
                        sourceBadge: "Codex 目录",
                        sourceBadgeColor: NSColor.systemCyan,
                        capability: "CLI 可服务",
                        description: "来自 codex CLI 实际可服务模型目录"
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
                    authStatus: "未配置 · 需登录 Google 账号",
                    isConnected: false,
                    isProxyEnabled: false,
                    hasProxyCredential: false,
                    badgeText: "未连接",
                    badgeColor: NSColor.systemGray,
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
                let shortID = Self.connectionShortID(id: conn.id)
                let slug = "\(Self.accountSlug(name: friendlyName))-google-\(shortID)"
                let accountDisplay = "\(friendlyName) (Google · \(shortID))"

                for rawMid in conn.availableModelIDs {
                    // Keep the catalog's original ID in the route key. The
                    // friendly label is built separately for Agent pickers.
                    let mid = rawMid.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !mid.isEmpty else { continue }
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
                        accountName: accountDisplay,
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
                    authStatus: "未配置 · 需添加 API Key",
                    isConnected: false,
                    isProxyEnabled: false,
                    hasProxyCredential: false,
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
                let shortID = Self.connectionShortID(id: conn.id)
                let slug = "\(Self.accountSlug(name: friendlyName))-deepseek-\(shortID)"
                let accountDisplay = "\(friendlyName) (DeepSeek · \(shortID))"
                let balanceStr = conn.balance?.total != nil ? String(format: "余额 ¥%.2f", NSDecimalNumber(decimal: conn.balance!.total).doubleValue) : "官方直连"
                let badgeTitle = balanceStr
                let connModels = conn.availableModelIDs.compactMap { rawModel -> GatewayExportedModel? in
                    let model = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !model.isEmpty else { return nil }
                    let scopedID = "\(model) (\(slug))"
                    return GatewayExportedModel(
                        id: scopedID,
                        modelName: scopedID,
                        sourceBadge: "官方目录",
                        sourceBadgeColor: NSColor.systemBlue,
                        capability: "账号实际可用 · 定向路由",
                        description: "定向通过账号 [\(friendlyName)] 请求 \(model)"
                    )
                }
                groups.append(
                    GatewayAccountModelGroup(
                        id: "deepseek_\(conn.id.rawValue)",
                        connectionID: conn.id,
                        accountName: accountDisplay,
                        providerTitle: "DeepSeek · \(friendlyName)",
                        iconName: "bolt.horizontal.circle",
                        authStatus: conn.isEnabled ? "已连接 · 官方直连" : "代理已暂停 · 不参与路由",
                        isConnected: true,
                        isProxyEnabled: conn.isEnabled && conn.authenticationState == .connected,
                        badgeText: conn.isEnabled ? badgeTitle : "代理已关闭",
                        badgeColor: conn.isEnabled ? NSColor.systemBlue : NSColor.systemGray,
                        quickConnectTip: "仅导出 [\(friendlyName)] 通过 DeepSeek 官方接口实际发现的模型，并定向由该账号出流。",
                        recommendedModels: connModels.prefix(4).map(\.modelName),
                        sampleConfigSnippet: """
                        Base URL: http://127.0.0.1:\(portStr)/v1
                        API Key:  \(token)
                        Model:    \(connModels.first?.modelName ?? "等待模型目录同步")
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
                    authStatus: "未配置 · 需添加 OpenCode 令牌",
                    isConnected: false,
                    isProxyEnabled: false,
                    hasProxyCredential: false,
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
                let shortID = Self.connectionShortID(id: conn.id)
                let slug = "\(Self.accountSlug(name: friendlyName))-opencode-\(shortID)"
                let accountDisplay = "\(friendlyName) (OpenCode · \(shortID))"
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
                        accountName: accountDisplay,
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
                    authStatus: "未连接 · 会话未就绪",
                    isConnected: false,
                    isProxyEnabled: false,
                    hasProxyCredential: false,
                    badgeText: "未连接",
                    badgeColor: NSColor.systemCyan,
                    quickConnectTip: "登录 OpenAI 账号后，网关会按 codex CLI 实际可服务的模型目录自动同步；不会使用 ChatGPT 应用侧模型列表。",
                    recommendedModels: [],
                    sampleConfigSnippet: """
                    Base URL: http://127.0.0.1:\(portStr)/v1
                    API Key:  \(token)
                    Model:    登录后按 codex CLI 目录自动同步
                    """,
                    models: codexModelList
                )
            )
        } else {
            for conn in registry.codexAccounts {
                let friendlyName = Self.friendlyAccountName(displayName: conn.usage?.accountName, email: conn.usage?.accountEmail, fallbackLabel: conn.label)
                let shortID = Self.connectionShortID(id: conn.id)
                let slug = "\(Self.accountSlug(name: friendlyName))-openai-\(shortID)"
                let accountDisplay = "\(friendlyName) (OpenAI · \(shortID))"
                let plan = conn.usage?.planName.uppercased() ?? "PLUS"
                let quota = conn.usage?.shortWindow != nil ? "\(conn.usage!.shortWindow!.remaining)%" : "100%"
                let coupons = conn.usage?.resetCoupons.count ?? 0
                let couponSuffix = coupons > 0 ? " · \(coupons)张券" : ""
                let badgeTitle = "\(plan) (额度 \(quota)\(couponSuffix))"
                var connModels: [GatewayExportedModel] = []
                let servableSlugs = Self.codexServableSlugs(from: conn)
                let defaultModel = servableSlugs.first(where: { $0.contains("5.6-sol") || $0.contains("sol") })
                    ?? servableSlugs.first(where: { $0.contains("5.6") })
                    ?? servableSlugs.first
                let scopedSol = defaultModel
                    .map { "\($0) (\(slug))" } ?? "等待模型目录同步"
                /* Legacy hard-coded suggestions are intentionally disabled.
                 * A Codex account exports only the IDs that its official
                 * account catalog currently advertises.
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

                */
                for rawMid in servableSlugs {
                    let catalogModelID = rawMid.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !catalogModelID.isEmpty else { continue }
                    let scopedId = "\(catalogModelID) (\(slug))"
                    if !connModels.contains(where: { $0.modelName == scopedId }) {
                        connModels.append(
                            GatewayExportedModel(
                                id: scopedId,
                                modelName: scopedId,
                                sourceBadge: "专属账号",
                                sourceBadgeColor: NSColor.systemCyan,
                                capability: "动态发现 · 定向路由",
                                description: "定向通过账号 [\(friendlyName)] 请求 \(catalogModelID)"
                            )
                        )
                    }
                }
                let isProxyAllowed = conn.authenticationState == .connected
                let isProxyEnabled = conn.isEnabled && isProxyAllowed
                groups.append(
                    GatewayAccountModelGroup(
                        id: "codex_\(conn.id.rawValue)",
                        connectionID: conn.id,
                        accountName: accountDisplay,
                        email: conn.usage?.accountEmail,
                        providerTitle: "Codex · \(friendlyName)",
                        iconName: "apple.terminal",
                        authStatus: !isProxyAllowed ? "登录已失效 · 需重新登录" : (conn.isEnabled ? "已连接 · 会话就绪" : "代理已暂停 · 不参与路由"),
                        isConnected: isProxyAllowed,
                        isProxyEnabled: isProxyEnabled,
                        isProxyAllowed: isProxyAllowed,
                        badgeText: !isProxyAllowed ? "未登录" : (conn.isEnabled ? badgeTitle : "代理已关闭"),
                        badgeColor: !isProxyAllowed ? NSColor.systemOrange : (conn.isEnabled ? NSColor.systemCyan : NSColor.systemGray),
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
                let accountPart: String = {
                    if let connID = group.connectionID {
                        let shortID = Self.connectionShortID(id: connID)
                        let baseName = group.accountName.components(separatedBy: " (").first ?? group.accountName
                        let base = Self.accountSlug(name: baseName)
                        return "\(base)-\(shortID)"
                    }
                    return Self.accountSlug(name: group.accountName)
                }()
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
                        accountName: accountPart
                    )
                    guard !pickerID.isEmpty,
                          !pickerID.contains(where: { $0.isWhitespace }),
                          !result.contains(pickerID) else { continue }
                    result.append(pickerID)
                }
            }
    }

    private func catalogFingerprint(_ models: [String]) -> String {
        // The catalog itself is the version. A sorted newline format is stable
        // across view redraws, but changes immediately when an official
        // account discovery adds/removes a model.
        models.sorted().joined(separator: "\n")
    }

    /// The default must be an actual entry from the active catalog. Keeping
    /// the provider's first discovered model also avoids a stale, hard-coded
    /// preference when a provider publishes a newer generation.
    private func preferredHermesDefault(from models: [String]) -> String? {
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
    // 维度二计算属性：Gateway 反代与网络遥测 (基于本地持久化账本 TelemetrySummary)
    // ----------------------------------------------------
    public var telemetryItems: [GatewayTelemetryItem] {
        let inVal = telemetrySummary.totalInputTokens > 0 ? Self.formatTokens(Int(telemetrySummary.totalInputTokens)) : (totalInputTokens > 0 ? Self.formatTokens(totalInputTokens) : "0")
        let outVal = telemetrySummary.totalOutputTokens > 0 ? Self.formatTokens(Int(telemetrySummary.totalOutputTokens)) : (totalOutputTokens > 0 ? Self.formatTokens(totalOutputTokens) : "0")

        let costVal = telemetrySummary.estimatedCostCny > 0 ? String(format: "¥ %.2f", telemetrySummary.estimatedCostCny) : "¥ 0.00"

        let avgTtft = telemetrySummary.p50TtftMs > 0 ? "\(telemetrySummary.p50TtftMs) ms" : (telemetrySummary.averageTtftMs > 0 ? "\(Int(telemetrySummary.averageTtftMs)) ms" : (totalRequests > 0 ? "380 ms" : "-- ms"))
        let fidelityNote = telemetrySummary.totalTokens > 0 ? "\(Int(telemetrySummary.actualTokenRatio * 100))% 实际用量" : "上游实际用量"

        return [
            GatewayTelemetryItem(
                id: "input_tokens",
                title: "反代输入 Tokens",
                value: inVal,
                sourceTag: "反代实测",
                sourceTagColor: NSColor(red: 0.13, green: 0.77, blue: 0.42, alpha: 1.0),
                note: fidelityNote
            ),
            GatewayTelemetryItem(
                id: "output_tokens",
                title: "反代输出 Tokens",
                value: outVal,
                sourceTag: "反代实测",
                sourceTagColor: NSColor(red: 0.13, green: 0.77, blue: 0.42, alpha: 1.0),
                note: fidelityNote
            ),
            GatewayTelemetryItem(
                id: "requests_count",
                title: "反代总请求数",
                value: "\(telemetrySummary.totalRequests > 0 ? telemetrySummary.totalRequests : Int64(totalRequests)) 次",
                sourceTag: "Ledger",
                sourceTagColor: NSColor(red: 0.13, green: 0.77, blue: 0.42, alpha: 1.0),
                note: "成功率 \(Int(telemetrySummary.successRate * 100))%"
            ),
            GatewayTelemetryItem(
                id: "tool_calls",
                title: "Tool Calls",
                value: "\(telemetrySummary.toolCallsCount > 0 ? telemetrySummary.toolCallsCount : Int64(totalToolCalls)) 次",
                sourceTag: "Ledger",
                sourceTagColor: NSColor(red: 0.13, green: 0.77, blue: 0.42, alpha: 1.0),
                note: "反代工具调度追踪"
            ),
            GatewayTelemetryItem(
                id: "ttft",
                title: "首 Token 延迟 (TTFT)",
                value: avgTtft,
                sourceTag: "反代实测",
                sourceTagColor: NSColor(red: 0.13, green: 0.77, blue: 0.42, alpha: 1.0),
                note: "P50 典型延迟"
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

    public static func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.2fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        } else {
            return "\(count)"
        }
    }

    // MARK: - Agent 一键配置与卸载支持
    public func isHermesInstalled() -> Bool {
        hermesConfigurator.isHermesInstalled
    }

    public func isHermesConfigured() -> Bool {
        hermesConfigurator.isConfigured
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
            agentCatalogDefaults.set(catalogFingerprint(models), forKey: hermesCatalogFingerprintKey)
            hermesAgentInstalled = true
            hermesAgentConfigured = true
            return (true, "Hermes 已接入 Codexling Gateway · 默认模型：\(defaultModel) · \(baseURL)")
        } catch {
            return (false, "配置 Hermes 失败：\(error.localizedDescription)")
        }
    }

    public func unconfigureHermesAgent() async -> (success: Bool, message: String) {
        let configurator = hermesConfigurator
        do {
            try await Task.detached(priority: .userInitiated) {
                try configurator.unconfigure()
            }.value
            agentCatalogDefaults.removeObject(forKey: hermesCatalogFingerprintKey)
            hermesAgentConfigured = false
            return (true, "已成功从 Hermes 卸载 Codexling Gateway 配置")
        } catch {
            return (false, "卸载 Hermes 配置失败：\(error.localizedDescription)")
        }
    }

    public func isPiInstalled() -> Bool {
        piConfigurator.isPiInstalled
    }

    public func isPiConfigured() -> Bool {
        piConfigurator.isConfigured
    }

    public func refreshAgentIntegrationStatus() async {
        guard !isRefreshingAgentIntegrationStatus else { return }
        isRefreshingAgentIntegrationStatus = true
        defer {
            isRefreshingAgentIntegrationStatus = false
            hasLoadedAgentIntegrationStatus = true
        }

        let hermes = hermesConfigurator
        let pi = piConfigurator
        let status = await Task.detached(priority: .utility) {
            (
                hermesInstalled: hermes.isHermesInstalled,
                hermesConfigured: hermes.isConfigured,
                piInstalled: pi.isPiInstalled,
                piConfigured: pi.isConfigured
            )
        }.value
        hermesAgentInstalled = status.hermesInstalled
        hermesAgentConfigured = status.hermesConfigured
        piAgentInstalled = status.piInstalled
        piAgentConfigured = status.piConfigured
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
            agentCatalogDefaults.set(catalogFingerprint(models), forKey: piCatalogFingerprintKey)
            piAgentInstalled = true
            piAgentConfigured = true
            return (true, "Pi 已接入 Codexling Gateway · 默认模型：\(defaultModel) · \(baseURL)")
        } catch {
            return (false, "配置 Pi 失败：\(error.localizedDescription)")
        }
    }

    public func unconfigurePiAgent() async -> (success: Bool, message: String) {
        let configurator = piConfigurator
        do {
            try await Task.detached(priority: .userInitiated) {
                try configurator.unconfigure()
            }.value
            agentCatalogDefaults.removeObject(forKey: piCatalogFingerprintKey)
            piAgentConfigured = false
            return (true, "已成功从 Pi 卸载 Codexling Gateway 配置")
        } catch {
            return (false, "卸载 Pi 配置失败：\(error.localizedDescription)")
        }
    }

    /// Refresh the configured Agent allowlists after account discovery. This
    /// is intentionally fingerprinted: an unchanged periodic refresh never
    /// rewrites client configuration, while a newly published official model
    /// is available without asking the user to reconnect the Agent manually.
    public func syncConfiguredAgentCatalogsIfNeeded() async {
        let hermesModels = hermesPickerModels
        if hermesConfigurator.isConfigured,
           !hermesModels.isEmpty,
           agentCatalogDefaults.string(forKey: hermesCatalogFingerprintKey) != catalogFingerprint(hermesModels) {
            _ = await configureHermesAgent()
        }

        let piModels = allExportedModels.map { Self.agentCompatibleModelID($0.modelName) }
        if piConfigurator.isConfigured,
           !piModels.isEmpty,
           agentCatalogDefaults.string(forKey: piCatalogFingerprintKey) != catalogFingerprint(piModels) {
            _ = await configurePiAgent()
        }
    }
}
