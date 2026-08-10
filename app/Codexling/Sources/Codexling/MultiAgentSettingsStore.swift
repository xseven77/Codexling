import Foundation
import Observation

@MainActor
@Observable
final class MultiAgentSettingsStore {
    private let hookManager: AgentHookManager
    private let registryStorage: ConnectionRegistryStorage
    private let codexRuntimeManager: CodexAccountRuntimeManager
    private let credentialStore: any DeepSeekCredentialStoring
    private let deepSeekBalanceService: DeepSeekBalanceService

    private(set) var integrations: [AgentIntegrationStatus] = []
    private(set) var mutatingAgentIDs: Set<AgentID> = []
    private(set) var codexAccounts: [CodexAccountConnection] = []
    private(set) var deepSeekConnections: [DeepSeekAPIConnection] = []
    private(set) var isMutatingConnections = false
    private(set) var lastMessage: String?

    init(
        hookManager: AgentHookManager = AgentHookManager(),
        registryStorage: ConnectionRegistryStorage = ConnectionRegistryStorage(),
        codexRuntimeManager: CodexAccountRuntimeManager = CodexAccountRuntimeManager(),
        credentialStore: any DeepSeekCredentialStoring = DeepSeekCredentialStore(),
        deepSeekBalanceService: DeepSeekBalanceService = DeepSeekBalanceService()
    ) {
        self.hookManager = hookManager
        self.registryStorage = registryStorage
        self.codexRuntimeManager = codexRuntimeManager
        self.credentialStore = credentialStore
        self.deepSeekBalanceService = deepSeekBalanceService
        let registry = registryStorage.load()
        codexAccounts = registry.codexAccounts
        deepSeekConnections = registry.deepSeekConnections
        refresh()
    }

    func refresh() {
        integrations = hookManager.integrationStatuses()
    }

    func isMutating(_ agentID: AgentID) -> Bool {
        mutatingAgentIDs.contains(agentID)
    }

    func installHook(for agentID: AgentID) {
        guard !mutatingAgentIDs.contains(agentID) else { return }
        mutatingAgentIDs.insert(agentID)
        defer { mutatingAgentIDs.remove(agentID) }
        do {
            try hookManager.installHook(for: agentID)
            lastMessage = agentID == .codex
                ? "Codex Hook 已安装；请在 Codex /hooks 中审阅并信任"
                : "\(displayName(for: agentID)) Hook 已安装"
        } catch {
            lastMessage = "安装失败：\(error.localizedDescription)"
        }
        refresh()
    }

    func uninstallHook(for agentID: AgentID) {
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

    func addCodexAccount(label: String) {
        guard !isMutatingConnections else { return }
        isMutatingConnections = true
        defer { isMutatingConnections = false }
        do {
            let fallback = "Codex 账号 \(codexAccounts.count + 1)"
            let connection = try codexRuntimeManager.createAccount(
                label: normalizedLabel(label, fallback: fallback)
            )
            codexAccounts.append(connection)
            try saveRegistry()
            try codexRuntimeManager.launchLogin(for: connection)
            lastMessage = "已创建 \(connection.label)，正在打开官方 codex login"
        } catch {
            lastMessage = "添加 Codex 账号失败：\(error.localizedDescription)"
        }
    }

    func launchCodexLogin(for connection: CodexAccountConnection) {
        do {
            try codexRuntimeManager.launchLogin(for: connection)
            lastMessage = "正在打开 \(connection.label) 的官方登录"
        } catch {
            lastMessage = "无法启动登录：\(error.localizedDescription)"
        }
    }

    func removeCodexAccount(_ connection: CodexAccountConnection) {
        guard !isMutatingConnections else { return }
        isMutatingConnections = true
        defer { isMutatingConnections = false }
        do {
            try codexRuntimeManager.removeRuntime(for: connection)
            codexAccounts.removeAll { $0.id == connection.id }
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
}
