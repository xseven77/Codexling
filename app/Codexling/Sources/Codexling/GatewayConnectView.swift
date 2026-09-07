import AppKit
import SwiftUI

@MainActor
struct GatewayConnectView: View {
    @Bindable var store: GatewayStore
    var supervisor: GatewaySupervisor = .shared
    var settingsStore: MultiAgentSettingsStore?
    var onToast: GatewayToastHandler

    @State private var copiedEndpoint = false
    @State private var copiedKey = false
    @State private var copiedAllModels = false
    @State private var syncingConnectionIDs: Set<ConnectionID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 本地网关服务控制 (运行状态 / 开启/停止服务)
            heroControlCard

            // 顶部通用标准接入配置
            universalConnectionBar

            CodexDivider(.horizontal)

            // 供应商聚合模块列表 (彻底解决换行与多账号重复卡片问题)
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("按供应商聚合 · 快速接入方案与全量模型")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(Color.codexInk)
                    Text("所有账号已自动桥接为标准 OpenAI 与 Anthropic API 格式，点击模型卡片即可一键复制。")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.codexMuted)
                }

                ForEach(store.providerSections) { section in
                    GatewayProviderSectionCard(
                        section: section,
                        store: store,
                        settingsStore: settingsStore,
                        syncingConnectionIDs: $syncingConnectionIDs,
                        onToast: onToast
                    )
                }
            }
        }
    }

    // MARK: - 顶部通用连接参数条
    private var universalConnectionBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "network.badge.shield.half.filled")
                        .foregroundStyle(Color.codexInk)
                        .font(.system(size: 14, weight: .semibold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("通用网关接入参数")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.codexInk)
                        Text("兼容 99% 的 AI Agent 客户端（如 Cursor、Hermes、Aider、Claude Code 等）")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.codexMuted)
                    }
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.allModelNamesListString, forType: .string)
                    copiedAllModels = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedAllModels = false
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: copiedAllModels ? "checkmark" : "doc.on.doc")
                        Text(copiedAllModels ? "已复制全量模型名" : "复制全部可用模型名")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.codexMist, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .foregroundStyle(copiedAllModels ? Color.green : Color.codexInk)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                // OpenAI Base URL
                connectionTile(
                    title: "OpenAI 兼容 Base URL (推荐)",
                    value: store.openAIBaseURL,
                    isCopied: copiedEndpoint
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.openAIBaseURL, forType: .string)
                    copiedEndpoint = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedEndpoint = false
                    }
                }

                // Anthropic Base URL
                connectionTile(
                    title: "Anthropic Messages 端点",
                    value: store.anthropicBaseURL,
                    isCopied: false
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.anthropicBaseURL, forType: .string)
                }

                // API Key
                connectionTile(
                    title: "本地授权 API Key",
                    value: store.localToken,
                    isCopied: copiedKey
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.localToken, forType: .string)
                    copiedKey = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedKey = false
                    }
                }
            }

            // Minimal dynamic pass-through footer
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                Text("全量模型动态透传已生效：直接在客户端指定上游支持的任意模型名即可原生调用。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.codexMuted)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(Color.codexCard)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
        )
    }

    private func connectionTile(title: String, value: String, isCopied: Bool, copyAction: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Color.codexMuted)
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.codexInk)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 2)

                Button(action: copyAction) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(isCopied ? Color.green : Color.codexMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.codexBackground.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.codexLine.opacity(0.25), lineWidth: 0.6)
        )
    }
    private var heroControlCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(supervisor.isRunning ? Color.green : Color.red)
                        .frame(width: 7, height: 7)
                    Text(supervisor.statusText)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(supervisor.isRunning ? Color.green : Color.red)
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(supervisor.isRunning ? Color.green.opacity(0.12) : Color.red.opacity(0.12), in: Capsule())

                Spacer()

                Button {
                    supervisor.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: supervisor.isRunning ? "stop.fill" : "play.fill")
                        Text(supervisor.isRunning ? "停止服务" : "启动服务")
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(supervisor.isRunning ? Color.red.opacity(0.88) : Color.codexPrimary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .foregroundStyle(Color.white)
                }
                .buttonStyle(CodexPressableStyle(cornerRadius: 6))
            }

            CodexDivider(.horizontal)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("对外标准 API 端点")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.codexMuted)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(store.openAIBaseURL)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.codexInk)
                            .lineLimit(1)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(store.openAIBaseURL, forType: .string)
                            copiedEndpoint = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedEndpoint = false
                            }
                        } label: {
                            Image(systemName: copiedEndpoint ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10.5))
                                .foregroundStyle(copiedEndpoint ? Color.green : Color.codexMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("活跃调用")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.codexMuted)
                            .lineLimit(1)
                        Text("\(supervisor.activeRequests)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.codexInk)
                            .lineLimit(1)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("外部总请求")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.codexMuted)
                            .lineLimit(1)
                        Text("\(supervisor.todayRequests)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.codexInk)
                            .lineLimit(1)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("网关运行时间")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.codexMuted)
                            .lineLimit(1)
                        Text(supervisor.uptimeText)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.codexInk)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.codexCard)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
        )
    }
}

// MARK: - 供应商聚合模块卡片 (多账号切换 + 2列防折叠模型矩阵)
@MainActor
struct GatewayProviderSectionCard: View {
    let section: GatewayProviderSection
    @Bindable var store: GatewayStore
    var settingsStore: MultiAgentSettingsStore?
    @Binding var syncingConnectionIDs: Set<ConnectionID>
    var onToast: GatewayToastHandler

    @State private var selectedAccountId: String? = nil
    @State private var isExpanded: Bool = false
    @State private var copiedGroupId: String? = nil
    @State private var copiedModelId: String? = nil
    @State private var isAddingModel: Bool = false
    @State private var customModelInput: String = ""

    private var activeGroup: GatewayAccountModelGroup {
        if let selectedId = selectedAccountId,
           let match = section.accountGroups.first(where: { $0.id == selectedId }) {
            return match
        }
        return section.accountGroups[0]
    }

    private var totalModelsCount: Int {
        section.accountGroups.reduce(0) { $0 + $1.models.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GatewayProviderCardHeader(
                section: section,
                totalModelsCount: totalModelsCount,
                isConsolidated: store.isProviderConsolidated(section.id),
                onToggleConsolidated: { enabled in
                    store.setProviderConsolidated(section.id, enabled: enabled)
                }
            )

            if section.accountGroups.count > 1 {
                GatewayAccountSwitcherBar(
                    groups: section.accountGroups,
                    activeGroupId: activeGroup.id,
                    onSelect: { selectedAccountId = $0 }
                )
            }

            activeAccountWorkspace
        }
        .padding(12)
        .background(Color.codexCard)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
        )
    }

    private var activeAccountWorkspace: some View {
        let isSyncing = activeGroup.connectionID.map { syncingConnectionIDs.contains($0) } ?? false

        return VStack(alignment: .leading, spacing: 10) {
            // Info & Primary Actions Row
            HStack(alignment: .center, spacing: 8) {
                accountInfoView

                Spacer()

                if activeGroup.connectionID != nil {
                    GatewayAccountProxyToggleButton(
                        isEnabled: activeGroup.isProxyEnabled,
                        isAllowed: activeGroup.isProxyAllowed,
                        isSyncing: isSyncing,
                        onToggle: { toggleProxy(for: activeGroup) }
                    )
                }

                if activeGroup.isProxyEnabled {
                    copySnippetButton
                    expandDrawerButton
                }
            }

            GatewayAccountStatusBanners(
                isSyncing: isSyncing,
                isProxyEnabled: activeGroup.isProxyEnabled,
                isProxyAllowed: activeGroup.isProxyAllowed,
                hasZeroModels: activeGroup.models.isEmpty && activeGroup.connectionID != nil,
                onResync: { syncModels(for: activeGroup) }
            )

            if activeGroup.isProxyEnabled && !activeGroup.recommendedModels.isEmpty {
                GatewayRecommendedModelsGrid(
                    models: activeGroup.recommendedModels,
                    copiedModelId: copiedModelId,
                    onCopy: { modelId in
                        copyModel(modelId, id: modelId)
                    }
                )
            }

            if activeGroup.isProxyEnabled && isExpanded {
                GatewayAccountModelsDrawer(
                    activeGroup: activeGroup,
                    isAddingModel: $isAddingModel,
                    customModelInput: $customModelInput,
                    copiedModelId: copiedModelId,
                    onAddCustomModel: { name in
                        addCustomModel(name, toGroupId: activeGroup.id)
                    },
                    onRemoveCustomModel: { name in
                        removeCustomModel(name, fromGroupId: activeGroup.id)
                    },
                    onCopyModel: { name, id in
                        copyModel(name, id: id)
                    }
                )
            }
        }
        .padding(10)
        .background(Color.codexBackground.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.codexLine.opacity(0.25), lineWidth: 0.6)
        )
    }

    private var accountInfoView: some View {
        VStack(alignment: .leading, spacing: 2.5) {
            HStack(spacing: 6) {
                Text("当前选定账号:")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.codexMuted)

                Text(activeGroup.accountName)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color.codexInk)
                    .lineLimit(1)

                Text(activeGroup.isProxyEnabled ? activeGroup.badgeText : "代理已停用")
                    .font(.system(size: 9.5, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(activeGroup.isProxyEnabled ? Color.green.opacity(0.12) : Color.codexMist, in: Capsule())
                    .foregroundStyle(activeGroup.isProxyEnabled ? Color.green : Color.codexMuted)
                    .lineLimit(1)
            }

            if let email = activeGroup.email, !email.isEmpty {
                Text(email)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)
            }
        }
    }

    private var copySnippetButton: some View {
        let isCopied = copiedGroupId == activeGroup.id
        return Button {
            copySnippet(for: activeGroup)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                Text(isCopied ? "已复制接入参数" : "一键复制接入参数")
            }
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(isCopied ? Color.green : Color.codexPrimary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .foregroundStyle(Color.codexOnPrimary)
        }
        .buttonStyle(CodexPressableStyle(cornerRadius: 6))
    }

    private var expandDrawerButton: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Text(isExpanded ? "收起" : "全部模型 (\(activeGroup.models.count))")
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .font(.system(size: 10.5, weight: .medium))
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(Color.codexMist, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .foregroundStyle(Color.codexInk)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
            )
        }
        .buttonStyle(CodexPressableStyle(cornerRadius: 6))
    }

    private func toggleProxy(for group: GatewayAccountModelGroup) {
        guard let connID = group.connectionID, group.isProxyAllowed else { return }
        let isSyncing = syncingConnectionIDs.contains(connID)
        guard !isSyncing else { return }

        let willEnable = !group.isProxyEnabled
        if willEnable {
            syncingConnectionIDs.insert(connID)
            Task { @MainActor in
                if let ss = settingsStore {
                    ss.setConnectionProxyEnabled(id: connID, enabled: true)
                    store.toggleConnectionProxy(id: connID)

                    let result = await ss.syncConnectionModels(id: connID)
                    store.toggleConnectionProxy(id: connID)
                    syncingConnectionIDs.remove(connID)

                    switch result {
                    case let .success(count, _):
                        onToast("已开启 [\(group.accountName)] 代理 · 同步到 \(count) 款可用模型", "checkmark.circle.fill", true)
                    case let .warning(msg):
                        onToast("已开启代理 · \(msg)", "exclamationmark.triangle.fill", true)
                    case let .failure(errMsg):
                        ss.setConnectionProxyEnabled(id: connID, enabled: false)
                        store.toggleConnectionProxy(id: connID)
                        onToast("开启代理失败：\(errMsg)", "xmark.circle.fill", false)
                    }
                } else {
                    store.toggleConnectionProxy(id: connID)
                    syncingConnectionIDs.remove(connID)
                    onToast("已开启网关代理", "checkmark.circle.fill", true)
                }
            }
        } else {
            if let ss = settingsStore {
                ss.setConnectionProxyEnabled(id: connID, enabled: false)
            }
            store.toggleConnectionProxy(id: connID)
            onToast("已关闭 [\(group.accountName)] 网关代理", "pause.circle.fill", true)
        }
    }

    private func syncModels(for group: GatewayAccountModelGroup) {
        guard let connID = group.connectionID else { return }
        syncingConnectionIDs.insert(connID)
        Task { @MainActor in
            if let ss = settingsStore {
                let result = await ss.syncConnectionModels(id: connID)
                store.toggleConnectionProxy(id: connID)
                syncingConnectionIDs.remove(connID)
                switch result {
                case let .success(count, _):
                    onToast("已成功同步 \(count) 款可用模型", "checkmark.circle.fill", true)
                case let .warning(msg):
                    onToast(msg, "exclamationmark.triangle.fill", true)
                case let .failure(errMsg):
                    onToast("同步失败：\(errMsg)", "xmark.circle.fill", false)
                }
            } else {
                syncingConnectionIDs.remove(connID)
            }
        }
    }

    private func copySnippet(for group: GatewayAccountModelGroup) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(group.sampleConfigSnippet, forType: .string)
        copiedGroupId = group.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedGroupId = nil
        }
    }

    private func copyModel(_ modelName: String, id: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(modelName, forType: .string)
        copiedModelId = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedModelId = nil
        }
    }

    private func addCustomModel(_ name: String, toGroupId: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            store.addCustomModel(trimmed, toGroupId: toGroupId)
            isAddingModel = false
            customModelInput = ""
        }
    }

    private func removeCustomModel(_ name: String, fromGroupId: String) {
        store.removeCustomModel(name, fromGroupId: fromGroupId)
    }
}

// MARK: - Subviews for ProviderSectionCard

@MainActor
private struct GatewayProviderCardHeader: View {
    let section: GatewayProviderSection
    let totalModelsCount: Int
    let isConsolidated: Bool
    let onToggleConsolidated: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            BrandIconView(
                asset: section.brandAsset,
                size: 34,
                cornerRadius: 8
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(section.providerTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.codexInk)

                    Text("\(section.accountGroups.count) 个已连接账号 · 共 \(totalModelsCount) 款模型")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.codexPrimary.opacity(0.06), in: Capsule())
                        .foregroundStyle(Color.codexInk)
                }

                Text(section.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)
            }

            Spacer()

            consolidationToggle
        }
    }

    private var consolidationToggle: some View {
        HStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 1.5) {
                HStack(spacing: 4) {
                    Image(systemName: isConsolidated ? "square.stack.3d.up.fill" : "square.stack.3d.up")
                        .font(.system(size: 10))
                        .foregroundStyle(isConsolidated ? Color.purple : Color.codexMuted)
                    Text("账号池聚合")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.codexInk)
                }
                Text(isConsolidated ? "额度健康调度 · 故障转移" : "逐账号独立隔离")
                    .font(.system(size: 9.5))
                    .foregroundStyle(isConsolidated ? Color.purple : Color.codexMuted)
            }

            Toggle("", isOn: Binding(
                get: { isConsolidated },
                set: { onToggleConsolidated($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            isConsolidated
                ? Color.purple.opacity(0.06)
                : Color.codexMist.opacity(0.4),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isConsolidated
                        ? Color.purple.opacity(0.25)
                        : Color.codexLine.opacity(0.3),
                    lineWidth: 0.8
                )
        )
    }
}

@MainActor
private struct GatewayAccountSwitcherBar: View {
    let groups: [GatewayAccountModelGroup]
    let activeGroupId: String
    let onSelect: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(groups) { grp in
                        let isSelected = activeGroupId == grp.id
                        Button {
                            onSelect(grp.id)
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(grp.id, anchor: .center)
                            }
                        } label: {
                            accountTabLabel(grp: grp, isSelected: isSelected)
                        }
                        .id(grp.id)
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
                .background(ScrollIndicatorHider())
            }
            .scrollIndicators(.hidden)
            .onChange(of: activeGroupId) { _, newID in
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
    }

    private func accountTabLabel(grp: GatewayAccountModelGroup, isSelected: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(grp.isProxyEnabled ? (isSelected ? Color.green : Color.green.opacity(0.7)) : Color.codexMuted.opacity(0.4))
                .frame(width: 5.5, height: 5.5)

            Text(grp.accountName)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .lineLimit(1)

            Text(grp.isProxyEnabled ? grp.badgeText : "已停用")
                .font(.system(size: 9.5))
                .opacity(isSelected ? 0.9 : 0.65)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 27)
        .background(
            isSelected ? Color.codexPrimary : Color.codexMist.opacity(0.55),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .foregroundStyle(isSelected ? Color.codexOnPrimary : (grp.isProxyEnabled ? Color.codexInk : Color.codexMuted))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isSelected ? Color.clear : Color.codexLine.opacity(0.3), lineWidth: 0.6)
        )
    }
}

@MainActor
private struct GatewayAccountProxyToggleButton: View {
    let isEnabled: Bool
    let isAllowed: Bool
    let isSyncing: Bool
    let onToggle: () -> Void

    private var circleColor: Color {
        if isSyncing { return Color.orange }
        if isEnabled { return Color.green }
        return isAllowed ? Color.codexMuted : Color.orange
    }

    private var textColor: Color {
        if isSyncing { return Color.orange }
        if isEnabled { return Color.green }
        return isAllowed ? Color.codexMuted : Color.orange
    }

    private var btnTitle: String {
        if isSyncing {
            return isEnabled ? "正在开启..." : "正在同步..."
        }
        if isEnabled {
            return "代理已开启"
        }
        return isAllowed ? "代理已关闭" : "OAuth 未就绪"
    }

    private var btnBg: Color {
        if isSyncing { return Color.orange.opacity(0.12) }
        if isEnabled { return Color.green.opacity(0.12) }
        return isAllowed ? Color.codexMist : Color.orange.opacity(0.12)
    }

    private var strokeColor: Color {
        if isSyncing { return Color.orange.opacity(0.4) }
        if isEnabled { return Color.green.opacity(0.3) }
        return isAllowed ? Color.codexLine.opacity(0.4) : Color.orange.opacity(0.4)
    }

    private var helpText: String {
        if !isAllowed { return "请重新登录 OAuth 账号后再开启代理" }
        if isSyncing { return "正在验证授权并同步可用模型..." }
        if isEnabled { return "点击关闭该账号的网关代理" }
        return "点击开启该账号的网关代理并同步模型"
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 4.5) {
                if isSyncing {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Circle()
                        .fill(circleColor)
                        .frame(width: 5.5, height: 5.5)
                }
                Text(btnTitle)
            }
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(btnBg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .foregroundStyle(textColor)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(strokeColor, lineWidth: 0.8)
            )
        }
        .buttonStyle(CodexPressableStyle(cornerRadius: 6))
        .help(helpText)
        .disabled(!isAllowed || isSyncing)
    }
}

@MainActor
private struct GatewayAccountStatusBanners: View {
    let isSyncing: Bool
    let isProxyEnabled: Bool
    let isProxyAllowed: Bool
    let hasZeroModels: Bool
    let onResync: () -> Void

    var body: some View {
        if isSyncing {
            HStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("正在验证授权并同步可用模型目录...")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.codexInk)
                    Text("正在向官方服务验证 OAuth 凭据并拉取可用模型配额，首次或重连通常需要 1~2 秒，完成后将自动刷新网关模型路由。")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.codexMuted)
                }
                Spacer()
            }
            .padding(10)
            .background(Color.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.purple.opacity(0.25), lineWidth: 0.8)
            )
        } else if !isProxyEnabled {
            HStack(spacing: 8) {
                Image(systemName: isProxyAllowed ? "pause.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isProxyAllowed ? "该账号已关闭网关代理" : "OAuth 未就绪")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.codexInk)

                    Text(isProxyAllowed ? "该账号的所有模型已在网关模型列表 (/v1/models) 中隐藏，且不再参与网关路由分流。" : "请重新登录账号；Gateway 只使用有效凭据出流。")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.codexMuted)
                }

                Spacer()
            }
            .padding(10)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.orange.opacity(0.25), lineWidth: 0.8)
            )
        } else if hasZeroModels {
            HStack(spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("代理已开启 · 暂未发现可用模型")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.codexInk)

                    Text("官方授权已连接，但尚未拉取到可用的模型列表。点击右侧按钮可重新同步，或在下方手动添加自定义透传模型。")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.codexMuted)
                }

                Spacer()

                Button(action: onResync) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("立即同步模型")
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .padding(.horizontal, 9)
                    .frame(height: 25)
                    .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .foregroundStyle(Color.orange)
                }
                .buttonStyle(CodexPressableStyle(cornerRadius: 5))
            }
            .padding(10)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.orange.opacity(0.25), lineWidth: 0.8)
            )
        }
    }
}

@MainActor
private struct GatewayRecommendedModelsGrid: View {
    let models: [String]
    let copiedModelId: String?
    let onCopy: (String) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(models, id: \.self) { modelId in
                let isCopied = copiedModelId == modelId
                Button {
                    onCopy(modelId)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isCopied ? "checkmark.circle.fill" : "cube.fill")
                            .font(.system(size: 10.5))
                            .foregroundStyle(isCopied ? Color.green : Color.codexMuted)

                        Text(modelId)
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(isCopied ? Color.green : Color.codexInk)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 0)

                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9))
                            .foregroundStyle(isCopied ? Color.green : Color.codexMuted.opacity(0.7))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(Color.codexBackground.opacity(0.75), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isCopied ? Color.green.opacity(0.6) : Color.codexLine.opacity(0.3), lineWidth: 0.6)
                    )
                }
                .buttonStyle(.plain)
                .help("点击复制 \(modelId)")
            }
        }
    }
}

@MainActor
private struct GatewayAccountModelsDrawer: View {
    let activeGroup: GatewayAccountModelGroup
    @Binding var isAddingModel: Bool
    @Binding var customModelInput: String
    let copiedModelId: String?
    let onAddCustomModel: (String) -> Void
    let onRemoveCustomModel: (String) -> Void
    let onCopyModel: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CodexDivider(.horizontal)

            // Quick Connect Tip
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .padding(.top, 1)
                Text(activeGroup.quickConnectTip)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.codexInk)
                    .lineSpacing(2)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.codexPrimary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Custom Model Input & Models Table
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("可访问模型全量清单 (\(activeGroup.models.count))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.codexInk)

                    Spacer()

                    Button {
                        isAddingModel.toggle()
                        if !isAddingModel {
                            customModelInput = ""
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: isAddingModel ? "xmark" : "plus.circle")
                            Text(isAddingModel ? "取消" : "添加/自定义透传模型")
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(Color.codexInk)
                    }
                    .buttonStyle(.plain)
                }

                if isAddingModel {
                    HStack(spacing: 6) {
                        TextField("输入模型 ID (例如 gemini-3.7-flash, deepseek-v4-pro...)", text: $customModelInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 10.5, design: .monospaced))

                        Button("添加") {
                            onAddCustomModel(customModelInput)
                        }
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Color.codexPrimary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .foregroundStyle(Color.codexOnPrimary)
                        .buttonStyle(CodexPressableStyle(cornerRadius: 5))
                    }
                    .padding(.vertical, 4)
                }

                ForEach(activeGroup.models) { model in
                    let isCopied = copiedModelId == model.id
                    HStack(spacing: 8) {
                        Text(model.modelName)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.codexInk)
                            .frame(width: 190, alignment: .leading)
                            .lineLimit(1)

                        Text(model.capability)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.codexMuted)
                            .frame(width: 150, alignment: .leading)
                            .lineLimit(1)

                        Text(model.description)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.codexMuted)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        if model.isCustom {
                            Button {
                                onRemoveCustomModel(model.modelName)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .help("移除自定义透传模型")
                        }

                        Button {
                            onCopyModel(model.modelName, model.id)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                Text(isCopied ? "已复制" : "复制")
                            }
                            .font(.system(size: 9.5))
                            .foregroundStyle(isCopied ? Color.green : Color.codexMuted)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.codexBackground.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
