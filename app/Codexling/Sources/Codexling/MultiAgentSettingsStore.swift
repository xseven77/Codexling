import Foundation
import Observation

@MainActor
@Observable
final class MultiAgentSettingsStore {
    static let currentCodexConnectionKey = "codex.current"
    private static let selectedConnectionDefaultsKey = "dashboard.selectedConnection"
    private let hookManager: AgentHookManager
    private let registryStorage: ConnectionRegistryStorage
    private let codexRuntimeManager: CodexAccountRuntimeManager
    private let codexAppServerSupervisor: CodexAppServerSupervisor
    private let credentialStore: any DeepSeekCredentialStoring
    private let deepSeekBalanceService: DeepSeekBalanceService

    private(set) var integrations: [AgentIntegrationStatus] = []
    private(set) var mutatingAgentIDs: Set<AgentID> = []
    private(set) var codexAccounts: [CodexAccountConnection] = []
    private(set) var deepSeekConnections: [DeepSeekAPIConnection] = []
    private(set) var isMutatingConnections = false
    private(set) var isCodexOAuthInProgress = false
    private(set) var lastMessage: String?
    private var activeCodexOAuthService: CodexUsageService?
    var selectedConnectionKey: String {
        didSet { UserDefaults.standard.set(selectedConnectionKey, forKey: Self.selectedConnectionDefaultsKey) }
    }

    init(
        hookManager: AgentHookManager = AgentHookManager(),
        registryStorage: ConnectionRegistryStorage = ConnectionRegistryStorage(),
        codexRuntimeManager: CodexAccountRuntimeManager = CodexAccountRuntimeManager(),
        codexAppServerSupervisor: CodexAppServerSupervisor = CodexAppServerSupervisor(),
        credentialStore: any DeepSeekCredentialStoring = DeepSeekCredentialStore(),
        deepSeekBalanceService: DeepSeekBalanceService = DeepSeekBalanceService()
    ) {
        self.hookManager = hookManager
        self.registryStorage = registryStorage
        self.codexRuntimeManager = codexRuntimeManager
        self.codexAppServerSupervisor = codexAppServerSupervisor
        self.credentialStore = credentialStore
        self.deepSeekBalanceService = deepSeekBalanceService
        selectedConnectionKey = UserDefaults.standard.string(forKey: Self.selectedConnectionDefaultsKey)
            ?? Self.currentCodexConnectionKey
        let registry = registryStorage.load()
        codexAccounts = registry.codexAccounts
        deepSeekConnections = registry.deepSeekConnections
        refresh()
        validateSelectedConnection()
        Task { await refreshCodexAccounts() }
    }

    func refresh() {
        integrations = hookManager.integrationStatuses()
    }

    func isMutating(_ agentID: AgentID) -> Bool {
        mutatingAgentIDs.contains(agentID)
    }

    func installHook(for agentID: AgentID) {
        guard agentID != .codex else {
            lastMessage = "Codex 由 Codexling 内置适配，无需安装 Hook"
            return
        }
        guard !mutatingAgentIDs.contains(agentID) else { return }
        mutatingAgentIDs.insert(agentID)
        defer { mutatingAgentIDs.remove(agentID) }
        do {
            try hookManager.installHook(for: agentID)
            lastMessage = "\(displayName(for: agentID)) Hook 已安装"
        } catch {
            lastMessage = "安装失败：\(error.localizedDescription)"
        }
        refresh()
    }

    func uninstallHook(for agentID: AgentID) {
        guard agentID != .codex else {
            lastMessage = "Codex 内置适配无需卸载"
            return
        }
        guard !mutatingAgentIDs.contains(agentID) else { return }
        mutatingAgentIDs.insert(agentID)
        defer { mutatingAgentIDs.remove(agentID) }
        do {
            try hookManager.uninstallHook(for: agentID)
            lastMessage = "\(displayName(for: agentID)) Hook 已卸载"
        } catch {
            lastMessage = "卸载失败：\(error.localizedDescription)"
        }
        refresh()
    }

    func clearLastMessage() {
        lastMessage = nil
    }

    func selectCurrentCodexConnection() {
        selectedConnectionKey = Self.currentCodexConnectionKey
    }

    func selectCodexConnection(_ connection: CodexAccountConnection) {
        selectedConnectionKey = "codex.\(connection.id.rawValue.uuidString.lowercased())"
    }

    func selectDeepSeekConnection(_ connection: DeepSeekAPIConnection) {
        selectedConnectionKey = "deepseek.\(connection.id.rawValue.uuidString.lowercased())"
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

    func refreshCodexAccounts() async {
        let manager = codexRuntimeManager
        let supervisor = codexAppServerSupervisor
        let accounts = codexAccounts
        var results: [CodexAccountRefreshResult] = []
        for connection in accounts {
            guard connection.isEnabled else {
                results.append(CodexAccountRefreshResult(id: connection.id, state: .needsLogin, usage: nil))
                continue
            }
            do {
                let tokenStore = CodexOAuthTokenStore(fileURL: try manager.oauthTokenURL(for: connection))
                if tokenStore.hasStoredToken() {
                    let snapshot = try await CodexUsageService(tokenStore: tokenStore).fetchWithStoredToken()
                    results.append(CodexAccountRefreshResult(
                        id: connection.id,
                        state: .connected,
                        usage: codexAccountUsage(from: snapshot)
                    ))
                    continue
                }
            } catch {
                results.append(CodexAccountRefreshResult(id: connection.id, state: .needsLogin, usage: nil))
                continue
            }

            let state = manager.authenticationState(for: connection)
            guard state == .connected else {
                results.append(CodexAccountRefreshResult(id: connection.id, state: state, usage: nil))
                continue
            }
            do {
                let usage = try supervisor.snapshot(
                    for: connection,
                    homeURL: manager.homeURL(for: connection),
                    executableURL: manager.locateCodexExecutable()
                )
                results.append(CodexAccountRefreshResult(id: connection.id, state: .connected, usage: usage))
            } catch {
                results.append(CodexAccountRefreshResult(id: connection.id, state: state, usage: nil))
            }
        }
        var changed = false
        for result in results {
            guard let index = codexAccounts.firstIndex(where: { $0.id == result.id }) else { continue }
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
        do {
            let fallback = "Codex 账号 \(codexAccounts.count + 1)"
            var connection = try codexRuntimeManager.createAccount(label: fallback)
            pendingConnection = connection
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
            connection.label = normalizedLabel(
                snapshot.accountName ?? snapshot.accountEmail,
                fallback: fallback
            )
            connection.authenticationState = .connected
            connection.usage = codexAccountUsage(from: snapshot)
            codexAccounts.append(connection)
            try saveRegistry()
            selectCodexConnection(connection)
            lastMessage = "已登录并保存 \(connection.label)"
            return true
        } catch {
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
            codexAccounts[index].usage = codexAccountUsage(from: snapshot)
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
            validateSelectedConnection()
            try saveRegistry()
            lastMessage = "已移除 \(connection.label) 的独立运行目录"
        } catch {
            lastMessage = "移除失败：\(error.localizedDescription)"
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
        guard !isMutatingConnections else { return }
        isMutatingConnections = true
        defer { isMutatingConnections = false }
        do {
            let key = try credentialStore.read(handle: connection.credentialHandle)
            let balance = try await deepSeekBalanceService.fetch(apiKey: key, connectionID: connection.id)
            guard let index = deepSeekConnections.firstIndex(where: { $0.id == connection.id }) else { return }
            deepSeekConnections[index].balance = balance
            deepSeekConnections[index].authenticationState = .connected
            try saveRegistry()
            lastMessage = "\(connection.label) 余额已刷新"
        } catch {
            if let index = deepSeekConnections.firstIndex(where: { $0.id == connection.id }) {
                deepSeekConnections[index].authenticationState = .invalid
                try? saveRegistry()
            }
            lastMessage = "刷新失败：\(error.localizedDescription)"
        }
    }

    func removeDeepSeekConnection(_ connection: DeepSeekAPIConnection) {
        guard !isMutatingConnections else { return }
        isMutatingConnections = true
        defer { isMutatingConnections = false }
        do {
            try credentialStore.delete(handle: connection.credentialHandle)
            deepSeekConnections.removeAll { $0.id == connection.id }
            validateSelectedConnection()
            try saveRegistry()
            lastMessage = "已从 Keychain 移除 \(connection.label)"
        } catch {
            lastMessage = "移除失败：\(error.localizedDescription)"
        }
    }

    private func displayName(for agentID: AgentID) -> String {
        BuiltInAgentCatalog.prioritized.first(where: { $0.id == agentID })?.displayName ?? "Agent"
    }

    private func saveRegistry() throws {
        try registryStorage.save(ConnectionRegistrySnapshot(
            codexAccounts: codexAccounts,
            deepSeekConnections: deepSeekConnections
        ))
    }

    private func normalizedLabel(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : String(trimmed.prefix(60))
    }

    private func codexAccountUsage(from snapshot: CodexUsageSnapshot) -> CodexAccountUsageSnapshot {
        CodexAccountUsageSnapshot(
            email: snapshot.accountEmail,
            planType: snapshot.planName,
            primary: snapshot.shortWindow.map(codexRateLimitWindow),
            secondary: snapshot.hasWeeklyWindow ? codexRateLimitWindow(snapshot.weekly) : nil,
            fetchedAt: snapshot.fetchedAt
        )
    }

    private func codexRateLimitWindow(_ window: UsageWindow) -> CodexAccountRateLimitWindow {
        CodexAccountRateLimitWindow(
            usedPercent: 100 - Int((window.percent * 100).rounded()),
            resetsAt: UsageDateFormat.parseISO8601(window.resetsAt),
            windowDurationMinutes: nil
        )
    }

    private func validateSelectedConnection() {
        let valid = selectedConnectionKey == Self.currentCodexConnectionKey
            || codexAccounts.contains(where: isSelected)
            || deepSeekConnections.contains(where: isSelected)
        if !valid { selectedConnectionKey = Self.currentCodexConnectionKey }
    }
}

private struct CodexAccountRefreshResult: Sendable {
    let id: ConnectionID
    let state: ConnectionAuthenticationState
    let usage: CodexAccountUsageSnapshot?
}
