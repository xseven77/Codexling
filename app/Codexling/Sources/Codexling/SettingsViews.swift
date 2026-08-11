import AppKit
import SwiftUI

private enum SettingsLayoutMetrics {
    static let sectionSpacing: CGFloat = 24
    static let sidebarWidth: CGFloat = 154
    static let splitMinimumHeight: CGFloat = 560
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case accounts
    case agents
    case general
    case pet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accounts: "账户池"
        case .agents: "Agents 与 Hooks"
        case .general: "通用"
        case .pet: "状态栏与 Pet"
        }
    }

    var subtitle: String {
        switch self {
        case .accounts: "统一查看本机账号与 API Key"
        case .agents: "本地 Agent 探测与 Hook 管理"
        case .general: "应用、外观与刷新行为"
        case .pet: "Pet、状态胶囊与任务浮窗"
        }
    }

    var systemImage: String {
        switch self {
        case .accounts: "person.2"
        case .agents: "terminal"
        case .general: "slider.horizontal.3"
        case .pet: "pawprint"
        }
    }
}

private struct PendingAgentHookAction: Identifiable {
    let agentID: AgentID
    let agentName: String
    let installs: Bool

    var id: String { "\(agentID.rawValue)-\(installs ? "install" : "uninstall")" }
}

struct SettingsView: View {
    @Bindable var store: UsageSnapshotStore
    @Bindable var settings: AppSettingsStore
    @Bindable var multiAgentSettings: MultiAgentSettingsStore
    @Bindable var updater: AppUpdateController
    let layout: UsagePanelLayout
    let onLogout: () -> Void
    let onClose: () -> Void
    var onMeasuredContentHeightChange: (CGFloat) -> Void = { _ in }
    @State private var showsLogoutConfirmation = false
    @State private var showsPetPicker = false
    @State private var showsCodexRestartConfirmation = false
    @State private var isRestartingCodex = false
    @State private var pendingHookAction: PendingAgentHookAction?
    @State private var toast: SettingsToast?
    @State private var toastDismissGeneration = 0
    @State private var selectedTab: SettingsTab = .accounts
    @Environment(\.openURL) private var openURL

    var body: some View {
        lifecycleContent
    }

    private var lifecycleContent: some View {
        alertContent
            .onPreferenceChange(SettingsMeasuredContentHeightKey.self) { height in
                guard layout == .window, height > 1 else { return }
                onMeasuredContentHeightChange(height)
            }
            .onAppear {
                guard layout == .window else { return }
                onMeasuredContentHeightChange(0)
            }
            .task(id: petPreviewIdentity) {
                await PetThumbnailLoader.shared.preload(
                    settings.availablePets.map(\.spritesheetURL)
                )
            }
            .onChange(of: settingsMeasuredContentIdentity) { _, _ in
                guard layout == .window else { return }
                onMeasuredContentHeightChange(-1)
            }
    }

    private var alertContent: some View {
        toastTrackingContent
            .alert("确认退出登录？", isPresented: $showsLogoutConfirmation) {
                Button("取消", role: .cancel) {}
                Button("退出登录", role: .destructive, action: onLogout)
            } message: {
                Text("退出后需要重新授权才能查看用量。")
            }
            .alert("重启 Codex 以切换 Pet？", isPresented: $showsCodexRestartConfirmation) {
                Button("取消", role: .cancel) {}
                Button("重启 Codex", role: .destructive) {
                    restartCodex()
                }
            } message: {
                Text("这会退出并重新打开 Codex，正在运行或等待确认的任务可能会被中断。")
            }
            .alert(item: $pendingHookAction) { pending in
                hookActionAlert(pending)
            }
            .onChange(of: multiAgentSettings.lastMessage) { _, message in
                guard let message else { return }
                showToast(message, systemImage: message.contains("失败") ? "exclamationmark.triangle.fill" : "link.badge.plus")
                multiAgentSettings.clearLastMessage()
            }
    }

    private var toastTrackingContent: some View {
        baseContent
            .onChange(of: settings.theme) { _, theme in
                showToast("主题：\(theme.title)")
            }
            .onChange(of: settings.autoRefreshInterval) { _, interval in
                showToast("自动刷新：\(interval.title)")
            }
            .onChange(of: settings.dashboardOrientation) { _, orientation in
                showToast("主界面布局：\(orientation.title)")
            }
            .onChange(of: settings.statusBarWaveEnabled) { _, enabled in
                showToast("活动流光已\(enabled ? "开启" : "关闭")")
            }
            .onChange(of: settings.statusBarIndicatorColorMode) { _, mode in
                showToast("状态圆灯颜色：\(mode.title)")
            }
            .onChange(of: settings.statusBarWaveColorMode) { _, mode in
                showToast("活动流光颜色：\(mode.title)")
            }
            .onChange(of: settings.autoOpenTaskHoverEnabled) { _, enabled in
                showToast("任务浮窗自动展开已\(enabled ? "开启" : "关闭")")
            }
            .onChange(of: updater.phase) { oldPhase, phase in
                handleUpdaterPhaseChange(from: oldPhase, to: phase)
            }
    }

    private var baseContent: some View {
        VStack(spacing: 0) {
            header
            if layout == .window {
                settingsSplitView
            } else {
                ScrollView {
                    allSettingsContent
                }
                .scrollIndicators(.hidden)
                .background(ScrollIndicatorHider())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(Color.codexInk)
        .overlay(alignment: .bottom) {
            if let toast {
                Label(toast.message, systemImage: toast.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(.black.opacity(0.84), in: Capsule(style: .continuous))
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityLabel(toast.message)
            }
        }
    }

    private func handleUpdaterPhaseChange(from oldPhase: AppUpdatePhase, to phase: AppUpdatePhase) {
        guard oldPhase != phase else { return }
        switch phase {
        case .upToDate:
            showToast("已是最新版本")
        case .available:
            if let version = updater.latestRelease?.version {
                showToast("发现新版本 \(version)", systemImage: "arrow.down.circle.fill")
            } else {
                showToast("发现新版本", systemImage: "arrow.down.circle.fill")
            }
        case .failed(let message):
            showToast(message, systemImage: "exclamationmark.triangle.fill")
        case .installing:
            showToast("正在安装，完成后将自动重启", systemImage: "arrow.down.circle.fill")
        default:
            break
        }
    }

    private var settingsSplitView: some View {
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: SettingsLayoutMetrics.sidebarWidth)

            CodexDivider(.vertical)

            ScrollView {
                selectedSettingsContent
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.automatic)
            .background(Color.codexBackground.opacity(0.50))
        }
        .frame(minHeight: SettingsLayoutMetrics.splitMinimumHeight)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: SettingsMeasuredContentHeightKey.self,
                    value: geometry.size.height + DetachedWindowMetrics.chromeHeaderHeight
                )
            }
        }
        .id(settingsMeasuredContentIdentity)
    }

    private var allSettingsContent: some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            accountPoolSection
            agentIntegrationsSection
            updateSection
            petSection
            thirdPartyPetResourcesSection
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SETTINGS")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Color.codexMuted)
                .padding(.horizontal, 10)
                .padding(.bottom, 7)

            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 18)
                        Text(tab.title)
                            .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(selectedTab == tab ? Color.codexInk : Color.codexMuted)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .contentShape(Rectangle())
                    .background(
                        selectedTab == tab ? Color.codexPrimary.opacity(0.10) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                }
                .buttonStyle(CodexPressableStyle(cornerRadius: 9))
                .accessibilityValue(selectedTab == tab ? "已选择" : "")
            }

            Spacer(minLength: 12)

            Text("Codexling \(updater.currentVersion)")
                .font(.system(size: 9))
                .foregroundStyle(Color.codexMuted.opacity(0.82))
                .padding(.horizontal, 10)
        }
        .padding(.horizontal, 10)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.codexCard.opacity(0.72))
    }

    private var selectedSettingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedTab.title)
                    .font(.system(size: 20, weight: .bold))
                Text(selectedTab.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.codexMuted)
            }

            switch selectedTab {
            case .accounts:
                accountPoolSection
            case .agents:
                agentIntegrationsSection
            case .general:
                updateSection
            case .pet:
                petSection
                thirdPartyPetResourcesSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsMeasuredContentIdentity: String {
        [
            settings.isCodexlingPetInstalled ? "1" : "0",
            String(settings.availablePets.count),
            store.isLoggedIn ? "1" : "0",
            String(multiAgentSettings.codexAccounts.count),
            String(multiAgentSettings.deepSeekConnections.count),
            String(describing: updater.phase),
        ].joined(separator: "-")
    }

    private var petPreviewIdentity: String {
        settings.availablePets.map(\.id).joined(separator: "|")
    }

    private var accountPoolSection: some View {
        SettingsSection(
            title: "已连接",
            subtitle: "账号凭据保持隔离；新增账号或 API Key 请使用主界面的加号。"
        ) {
            VStack(spacing: 0) {
                if store.isLoggedIn {
                    accountPoolRow(
                        asset: .codex,
                        title: store.snapshot.companionAccountName,
                        subtitle: store.snapshot.accountEmail,
                        badge: store.snapshot.planName.isEmpty ? "当前 Codex" : store.snapshot.planName,
                        badgeColor: Color.codexGreen
                    )
                    CodexDivider()
                }

                ForEach(multiAgentSettings.codexAccounts) { connection in
                    accountPoolRow(
                        asset: .codex,
                        title: connection.label,
                        subtitle: connection.usage?.email ?? "独立 CODEX_HOME",
                        badge: connection.authenticationState == .connected ? "已连接" : "待登录",
                        badgeColor: connection.authenticationState == .connected ? Color.codexGreen : Color.codexAmber
                    )
                    CodexDivider()
                }

                ForEach(multiAgentSettings.deepSeekConnections) { connection in
                    accountPoolRow(
                        asset: .deepSeek,
                        title: connection.label,
                        subtitle: "sk-•••• \(connection.keySuffix)",
                        badge: deepSeekPoolBadge(connection),
                        badgeColor: deepSeekPoolColor(connection)
                    )
                    CodexDivider()
                }

                if !store.isLoggedIn,
                   multiAgentSettings.codexAccounts.isEmpty,
                   multiAgentSettings.deepSeekConnections.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.2.badge.plus")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color.codexMuted)
                        Text("账户池为空")
                            .font(.system(size: 12, weight: .semibold))
                        Text("回到主界面，通过加号添加 Codex 账号或 DeepSeek API Key。")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.codexMuted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 128)
                    .padding(16)
                }
            }
            .settingsGroupSurface()
        }
    }

    private func accountPoolRow(
        asset: BrandAssetID,
        title: String,
        subtitle: String,
        badge: String,
        badgeColor: Color
    ) -> some View {
        HStack(spacing: 12) {
            BrandIconView(asset: asset, size: 38, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(badge)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(badgeColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(badgeColor.opacity(0.10), in: Capsule())
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 64)
    }

    private func deepSeekPoolBadge(_ connection: DeepSeekAPIConnection) -> String {
        guard connection.authenticationState == .connected else { return "异常" }
        guard let total = connection.balance?.total else { return "待查询" }
        return "¥\(total)"
    }

    private func deepSeekPoolColor(_ connection: DeepSeekAPIConnection) -> Color {
        switch ProviderBalanceIndicator.resolve(
            total: connection.balance?.total,
            authenticationState: connection.authenticationState
        ) {
        case .healthy: Color.codexGreen
        case .low: Color.codexAmber
        case .depleted: Color.codexRed
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            accountCardIdentityRow
                .padding(.horizontal, 16)
                .frame(minHeight: 62)

            if store.isLoggedIn {
                CodexDivider()
                accountCardSubscriptionRow
                    .padding(.horizontal, 16)
                    .frame(minHeight: 60)
            }
        }
        .settingsGroupSurface()
    }

    private var accountCardIdentityRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(store.isLoggedIn && store.snapshot.accountName?.isEmpty == false
                         ? store.snapshot.accountName!
                         : "OpenAI 账号")
                        .font(.system(size: 13, weight: .semibold))
                    if store.isLoggedIn {
                        Text(store.snapshot.planName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.codexGreen)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.codexGreen.opacity(0.10), in: Capsule())
                    }
                }
                Text(store.isLoggedIn
                     ? "\(store.snapshot.accountEmail) · \(store.snapshot.workspaceName)"
                     : "尚未连接 ChatGPT / Codex")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if store.isLoggedIn {
                Button {
                    showsLogoutConfirmation = true
                } label: {
                    Text("退出登录")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.codexRed)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color.codexRed.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.codexRed.opacity(0.18), lineWidth: 0.7))
                }
                .buttonStyle(CodexPressableStyle(cornerRadius: 7))
            } else {
                Text("未登录")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.codexMuted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.codexMuted.opacity(0.10), in: Capsule())
            }
        }
    }

    private var accountCardSubscriptionRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let expiryLine = store.snapshot.subscriptionSettingsExpiryLine {
                    Text(expiryLine)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(store.snapshot.showsSubscriptionExpiryReminder
                            ? Color.codexAmber
                            : Color.codexInk.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let renewalLine = store.snapshot.subscriptionSettingsRenewalLine {
                    Text(renewalLine)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.codexMuted)
                } else if store.snapshot.subscriptionSettingsExpiryLine == nil {
                    Text("订阅与账单请在 ChatGPT 官网管理")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.codexMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ChatGPTBillingCompactLink(
                title: "官方 Billing",
                fontSize: 11,
                waveFillsAvailableWidth: false
            ) {
                openURL(ChatGPTWebLinks.billingPage)
            }
        }
    }

    private var agentIntegrationsSection: some View {
        SettingsSection(
            title: "Agents 与 Hooks",
            subtitle: "Codex 由 Codexling 内置适配，无需安装 Hook。其他 Agent 的 Hook 只向本地 Bridge 上报脱敏生命周期状态。"
        ) {
            VStack(spacing: 0) {
                ForEach(Array(multiAgentSettings.integrations.enumerated()), id: \.element.id) { index, integration in
                    agentIntegrationRow(integration)
                    if index < multiAgentSettings.integrations.count - 1 {
                        CodexDivider()
                    }
                }
            }
            .settingsGroupSurface()
        }
    }

    private func agentIntegrationRow(_ integration: AgentIntegrationStatus) -> some View {
        HStack(spacing: 12) {
            BrandIconView(
                asset: .agent(integration.id)
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(integration.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(agentAvailabilityTitle(integration))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(agentAvailabilityColor(integration))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(agentAvailabilityColor(integration).opacity(0.09), in: Capsule())
                }
                Text(integration.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.codexMuted)
                Text(hookStatusLine(integration))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(hookStatusColor(integration.hookState))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            hookActionButton(integration)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 76)
    }

    @ViewBuilder
    private func hookActionButton(_ integration: AgentIntegrationStatus) -> some View {
        if integration.id == .codex {
            Label("默认支持", systemImage: "checkmark.circle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.codexGreen)
                .frame(width: 74, alignment: .trailing)
        } else if multiAgentSettings.isMutating(integration.id) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 66)
        } else {
            switch integration.hookState {
            case .builtIn:
                EmptyView()
            case .installed:
                Button("卸载") {
                    pendingHookAction = PendingAgentHookAction(
                        agentID: integration.id,
                        agentName: integration.name,
                        installs: false
                    )
                }
                .buttonStyle(CodexPressableStyle(cornerRadius: 7))
            case .notInstalled, .conflict, .failed:
                Button("安装") {
                    pendingHookAction = PendingAgentHookAction(
                        agentID: integration.id,
                        agentName: integration.name,
                        installs: true
                    )
                }
                .buttonStyle(CodexlingPetInstallButtonStyle())
            case .unavailable:
                Button("重新探测") { multiAgentSettings.refresh() }
                    .buttonStyle(CodexPressableStyle(cornerRadius: 7))
            }
        }
    }

    private func hookConfirmationMessage(for pending: PendingAgentHookAction) -> String {
        if pending.installs {
            let eventCount = pending.agentID == .hermes ? 7 : 8
            return "配置变更预览：新增 \(eventCount) 个 lifecycle command hook，命令只调用 Codexling 本地 Bridge；不读取 prompt、回复、tool 参数、命令、环境变量或 transcript。Agent/Codexling 未运行时 Hook 会 fail-open。"
        }
        return "只移除命令中包含 codexling-agent-bridge 的配置项；其他 Hook 与 Agent 配置保持不变。"
    }

    private func hookActionAlert(_ pending: PendingAgentHookAction) -> Alert {
        if pending.installs {
            return Alert(
                title: Text("安装 \(pending.agentName) Hook？"),
                message: Text(hookConfirmationMessage(for: pending)),
                primaryButton: .default(Text("安装")) {
                    multiAgentSettings.installHook(for: pending.agentID)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        return Alert(
            title: Text("卸载 \(pending.agentName) Hook？"),
            message: Text(hookConfirmationMessage(for: pending)),
            primaryButton: .destructive(Text("卸载")) {
                multiAgentSettings.uninstallHook(for: pending.agentID)
            },
            secondaryButton: .cancel(Text("取消"))
        )
    }

    private func agentAvailabilityTitle(_ integration: AgentIntegrationStatus) -> String {
        if integration.id == .codex { return "内置适配" }
        if integration.cliInstalled && integration.desktopInstalled { return "CLI + Desktop" }
        if integration.cliInstalled { return "CLI 已安装" }
        if integration.desktopInstalled { return "Desktop 已安装" }
        return "未发现"
    }

    private func agentAvailabilityColor(_ integration: AgentIntegrationStatus) -> Color {
        if integration.id == .codex { return Color.codexGreen }
        return integration.cliInstalled || integration.desktopInstalled ? Color.codexGreen : Color.codexMuted
    }

    private func hookStatusLine(_ integration: AgentIntegrationStatus) -> String {
        if integration.id == .codex {
            return integration.cliInstalled || integration.desktopInstalled
                ? "已自动接入 · 无需安装 Hook"
                : "内置适配已就绪 · Codex 启动后自动接入"
        }
        return switch integration.hookState {
        case .builtIn: "内置适配 · 无需安装 Hook"
        case .notInstalled: "Hook 未安装"
        case .installed: "Hook 已安装 · 本地脱敏事件"
        case .unavailable(let message): message
        case .conflict(let message), .failed(let message): message
        }
    }

    private func hookStatusColor(_ state: AgentHookInstallationState) -> Color {
        switch state {
        case .builtIn, .installed: Color.codexGreen
        case .conflict, .failed: Color.codexRed
        case .notInstalled, .unavailable: Color.codexMuted
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 42, height: 28)
            Spacer()
            Text("设置")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            HStack(spacing: 4) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.codexInk)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(CodexPressableStyle(cornerRadius: 8))
                .offset(y: -3)
                .help("关闭设置")
                .accessibilityLabel("关闭设置")
                Color.clear.frame(width: 10, height: 28)
            }
            .frame(width: 42)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: DetachedWindowMetrics.chromeHeaderHeight)
        .background(CodexChromeBackground(intensity: .header))
        .fixedSize(horizontal: false, vertical: true)
    }

    private var updateSection: some View {
        SettingsSection(title: "应用") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Codexling \(updater.currentVersion)（\(updater.currentBuild)）")
                            .font(.system(size: 13, weight: .semibold))
                        Text(updater.settingsStatusLine)
                            .font(.system(size: 11))
                            .foregroundStyle(statusColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 7) {
                        IconButton(
                            systemName: "arrow.up.right",
                            title: "打开 GitHub Releases",
                            action: updater.openReleasesPage
                        )
                        Button(updater.settingsPrimaryActionTitle, action: primaryUpdateAction)
                            .buttonStyle(CodexlingPetInstallButtonStyle())
                            .disabled(updater.phase.isBusy)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 62)

                if case .downloading = updater.phase {
                    ProgressView(value: updater.downloadProgress)
                        .progressViewStyle(.linear)
                        .tint(Color.codexPrimary)
                }
                CodexDivider()
                themeSection
                CodexDivider()
                orientationSection
                CodexDivider()
                refreshSection
            }
            .settingsGroupSurface()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusColor: Color {
        switch updater.phase {
        case .failed:
            .codexRed
        case .available:
            .codexAmber
        case .upToDate:
            .codexGreen
        default:
            .codexMuted
        }
    }

    private func primaryUpdateAction() {
        switch updater.phase {
        case .available:
            updater.downloadAndInstall()
        default:
            updater.checkForUpdates()
        }
    }

    private var themeSection: some View {
        SettingsInlineRow(title: "主题", subtitle: "跟随系统，或固定浅色 / 深色") {
            SettingsMenuPicker(
                selection: $settings.theme,
                options: AppThemePreference.allCases,
                title: \.title
            )
        }
    }

    private var orientationSection: some View {
        SettingsInlineRow(
            title: "主界面布局",
            subtitle: "横向：宠物在左侧；竖向：宠物移到顶部，窗口收窄到 330pt"
        ) {
            SettingsMenuPicker(
                selection: $settings.dashboardOrientation,
                options: DashboardOrientation.allCases,
                title: \.title
            )
        }
    }

    private var refreshSection: some View {
        SettingsInlineRow(title: "自动刷新", subtitle: "登录后按设定间隔自动拉取额度") {
            SettingsMenuPicker(
                selection: $settings.autoRefreshInterval,
                options: AutoRefreshInterval.allCases,
                title: \.title
            )
        }
    }

    private var petSection: some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            SettingsSection(
                title: "状态栏与 Pet",
                subtitle: "调整胶囊透明度与任务活动效果。"
            ) {
                VStack(spacing: 0) {
                SettingsInlineRow(
                    title: "胶囊背景透明度",
                    subtitle: "调整状态栏胶囊白色背景的透明度"
                ) {
                    SettingsPercentageSlider(value: $settings.statusBarOpacityPercent)
                }
                CodexDivider()

                SettingsInlineRow(
                    title: "状态圆灯颜色",
                    subtitle: "选择跟随任务状态、额度状态或固定单色"
                ) {
                    SettingsMenuPicker(
                        selection: $settings.statusBarIndicatorColorMode,
                        options: StatusCapsuleColorMode.allCases,
                        title: \.title,
                        swatchColor: \.swatchColor
                    )
                }
                CodexDivider()

                SettingsInlineRow(
                    title: "活动流光",
                    subtitle: "任务活动时，在状态栏和 Pet 胶囊显示顺时针边缘流光"
                ) {
                    SettingsSwitch(
                        isOn: $settings.statusBarWaveEnabled,
                        accessibilityLabel: "活动流光"
                    )
                }
                CodexDivider()

                SettingsInlineRow(
                    title: "活动流光颜色",
                    subtitle: "选择跟随任务状态或固定单色"
                ) {
                    SettingsMenuPicker(
                        selection: $settings.statusBarWaveColorMode,
                        options: StatusCapsuleColorMode.activityFlowCases,
                        title: \.title,
                        swatchColor: \.swatchColor
                    )
                }
                CodexDivider()

                SettingsInlineRow(
                    title: "自动展开任务浮窗",
                    subtitle: "Codex 开始工作时自动显示；关闭后仍可悬停胶囊查看"
                ) {
                    SettingsSwitch(
                        isOn: $settings.autoOpenTaskHoverEnabled,
                        accessibilityLabel: "自动展开任务浮窗"
                    )
                }
                CodexDivider()

                SettingsInlineRow(
                    title: "任务浮窗显示位置",
                    subtitle: "选择任务浮窗自动出现的显示器"
                ) {
                    SettingsMenuPicker(
                        selection: $settings.taskHoverDisplayMode,
                        options: TaskHoverDisplayMode.allCases,
                        title: \.title
                    )
                }
                }
                .settingsGroupSurface()
            }

            SettingsSection(
                title: "当前 Pet",
                subtitle: "未安装 Codexling Pet 时显示安装入口；安装后重扫并自动选中。"
            ) {
                VStack(spacing: 8) {
                if let pet = settings.selectedPet {
                    HStack(spacing: 12) {
                        PetSettingsThumbnail(pet: pet)
                            .frame(width: 58, height: 58)
                            .background(
                                Color.codexMuted.opacity(0.055),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(pet.displayName)
                                .font(.system(size: 14, weight: .semibold))
                            Text("\(pet.source.title) · v\(pet.spriteVersionNumber) · \(pet.rowCount) 行动画")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.codexMuted)
                        }

                        Spacer(minLength: 8)
                        petPicker
                    }
                    .padding(16)
                    .settingsGroupSurface()
                } else {
                    Text("没有发现可用 Pet。请安装 Codex，或把自定义 Pet 放入 ~/.codex/pets。")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.codexAmber)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .settingsGroupSurface()
                }

                if settings.codexPetRestartRequired {
                    codexPetRestartNotice
                }

                HStack(spacing: 10) {
                    let builtInCount = settings.availablePets.filter { $0.source == .codexBuiltIn }.count
                    let customCount = settings.availablePets.filter { $0.source == .custom }.count
                    Text("已发现 \(builtInCount) 个内置 Pet，\(customCount) 个自定义 Pet")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.codexMuted)
                    Spacer()
                    Button(action: openCustomPetsFolderInFinder) {
                        SettingsSecondaryActionLabel(
                            title: "打开文件夹",
                            systemImage: "folder"
                        )
                    }
                    .buttonStyle(CodexPressableStyle(cornerRadius: 7))
                    .help("在 Finder 中打开 ~/.codex/pets")
                    Button {
                        settings.reloadPets()
                        let builtIn = settings.availablePets.filter { $0.source == .codexBuiltIn }.count
                        let custom = settings.availablePets.filter { $0.source == .custom }.count
                        showToast("已扫描：\(builtIn) 个内置，\(custom) 个自定义 Pet")
                    } label: {
                        SettingsSecondaryActionLabel(
                            title: "重新扫描",
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .buttonStyle(CodexPressableStyle(cornerRadius: 7))
                }
                .padding(.horizontal, 4)

                if !settings.isCodexlingPetInstalled {
                    codexlingPetInstallationCard
                }

                if let installationError = settings.codexlingPetInstallationError {
                    Text("Codexling Pet 安装失败：\(installationError)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.codexRed)
                        .padding(.horizontal, 4)
                }
                }
            }
        }
    }

    private var thirdPartyPetResourcesSection: some View {
        SettingsSection(
            title: "更多 Pet",
            subtitle: "到下列站点下载更多精灵，放入 ~/.codex/pets 后点「重新扫描」。感谢 Petdex、codex-pets.net 与 GitHub 社区的整理与分享。"
        ) {
            VStack(spacing: 0) {
                SettingsExternalLinkRow(
                    icon: .symbol("safari"),
                    title: "codex-pets.net",
                    subtitle: "Pet 资源站",
                    url: URL(string: "https://codex-pets.net/")!
                )
                CodexDivider()
                SettingsExternalLinkRow(
                    icon: .symbol("safari"),
                    title: "Petdex",
                    subtitle: "Coding Agent Pet 图鉴",
                    url: URL(string: "https://petdex.dev/")!
                )
                CodexDivider()
                SettingsExternalLinkRow(
                    icon: .githubMark,
                    title: "Awesome Codex Pet",
                    subtitle: "GitHub 精选合集",
                    url: URL(string: "https://github.com/legeling/awesome-codex-pet")!
                )
            }
            .settingsGroupSurface()
        }
    }

    private var codexlingPetInstallationCard: some View {
        HStack(spacing: 12) {
            BundledCodexlingPetThumbnail()
                .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text("安装 Codexling Pet")
                    .font(.system(size: 14, weight: .semibold))
                Text("Codexling 的专属小精灵 · v2 · 11 行动画")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.codexMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                settings.installCodexlingPet()
                showCodexlingPetInstallToastIfNeeded()
            } label: {
                Label("安装", systemImage: "arrow.down.to.line")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(CodexlingPetInstallButtonStyle())
            .fixedSize()
        }
        .padding(16)
        .background(Color.codexGreen.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.codexGreen.opacity(0.20), lineWidth: 0.8))
    }

    private var petPicker: some View {
        let builtIns = settings.availablePets.filter { $0.source == .codexBuiltIn }
        let custom = settings.availablePets.filter { $0.source == .custom }

        return Button {
            showsPetPicker.toggle()
        } label: {
            SettingsMenuTriggerLabel(title: "选择", fontSize: 12)
        }
        .buttonStyle(CodexPressableStyle(cornerRadius: 7))
        .popover(isPresented: $showsPetPicker, arrowEdge: .bottom) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if !builtIns.isEmpty {
                        SettingsPopoverSection(title: "Codex 内置") {
                            LazyVGrid(columns: petPickerColumns, spacing: 6) {
                                ForEach(builtIns) { pet in
                                    petPopoverGridItem(pet)
                                }
                            }
                        }
                    }
                    if !custom.isEmpty {
                        SettingsPopoverSection(title: "自定义") {
                            LazyVGrid(columns: petPickerColumns, spacing: 6) {
                                ForEach(custom) { pet in
                                    petPopoverGridItem(pet)
                                }
                            }
                        }
                    }
                }
                .padding(8)
            }
            .frame(width: 330)
            .frame(maxHeight: 520)
        }
        .fixedSize()
    }

    private var petPickerColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 84), spacing: 6),
            count: 3
        )
    }

    private func petPopoverGridItem(_ pet: CodexPet) -> some View {
        let isSelected = settings.selectedPetID == pet.id

        return Button {
            guard !isSelected else {
                showsPetPicker = false
                return
            }
            settings.selectedPetID = pet.id
            showsPetPicker = false
            if let error = settings.codexPetSyncError {
                showToast("Codex Pet 同步失败：\(error)", systemImage: "exclamationmark.triangle.fill")
            } else {
                showToast("已写入 Codex，重启后切换为 \(pet.displayName)", systemImage: "arrow.clockwise.circle.fill")
            }
        } label: {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    PetSettingsThumbnail(pet: pet)
                        .frame(width: 58, height: 58)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.codexPrimary)
                            .background(Color.codexBackground, in: Circle())
                    }
                }
                .frame(maxWidth: .infinity)

                Text(pet.displayName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)
            }
            .padding(6)
            .background(
                isSelected
                    ? Color.codexPrimary.opacity(0.10)
                    : Color.codexMuted.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected
                            ? Color.codexPrimary.opacity(0.50)
                            : Color.codexMuted.opacity(0.10),
                        lineWidth: isSelected ? 1.2 : 0.7
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isSelected
                ? "\(pet.displayName)，当前已选择"
                : pet.displayName
        )
    }

    private var codexPetRestartNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.codexAmber)

            VStack(alignment: .leading, spacing: 2) {
                Text("Codex 重启后生效")
                    .font(.system(size: 12, weight: .semibold))
                Text("当前运行中的 Pet 不会自动刷新。")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.codexMuted)
            }

            Spacer(minLength: 8)

            Button {
                showsCodexRestartConfirmation = true
            } label: {
                if isRestartingCodex {
                    ProgressView()
                        .controlSize(.small)
                        .frame(minWidth: 64)
                } else {
                    Text("重启 Codex")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                }
            }
            .buttonStyle(CodexPressableStyle(cornerRadius: 7))
            .disabled(isRestartingCodex)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.codexAmber.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.codexAmber.opacity(0.24), lineWidth: 0.8)
        }
    }

    private func restartCodex() {
        guard !isRestartingCodex else { return }
        isRestartingCodex = true
        Task { @MainActor in
            do {
                try await CodexApplicationController().restart()
                settings.markCodexPetRestartCompleted()
                showToast("Codex 已重新打开，Pet 已生效", systemImage: "pawprint.fill")
            } catch {
                showToast("无法重启 Codex：\(error.localizedDescription)", systemImage: "exclamationmark.triangle.fill")
            }
            isRestartingCodex = false
        }
    }

    private func openCustomPetsFolderInFinder() {
        let directory = CodexPetCatalog.defaultCustomPetsRoot
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(directory)
            showToast("已在 Finder 中打开 Pet 文件夹", systemImage: "folder.fill")
        } catch {
            showToast("无法打开 Pet 文件夹：\(error.localizedDescription)", systemImage: "exclamationmark.triangle.fill")
        }
    }

    private func showCodexlingPetInstallToastIfNeeded() {
        if settings.isCodexlingPetInstalled {
            showToast("Codexling Pet 已安装到本机 Codex")
            return
        }
        if let error = settings.codexlingPetInstallationError {
            showToast("Codexling Pet 安装失败：\(error)", systemImage: "exclamationmark.triangle.fill")
        }
    }

    private func showToast(_ message: String, systemImage: String = "checkmark.circle.fill") {
        toastDismissGeneration += 1
        let generation = toastDismissGeneration
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            toast = SettingsToast(message: message, systemImage: systemImage)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            guard generation == toastDismissGeneration else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                toast = nil
            }
        }
    }
}

private struct SettingsToast: Equatable {
    let message: String
    let systemImage: String
}

private struct ScrollIndicatorHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        hideIndicators(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        hideIndicators(from: nsView)
    }

    private func hideIndicators(from view: NSView) {
        DispatchQueue.main.async {
            guard let scrollView = view.enclosingScrollView else { return }
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
        }
    }
}

private struct PetSettingsThumbnail: View {
    let pet: CodexPet
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(4)
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.codexMuted)
            }
        }
        .task(id: pet.id) {
            guard let frame = await PetThumbnailLoader.shared.frame(
                for: pet.spritesheetURL
            ) else {
                image = nil
                return
            }
            image = NSImage(
                cgImage: frame,
                size: NSSize(
                    width: PetSpriteSheet.cellWidth,
                    height: PetSpriteSheet.cellHeight
                )
            )
        }
        .accessibilityLabel(pet.displayName)
    }
}

private actor PetThumbnailLoader {
    static let shared = PetThumbnailLoader()

    private var frames: [URL: CGImage] = [:]
    private var failedURLs = Set<URL>()

    func preload(_ urls: [URL]) {
        for url in urls {
            _ = frame(for: url)
        }
    }

    func frame(for url: URL) -> CGImage? {
        if let cached = frames[url] {
            return cached
        }
        guard !failedURLs.contains(url),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let spritesheet = CGImageSourceCreateImageAtIndex(source, 0, nil),
              spritesheet.width == PetSpriteSheet.cellWidth * 8,
              spritesheet.height >= PetSpriteSheet.cellHeight,
              let frame = spritesheet.cropping(
                  to: CGRect(
                      x: 0,
                      y: 0,
                      width: PetSpriteSheet.cellWidth,
                      height: PetSpriteSheet.cellHeight
                  )
              ) else {
            failedURLs.insert(url)
            return nil
        }
        frames[url] = frame
        return frame
    }
}

private struct BundledCodexlingPetThumbnail: View {
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(4)
            } else {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.codexPrimary)
            }
        }
        .task {
            guard let directory = CodexlingPetInstaller.bundledPetDirectory() else { return }
            image = PetSpriteSheet(url: directory.appendingPathComponent("spritesheet.webp"))?.frame(
                row: 0,
                column: 0,
                displayHeight: 52
            )
        }
        .accessibilityLabel("Codexling Pet 预览")
    }
}

private struct CodexlingPetInstallButtonStyle: PrimitiveButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let isDark = colorScheme == .dark
        let backgroundColor: Color = if isDark {
            Color.white.opacity(0.11)
        } else {
            Color.codexPrimary
        }
        let foregroundColor: Color = if isDark {
            Color.white.opacity(isEnabled ? 0.96 : 0.42)
        } else {
            Color.white.opacity(isEnabled ? 1 : 0.58)
        }

        CodexMaterialWaveButtonBody(
            action: { configuration.trigger() },
            cornerRadius: 8,
            ink: .softLight
        ) {
            configuration.label
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(backgroundColor.opacity(isEnabled ? 1 : 0.60))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            isDark ? Color.white.opacity(isEnabled ? 0.16 : 0.08) : Color.black.opacity(0.08),
                            lineWidth: 0.8
                        )
                )
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.codexMuted)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsInlineRow<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.codexMuted)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 58)
    }
}

private struct SettingsMenuTriggerLabel: View {
    let title: String
    var fontSize: CGFloat = 13
    var swatchColor: Color? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let swatchColor {
                Circle()
                    .fill(swatchColor)
                    .frame(width: 8, height: 8)
                    .overlay {
                        Circle().stroke(Color.white.opacity(0.72), lineWidth: 0.7)
                    }
            }
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(Color.codexMuted.opacity(0.9))
                .imageScale(.small)
        }
        .font(.system(size: fontSize, weight: .medium))
        .foregroundStyle(Color.codexInk.opacity(0.90))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Color.codexMuted.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.codexLine.opacity(0.66), lineWidth: 0.7)
        }
    }
}

private struct SettingsSecondaryActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Color.codexInk.opacity(0.84))
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                Color.codexCard.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.codexLine.opacity(0.72), lineWidth: 0.7)
            }
    }
}

private struct SettingsPopoverSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.codexMuted)
                .padding(.horizontal, 8)
                .padding(.top, 2)
            content
        }
    }
}

private struct SettingsMenuPicker<Option: Hashable & Identifiable>: View {
    @Binding var selection: Option
    let options: [Option]
    let title: (Option) -> String
    var swatchColor: (Option) -> Color? = { _ in nil }
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            SettingsMenuTriggerLabel(
                title: title(selection),
                swatchColor: swatchColor(selection)
            )
        }
        .buttonStyle(CodexPressableStyle(cornerRadius: 7))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(options) { option in
                    Button {
                        selection = option
                        isPresented = false
                    } label: {
                        HStack(spacing: 8) {
                            if let color = swatchColor(option) {
                                Circle()
                                    .fill(color)
                                    .frame(width: 9, height: 9)
                                    .overlay {
                                        Circle().stroke(Color.white.opacity(0.72), lineWidth: 0.7)
                                    }
                            }
                            Text(title(option))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if selection == option {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .font(.system(size: 13))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .frame(minWidth: 140)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct SettingsPercentageSlider: View {
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 9) {
            Slider(value: $value, in: 0...50, step: 1)
                .frame(width: 108)
                .tint(Color.accentColor)
                .accessibilityLabel("胶囊透明度")

            Text("\(Int(value.rounded()))%")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.codexInk.opacity(0.82))
                .frame(width: 34, alignment: .trailing)
        }
    }
}

private struct SettingsSwitch: View {
    @Binding var isOn: Bool
    let accessibilityLabel: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Color.accentColor : inactiveTrack)
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .padding(3)
                    .shadow(color: Color.black.opacity(0.16), radius: 1.5, y: 1)
            }
            .frame(width: 38, height: 22)
            .contentShape(Capsule())
        }
        .buttonStyle(SettingsSwitchButtonStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isOn ? "已开启" : "已关闭")
        .accessibilityAddTraits(.isButton)
    }

    private var inactiveTrack: Color {
        colorScheme == .dark
            ? Color(red: 0.30, green: 0.31, blue: 0.32)
            : Color(red: 0.78, green: 0.79, blue: 0.80)
    }
}

private struct SettingsSwitchButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CodexMaterialWaveButtonBody(
            action: { configuration.trigger() },
            cornerRadius: 12,
            usesCapsule: true,
            ink: .adaptiveMint
        ) {
            configuration.label
        }
    }
}

private enum SettingsLinkIcon {
    case symbol(String)
    case githubMark
}

private struct SettingsLinkIconView: View {
    let icon: SettingsLinkIcon
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch icon {
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: 13, weight: .semibold))
            case .githubMark:
                GitHubMarkIcon()
            }
        }
        .foregroundStyle(iconForeground)
        .frame(width: 32, height: 32)
        .background(iconBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(iconBorder, lineWidth: 0.7)
        }
    }

    private var iconForeground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.82)
            : Color.codexPrimary.opacity(0.90)
    }

    private var iconBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.07)
            : Color.codexPrimary.opacity(0.06)
    }

    private var iconBorder: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.codexLine.opacity(0.58)
    }
}

private struct GitHubMarkIcon: View {
    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: "github-mark", withExtension: "svg"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 17, height: 17)
            } else {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 13, weight: .semibold))
            }
        }
    }
}

private struct SettingsExternalLinkRow: View {
    let icon: SettingsLinkIcon
    let title: String
    let subtitle: String
    let url: URL
    @Environment(\.openURL) private var openURL

    init(
        icon: SettingsLinkIcon,
        title: String,
        subtitle: String,
        url: URL
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.url = url
    }

    var body: some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: 12) {
                SettingsLinkIconView(icon: icon)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.codexInk)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.codexMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.codexMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(CodexPressableStyle(cornerRadius: 12))
        .accessibilityLabel("\(title)，\(subtitle)")
        .accessibilityHint("在浏览器中打开")
    }
}

private enum SettingsMeasuredContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    func settingsGroupSurface() -> some View {
        modifier(SettingsGroupSurfaceModifier())
    }
}

struct SettingsGroupSurfaceModifier: ViewModifier {
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        content
            .background(Color.codexCard.opacity(0.72), in: shape)
            .overlay {
                shape.stroke(
                    CodexDivider.color,
                    lineWidth: CodexDivider.renderedThickness(displayScale: displayScale)
                )
            }
    }
}
