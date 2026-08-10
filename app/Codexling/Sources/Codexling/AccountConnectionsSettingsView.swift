import SwiftUI

private enum AddConnectionSheet: String, Identifiable {
    case codex
    case deepSeek

    var id: String { rawValue }
}

private struct PendingConnectionRemoval: Identifiable {
    enum Target {
        case codex(CodexAccountConnection)
        case deepSeek(DeepSeekAPIConnection)
    }

    let id = UUID()
    let target: Target
}

struct AccountConnectionsSettingsView: View {
    @Bindable var store: MultiAgentSettingsStore
    @State private var addSheet: AddConnectionSheet?
    @State private var pendingRemoval: PendingConnectionRemoval?

    var body: some View {
        SettingsSection(
            title: "账号与 API Keys",
            subtitle: "每个 Codex 账号使用独立 CODEX_HOME；DeepSeek Key 只存入 Keychain，余额按官方账户口径显示。"
        ) {
            VStack(spacing: 0) {
                connectionActions
                if !store.codexAccounts.isEmpty || !store.deepSeekConnections.isEmpty {
                    CodexDivider()
                    connectionRows
                }
            }
            .settingsGroupSurface()
        }
        .sheet(item: $addSheet) { sheet in
            switch sheet {
            case .codex:
                AddCodexAccountSheet(store: store) { addSheet = nil }
            case .deepSeek:
                AddDeepSeekKeySheet(store: store) { addSheet = nil }
            }
        }
        .alert(item: $pendingRemoval) { pending in
            removalAlert(pending)
        }
    }

    private var connectionActions: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("新增连接")
                    .font(.system(size: 12, weight: .semibold))
                Text("登录由官方 CLI 完成；Codexling 不读取或复制 token")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.codexMuted)
            }
            Spacer(minLength: 8)
            Button {
                addSheet = .codex
            } label: {
                Label("Codex 账号", systemImage: "person.badge.plus")
            }
            .buttonStyle(.bordered)
            Button {
                addSheet = .deepSeek
            } label: {
                Label("DeepSeek Key", systemImage: "key")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 62)
    }

    private var connectionRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.codexAccounts.enumerated()), id: \.element.id) { index, connection in
                codexRow(connection)
                if index < store.codexAccounts.count - 1 || !store.deepSeekConnections.isEmpty {
                    CodexDivider()
                }
            }
            ForEach(Array(store.deepSeekConnections.enumerated()), id: \.element.id) { index, connection in
                deepSeekRow(connection)
                if index < store.deepSeekConnections.count - 1 {
                    CodexDivider()
                }
            }
        }
    }

    private func codexRow(_ connection: CodexAccountConnection) -> some View {
        HStack(spacing: 12) {
            BrandIconView(asset: .codex, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(connection.label)
                    .font(.system(size: 12, weight: .semibold))
                Text("独立 CODEX_HOME · \(connection.relativeHomeDirectory.prefix(8))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.codexMuted)
            }
            Spacer(minLength: 8)
            Text(connection.authenticationState == .connected ? "已连接" : "待登录")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(connection.authenticationState == .connected ? Color.codexGreen : Color.codexAmber)
            Button("登录") { store.launchCodexLogin(for: connection) }
                .buttonStyle(.bordered)
            Button(role: .destructive) {
                pendingRemoval = PendingConnectionRemoval(target: .codex(connection))
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("移除此 Codex 账号运行目录")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 64)
    }

    private func deepSeekRow(_ connection: DeepSeekAPIConnection) -> some View {
        HStack(spacing: 12) {
            BrandIconView(asset: .deepSeek, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(connection.label)
                    .font(.system(size: 12, weight: .semibold))
                Text("sk-•••• \(connection.keySuffix) · 账户余额")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.codexMuted)
            }
            Spacer(minLength: 8)
            if let balance = connection.balance {
                Text(balanceText(balance))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            } else {
                Text("—")
                    .foregroundStyle(Color.codexMuted)
            }
            Button {
                Task { await store.refreshDeepSeekConnection(connection) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(store.isMutatingConnections)
            Button(role: .destructive) {
                pendingRemoval = PendingConnectionRemoval(target: .deepSeek(connection))
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("从 Keychain 移除此 API Key")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 64)
    }

    private func balanceText(_ balance: ProviderBalanceSnapshot) -> String {
        let value = NSDecimalNumber(decimal: balance.total).stringValue
        return balance.currency == "CNY" ? "¥\(value)" : "\(balance.currency) \(value)"
    }

    private func removalAlert(_ pending: PendingConnectionRemoval) -> Alert {
        switch pending.target {
        case .codex(let connection):
            return Alert(
                title: Text("移除 \(connection.label)？"),
                message: Text("将删除这个账号的独立 CODEX_HOME，包括由官方 Codex 写入其中的登录状态和本地 session；其他账号不受影响。"),
                primaryButton: .destructive(Text("移除")) { store.removeCodexAccount(connection) },
                secondaryButton: .cancel()
            )
        case .deepSeek(let connection):
            return Alert(
                title: Text("移除 \(connection.label)？"),
                message: Text("将从 Keychain 删除对应 API Key；其他 Key 不受影响。"),
                primaryButton: .destructive(Text("移除")) { store.removeDeepSeekConnection(connection) },
                secondaryButton: .cancel()
            )
        }
    }
}

private struct AddCodexAccountSheet: View {
    @Bindable var store: MultiAgentSettingsStore
    let onClose: () -> Void
    @State private var label = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("添加 Codex 账号")
                .font(.system(size: 18, weight: .bold))
            Text("Codexling 将创建独立 CODEX_HOME，并在 Terminal 中启动官方 codex login。")
                .font(.system(size: 11))
                .foregroundStyle(Color.codexMuted)
            TextField("例如：Work / Personal", text: $label)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消", action: onClose)
                Button("创建并登录") {
                    store.addCodexAccount(label: label)
                    onClose()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 390)
    }
}

private struct AddDeepSeekKeySheet: View {
    @Bindable var store: MultiAgentSettingsStore
    let onClose: () -> Void
    @State private var label = ""
    @State private var apiKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("添加 DeepSeek API Key")
                .font(.system(size: 18, weight: .bold))
            Text("Key 将保存到 macOS Keychain，并发送到 DeepSeek 官方 /user/balance 接口验证。显示的是账户余额，不是每 Key 独享余额。")
                .font(.system(size: 11))
                .foregroundStyle(Color.codexMuted)
            TextField("连接名称", text: $label)
                .textFieldStyle(.roundedBorder)
            SecureField("sk-…", text: $apiKey)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消", action: onClose)
                Button {
                    Task {
                        if await store.addDeepSeekConnection(label: label, apiKey: apiKey) {
                            onClose()
                        }
                    }
                } label: {
                    if store.isMutatingConnections {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("验证并添加")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isMutatingConnections || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
    }
}
