import AppKit
import SwiftUI

private enum SettingsLayoutMetrics {
    static let sectionSpacing: CGFloat = 24
    static let sidebarWidth: CGFloat = 166
    /// Clears the native traffic lights without reserving a separate title row.
    static let windowTopInset: CGFloat = 14
    static let sidebarTopInset: CGFloat = 14
    static let windowBottomInset: CGFloat = 12
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
        case .accounts: "管理本机账号与 API Key"
        case .agents: "接入并管理本地 Coding Agent"
        case .general: "更新、外观、布局与刷新"
        case .pet: "菜单栏、任务浮窗与 Pet"
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
    var authorizationOnly = false

    var id: String { "\(agentID.rawValue)-\(installs ? "install" : "uninstall")" }
}

struct SettingsView: View {
    @Bindable var store: UsageSnapshotStore
    @Bindable var settings: AppSettingsStore
    @Bindable var multiAgentSettings: MultiAgentSettingsStore
    @Bindable var updater: AppUpdateController
    let layout: UsagePanelLayout
    let onLogout: () -> Void
    var onMeasuredContentHeightChange: (CGFloat) -> Void = { _ in }
    @State private var showsLogoutConfirmation = false
    @State private var showsPetPicker = false
    @State private var showsCodexRestartConfirmation = false
    @State private var isRestartingCodex = false
    @State private var pendingHookAction: PendingAgentHookAction?
    @State private var pendingAccountRemoval: PendingAccountRemoval?
    @State private var showsConnectionSheet = false
    @State private var toast: SettingsToast?
    @State private var toastDismissGeneration = 0
    @State private var selectedTab: SettingsTab = .accounts
    @State private var showsStickySettingsTitle = false
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
            .overlay {
                if showsConnectionSheet {
                    ZStack {
                        Rectangle()
                            .fill(Color.black.opacity(0.25))
                            .background(.ultraThinMaterial)
                            .ignoresSafeArea()
                            .onTapGesture { showsConnectionSheet = false }

                        AccountConnectionsModalView(store: multiAgentSettings) {
                            showsConnectionSheet = false
                        }
                        .padding(14)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                    }
                    .zIndex(20)
                }
            }
            .animation(.easeOut(duration: 0.18), value: showsConnectionSheet)
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
            .alert(item: $pendingAccountRemoval) { pending in
                accountRemovalAlert(pending)
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
            .onChange(of: settings.accountCarouselInterval) { _, interval in
                showToast("账号自动轮播：\(interval.title)")
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
            .onChange(of: updater.phase) { oldPhase, phase in
                handleUpdaterPhaseChange(from: oldPhase, to: phase)
            }
    }

    private var baseContent: some View {
        Group {
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
                    .padding(.top, SettingsLayoutMetrics.windowTopInset)
                    .padding(.bottom, SettingsLayoutMetrics.windowBottomInset)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: SettingsMeasuredContentHeightKey.self,
                                value: geometry.size.height
                            )
                        }
                    }
            }
            .coordinateSpace(name: SettingsScrollCoordinateSpace.name)
            .onPreferenceChange(SettingsHeaderMinYKey.self) { minY in
                if showsStickySettingsTitle {
                    if minY > -44 {
                        showsStickySettingsTitle = false
                    }
                } else if minY < -72 {
                    showsStickySettingsTitle = true
                }
            }
            .scrollIndicators(.hidden)
            .background {
                ZStack {
                    Color.codexBackground.opacity(0.50)
                    ScrollIndicatorHider()
                }
            }
        }
        .overlay(alignment: .top) {
            if showsStickySettingsTitle {
                HStack(alignment: .top, spacing: 0) {
                    Color.clear
                        .frame(width: SettingsLayoutMetrics.sidebarWidth + 1, height: 110)
                    stickySettingsTitle
                }
                .offset(y: -34)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: showsStickySettingsTitle)
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
        .padding(.top, SettingsLayoutMetrics.sidebarTopInset)
        .padding(.bottom, 14)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.codexCard.opacity(0.72))
    }

    private var selectedSettingsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedTab.title)
                    .font(.system(size: 20, weight: .bold))
                Text(selectedTab.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.codexMuted)
            }
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: SettingsHeaderMinYKey.self,
                        value: geometry.frame(in: .named(SettingsScrollCoordinateSpace.name)).minY
                    )
                }
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

    private var stickySettingsTitle: some View {
        Text(selectedTab.title)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Color.codexInk)
            .padding(.horizontal, 20)
            .padding(.top, 19)
            .frame(height: 110, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                LinearGradient(
                    stops: [
                        .init(color: Color.codexBackground, location: 0),
                        .init(color: Color.codexBackground, location: 0.48),
                        .init(color: Color.codexBackground.opacity(0.72), location: 0.72),
                        .init(color: Color.codexBackground.opacity(0), location: 1),
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomTrailing
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
            subtitle: "按供应商分组，凭据彼此隔离。"
        ) {
            VStack(spacing: 12) {
                // 添加按钮置顶，避免数据多时需滚动到底部
                if store.isLoggedIn
                    || !multiAgentSettings.codexAccounts.isEmpty
                    || !multiAgentSettings.deepSeekConnections.isEmpty {
                    Button {
                        showsConnectionSheet = true
                    } label: {
                        Label("添加供应商", systemImage: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                    .buttonStyle(CodexPressableStyle(cornerRadius: 9))
                    .foregroundStyle(Color.accentColor)
                }

                if store.isLoggedIn || !multiAgentSettings.codexAccounts.isEmpty {
                    accountProviderGroup(
                        name: "Codex",
                        detail: "账号",
                        count: (store.isLoggedIn ? 1 : 0) + multiAgentSettings.codexAccounts.count
                    ) {
                        if store.isLoggedIn {
                            accountPoolRow(
                                asset: .codex,
                                title: store.snapshot.companionAccountName,
                                subtitle: store.snapshot.accountEmail,
                                badge: store.snapshot.planName.isEmpty ? "当前 Codex" : store.snapshot.planName,
                                badgeColor: Color.codexGreen,
                                actionTitle: "退出"
                            ) {
                                showsLogoutConfirmation = true
                            }
                            if !multiAgentSettings.codexAccounts.isEmpty {
                                CodexDivider()
                            }
                        }

                        ForEach(multiAgentSettings.codexAccounts) { connection in
                            accountPoolRow(
                                asset: .codex,
                                title: connection.label,
                                subtitle: connection.usage?.accountEmail ?? "Codex 账号",
                                badge: connection.authenticationState == .connected ? "已连接" : "待登录",
                                badgeColor: connection.authenticationState == .connected ? Color.codexGreen : Color.codexAmber,
                                actionTitle: "删除"
                            ) {
                                pendingAccountRemoval = .codex(connection)
                            }
                            if connection.id != multiAgentSettings.codexAccounts.last?.id {
                                CodexDivider()
                            }
                        }
                    }
                }

                if !multiAgentSettings.deepSeekConnections.isEmpty {
                    accountProviderGroup(
                        name: "DeepSeek",
                        detail: "API Key",
                        count: multiAgentSettings.deepSeekConnections.count
                    ) {
                        ForEach(multiAgentSettings.deepSeekConnections) { connection in
                            accountPoolRow(
                                asset: .deepSeek,
                                title: connection.label,
                                subtitle: "sk-•••• \(connection.keySuffix)",
                                badge: deepSeekPoolBadge(connection),
                                badgeColor: deepSeekPoolColor(connection),
                                actionTitle: "删除"
                            ) {
                                pendingAccountRemoval = .deepSeek(connection)
                            }
                            if connection.id != multiAgentSettings.deepSeekConnections.last?.id {
                                CodexDivider()
                            }
                        }
                    }
                }

                if !store.isLoggedIn,
                   multiAgentSettings.codexAccounts.isEmpty,
                   multiAgentSettings.deepSeekConnections.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.badge.plus")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color.codexMuted)
                        Text("账户池为空")
                            .font(.system(size: 12, weight: .semibold))

                        Button {
                            showsConnectionSheet = true
                        } label: {
                            Label("添加供应商", systemImage: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 16)
                                .frame(height: 36)
                        }
                        .buttonStyle(CodexPressableStyle(cornerRadius: 8))
                        .foregroundStyle(Color.accentColor)
                    }
                    .frame(maxWidth: .infinity, minHeight: 148)
                    .padding(16)
                    .settingsGroupSurface()
                }
            }
        }
    }

    private func accountProviderGroup<Content: View>(
        name: String,
        detail: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.codexMuted)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.codexMuted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.codexMuted.opacity(0.09), in: Capsule())
            }
            .padding(.horizontal, 14)
            .frame(height: 34)

            CodexDivider()
            content()
        }
        .settingsGroupSurface()
    }

    private func accountPoolRow(
        asset: BrandAssetID,
        title: String,
        subtitle: String,
        badge: String,
        badgeColor: Color,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            BrandIconView(asset: asset, size: 38, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(badgeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(badgeColor.opacity(0.10), in: Capsule())
                }
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button(actionTitle, action: action)
                .buttonStyle(.plain)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Color.codexRed)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.codexRed.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.codexRed.opacity(0.14), lineWidth: 0.7)
                }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 64)
    }

    private func accountRemovalAlert(_ pending: PendingAccountRemoval) -> Alert {
        Alert(
            title: Text(pending.title),
            message: Text(pending.message),
            primaryButton: .destructive(Text("删除")) {
                switch pending {
                case let .codex(connection):
                    multiAgentSettings.removeCodexAccount(connection)
                case let .deepSeek(connection):
                    multiAgentSettings.removeDeepSeekConnection(connection)
                }
            },
            secondaryButton: .cancel(Text("取消"))
        )
    }

    private func deepSeekPoolBadge(_ connection: DeepSeekAPIConnection) -> String {
        guard connection.authenticationState == .connected else { return "异常" }
        guard let total = connection.balance?.total else { return "待查询" }
        return "¥\(total)"
    }

    private func deepSeekPoolColor(_ connection: DeepSeekAPIConnection) -> Color {
        ProviderBalanceIndicator.resolve(
            total: connection.balance?.total,
            authenticationState: connection.authenticationState
        ).color
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
            title: "接入状态",
            subtitle: "Codex 无需配置；其他 Agent 仅向本地 Bridge 上报脱敏生命周期事件。"
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
            Label("无需配置", systemImage: "checkmark.circle.fill")
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
            case .notInstalled, .authorizationRequired, .conflict, .failed:
                Button(integration.hookState == .authorizationRequired ? "完成授权" : "安装") {
                    pendingHookAction = PendingAgentHookAction(
                        agentID: integration.id,
                        agentName: integration.name,
                        installs: true,
                        authorizationOnly: integration.hookState == .authorizationRequired
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
            let authorization = pending.agentID == .hermes
                ? "；同时仅授权这 7 条 Codexling Bridge 命令，不会开启 Hermes 的全局 Hook 自动批准"
                : ""
            if pending.authorizationOnly {
                return "将重新校准 Codexling 的 Hermes Hook，并仅授权 7 条 Codexling Bridge 命令；不会开启 Hermes 的全局 Hook 自动批准。"
            }
            return "配置变更预览：新增 \(eventCount) 个 lifecycle command hook\(authorization)。命令只调用 Codexling 本地 Bridge；不读取 prompt、回复、tool 参数、命令、环境变量或 transcript。Agent/Codexling 未运行时 Hook 会 fail-open。"
        }
        return "只移除命令中包含 codexling-agent-bridge 的配置项；其他 Hook 与 Agent 配置保持不变。"
    }

    private func hookActionAlert(_ pending: PendingAgentHookAction) -> Alert {
        if pending.installs {
            let actionTitle = pending.authorizationOnly ? "完成 Hermes Hook 授权？" : "安装 \(pending.agentName) Hook？"
            let actionLabel = pending.authorizationOnly ? "完成授权" : "安装"
            return Alert(
                title: Text(actionTitle),
                message: Text(hookConfirmationMessage(for: pending)),
                primaryButton: .default(Text(actionLabel)) {
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
        if integration.id == .codex { return "内置" }
        if integration.cliInstalled && integration.desktopInstalled { return "CLI + Desktop" }
        if integration.cliInstalled { return "CLI" }
        if integration.desktopInstalled { return "Desktop" }
        return "未发现"
    }

    private func agentAvailabilityColor(_ integration: AgentIntegrationStatus) -> Color {
        if integration.id == .codex { return Color.codexGreen }
        return integration.cliInstalled || integration.desktopInstalled ? Color.codexGreen : Color.codexMuted
    }

    private func hookStatusLine(_ integration: AgentIntegrationStatus) -> String {
        if integration.id == .codex {
            return integration.cliInstalled || integration.desktopInstalled
                ? "已接入"
                : "已就绪 · Codex 启动后自动接入"
        }
        return switch integration.hookState {
        case .builtIn: "已接入"
        case .notInstalled: "未接入"
        case .authorizationRequired: "已配置 · 等待授权"
        case .installed: "已接入 · 仅本地脱敏事件"
        case .unavailable(let message): message
        case .conflict(let message), .failed(let message): message
        }
    }

    private func hookStatusColor(_ state: AgentHookInstallationState) -> Color {
        switch state {
        case .builtIn, .installed: Color.codexGreen
        case .conflict, .failed: Color.codexRed
        case .notInstalled, .authorizationRequired, .unavailable: Color.codexMuted
        }
    }

    private var updateSection: some View {
        SettingsSection(title: "应用与偏好") {
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
                accountCarouselSection
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

    private var accountCarouselSection: some View {
        SettingsInlineRow(
            title: "账号自动轮播",
            subtitle: "按设定间隔自动切换账号；鼠标停在 logo 行时暂停"
        ) {
            SettingsMenuPicker(
                selection: $settings.accountCarouselInterval,
                options: AccountCarouselInterval.allCases,
                title: \.title
            )
        }
    }

    private var petSection: some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            SettingsSection(
                title: "状态显示"
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
                    title: "刘海面板显示位置",
                    subtitle: "选择显示刘海面板的显示器（其余显示器显示降级胶囊）"
                ) {
                    SettingsMenuPicker(
                        selection: $settings.notchDisplayTarget,
                        options: notchDisplayOptions,
                        title: { notchDisplayTitle($0) }
                    )
                }
                }
                .settingsGroupSurface()
            }

            SettingsSection(
                title: "Pet 选择"
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
            title: "Pet 资源",
            subtitle: "下载后放入 ~/.codex/pets，再返回上方重新扫描。"
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
            .scrollIndicators(.hidden)
            .background(ScrollIndicatorHider())
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

private enum PendingAccountRemoval: Identifiable {
    case codex(CodexAccountConnection)
    case deepSeek(DeepSeekAPIConnection)

    var id: ConnectionID {
        switch self {
        case let .codex(connection): connection.id
        case let .deepSeek(connection): connection.id
        }
    }

    var title: String {
        switch self {
        case .codex: "删除 Codex 账号？"
        case .deepSeek: "删除 DeepSeek API Key？"
        }
    }

    var message: String {
        switch self {
        case let .codex(connection):
            "将删除 \(connection.label) 的本地独立运行目录和连接记录，不会删除供应商侧账号。"
        case let .deepSeek(connection):
            "将从本机 Keychain 删除 \(connection.label) 的 API Key 和连接记录，此操作无法撤销。"
        }
    }
}

struct ScrollIndicatorHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ScrollIndicatorHiderView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ScrollIndicatorHiderView)?.scheduleUpdate()
    }
}

private final class ScrollIndicatorHiderView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        scheduleUpdate()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleUpdate()
    }

    override func layout() {
        super.layout()
        hideIndicators()
    }

    func scheduleUpdate() {
        for delay in [0.0, 0.05, 0.25] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.hideIndicators()
            }
        }
    }

    private func hideIndicators() {
        guard let rootView = window?.contentView else { return }
        let markerRect = convert(bounds, to: nil)
        var candidates: [NSScrollView] = []
        collectScrollViews(in: rootView, into: &candidates)
        guard let scrollView = candidates
            .filter({ $0.convert($0.bounds, to: nil).intersects(markerRect) })
            .min(by: { scrollViewArea($0) < scrollViewArea($1) })
        else { return }

        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScroller?.isHidden = true
        scrollView.horizontalScroller?.isHidden = true
        scrollView.verticalScroller?.alphaValue = 0
        scrollView.horizontalScroller?.alphaValue = 0
        scrollView.autohidesScrollers = true
    }

    private func collectScrollViews(in view: NSView, into result: inout [NSScrollView]) {
        if let scrollView = view as? NSScrollView {
            result.append(scrollView)
        }
        for subview in view.subviews {
            collectScrollViews(in: subview, into: &result)
        }
    }

    private func scrollViewArea(_ scrollView: NSScrollView) -> CGFloat {
        let rect = scrollView.convert(scrollView.bounds, to: nil)
        return rect.width * rect.height
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

private enum SettingsScrollCoordinateSpace {
    static let name = "settings-content-scroll"
}

private enum SettingsHeaderMinYKey: PreferenceKey {
    static let defaultValue = CGFloat.greatestFiniteMagnitude

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
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

// MARK: - 刘海显示器选项（系统 API 动态获取）

private var notchDisplayOptions: [NotchDisplayTarget] {
    var options: [NotchDisplayTarget] = []
    for screen in NSScreen.screens {
        options.append(.specificScreen(screen.screenNumber))
    }
    // 特殊选项放到最后。
    options.append(.allDisplays)
    options.append(.off)
    return options
}

private func notchDisplayTitle(_ target: NotchDisplayTarget) -> String {
    switch target {
    case .off:
        return "所有显示器都不开刘海"
    case .allDisplays:
        return "所有显示器"
    case .specificScreen(let number):
        return NSScreen.screens.first(where: { $0.screenNumber == number })?.displayName
            ?? "显示器 \(number)"
    }
}
