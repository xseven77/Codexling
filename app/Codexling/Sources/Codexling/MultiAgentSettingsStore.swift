import Foundation
import Observation

enum ConnectionCarousel {
    static func nextKey(after selectedKey: String, availableKeys: [String]) -> String? {
        guard availableKeys.count > 1 else { return nil }
        guard let selectedIndex = availableKeys.firstIndex(of: selectedKey) else {
            return availableKeys.first
        }
        return availableKeys[(selectedIndex + 1) % availableKeys.count]
    }
}

enum AccountCarouselPauseSource: Hashable {
    case dashboard
    case dashboardInfo
    case notch(screenNumber: UInt32)
}

@MainActor
@Observable
final class MultiAgentSettingsStore {
    private static let selectedConnectionDefaultsKey = "dashboard.selectedConnection"
    private let hookManager: AgentHookManager
    private let registryStorage: ConnectionRegistryStorage
    private let codexRuntimeManager: CodexAccountRuntimeManager
    private let codexAppServerSupervisor: CodexAppServerSupervisor
    private let credentialStore: any DeepSeekCredentialStoring
    private let deepSeekBalanceService: any DeepSeekBalanceFetching

    private(set) var integrations: [AgentIntegrationStatus] = []
    private(set) var codexAccounts: [CodexAccountConnection] = []
    private(set) var deepSeekConnections: [DeepSeekAPIConnection] = []
    private(set) var connectionOrder: [String] = []
    private(set) var isMutatingConnections = false
    private(set) var isRefreshingConnections = false
    /// 正在单独请求中的连接 id（按账号分开加载：完成一个移除一个）。
    private(set) var refreshingConnectionIDs: Set<ConnectionID> = []
    private(set) var isCodexOAuthInProgress = false
    private(set) var lastMessage: String?
    private(set) var isAccountCarouselPaused = false
    private var accountCarouselPauseSources: Set<AccountCarouselPauseSource> = []
    var onSelectedConnectionChanged: (() -> Void)?
    var onAccountCarouselPauseChanged: ((Bool) -> Void)?
    private var activeCodexOAuthService: CodexUsageService?
    var selectedConnectionKey: String {
        didSet {
            guard selectedConnectionKey != oldValue else { return }
            UserDefaults.standard.set(selectedConnectionKey, forKey: Self.selectedConnectionDefaultsKey)
            onSelectedConnectionChanged?()
        }
    }

    init(
        hookManager: AgentHookManager = AgentHookManager(),
        registryStorage: ConnectionRegistryStorage = ConnectionRegistryStorage(),
        codexRuntimeManager: CodexAccountRuntimeManager = CodexAccountRuntimeManager(),
        codexAppServerSupervisor: CodexAppServerSupervisor = CodexAppServerSupervisor(),
        credentialStore: any DeepSeekCredentialStoring = DeepSeekCredentialStore(),
        deepSeekBalanceService: any DeepSeekBalanceFetching = DeepSeekBalanceService(),
        startsAutomaticRefresh: Bool = true,
        migratesLegacyAccount: Bool = true
    ) {
        self.hookManager = hookManager
        self.registryStorage = registryStorage
        self.codexRuntimeManager = codexRuntimeManager
        self.codexAppServerSupervisor = codexAppServerSupervisor
        self.credentialStore = credentialStore
        self.deepSeekBalanceService = deepSeekBalanceService
        selectedConnectionKey = UserDefaults.standard.string(forKey: Self.selectedConnectionDefaultsKey)
            ?? ""
        let registry = registryStorage.load()
        codexAccounts = registry.codexAccounts
        deepSeekConnections = registry.deepSeekConnections
        if migratesLegacyAccount {
            migrateLegacyCodexAccountIfNeeded()
        }
        connectionOrder = registry.connectionOrder
        refresh()
        validateSelectedConnection()
        if startsAutomaticRefresh {
            Task { await refreshAllConnections() }
        }
    }

    func refresh() {
        integrations = hookManager.integrationStatuses()
    }

    func clearLastMessage() {
        lastMessage = nil
    }

    func selectCodexConnection(_ connection: CodexAccountConnection) {
        selectedConnectionKey = "codex.\(connection.id.rawValue.uuidString.lowercased())"
    }

    func selectDeepSeekConnection(_ connection: DeepSeekAPIConnection) {
        selectedConnectionKey = "deepseek.\(connection.id.rawValue.uuidString.lowercased())"
    }

    func setAccountCarouselPaused(
        _ isPaused: Bool,
        source: AccountCarouselPauseSource = .dashboard
    ) {
        if isPaused {
            accountCarouselPauseSources.insert(source)
        } else {
            accountCarouselPauseSources.remove(source)
        }

        let shouldPause = !accountCarouselPauseSources.isEmpty
        guard isAccountCarouselPaused != shouldPause else { return }
        isAccountCarouselPaused = shouldPause
        onAccountCarouselPauseChanged?(shouldPause)
    }

    func selectNextConnection() {
        let keys = orderedConnectionKeys
        guard let nextKey = ConnectionCarousel.nextKey(
            after: selectedConnectionKey,
            availableKeys: keys
        ) else { return }

        if let account = codexAccounts.first(where: { connectionKey(for: $0) == nextKey }) {
            selectCodexConnection(account)
        } else if let connection = deepSeekConnections.first(where: { connectionKey(for: $0) == nextKey }) {
            selectDeepSeekConnection(connection)
        }
    }

    func isSelected(_ connection: CodexAccountConnection) -> Bool {
        selectedConnectionKey == "codex.\(connection.id.rawValue.uuidString.lowercased())"
    }

    func isSelected(_ connection: DeepSeekAPIConnection) -> Bool {
        selectedConnectionKey == "deepseek.\(connection.id.rawValue.uuidString.lowercased())"
    }

    var selectedCodexAccount: CodexAccountConnection? {
        codexAccounts.first(where: isSelected)
    }

    var selectedDeepSeekConnection: DeepSeekAPIConnection? {
        deepSeekConnections.first(where: isSelected)
    }

    @discardableResult
    func refreshCodexAccounts() async -> RefreshOutcome {
        guard !isRefreshingConnections else {
            return RefreshOutcome(failures: ["连接正在刷新"])
        }
        isRefreshingConnections = true
        defer { isRefreshingConnections = false }

        refreshingConnectionIDs.formUnion(codexAccounts.map(\.id))
        var outcome = RefreshOutcome()
        for connection in codexAccounts {
            outcome.merge(await refreshCodexAccountWithoutLock(connection))
            refreshingConnectionIDs.remove(connection.id)
        }
        return outcome
    }

    /// Shared refresh entry point for the timer and every manual refresh
    /// surface. New connection types should be added here so there is only one
    /// scheduling policy for all accounts and API keys.
    ///
    /// 每个供应商独立并发请求、各自完成后立即生效（互不等待），最后合并成统一结果。
    @discardableResult
    func refreshAllConnections() async -> RefreshOutcome {
        guard !isRefreshingConnections, !isMutatingConnections else {
            return RefreshOutcome(failures: ["连接正在刷新"])
        }
        isRefreshingConnections = true
        defer { isRefreshingConnections = false }

        let codexAccounts = self.codexAccounts
        let deepSeekConnections = self.deepSeekConnections
        // 先登记全部账号为「加载中」，各自完成后逐个移除，
        // 让界面可以按账号单独展示加载 / 完成状态。
        refreshingConnectionIDs.formUnion(codexAccounts.map(\.id))
        refreshingConnectionIDs.formUnion(deepSeekConnections.map(\.id))

        var tasks: [Task<RefreshOutcome, Never>] = []
        for connection in codexAccounts {
            tasks.append(Task { @MainActor [weak self] in
                let outcome = await self?.refreshCodexAccountWithoutLock(connection) ?? RefreshOutcome()
                self?.refreshingConnectionIDs.remove(connection.id)
                return outcome
            })
        }
        for connection in deepSeekConnections {
            tasks.append(Task { @MainActor [weak self] in
                let outcome = await self?.refreshDeepSeekConnectionWithoutLock(connection, publishesMessage: false)
                    ?? RefreshOutcome()
                self?.refreshingConnectionIDs.remove(connection.id)
                return outcome
            })
        }

        var outcome = RefreshOutcome()
        for task in tasks {
            outcome.merge(await task.value)
        }
        return outcome
    }

    /// 抓取单个 Codex 账号的额度结果（纯抓取，不修改状态）。
    private func fetchCodexAccountResult(_ connection: CodexAccountConnection) async -> CodexAccountRefreshResult {
        let manager = codexRuntimeManager
        let supervisor = codexAppServerSupervisor

        guard connection.isEnabled else {
            return CodexAccountRefreshResult(id: connection.id, state: .needsLogin, usage: nil)
        }
        let tokenStore: CodexOAuthTokenStore
        do {
            tokenStore = CodexOAuthTokenStore(fileURL: try manager.oauthTokenURL(for: connection))
        } catch {
            return CodexAccountRefreshResult(id: connection.id, state: .needsLogin, usage: nil)
        }

        if tokenStore.hasStoredToken() {
            do {
                let snapshot = try await CodexUsageService(tokenStore: tokenStore).fetchWithStoredToken()
                return CodexAccountRefreshResult(id: connection.id, state: .connected, usage: snapshot)
            } catch let codexError as CodexUsageError where codexError == .noStoredToken || codexError == .invalidTokenResponse {
                // 令牌缺失或已失效 → 需要重新登录。
                return CodexAccountRefreshResult(id: connection.id, state: .needsLogin, usage: nil)
            } catch CodexUsageError.quotaUnavailable {
                // 令牌有效但额度接口暂不可用 → 保持「已连接」，仅保留旧额度。
                return CodexAccountRefreshResult(id: connection.id, state: .connected, usage: connection.usage)
            } catch {
                // 网络抖动等瞬时错误 → 不降级，保留原状态。
                return CodexAccountRefreshResult(id: connection.id, state: connection.authenticationState, usage: connection.usage)
            }
        }

        // 没有本地 OAuth token → 回退到 CLI `codex login` 状态。
        let state = manager.authenticationState(for: connection)
        guard state == .connected else {
            return CodexAccountRefreshResult(id: connection.id, state: state, usage: nil)
        }
        do {
            let usage = try supervisor.snapshot(
                for: connection,
                homeURL: manager.homeURL(for: connection),
                executableURL: manager.locateCodexExecutable()
            )
            return CodexAccountRefreshResult(id: connection.id, state: .connected, usage: codexUsage(from: usage))
        } catch {
            return CodexAccountRefreshResult(id: connection.id, state: state, usage: nil)
        }
    }

    /// 应用单个账号的刷新结果（立即生效）并返回其刷新结果。
    private func applyCodexAccountResult(
        _ result: CodexAccountRefreshResult,
        for connection: CodexAccountConnection
    ) -> RefreshOutcome {
        var changed = false
        if let index = codexAccounts.firstIndex(where: { $0.id == result.id }) {
            if codexAccounts[index].authenticationState != result.state {
                codexAccounts[index].authenticationState = result.state
                changed = true
            }
            if let usage = result.usage, codexAccounts[index].usage != usage {
                codexAccounts[index].usage = usage
                changed = true
            }
        }
        if changed { try? saveRegistry() }

        guard connection.isEnabled else { return RefreshOutcome() }
        if result.state == .connected, result.usage != nil {
            return RefreshOutcome(successCount: 1)
        } else {
            return RefreshOutcome(failures: ["\(connection.label) 未能刷新"])
        }
    }

    private func refreshCodexAccountWithoutLock(_ connection: CodexAccountConnection) async -> RefreshOutcome {
        let result = await fetchCodexAccountResult(connection)
        return applyCodexAccountResult(result, for: connection)
    }

    func stopCodexAppServers() {
        codexAppServerSupervisor.stopAll()
    }

    func cancelCurrentCodexOAuth() {
        guard isCodexOAuthInProgress, let service = activeCodexOAuthService else { return }
        lastMessage = "正在取消 Codex 登录…"
        Task { await service.cancelOAuthAuthorization() }
    }

    func addCodexAccount() async -> Bool {
        guard !isMutatingConnections else { return false }
        isMutatingConnections = true
        defer { isMutatingConnections = false }
        var pendingConnection: CodexAccountConnection?
        var pendingTokenStore: CodexOAuthTokenStore?
        do {
            let fallback = "Codex 账号 \(codexAccounts.count + 1)"
            var connection = try codexRuntimeManager.createAccount(label: fallback)
            pendingConnection = connection
            let tokenStore = CodexOAuthTokenStore(
                fileURL: try codexRuntimeManager.oauthTokenURL(for: connection)
            )
            pendingTokenStore = tokenStore
            let service = CodexUsageService(tokenStore: tokenStore)
            activeCodexOAuthService = service
            isCodexOAuthInProgress = true
            defer {
                activeCodexOAuthService = nil
                isCodexOAuthInProgress = false
            }
            let snapshot = try await service.connectAndFetch(forceLogin: true)
            connection.label = normalizedLabel(
                snapshot.accountName ?? snapshot.accountEmail,
                fallback: fallback
            )
            connection.authenticationState = .connected
            connection.usage = snapshot
            codexAccounts.append(connection)
            try saveRegistry()
            selectCodexConnection(connection)
            lastMessage = "已登录并保存 \(connection.label)"
            return true
        } catch {
            // OAuth 已成功落盘 token，只是额度抓取失败（如请求超时）→ 仍视为已登录。
            if let pendingConnection,
               let tokenStore = pendingTokenStore,
               tokenStore.hasStoredToken() {
                var connection = pendingConnection
                connection.authenticationState = .connected
                connection.usage = nil
                codexAccounts.append(connection)
                try? saveRegistry()
                selectCodexConnection(connection)
                lastMessage = "已登录，额度获取失败：\(error.localizedDescription)"
                return true
            }
            if let pendingConnection {
                try? codexRuntimeManager.removeRuntime(for: pendingConnection)
            }
            if error as? CodexUsageError == .oauthCancelled || error is CancellationError {
                lastMessage = "已取消 Codex 登录"
            } else {
                lastMessage = "Codex 登录失败：\(error.localizedDescription)"
            }
            return false
        }
    }

    func authenticateCodexAccount(_ connection: CodexAccountConnection) async -> Bool {
        guard !isMutatingConnections else { return false }
        isMutatingConnections = true
        defer { isMutatingConnections = false }
        do {
            let tokenStore = CodexOAuthTokenStore(
                fileURL: try codexRuntimeManager.oauthTokenURL(for: connection)
            )
            let service = CodexUsageService(tokenStore: tokenStore)
            activeCodexOAuthService = service
            isCodexOAuthInProgress = true
            defer {
                activeCodexOAuthService = nil
                isCodexOAuthInProgress = false
            }
            let snapshot = try await service.connectAndFetch(forceLogin: true)
            guard let index = codexAccounts.firstIndex(where: { $0.id == connection.id }) else {
                return false
            }
            codexAccounts[index].label = normalizedLabel(
                snapshot.accountName ?? snapshot.accountEmail,
                fallback: connection.label
            )
            codexAccounts[index].authenticationState = .connected
            codexAccounts[index].usage = snapshot
            try saveRegistry()
            lastMessage = "已登录并更新 \(codexAccounts[index].label)"
            return true
        } catch {
            if error as? CodexUsageError == .oauthCancelled || error is CancellationError {
                lastMessage = "已取消 Codex 登录"
            } else {
                lastMessage = "Codex 登录失败：\(error.localizedDescription)"
            }
            return false
        }
    }

    func removeCodexAccount(_ connection: CodexAccountConnection) {
        guard !isMutatingConnections else { return }
        isMutatingConnections = true
        defer { isMutatingConnections = false }
        do {
            try codexRuntimeManager.removeRuntime(for: connection)
            codexAppServerSupervisor.remove(connectionID: connection.id)
            codexAccounts.removeAll { $0.id == connection.id }
            connectionOrder.removeAll { $0 == connectionKey(for: connection) }
            validateSelectedConnection()
            try saveRegistry()
            lastMessage = "已移除 \(connection.label) 的独立运行目录"
        } catch {
            lastMessage = "移除失败：\(error.localizedDescription)"
        }
    }

    /// Disconnect the selected connection without privileging any provider.
    /// Codex credentials are cleared while the connection record remains so it
    /// can be authenticated again; API-key connections are removed entirely.
    func disconnectSelectedConnection() {
        if let account = selectedCodexAccount {
            do {
                let tokenStore = CodexOAuthTokenStore(
                    fileURL: try codexRuntimeManager.oauthTokenURL(for: account)
                )
                tokenStore.clear()
                if let index = codexAccounts.firstIndex(where: { $0.id == account.id }) {
                    codexAccounts[index].authenticationState = .needsLogin
                    codexAccounts[index].usage = nil
                }
                try saveRegistry()
                lastMessage = "已退出 (account.label)"
            } catch {
                lastMessage = "退出失败：\(error.localizedDescription)"
            }
        } else if let connection = selectedDeepSeekConnection {
            removeDeepSeekConnection(connection)
        }
    }

    func addDeepSeekConnection(label: String, apiKey: String) async -> Bool {
        guard !isMutatingConnections else { return false }
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedKey.count >= 12 else {
            lastMessage = "DeepSeek API Key 格式不正确"
            return false
        }

        isMutatingConnections = true
        defer { isMutatingConnections = false }
        let id = ConnectionID(rawValue: UUID())
        let handle = id.rawValue.uuidString.lowercased()
        do {
            try credentialStore.save(apiKey: trimmedKey, handle: handle)
            let balance = try await deepSeekBalanceService.fetch(apiKey: trimmedKey, connectionID: id)
            let connection = DeepSeekAPIConnection(
                id: id,
                label: normalizedLabel(label, fallback: "DeepSeek Key \(deepSeekConnections.count + 1)"),
                credentialHandle: handle,
                keySuffix: String(trimmedKey.suffix(4)),
                authenticationState: .connected,
                balance: balance,
                createdAt: Date()
            )
            deepSeekConnections.append(connection)
            selectDeepSeekConnection(connection)
            try saveRegistry()
            lastMessage = "DeepSeek Key 已验证并安全保存"
            return true
        } catch {
            try? credentialStore.delete(handle: handle)
            lastMessage = "DeepSeek Key 验证失败：\(error.localizedDescription)"
            return false
        }
    }

    func refreshDeepSeekConnection(_ connection: DeepSeekAPIConnection) async {
        guard !isRefreshingConnections, !isMutatingConnections else { return }
        isRefreshingConnections = true
        defer { isRefreshingConnections = false }
        refreshingConnectionIDs.insert(connection.id)
        _ = await refreshDeepSeekConnectionWithoutLock(connection, publishesMessage: true)
        refreshingConnectionIDs.remove(connection.id)
    }

    private func refreshDeepSeekConnectionWithoutLock(
        _ connection: DeepSeekAPIConnection,
        publishesMessage: Bool
    ) async -> RefreshOutcome {
        do {
            let key = try credentialStore.read(handle: connection.credentialHandle)
            let balance = try await deepSeekBalanceService.fetch(apiKey: key, connectionID: connection.id)
            guard let index = deepSeekConnections.firstIndex(where: { $0.id == connection.id }) else {
                return RefreshOutcome(failures: ["\(connection.label)：连接已不存在"])
            }
            deepSeekConnections[index].balance = balance
            deepSeekConnections[index].authenticationState = .connected
            try saveRegistry()
            if publishesMessage { lastMessage = "\(connection.label) 余额已刷新" }
            return RefreshOutcome(successCount: 1)
        } catch DeepSeekCredentialError.interactionRequired {
            // Never let a scheduled refresh summon a system password dialog.
            // Keep the last successful balance visible until the user replaces
            // the credential under the current stable application signature.
            let message = "\(connection.label)：此 Key 需要重新保存，已保留上次余额"
            if publishesMessage { lastMessage = message }
            return RefreshOutcome(failures: [message])
        } catch {
            if let index = deepSeekConnections.firstIndex(where: { $0.id == connection.id }) {
                deepSeekConnections[index].authenticationState = .invalid
                try? saveRegistry()
            }
            let message = "\(connection.label)：\(error.localizedDescription)"
            if publishesMessage { lastMessage = "刷新失败：\(error.localizedDescription)" }
            return RefreshOutcome(failures: [message])
        }
    }

    func removeDeepSeekConnection(_ connection: DeepSeekAPIConnection) {
        guard !isMutatingConnections else { return }
        isMutatingConnections = true
        defer { isMutatingConnections = false }
        do {
            try credentialStore.delete(handle: connection.credentialHandle)
            deepSeekConnections.removeAll { $0.id == connection.id }
            connectionOrder.removeAll { $0 == connectionKey(for: connection) }
            validateSelectedConnection()
            try saveRegistry()
            lastMessage = "已从 Keychain 移除 \(connection.label)"
        } catch {
            lastMessage = "移除失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Connection Ordering and Selection

    func connectionKey(for account: CodexAccountConnection) -> String {
        "codex.\(account.id.rawValue.uuidString.lowercased())"
    }

    func connectionKey(for connection: DeepSeekAPIConnection) -> String {
        "deepseek.\(connection.id.rawValue.uuidString.lowercased())"
    }

    /// 已保存的顺序优先；新连接追加到末尾，已删除或重复的 key 会被忽略。
    var orderedConnectionKeys: [String] {
        var seen: Set<String> = []
        var result = connectionOrder.filter { key in
            connectionExists(key) && seen.insert(key).inserted
        }

        func appendIfNeeded(_ key: String) {
            guard connectionExists(key), seen.insert(key).inserted else { return }
            result.append(key)
        }

        codexAccounts.forEach { appendIfNeeded(connectionKey(for: $0)) }
        deepSeekConnections.forEach { appendIfNeeded(connectionKey(for: $0)) }
        return result
    }

    func moveConnection(fromOffsets source: IndexSet, toOffset destination: Int) {
        var keys = orderedConnectionKeys
        keys.move(fromOffsets: source, toOffset: destination)
        connectionOrder = keys
        persistConnectionOrder()
    }

    /// 只重排当前界面可见的连接，同时保持隐藏连接在完整顺序中的相对位置。
    func moveConnection(key: String, to targetIndex: Int, among visibleKeys: [String]) {
        var reorderedVisibleKeys = visibleKeys.filter(connectionExists)
        guard let sourceIndex = reorderedVisibleKeys.firstIndex(of: key),
              reorderedVisibleKeys.indices.contains(targetIndex),
              sourceIndex != targetIndex
        else { return }

        let movedKey = reorderedVisibleKeys.remove(at: sourceIndex)
        reorderedVisibleKeys.insert(movedKey, at: targetIndex)
        let visibleKeySet = Set(reorderedVisibleKeys)
        var iterator = reorderedVisibleKeys.makeIterator()
        connectionOrder = orderedConnectionKeys.map { existingKey in
            visibleKeySet.contains(existingKey) ? (iterator.next() ?? existingKey) : existingKey
        }
        persistConnectionOrder()
    }

    private func persistConnectionOrder() {
        do {
            try saveRegistry()
        } catch {
            NSLog("Codexling persist connection order failed: %@", error.localizedDescription)
        }
    }

    func selectConnection(key: String) {
        guard connectionExists(key) else { return }
        selectedConnectionKey = key
    }

    // MARK: - 单账号加载状态

    func isRefreshingConnection(_ connection: DeepSeekAPIConnection) -> Bool {
        refreshingConnectionIDs.contains(connection.id)
    }

    func isRefreshingConnection(_ connection: CodexAccountConnection) -> Bool {
        refreshingConnectionIDs.contains(connection.id)
    }

    private func connectionExists(_ key: String) -> Bool {
        if key.hasPrefix("codex."),
           let uuid = UUID(uuidString: String(key.dropFirst("codex.".count))) {
            return codexAccounts.contains { $0.id.rawValue == uuid }
        }
        if key.hasPrefix("deepseek."),
           let uuid = UUID(uuidString: String(key.dropFirst("deepseek.".count))) {
            return deepSeekConnections.contains { $0.id.rawValue == uuid }
        }
        return false
    }

    // MARK: - Helpers

    private func displayName(for agentID: AgentID) -> String {
        BuiltInAgentCatalog.prioritized.first(where: { $0.id == agentID })?.displayName ?? "Agent"
    }

    private func saveRegistry() throws {
        try registryStorage.save(ConnectionRegistrySnapshot(
            codexAccounts: codexAccounts,
            deepSeekConnections: deepSeekConnections,
            connectionOrder: orderedConnectionKeys
        ))
    }

    private func normalizedLabel(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : String(trimmed.prefix(60))
    }

    /// 把 CLI 回退路径返回的精简快照转成与主流程一致的全量快照。
    private func codexUsage(from usage: CodexAccountUsageSnapshot) -> CodexUsageSnapshot {
        CodexUsageSnapshot(
            accountName: nil,
            accountEmail: usage.email ?? "",
            workspaceName: "",
            planName: usage.planType ?? "",
            shortWindow: usage.primary.map { usageWindow(from: $0, fallbackLabel: "5 小时") },
            weekly: usage.secondary.map { usageWindow(from: $0, fallbackLabel: "周额度") }
                ?? UsageWindow(label: "周额度", remaining: 0, total: 0, resetsAt: "未知"),
            credits: CreditBalance(balance: 0, expiresAt: "未知"),
            resetCoupons: usage.resetCoupons,
            fetchedAt: usage.fetchedAt,
            refreshState: "成功",
            sourceURL: "",
            subscriptionActiveUntilISO: usage.subscriptionActiveUntilISO,
            subscriptionWillRenew: usage.subscriptionWillRenew
        )
    }

    private func usageWindow(from window: CodexAccountRateLimitWindow, fallbackLabel: String) -> UsageWindow {
        let label: String
        if let minutes = window.windowDurationMinutes {
            if minutes >= 24 * 60 { label = "周额度" }
            else if minutes >= 60 { label = "\(minutes / 60) 小时" }
            else { label = "\(minutes) 分钟" }
        } else {
            label = fallbackLabel
        }
        return UsageWindow(
            label: label,
            remaining: window.remainingPercent,
            total: 100,
            resetsAt: window.resetsAt.map { UsageDateFormat.display($0) } ?? "未知"
        )
    }

    private func validateSelectedConnection() {
        let valid = codexAccounts.contains(where: isSelected)
            || deepSeekConnections.contains(where: isSelected)
        if !valid { selectedConnectionKey = orderedConnectionKeys.first ?? "" }
    }

    /// Migrate the legacy single-account token into the same per-connection
    /// directory used by every other Codex account. The old global token is
    /// never treated as a special runtime after this point.
    private func migrateLegacyCodexAccountIfNeeded() {
        guard let token = CodexOAuthTokenStore().load() else { return }
        do {
            let fallback = normalizedLabel(
                token.displayName ?? token.email ?? "Codex 账号",
                fallback: "Codex 账号 1"
            )
            let connection = try codexRuntimeManager.createAccount(label: fallback)
            let scopedStore = CodexOAuthTokenStore(
                fileURL: try codexRuntimeManager.oauthTokenURL(for: connection)
            )
            scopedStore.save(token)
            var migrated = connection
            migrated.authenticationState = .connected
            migrated.usage = UsageSnapshotCache().load()
            codexAccounts.append(migrated)
            CodexOAuthTokenStore().clear()
            try? saveRegistry()
            selectedConnectionKey = connectionKey(for: migrated)
        } catch {
            NSLog("Codexling legacy Codex account migration failed: %@", error.localizedDescription)
        }
    }
}

private struct CodexAccountRefreshResult: Sendable {
    let id: ConnectionID
    let state: ConnectionAuthenticationState
    let usage: CodexUsageSnapshot?
}
