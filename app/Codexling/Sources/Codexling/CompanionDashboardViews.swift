import AppKit
import SwiftUI

struct CompanionDashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var store: UsageSnapshotStore
    @Bindable var settings: AppSettingsStore
    @Bindable var multiAgentSettings: MultiAgentSettingsStore
    @Bindable var activityStore: CodexActivityStore
    @Bindable var frameStore: PetFrameStore
    @Bindable var companionStatsStore: CompanionStatsStore
    let actions: UsageActions
    let layout: UsagePanelLayout
    let showsDetachedButton: Bool
    let onOpenSettings: () -> Void
    /// 竖向独立窗口上报内容自然高度。
    var onMeasuredContentHeightChange: (CGFloat, String) -> Void = { _, _ in }

    @State private var selectedTaskID: String?
    @State private var showsConnectionSheet = false

    private var selectedProviderContext: DashboardProviderContext {
        if let connection = multiAgentSettings.selectedDeepSeekConnection {
            let balanceText = connection.balance.map { balance in
                let value = NSDecimalNumber(decimal: balance.total).stringValue
                return balance.currency == "CNY" ? "¥\(value)" : "\(balance.currency) \(value)"
            } ?? "待查询"
            let isConnected = connection.authenticationState == .connected
            return DashboardProviderContext(
                asset: .deepSeek,
                title: connection.label,
                subtitle: "sk-•••• \(connection.keySuffix)",
                badge: "DeepSeek",
                badgeColor: .codexGreen,
                statusText: isConnected ? balanceText : "需要检查",
                statusColor: isConnected ? .codexGreen : .codexAmber,
                summaryText: "DeepSeek API · Key 保存在 macOS Keychain",
                accountLinkTitle: "DeepSeek 控制台",
                accountLinkURL: DashboardProviderLinks.deepSeekUsage,
                officialLinkHelp: "打开 DeepSeek 官方 Usage",
                officialLinkURL: DashboardProviderLinks.deepSeekUsage,
                syncState: isConnected ? "成功" : "Key 异常",
                syncedAt: connection.balance?.fetchedAt ?? connection.createdAt,
                isRefreshing: store.isUnifiedRefreshing,
                emphasizesAccountLink: false
            )
        }

        if let connection = multiAgentSettings.selectedCodexAccount {
            let isConnected = connection.authenticationState == .connected
            return DashboardProviderContext(
                asset: .codex,
                title: connection.label,
                subtitle: connection.usage?.email ?? "独立 CODEX_HOME",
                badge: connection.usage?.planType ?? "Codex",
                badgeColor: isConnected ? .codexGreen : .codexAmber,
                statusText: isConnected ? activityStore.snapshot.state.taskLabel : "待登录",
                statusColor: isConnected ? activityStore.snapshot.state.statusColor : .codexAmber,
                summaryText: "独立 Codex 账号",
                accountLinkTitle: "Codex Usage",
                accountLinkURL: DashboardProviderLinks.codexUsage,
                officialLinkHelp: "打开 Codex 官方 Usage",
                officialLinkURL: DashboardProviderLinks.codexUsage,
                syncState: isConnected ? "成功" : "待登录",
                syncedAt: connection.usage?.fetchedAt ?? connection.createdAt,
                isRefreshing: store.isUnifiedRefreshing,
                emphasizesAccountLink: false
            )
        }

        return DashboardProviderContext(
            asset: .codex,
            title: store.snapshot.companionAccountName,
            subtitle: store.snapshot.accountEmail,
            badge: store.snapshot.companionPlanBadgeText,
            badgeColor: .codexGreen,
            statusText: activityStore.snapshot.state.taskLabel,
            statusColor: activityStore.snapshot.state.statusColor,
            summaryText: store.snapshot.subscriptionCompactSummaryLine ?? "订阅与账单",
            accountLinkTitle: "官方 Billing",
            accountLinkURL: ChatGPTWebLinks.billingPage,
            officialLinkHelp: "打开 Codex 官方 Usage",
            officialLinkURL: DashboardProviderLinks.codexUsage,
            syncState: store.snapshot.refreshState,
            syncedAt: store.snapshot.fetchedAt,
            isRefreshing: store.snapshot.refreshState == "刷新中",
            emphasizesAccountLink: store.snapshot.showsSubscriptionExpiryReminder
        )
    }

    private func refreshSelectedProvider() {
        actions.refresh()
    }

    var body: some View {
        Group {
            switch settings.dashboardOrientation {
            case .horizontal:
                dashboard
            case .vertical:
                verticalDashboard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.codexInk)
        .overlay(alignment: .topLeading) {
            if layout == .window {
                verticalDashboardHeightProbe
            }
        }
        .onPreferenceChange(DashboardMeasuredContentSizeKey.self) { size in
            guard layout == .window,
                  DetachedWindowMetrics.isValidVerticalMeasurement(size) else {
                return
            }
            onMeasuredContentHeightChange(size.height, verticalDashboardMeasureIdentity)
        }
        .onChange(of: activityStore.snapshot.activeTasks.map(\.id)) { _, ids in
            if let selectedTaskID, !ids.contains(selectedTaskID) {
                self.selectedTaskID = ids.first
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = store.refreshToast {
                Label(
                    toast.message,
                    systemImage: toast.isSuccess
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill"
                )
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(minHeight: 38)
                .background(.black.opacity(0.86), in: Capsule(style: .continuous))
                .padding(.horizontal, 14)
                .padding(.bottom, layout == .window ? 60 : 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityLabel(toast.message)
                .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: store.refreshToast)
        .overlay {
            if showsConnectionSheet {
                ZStack {
                    Rectangle()
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.52 : 0.20))
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

    private var dashboard: some View {
        Group {
            if layout == .window {
                horizontalDashboardWindowLayout
            } else {
                horizontalDashboardCompactLayout
            }
        }
    }

    /// 独立横版：`GeometryReader` 贴合 AppKit contentLayoutRect，避免 frame/content 偏差。
    private var horizontalDashboardWindowLayout: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 0) {
                CompanionSidebar(
                    snapshot: store.snapshot,
                    activity: activityStore.snapshot,
                    integrations: multiAgentSettings.integrations,
                    settings: settings,
                    frameStore: frameStore,
                    todayMinutes: companionStatsStore.todayMinutes,
                    fillColumnHeight: true
                )
                .frame(width: DetachedWindowMetrics.sidebarWidth)
                .zIndex(2)

                VStack(spacing: 0) {
                    dashboardConnectionBar
                    if multiAgentSettings.selectedDeepSeekConnection == nil {
                        CompanionHorizontalAccountHeader(
                            context: selectedProviderContext
                        )
                    }
                    horizontalDashboardMainContent
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    horizontalDashboardSyncFooter
                        .layoutPriority(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color.codexCard.opacity(0.96))
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .background {
                DashboardWindowChromeBackground()
            }
        }
    }

    private var horizontalDashboardCompactLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            CompanionSidebar(
                snapshot: store.snapshot,
                activity: activityStore.snapshot,
                integrations: multiAgentSettings.integrations,
                settings: settings,
                frameStore: frameStore,
                todayMinutes: companionStatsStore.todayMinutes,
                expandsVertically: false
            )
            .frame(width: DetachedWindowMetrics.sidebarWidth)
            .zIndex(2)

            VStack(spacing: 0) {
                dashboardConnectionBar
                if multiAgentSettings.selectedDeepSeekConnection == nil {
                    CompanionHorizontalAccountHeader(
                        context: selectedProviderContext
                    )
                }
                horizontalDashboardRightColumn
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            DashboardWindowChromeBackground()
                .ignoresSafeArea()
        }
    }

    /// 右栏决定横版独立窗口高度；勿把侧栏 `maxHeight: .infinity` 算进测高。
    private var horizontalDashboardRightColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            horizontalDashboardMainContent
            horizontalDashboardSyncFooter
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Color.codexCard.opacity(0.96))
    }

    private var horizontalDashboardMainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ActivityHeading(
                activity: activityStore.snapshot,
                usage: store.snapshot,
                isLoggedIn: store.isLoggedIn
            )

            if store.snapshot.showsSubscriptionExpiryReminder,
               let message = store.snapshot.subscriptionExpiryReminderMessage {
                SubscriptionExpiryReminderBanner(message: message)
                    .padding(.top, 12)
            }

            TaskStackView(
                snapshot: activityStore.snapshot,
                selectedTaskID: $selectedTaskID
            )
            .padding(.top, 19)

            selectedConnectionSection
        }
        .padding(.top, layout == .window ? 12 : 15)
        .padding(.horizontal, DetachedWindowMetrics.dashboardContentPadding)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dashboardConnectionBar: some View {
        DashboardConnectionSwitcher(
            snapshot: store.snapshot,
            showsCurrentCodex: store.isLoggedIn,
            store: multiAgentSettings,
            onAdd: { showsConnectionSheet = true }
        )
        .padding(.horizontal, 16)
        .frame(height: 59)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.codexCard.opacity(0.96))
        .overlay(alignment: .bottom) { Color.codexLine.frame(height: 1) }
    }

    private var horizontalDashboardSyncFooter: some View {
        SyncFooterView(
            context: selectedProviderContext,
            actions: actions,
            showsDetachedButton: showsDetachedButton,
            onRefresh: refreshSelectedProvider,
            onOpenSettings: onOpenSettings
        )
        .padding(.horizontal, DetachedWindowMetrics.dashboardContentPadding)
        .padding(.bottom, layout == .window ? 14 : 16)
    }

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("额度")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if let nextReset = store.snapshot.detailWindow?.resetsAt {
                    Text("额度重置：\(UsageDateFormat.dateAndTime(nextReset))")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.codexMuted)
                }
            }

            QuotaCardsView(snapshot: store.snapshot, isLoggedIn: store.isLoggedIn)

            ResetCouponSummaryView(coupons: store.snapshot.resetCoupons)
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 18)
    }

    // MARK: - 竖向布局

    private var verticalDashboard: some View {
        Group {
            if layout == .window {
                verticalDashboardWindowLayout
            } else {
                verticalDashboardMeasureColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background {
                        Color.codexCard.ignoresSafeArea()
                }
            }
        }
    }

    /// 竖向独立窗口使用切换前预排版得到的自然高度，不在内容区引入滚动。
    private var verticalDashboardWindowLayout: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                verticalDashboardHeaderStack
                Spacer(minLength: 0)
                verticalDashboardSyncFooter
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .background {
                Color.codexCard
            }
        }
    }

    private var verticalDashboardHeaderStack: some View {
        VStack(spacing: 0) {
            CompanionPetHeader(
                snapshot: store.snapshot,
                activity: activityStore.snapshot,
                integrations: multiAgentSettings.integrations,
                settings: settings,
                frameStore: frameStore,
                todayMinutes: companionStatsStore.todayMinutes,
                selectedTaskID: $selectedTaskID
            )
            .zIndex(5)

            DashboardConnectionSwitcher(
                snapshot: store.snapshot,
                showsCurrentCodex: store.isLoggedIn,
                store: multiAgentSettings,
                onAdd: { showsConnectionSheet = true },
                compact: true
            )
            .padding(.horizontal, DetachedWindowMetrics.verticalContentPadding)
            .frame(height: 59)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.codexCard.opacity(0.96))
            .overlay(alignment: .bottom) { Color.codexLine.frame(height: 1) }

            if multiAgentSettings.selectedDeepSeekConnection == nil {
                CompanionAccountRow(context: selectedProviderContext)
            }

            VStack(alignment: .leading, spacing: 0) {
                if store.snapshot.showsSubscriptionExpiryReminder,
                   let message = store.snapshot.subscriptionExpiryReminderMessage {
                    SubscriptionExpiryReminderBanner(message: message)
                        .padding(.bottom, 3)
                }

                selectedVerticalConnectionSection
            }
            // A single shared lead-in keeps every provider aligned without
            // stacking branch-specific top padding.
            .padding(.top, 18)
            .padding(.horizontal, DetachedWindowMetrics.verticalContentPadding)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var verticalDashboardSyncFooter: some View {
        SyncFooterView(
            context: selectedProviderContext,
            actions: actions,
            showsDetachedButton: showsDetachedButton,
            isCompact: true,
            onRefresh: refreshSelectedProvider,
            onOpenSettings: onOpenSettings
        )
        .padding(.horizontal, DetachedWindowMetrics.verticalContentPadding)
        .padding(.bottom, 14)
    }

    private var verticalDashboardMeasureColumn: some View {
        VStack(spacing: 0) {
            verticalDashboardHeaderStack
            verticalDashboardSyncFooter
        }
    }

    /// 横版显示期间就按 330pt 宽度排好竖版并缓存高度，方向切换时可一次完成 resize。
    private var verticalDashboardHeightProbe: some View {
        verticalDashboardMeasureColumn
            .frame(width: DetachedWindowMetrics.verticalDashboardWidth, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: DashboardMeasuredContentSizeKey.self,
                        value: geometry.size
                    )
                }
            }
            .id(verticalDashboardMeasureIdentity)
            .hidden()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var verticalDashboardMeasureIdentity: String {
        let coupons = store.snapshot.resetCoupons.map {
            "\($0.id):\($0.count):\($0.description ?? "")"
        }.joined(separator: "|")
        return [
            multiAgentSettings.selectedConnectionKey,
            coupons,
            store.snapshot.subscriptionExpiryReminderMessage ?? "",
            store.snapshot.hasShortWindow ? "1" : "0",
            store.snapshot.hasWeeklyWindow ? "1" : "0",
            String(activityStore.snapshot.activeTasks.count),
            multiAgentSettings.selectedDeepSeekConnection?.authenticationState.rawValue ?? "",
            multiAgentSettings.selectedDeepSeekConnection?.balance.map { String(describing: $0.total) } ?? "",
            multiAgentSettings.selectedCodexAccount?.authenticationState.rawValue ?? "",
        ].joined(separator: "-")
    }

    private var verticalQuotaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("额度")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 6)
                if let nextReset = store.snapshot.detailWindow?.resetsAt {
                    Text("额度重置：\(UsageDateFormat.dateAndTime(nextReset))")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.codexMuted)
                        .lineLimit(1)
                }
            }

            VerticalQuotaRowsView(snapshot: store.snapshot, isLoggedIn: store.isLoggedIn)

            ResetCouponSummaryView(coupons: store.snapshot.resetCoupons)
                .padding(.top, 2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var selectedConnectionSection: some View {
        if let connection = multiAgentSettings.selectedDeepSeekConnection {
            DeepSeekDashboardCard(
                connection: connection,
                isRefreshing: store.isUnifiedRefreshing
            ) {
                actions.refresh()
            }
            .padding(.top, 18)
        } else if let connection = multiAgentSettings.selectedCodexAccount {
            ManagedCodexDashboardCard(
                connection: connection,
                store: multiAgentSettings,
                isRefreshing: store.isUnifiedRefreshing,
                onRefresh: actions.refresh
            )
                .padding(.top, 18)
        } else {
            quotaSection
        }
    }

    @ViewBuilder
    private var selectedVerticalConnectionSection: some View {
        if let connection = multiAgentSettings.selectedDeepSeekConnection {
            DeepSeekDashboardCard(
                connection: connection,
                isRefreshing: store.isUnifiedRefreshing
            ) {
                actions.refresh()
            }
        } else if let connection = multiAgentSettings.selectedCodexAccount {
            ManagedCodexDashboardCard(
                connection: connection,
                store: multiAgentSettings,
                isRefreshing: store.isUnifiedRefreshing,
                onRefresh: actions.refresh
            )
        } else {
            verticalQuotaSection
        }
    }
}

private struct DashboardConnectionSwitcher: View {
    let snapshot: CodexUsageSnapshot
    let showsCurrentCodex: Bool
    @Bindable var store: MultiAgentSettingsStore
    let onAdd: () -> Void
    var compact = false

    private enum CredentialBadge {
        case account(Color)
        case apiKey(Color)

        var systemName: String {
            switch self {
            case .account: "checkmark.seal.fill"
            case .apiKey: "key.fill"
            }
        }

        var tint: Color {
            switch self {
            case .account(let color): color
            case .apiKey(let color): color
            }
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    if showsCurrentCodex {
                        connectionButton(
                            asset: .codex,
                            title: "Codex",
                            subtitle: snapshot.companionAccountName,
                            color: Color.codexGreen,
                            selected: store.selectedConnectionKey == MultiAgentSettingsStore.currentCodexConnectionKey,
                            credential: .account(currentCodexQuotaColor)
                        ) { store.selectCurrentCodexConnection() }
                    }
                    ForEach(store.codexAccounts) { connection in
                        connectionButton(
                            asset: .codex,
                            title: "Codex",
                            subtitle: connection.label,
                            color: Color.codexGreen,
                            selected: store.isSelected(connection),
                            credential: .account(codexQuotaColor(for: connection))
                        ) { store.selectCodexConnection(connection) }
                    }
                    ForEach(store.deepSeekConnections) { connection in
                        connectionButton(
                            asset: .deepSeek,
                            title: "DeepSeek",
                            subtitle: connection.label,
                            color: .deepSeekBrand,
                            selected: store.isSelected(connection),
                            credential: .apiKey(balanceColor(for: connection))
                        ) { store.selectDeepSeekConnection(connection) }
                    }
                }
            }
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(CodexPressableStyle(cornerRadius: 9))
            .foregroundStyle(Color.codexMuted)
            .background(Color.codexCard, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.codexLine, style: StrokeStyle(lineWidth: 1, dash: [3]))
            }
            .help("添加 Codex 账号或 DeepSeek API Key")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("我的连接")
    }

    private func connectionButton(
        asset: BrandAssetID,
        title: String,
        subtitle: String,
        color: Color,
        selected: Bool,
        credential: CredentialBadge,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if compact {
                    connectionIcon(asset: asset, credential: credential)
                        .frame(width: 42, height: 42)
                } else {
                    HStack(spacing: 6) {
                        connectionIcon(asset: asset, credential: credential)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(title).font(.system(size: 10, weight: .bold))
                            Text(subtitle).font(.system(size: 8)).foregroundStyle(Color.codexMuted).lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 42)
                }
            }
            .background(selected ? color.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(selected ? color.opacity(0.25) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(CodexPressableCardStyle(cornerRadius: 11))
        .accessibilityLabel("\(title)，\(subtitle)")
        .accessibilityValue(selected ? "已选择" : "未选择")
    }

    private func connectionIcon(asset: BrandAssetID, credential: CredentialBadge) -> some View {
        ZStack(alignment: .bottomTrailing) {
            BrandIconView(asset: asset, size: 32, cornerRadius: 11)
            Image(systemName: credential.systemName)
                .font(.system(size: 11, weight: .bold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(credential.tint)
                .frame(width: 14, height: 14)
                .offset(x: 2, y: 2)
                .accessibilityHidden(true)
        }
    }

    private var currentCodexQuotaColor: Color {
        QuotaHealthLevel.from(
            window: snapshot.primaryWindow,
            isLoggedIn: showsCurrentCodex
        ).color
    }

    private func codexQuotaColor(for connection: CodexAccountConnection) -> Color {
        guard connection.authenticationState == .connected else { return .codexRed }
        guard let remainingPercent = (connection.usage?.primary ?? connection.usage?.secondary)?.remainingPercent else {
            return .codexMuted
        }

        switch remainingPercent {
        case 50...:
            return .codexGreen
        case 20..<50:
            return .codexAmber
        default:
            return .codexRed
        }
    }

    private func balanceColor(for connection: DeepSeekAPIConnection) -> Color {
        ProviderBalanceIndicator.resolve(
            total: connection.balance?.total,
            authenticationState: connection.authenticationState
        ).color
    }
}

private struct ManagedCodexDashboardCard: View {
    let connection: CodexAccountConnection
    @Bindable var store: MultiAgentSettingsStore
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                BrandIconView(asset: .codex, size: 40, cornerRadius: 11)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Codex").font(.system(size: 20, weight: .bold))
                        Text(connection.usage?.planType ?? "官方 CLI")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.codexGreen)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.codexGreen.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                    }
                    Text([connection.label, connection.usage?.email].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 9)).foregroundStyle(Color.codexMuted)
                }
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(connection.authenticationState == .connected ? Color.codexGreen : Color.codexAmber)
                        .frame(width: 6, height: 6)
                    Text(connection.authenticationState == .connected ? "已连接" : "待登录")
                }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(connection.authenticationState == .connected ? Color.codexGreen : Color.codexAmber)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background((connection.authenticationState == .connected ? Color.codexGreen : Color.codexAmber).opacity(0.10), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("当前任务")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.codexMuted)
                        .textCase(.uppercase)
                    Spacer()
                    Text("独立 CODEX_HOME · \(connection.relativeHomeDirectory.prefix(8))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color.codexMuted)
                }
                VStack(spacing: 5) {
                    Text(connection.authenticationState == .connected ? "现在很安静" : "等待官方登录")
                        .font(.system(size: 12, weight: .bold))
                    Text(connection.authenticationState == .connected
                         ? "这个账号暂时没有由 Hook 上报的进行中任务"
                         : "通过官方 OAuth 单独授权，不读取或复制其他账号的 token")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.codexMuted)
                }
                .frame(maxWidth: .infinity, minHeight: 94)
                HStack {
                    Button(action: onRefresh) {
                        Group {
                            if isRefreshing {
                                ProgressView().controlSize(.mini)
                            } else {
                                Text("检查登录")
                            }
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 13)
                        .frame(height: 32)
                        .background(Color.codexLine.opacity(0.45), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(CodexPressableStyle(cornerRadius: 7))
                    .disabled(isRefreshing)
                    Spacer()
                    if connection.authenticationState != .connected {
                        if store.isCodexOAuthInProgress {
                            Button {
                                store.cancelCurrentCodexOAuth()
                            } label: {
                                Label("取消登录", systemImage: "xmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.codexRed)
                                    .padding(.horizontal, 13)
                                    .frame(height: 32)
                                    .background(Color.codexRed.opacity(0.09), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            .buttonStyle(CodexPressableStyle(cornerRadius: 7))
                        } else {
                            Button {
                                Task { await store.authenticateCodexAccount(connection) }
                            } label: {
                                Text("官方登录")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, 13)
                                    .frame(height: 32)
                                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            .buttonStyle(CodexPressableStyle(cornerRadius: 7, ink: .softLight))
                            .disabled(store.isMutatingConnections)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color.codexCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Color.codexLine) }
            .padding(.top, 20)

            if let usage = connection.usage,
               usage.primary != nil || usage.secondary != nil {
                HStack {
                    Text("额度").font(.system(size: 12, weight: .bold))
                    Spacer()
                    Text("来源：Codex 官方接口")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.codexMuted)
                }
                .padding(.top, 16)
                HStack(spacing: 8) {
                    if let primary = usage.primary {
                        ManagedCodexQuotaRing(label: quotaLabel(primary), window: primary)
                    }
                    if let secondary = usage.secondary {
                        ManagedCodexQuotaRing(label: quotaLabel(secondary), window: secondary)
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func quotaLabel(_ window: CodexAccountRateLimitWindow) -> String {
        guard let minutes = window.windowDurationMinutes else { return "额度" }
        if minutes >= 24 * 60 { return "本周" }
        if minutes >= 60 { return "\(minutes / 60) 小时" }
        return "\(minutes) 分钟"
    }
}

private struct ManagedCodexQuotaRing: View {
    let label: String
    let window: CodexAccountRateLimitWindow

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color.codexLine, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(window.remainingPercent) / 100)
                    .stroke(Color.codexGreen, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(window.remainingPercent)")
                    .font(.system(size: 9, weight: .bold))
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.system(size: 10, weight: .bold))
                Text("剩余 \(window.remainingPercent)%")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.codexMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.codexCard, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(Color.codexLine) }
    }
}

private struct DeepSeekDashboardCard: View {
    let connection: DeepSeekAPIConnection
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DeepSeek").font(.system(size: 20, weight: .bold))
                    Text("\(connection.label) · sk-•••• \(connection.keySuffix)")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.codexMuted)
                }
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(connection.authenticationState == .connected ? Color.codexGreen : Color.codexAmber)
                        .frame(width: 6, height: 6)
                    Text(connection.authenticationState == .connected ? "余额正常" : "需要检查")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(connection.authenticationState == .connected ? Color.codexGreen : Color.codexAmber)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background((connection.authenticationState == .connected ? Color.codexGreen : Color.codexAmber).opacity(0.10), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("可用余额")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.codexMuted)
                    .textCase(.uppercase)
                if let balance = connection.balance {
                    Text(balance.currency == "CNY"
                         ? "¥\(NSDecimalNumber(decimal: balance.total).stringValue)"
                         : "\(balance.currency) \(NSDecimalNumber(decimal: balance.total).stringValue)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(balanceIndicator.color)
                        .padding(.top, 4)
                    Text("充值 \(NSDecimalNumber(decimal: balance.toppedUp).stringValue) · 赠送 \(NSDecimalNumber(decimal: balance.granted).stringValue)")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.codexMuted)
                        .padding(.top, 2)
                } else {
                    Text("—").font(.system(size: 36, weight: .bold)).foregroundStyle(Color.codexMuted).padding(.top, 4)
                }
                Button(action: onRefresh) {
                    Group {
                        if isRefreshing {
                            ProgressView().controlSize(.small).tint(Color.codexOnPrimary)
                        } else {
                            Text("查询余额")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44, alignment: .center)
                    .foregroundStyle(Color.codexOnPrimary)
                    .background(Color.codexPrimary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(CodexPressableStyle(cornerRadius: 8, ink: .softLight))
                .disabled(isRefreshing)
                .padding(.top, 16)
            }
            .padding(20)
            .background(Color.codexCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(Color.codexLine) }
            .padding(.top, 20)

            Label("Key 保存在 macOS Keychain，只用于查询 DeepSeek 官方余额接口；余额属于账户，并非此 Key 独享。", systemImage: "checkmark.shield")
                .font(.system(size: 9))
                .foregroundStyle(Color.codexMuted)
            .padding(.top, 12)
        }
    }

    private var balanceIndicator: ProviderBalanceIndicator {
        ProviderBalanceIndicator.resolve(
            total: connection.balance?.total,
            authenticationState: connection.authenticationState
        )
    }
}


enum DashboardMeasuredContentSizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.height > value.height {
            value = next
        }
    }
}

/// 独立窗口底色：侧栏渐变 + 主内容区 card 色，铺满窗口避免底部露白。
struct DashboardWindowChromeBackground: View {
    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [Color.codexSidebarTop, Color.codexSidebarBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: DetachedWindowMetrics.sidebarWidth)

            Color.codexCard
        }
    }
}

/// 横向侧栏与竖向头部共用的账号文案，避免两套布局各写一份降级规则。
extension CodexUsageSnapshot {
    var companionAccountName: String {
        if let name = accountName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return accountEmail.split(separator: "@").first.map(String.init) ?? "Codex"
    }

    var companionPlanBadgeText: String {
        planName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum CompanionCopy {
    static func todayDuration(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) 分钟" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0
            ? "\(hours) 小时"
            : "\(hours) 小时 \(remainder) 分钟"
    }
}

/// 陪伴胶囊：轮播当前正在工作的 Agent 状态，横竖两版共用。
private struct CompanionStatusCapsule: View {
    let activity: CodexActivitySnapshot
    let quotaHealth: QuotaHealthLevel
    let height: CGFloat
    let waveEnabled: Bool
    let waveColorMode: StatusCapsuleColorMode
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedIndex = 0

    private var statuses: [CompanionAgentStatus] { activity.activeAgentStatuses }

    private var displayedStatus: CompanionAgentStatus? {
        guard !statuses.isEmpty else { return nil }
        return statuses[min(selectedIndex, statuses.count - 1)]
    }

    private var displayedState: CodexActivityState {
        displayedStatus?.state ?? .idle
    }

    private var rotationIdentity: String {
        statuses
            .map { "\($0.id):\($0.state.rawValue):\($0.taskCount)" }
            .joined(separator: "|")
    }

    private var showsActivityFlow: Bool {
        waveEnabled && displayedStatus != nil && displayedState.showsActivityWave
    }

    var body: some View {
        ZStack {
            statusRow
                .id(displayedStatus?.id ?? "idle")
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    )
                )
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 10)
        .frame(height: height)
        .background {
            ZStack {
                Color.codexCard.opacity(0.92)
                ActivityCapsuleWave(
                    isVisible: showsActivityFlow,
                    ink: waveInk,
                    presentation: .rotatingBorder(lineWidth: 2)
                )
            }
            .clipShape(Capsule())
        }
        .clipShape(Capsule())
        .overlay {
            if !showsActivityFlow {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.72), lineWidth: 0.7)
            }
        }
        .clipped()
        .task(id: rotationIdentity) {
            selectedIndex = 0
            guard statuses.count > 1 else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled, statuses.count > 1 else { return }
                withAnimation(.easeInOut(duration: 0.32)) {
                    selectedIndex = (selectedIndex + 1) % statuses.count
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var statusRow: some View {
        if let displayedStatus {
            HStack(spacing: 5) {
                Circle()
                    .fill(displayedStatus.state.statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText(for: displayedStatus))
                    .lineLimit(1)
            }
        } else {
            Text("暂无进行中的 Agent")
                .foregroundStyle(Color.codexMuted)
                .lineLimit(1)
        }
    }

    private func statusText(for status: CompanionAgentStatus) -> String {
        let count = status.taskCount > 1 ? " · \(status.taskCount) 个任务" : ""
        return "\(status.agentName) · \(status.state.companionText)\(count)"
    }

    private var accessibilityText: String {
        guard let displayedStatus else { return "暂无进行中的 Agent" }
        let position = statuses.count > 1
            ? "，第 \(selectedIndex + 1) 个，共 \(statuses.count) 个 Agent"
            : ""
        return "\(statusText(for: displayedStatus))\(position)"
    }

    private var waveInk: NSColor {
        waveColorMode.resolvedNSColor(
            activityState: displayedState,
            quotaHealth: quotaHealth
        ) ?? (colorScheme == .dark
            ? NSColor.white.withAlphaComponent(0.18)
            : NSColor.black.withAlphaComponent(0.10))
    }
}

private struct CompanionLocalAgentRow: Identifiable, Equatable {
    let id: AgentID
    let name: String
    let asset: BrandAssetID
    let state: CodexActivityState
    let summary: String
    let hookState: AgentHookInstallationState
}

/// Preview-aligned Pet-local Agent summary. It intentionally uses integration
/// and Hook activity data, not the selected account, so account switching does
/// not change what the Pet sees on this Mac.
private struct CompanionLocalAgentsControl: View {
    @Environment(\.colorScheme) private var colorScheme
    let activity: CodexActivitySnapshot
    let integrations: [AgentIntegrationStatus]
    var panelHorizontalOffset: CGFloat = 0
    var opensUpward = false
    @State private var isExpanded = false
    @State private var interceptedCloseRippleTrigger = 0

    private var rows: [CompanionLocalAgentRow] {
        integrations
            .filter { integration in
                integration.hookState == .builtIn || integration.hookState == .installed
            }
            .sorted { $0.priority < $1.priority }
            .compactMap { integration in
                guard let task = latestTask(for: integration), isOngoing(task.state) else {
                    return nil
                }
                return CompanionLocalAgentRow(
                    id: integration.id,
                    name: integration.name,
                    asset: .agent(integration.id),
                    state: task.state,
                    summary: summary(for: task, integration: integration),
                    hookState: integration.hookState
                )
            }
    }

    var body: some View {
        CodexMaterialWaveButtonBody(
            action: {
                withAnimation(.easeOut(duration: 0.18)) { isExpanded.toggle() }
            },
            cornerRadius: 15,
            usesCapsule: true,
            externalRippleTrigger: interceptedCloseRippleTrigger
        ) {
            HStack(spacing: 8) {
                HStack(spacing: -5) {
                    ForEach(rows.prefix(3)) { row in
                        BrandIconView(asset: row.asset, size: 20, cornerRadius: 7)
                    }
                }
                if rows.isEmpty {
                    Circle()
                        .fill(Color.codexMuted.opacity(0.7))
                        .frame(width: 7, height: 7)
                }
                Text(rows.isEmpty ? "空闲" : "\(rows.count) 进行中")
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .foregroundStyle(rows.isEmpty ? Color.codexMuted : Color.codexGreen)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Color.codexGreen.opacity(0.08), in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color.codexGreen.opacity(0.42), lineWidth: 1)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(rows.isEmpty ? "本地 Agent 空闲" : "\(rows.count) 个进行中 Agent")
        .accessibilityValue(isExpanded ? "已展开" : "已收起")
        .background {
            CompanionLocalAgentsPanelPresenter(
                isPresented: $isExpanded,
                interceptedCloseRippleTrigger: $interceptedCloseRippleTrigger,
                rows: rows,
                horizontalOffset: panelHorizontalOffset,
                opensUpward: opensUpward,
                colorScheme: colorScheme
            )
        }
        .zIndex(isExpanded ? 30 : 1)
    }

    private func latestTask(for integration: AgentIntegrationStatus) -> CodexTaskActivity? {
        (activity.localAgentTasks + activity.activeTasks)
            .filter { $0.agentDisplayName == integration.name }
            .max(by: { $0.updatedAt < $1.updatedAt })
    }

    private func isOngoing(_ state: CodexActivityState) -> Bool {
        switch state {
        case .thinking, .executing, .reviewing, .waitingForUser:
            true
        case .unavailable, .idle, .completed, .interrupted:
            false
        }
    }

    private func summary(
        for task: CodexTaskActivity?,
        integration: AgentIntegrationStatus
    ) -> String {
        guard let task else {
            if integration.hookState == .builtIn { return "内置适配已就绪" }
            return integration.hookState == .installed ? "Hooks 已就绪" : "等待 Hook 接入"
        }
        if task.title == integration.name || task.title.hasPrefix("\(integration.name) ·") {
            return task.detail.replacingOccurrences(of: "\(integration.name) ", with: "")
        }
        return task.title
    }
}

private struct CompanionLocalTasksPanelContent: View {
    let rows: [CompanionLocalAgentRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Pet 看到的本地任务")
                        .font(.system(size: 13, weight: .semibold))
                    Text("仅显示已接入且正在进行中的 Agent")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.codexMuted)
                }
                Spacer(minLength: 4)
                Text(rows.isEmpty ? "空闲" : "\(rows.count) 个进行中")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(rows.isEmpty ? Color.codexMuted : Color.codexGreen)
                    .padding(.top, 5)
            }

            VStack(spacing: 12) {
                ForEach(rows) { row in
                    localAgentRow(row)
                }
                if rows.isEmpty {
                    HStack(spacing: 9) {
                        Circle()
                            .fill(Color.codexMuted.opacity(0.7))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("当前空闲")
                                .font(.system(size: 11, weight: .semibold))
                            Text("已接入的 Agent 开始工作后会在这里显示。")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.codexMuted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
            }
            .padding(.top, 15)
        }
        .padding(14)
        .frame(width: 286, alignment: .leading)
        .foregroundStyle(Color.codexInk)
        .background(Color.codexCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.codexLine, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    private func localAgentRow(_ row: CompanionLocalAgentRow) -> some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                BrandIconView(asset: row.asset, size: 34, cornerRadius: 10)
                Circle()
                    .fill(row.state.statusColor)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.codexCard, lineWidth: 1.3))
                    .offset(x: 2, y: 2)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.system(size: 11, weight: .semibold))
                Text(row.summary)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(row.state.activityLabel)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(row.state.statusColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.name)，\(row.summary)，\(row.state.activityLabel)")
    }
}

private struct CompanionLocalAgentsPanelPresenter: NSViewRepresentable {
    @Binding var isPresented: Bool
    @Binding var interceptedCloseRippleTrigger: Int
    let rows: [CompanionLocalAgentRow]
    let horizontalOffset: CGFloat
    let opensUpward: Bool
    let colorScheme: ColorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isPresented: $isPresented,
            interceptedCloseRippleTrigger: $interceptedCloseRippleTrigger
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = CompanionHoverTrackingView(frame: .zero)
        view.onMouseEntered = { context.coordinator.anchorMouseEntered() }
        view.onMouseExited = { context.coordinator.anchorMouseExited() }
        context.coordinator.anchorView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isPresented = $isPresented
        context.coordinator.interceptedCloseRippleTrigger = $interceptedCloseRippleTrigger
        context.coordinator.update(
            rows: rows,
            horizontalOffset: horizontalOffset,
            opensUpward: opensUpward,
            colorScheme: colorScheme
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.dismiss()
    }

    @MainActor
    final class Coordinator {
        weak var anchorView: NSView?
        var isPresented: Binding<Bool>
        var interceptedCloseRippleTrigger: Binding<Int>
        private let controller = CompanionLocalAgentsPanelController()

        init(
            isPresented: Binding<Bool>,
            interceptedCloseRippleTrigger: Binding<Int>
        ) {
            self.isPresented = isPresented
            self.interceptedCloseRippleTrigger = interceptedCloseRippleTrigger
            controller.onInterceptedAnchorClick = { [weak self] in
                self?.interceptedCloseRippleTrigger.wrappedValue += 1
            }
            controller.onDismiss = { [weak self] in
                self?.isPresented.wrappedValue = false
            }
        }

        func update(
            rows: [CompanionLocalAgentRow],
            horizontalOffset: CGFloat,
            opensUpward: Bool,
            colorScheme: ColorScheme
        ) {
            controller.update(rows: rows, colorScheme: colorScheme)
            guard isPresented.wrappedValue, let anchorView else {
                controller.dismiss()
                return
            }
            DispatchQueue.main.async { [weak self, weak anchorView] in
                guard let self, let anchorView, self.isPresented.wrappedValue else { return }
                self.controller.show(
                    relativeTo: anchorView,
                    horizontalOffset: horizontalOffset,
                    opensUpward: opensUpward
                )
            }
        }

        func dismiss() {
            controller.dismiss()
        }

        func anchorMouseEntered() {
            controller.anchorMouseEntered()
        }

        func anchorMouseExited() {
            controller.anchorMouseExited()
        }
    }
}

private final class CompanionHoverTrackingView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    var capturedMouseDownRect: NSRect?
    var onCapturedMouseDown: (() -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? {
        if capturedMouseDownRect?.contains(point) == true {
            return self
        }
        return super.hitTest(point)
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if capturedMouseDownRect?.contains(point) == true {
            onCapturedMouseDown?()
            return
        }
        super.mouseDown(with: event)
    }
}

enum CompanionPanelAnchorClickRouting {
    static func captureRect(anchorFrame: NSRect, panelFrame: NSRect) -> NSRect? {
        let overlap = anchorFrame.intersection(panelFrame)
        guard !overlap.isNull, !overlap.isEmpty else { return nil }
        return NSRect(
            x: overlap.minX - panelFrame.minX,
            y: overlap.minY - panelFrame.minY,
            width: overlap.width,
            height: overlap.height
        )
    }
}

@MainActor
private final class CompanionLocalAgentsPanelController {
    private static let contentHorizontalInset: CGFloat = 20
    private static let contentVerticalInset: CGFloat = 6
    private static let attachmentGap: CGFloat = 4
    /// NSHostingView keeps additional fitting-space above the visible card.
    /// Pull the panel toward its trigger so the card, rather than the clear
    /// panel bounds, reads as visually attached to the capsule.
    private static let visibleCardAttachmentCorrection: CGFloat = 20
    private let panel: NSPanel
    private let hostingView: NSHostingView<AnyView>
    private let trackingView = CompanionHoverTrackingView(frame: .zero)
    private var anchorFrame: NSRect?
    private var safeTriangle: HoverSafeTriangle?
    private var safeTriangleTimer: Timer?
    private var safeTriangleDeadline: Date?
    private var lastOpensUpward = false
    private var presentationGeneration = 0
    private var isDismissing = false
    var onInterceptedAnchorClick: (() -> Void)?
    var onDismiss: (() -> Void)?

    init() {
        let rootView = CompanionLocalTasksPanelContent(rows: [])
        hostingView = NSHostingView(rootView: AnyView(rootView))
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 326, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.transient, .canJoinAllSpaces, .fullScreenAuxiliary]
        trackingView.addSubview(hostingView)
        trackingView.onMouseEntered = { [weak self] in
            self?.cancelSafeTriangleTracking()
        }
        trackingView.onMouseExited = { [weak self] in
            self?.panelMouseExited()
        }
        trackingView.onCapturedMouseDown = { [weak self] in
            guard let self else { return }
            onInterceptedAnchorClick?()
            dismiss()
            onDismiss?()
        }
        panel.contentView = trackingView
    }

    func update(rows: [CompanionLocalAgentRow], colorScheme: ColorScheme) {
        hostingView.rootView = AnyView(
            CompanionLocalTasksPanelContent(rows: rows)
                .preferredColorScheme(colorScheme)
        )
        hostingView.layoutSubtreeIfNeeded()
        let fittingHeight = max(164, hostingView.fittingSize.height)
        panel.setContentSize(NSSize(width: 326, height: fittingHeight))
        trackingView.frame = NSRect(x: 0, y: 0, width: 326, height: fittingHeight)
        hostingView.frame = NSRect(x: 0, y: 0, width: 326, height: fittingHeight)
    }

    func show(relativeTo anchorView: NSView, horizontalOffset: CGFloat, opensUpward: Bool) {
        guard let parentWindow = anchorView.window else { return }
        presentationGeneration += 1
        isDismissing = false
        lastOpensUpward = opensUpward
        panel.alphaValue = 1
        let anchorInWindow = anchorView.convert(anchorView.bounds, to: nil)
        let anchor = parentWindow.convertToScreen(anchorInWindow)
        anchorFrame = anchor
        let size = panel.frame.size
        let attachedY = if opensUpward {
            anchor.maxY
                - Self.contentVerticalInset
                + Self.attachmentGap
                - Self.visibleCardAttachmentCorrection
        } else {
            anchor.minY
                - size.height
                + Self.contentVerticalInset
                - Self.attachmentGap
                + Self.visibleCardAttachmentCorrection
        }
        var origin = NSPoint(
            x: anchor.midX - size.width / 2 + horizontalOffset,
            y: attachedY
        )

        if let visibleFrame = parentWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            origin.x = min(max(origin.x, visibleFrame.minX + 8), visibleFrame.maxX - size.width - 8)
            origin.y = min(max(origin.y, visibleFrame.minY + 8), visibleFrame.maxY - size.height - 8)
        }

        panel.setFrameOrigin(origin)
        trackingView.capturedMouseDownRect = CompanionPanelAnchorClickRouting.captureRect(
            anchorFrame: anchor,
            panelFrame: panel.frame
        )
        if panel.parent !== parentWindow {
            panel.parent?.removeChildWindow(panel)
            parentWindow.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    func dismiss(animated: Bool = true) {
        cancelSafeTriangleTracking()
        anchorFrame = nil
        trackingView.capturedMouseDownRect = nil
        guard panel.isVisible, !isDismissing else { return }

        let generation = presentationGeneration + 1
        presentationGeneration = generation
        let originalOrigin = panel.frame.origin

        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            finishDismiss(generation: generation, originalOrigin: originalOrigin)
            return
        }

        isDismissing = true
        let targetOrigin = NSPoint(
            x: originalOrigin.x,
            y: originalOrigin.y + (lastOpensUpward ? -4 : 4)
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(targetOrigin)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.finishDismiss(generation: generation, originalOrigin: originalOrigin)
            }
        }
    }

    private func finishDismiss(generation: Int, originalOrigin: NSPoint) {
        guard presentationGeneration == generation else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.alphaValue = 1
        panel.setFrameOrigin(originalOrigin)
        isDismissing = false
    }

    func anchorMouseEntered() {
        cancelSafeTriangleTracking()
    }

    func anchorMouseExited() {
        guard panel.isVisible else { return }
        beginSafeTriangleTracking(
            from: NSEvent.mouseLocation,
            toward: panelInteractionFrame
        )
    }

    private func panelMouseExited() {
        guard panel.isVisible, let anchorFrame else { return }
        beginSafeTriangleTracking(
            from: NSEvent.mouseLocation,
            toward: anchorFrame
        )
    }

    private var panelInteractionFrame: NSRect {
        panel.frame.insetBy(
            dx: Self.contentHorizontalInset,
            dy: Self.contentVerticalInset
        )
    }

    private func beginSafeTriangleTracking(from departurePoint: NSPoint, toward targetFrame: NSRect) {
        cancelSafeTriangleTracking()
        safeTriangle = HoverSafeTriangle(
            origin: departurePoint,
            targetFrame: targetFrame,
            buffer: 8
        )
        safeTriangleDeadline = Date().addingTimeInterval(2)
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluatePointerForDismissal()
            }
        }
        safeTriangleTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func evaluatePointerForDismissal() {
        let pointer = NSEvent.mouseLocation
        if panelInteractionFrame.contains(pointer) || anchorFrame?.contains(pointer) == true {
            cancelSafeTriangleTracking()
            return
        }
        if let safeTriangle,
           let safeTriangleDeadline,
           Date() < safeTriangleDeadline,
           safeTriangle.contains(pointer) {
            return
        }
        dismiss()
        onDismiss?()
    }

    private func cancelSafeTriangleTracking() {
        safeTriangleTimer?.invalidate()
        safeTriangleTimer = nil
        safeTriangle = nil
        safeTriangleDeadline = nil
    }
}

/// Pet 承载区的点击交互：涟漪 + 随机动作 + 无障碍，侧栏与顶部形象区共用。
private struct CompanionPetInteraction: ViewModifier {
    let space: String
    let frameStore: PetFrameStore
    @Binding var ripples: [CodexMaterialWaveToken]
    /// 通过辅助功能触发时没有点击位置，用这个点代替。
    let fallbackRippleLocation: CGPoint

    private var isInteractive: Bool { frameStore.canPlayIdleInteraction }

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .coordinateSpace(name: space)
            .gesture(
                codexMaterialTapGesture(in: space) { location in
                    play(rippleAt: location)
                }
            )
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(isInteractive ? .isButton : [])
            .accessibilityHint(isInteractive ? "点击播放随机动作" : "")
            .accessibilityAction(.default) {
                play(rippleAt: fallbackRippleLocation)
            }
    }

    private func play(rippleAt location: CGPoint) {
        guard isInteractive else { return }
        ripples.spawnWave(at: location)
        frameStore.playRandomIdleAction()
    }
}

private extension View {
    func companionPetInteraction(
        space: String,
        frameStore: PetFrameStore,
        ripples: Binding<[CodexMaterialWaveToken]>,
        fallbackRippleLocation: CGPoint
    ) -> some View {
        modifier(
            CompanionPetInteraction(
                space: space,
                frameStore: frameStore,
                ripples: ripples,
                fallbackRippleLocation: fallbackRippleLocation
            )
        )
    }
}

/// 竖向布局的顶部形象区：宠物、状态胶囊与陪伴时长，保留点击涟漪与随机动作。
private struct CompanionPetHeader: View {
    private static let headerSpace = "companionPetHeader"
    /// 让出无标题栏窗口左上角的交通灯与右上角的置顶按钮。
    private static let chromeTopPadding: CGFloat = 34

    let snapshot: CodexUsageSnapshot
    let activity: CodexActivitySnapshot
    let integrations: [AgentIntegrationStatus]
    @Bindable var settings: AppSettingsStore
    @Bindable var frameStore: PetFrameStore
    let todayMinutes: Int
    @Binding var selectedTaskID: String?
    @State private var ripples: [CodexMaterialWaveToken] = []

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.codexSidebarTop, Color.codexSidebarBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            // Wave sits on the header background, beneath pet and chrome.
            CodexMaterialWaveLayer(ripples: $ripples)

            VStack(spacing: 0) {
                InteractivePetStage(
                    frameStore: frameStore,
                    settings: settings,
                    activity: activity
                )
                .frame(width: 132, height: 132)
                .allowsHitTesting(false)

                CompanionStatusCapsule(
                    activity: activity,
                    quotaHealth: QuotaHealthLevel.from(
                        window: snapshot.primaryWindow,
                        isLoggedIn: true
                    ),
                    height: 28,
                    waveEnabled: settings.statusBarWaveEnabled,
                    waveColorMode: settings.statusBarWaveColorMode
                )

                Text("今天一起工作 \(CompanionCopy.todayDuration(minutes: todayMinutes))")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.codexMuted)
                    .padding(.top, 8)

                GlobalAgentTaskSection(
                    activity: activity,
                    integrations: integrations,
                    selectedTaskID: $selectedTaskID
                )
                .padding(.top, 16)
            }
            .padding(.top, Self.chromeTopPadding)
            .padding(.bottom, 14)
            .padding(.horizontal, 12)
            .zIndex(1)
        }
        .fixedSize(horizontal: false, vertical: true)
        .companionPetInteraction(
            space: Self.headerSpace,
            frameStore: frameStore,
            ripples: $ripples,
            fallbackRippleLocation: CGPoint(x: 146, y: 110)
        )
        .overlay(alignment: .bottom) {
            CodexDivider()
        }
    }
}

/// 横版右侧的账号上下文。左栏代表通用 Pet，不承载任何单账号信息。
private struct CompanionHorizontalAccountHeader: View {
    let context: DashboardProviderContext
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                BrandIconView(asset: context.asset, size: 38, cornerRadius: 10)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(context.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.codexInk)
                            .lineLimit(1)
                        if !context.badge.isEmpty {
                            Text(context.badge)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(context.badgeColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(context.badgeColor.opacity(0.10), in: Capsule())
                        }
                    }
                    Text(context.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.codexMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 10)

                HStack(spacing: 5) {
                    Circle()
                        .fill(context.statusColor)
                        .frame(width: 6, height: 6)
                    Text(context.statusText)
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(context.statusColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(context.statusColor.opacity(0.10), in: Capsule())
            }
            .padding(.top, 12)
            .padding(.bottom, 9)

            CodexDivider()

            HStack(spacing: 8) {
                Text(context.summaryText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)
                Spacer(minLength: 8)
                ChatGPTBillingCompactLink(
                    title: context.accountLinkTitle,
                    helpTitle: context.accountLinkTitle,
                    fontSize: 10
                ) {
                    openURL(context.accountLinkURL)
                }
            }
            .frame(height: 32)
        }
        .padding(.horizontal, DetachedWindowMetrics.dashboardContentPadding)
        .background(Color.codexCard.opacity(0.96))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("当前连接 \(context.title)")
    }
}

/// 竖向布局的账号行：把侧栏那块两行账号信息压成一条。
private struct CompanionAccountRow: View {
    let context: DashboardProviderContext
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(context.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.codexInk)
                        .lineLimit(1)
                    if !context.badge.isEmpty {
                        Text(context.badge)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(context.badgeColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(context.badgeColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(context.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ChatGPTBillingCompactLink(
                title: context.summaryText,
                helpTitle: context.accountLinkTitle,
                emphasizesExpiry: context.emphasizesAccountLink
            ) {
                openURL(context.accountLinkURL)
            }
        }
        .padding(.horizontal, DetachedWindowMetrics.verticalContentPadding)
        .frame(height: 46)
        .overlay(alignment: .bottom) {
            CodexDivider()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("当前连接 \(context.title)")
    }
}

/// 竖向布局的额度：330pt 放不下两张并排环卡，改成单行横条。
private struct VerticalQuotaRowsView: View {
    let snapshot: CodexUsageSnapshot
    let isLoggedIn: Bool

    private var primaryHealth: QuotaHealthLevel {
        QuotaHealthLevel.from(window: snapshot.primaryWindow, isLoggedIn: isLoggedIn)
    }

    var body: some View {
        VStack(spacing: 7) {
            if snapshot.hasShortWindow, let short = snapshot.shortWindow {
                VerticalQuotaRow(window: short, tint: primaryHealth.color)
            }
            if snapshot.hasWeeklyWindow {
                VerticalQuotaRow(
                    window: snapshot.weekly,
                    tint: snapshot.hasShortWindow ? Color.codexBlue : primaryHealth.color
                )
            }
            if !snapshot.hasShortWindow, !snapshot.hasWeeklyWindow {
                Text("额度暂不可用")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.codexMuted)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.codexMist.opacity(0.55), in: RoundedRectangle(cornerRadius: 11))
            }
        }
    }
}

private struct VerticalQuotaRow: View {
    private static let trackWidth: CGFloat = 84
    private static let percentWidth: CGFloat = 44

    let window: UsageWindow
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)

            Text(window.label == "周额度" ? "本周" : window.label)
                .font(.system(size: 11))
                .foregroundStyle(Color.codexMuted)
                .lineLimit(1)

            Spacer(minLength: 6)

            ZStack(alignment: .leading) {
                Capsule().fill(Color.codexTrack)
                Capsule()
                    .fill(tint)
                    .frame(width: max(Self.trackWidth * window.percent, window.percent > 0 ? 4 : 0))
            }
            .frame(width: Self.trackWidth, height: 5)

            Text(window.percentText)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: Self.percentWidth, alignment: .trailing)
                .layoutPriority(1)
        }
        .padding(.horizontal, 11)
        .frame(height: 38)
        .background(Color.codexCard, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.codexLine, lineWidth: 0.7))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(window.label) 剩余 \(window.percentText)，\(window.amountText)")
    }
}

private struct SubscriptionExpiryReminderBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.codexAmber)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.codexInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.codexAmber.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.codexAmber.opacity(0.28), lineWidth: 0.8)
        )
        .accessibilityLabel(message)
    }
}


private struct CompanionSidebar: View {
    private static let sidebarSpace = "companionSidebar"

    let snapshot: CodexUsageSnapshot
    let activity: CodexActivitySnapshot
    let integrations: [AgentIntegrationStatus]
    @Bindable var settings: AppSettingsStore
    @Bindable var frameStore: PetFrameStore
    let todayMinutes: Int
    /// 在父级 HStack 已确定行高时铺满侧栏（独立横版）。
    var fillColumnHeight = false
    var expandsVertically = true
    @State private var ripples: [CodexMaterialWaveToken] = []

    var body: some View {
        let centersPetVertically = expandsVertically && !fillColumnHeight

        ZStack {
            LinearGradient(
                colors: [Color.codexSidebarTop, Color.codexSidebarBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Wave sits on the sidebar background, beneath pet and chrome.
            CodexMaterialWaveLayer(ripples: $ripples)

            petView
                .frame(width: 145, height: 218)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: centersPetVertically ? .infinity : nil,
                    alignment: .center
                )
                .zIndex(1)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            sidebarFooter
        }
        .companionPetInteraction(
            space: Self.sidebarSpace,
            frameStore: frameStore,
            ripples: $ripples,
            fallbackRippleLocation: CGPoint(x: 94, y: 220)
        )
        .overlay(alignment: .trailing) {
            CodexDivider(.vertical)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: (fillColumnHeight || expandsVertically) ? .infinity : nil,
            alignment: .top
        )
        .fixedSize(horizontal: false, vertical: !fillColumnHeight && !expandsVertically)
    }

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            CompanionStatusCapsule(
                activity: activity,
                quotaHealth: QuotaHealthLevel.from(
                    window: snapshot.primaryWindow,
                    isLoggedIn: true
                ),
                height: 30,
                waveEnabled: settings.statusBarWaveEnabled,
                waveColorMode: settings.statusBarWaveColorMode
            )

            CompanionLocalAgentsControl(
                activity: activity,
                integrations: integrations,
                panelHorizontalOffset: 48,
                opensUpward: true
            )
            .padding(.top, 7)

            Text("今天一起工作 \(CompanionCopy.todayDuration(minutes: todayMinutes))")
                .font(.system(size: 11))
                .foregroundStyle(Color.codexMuted)
                .padding(.top, 9)
                .padding(.bottom, 19)
        }
    }

    private var petView: some View {
        InteractivePetStage(
            frameStore: frameStore,
            settings: settings,
            activity: activity
        )
    }
}

private struct InteractivePetStage: View {
    @Bindable var frameStore: PetFrameStore
    @Bindable var settings: AppSettingsStore
    let activity: CodexActivitySnapshot

    var body: some View {
        petContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var petContent: some View {
        if let frame = frameStore.currentFrame {
            Image(nsImage: frame)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .accessibilityLabel("\(settings.selectedPet?.displayName ?? "Pet") 动画")
        } else if let pet = settings.selectedPet {
            PetStaticFrameView(pet: pet)
                .accessibilityLabel("\(pet.displayName) 静态预览")
        } else {
            VStack(spacing: 9) {
                Circle()
                    .fill(activity.state.statusColor.opacity(0.14))
                    .frame(width: 76, height: 76)
                    .overlay(Circle().fill(activity.state.statusColor).frame(width: 12, height: 12))
                Text("未找到可用 Pet")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.codexMuted)
            }
        }
    }
}

private struct PetStaticFrameView: View {
    let pet: CodexPet
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: pet.id) {
            image = PetSpriteSheet(url: pet.spritesheetURL)?.frame(row: 0, column: 0, displayHeight: 218)
        }
    }
}

private struct ActivityHeading: View {
    let activity: CodexActivitySnapshot
    let usage: CodexUsageSnapshot
    let isLoggedIn: Bool
    var isCompact = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(activity.dashboardTitle)
                .font(.system(size: isCompact ? 17 : 20, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(isCompact ? 0.85 : 1)
            Spacer(minLength: 4)
            QuotaAtAGlanceChip(usage: usage, isLoggedIn: isLoggedIn)
        }
    }
}

/// Account-independent activity area shared by every locally connected Agent.
/// Native Codex tasks and Hook-backed Agent tasks already arrive in the same
/// `activeTasks` collection, so the card stack remains stable while accounts
/// are switched in the dashboard below.
private struct GlobalAgentTaskSection: View {
    let activity: CodexActivitySnapshot
    let integrations: [AgentIntegrationStatus]
    @Binding var selectedTaskID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text(activity.dashboardTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 4)

                CompanionLocalAgentsControl(
                    activity: activity,
                    integrations: integrations
                )
            }

            TaskStackView(
                snapshot: activity,
                selectedTaskID: $selectedTaskID
            )
            .padding(.top, 15)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuotaAtAGlanceChip: View {
    let usage: CodexUsageSnapshot
    let isLoggedIn: Bool

    private var window: UsageWindow { usage.primaryWindow }
    private var health: QuotaHealthLevel {
        QuotaHealthLevel.from(window: window, isLoggedIn: isLoggedIn)
    }

    private var isAvailable: Bool {
        isLoggedIn && window.total > 0
    }

    private var title: String {
        guard isAvailable else { return "额度不可用" }
        let name = window.label == "周额度" ? "本周" : window.label
        return "\(name) \(window.percentText)"
    }

    private var helpText: String {
        guard isAvailable else { return "登录并刷新后可查看额度余量" }
        var parts = ["\(window.label) 剩余 \(window.amountText)"]
        if !window.resetsAt.isEmpty {
            parts.append("重置 \(UsageDateFormat.dateAndTime(window.resetsAt))")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(health.color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(isAvailable ? health.color : Color.codexMuted)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            isAvailable ? health.color.opacity(0.10) : Color.codexMist.opacity(0.72),
            in: Capsule(style: .continuous)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(
                    isAvailable ? health.color.opacity(0.22) : Color.codexLine.opacity(0.75),
                    lineWidth: 0.7
                )
        )
        .help(helpText)
        .accessibilityLabel("\(title)，\(helpText)")
    }
}

private struct TaskStackView: View {
    private static let cardSpace = "taskCard"
    private static let cardHeight: CGFloat = 144
    private static let stackOffset: CGFloat = 9

    let snapshot: CodexActivitySnapshot
    @Binding var selectedTaskID: String?
    @State private var ripples: [CodexMaterialWaveToken] = []

    private var tasks: [CodexTaskActivity] { snapshot.activeTasks }

    private var displayedTask: CodexTaskActivity? {
        if let selectedTaskID, let task = tasks.first(where: { $0.id == selectedTaskID }) {
            return task
        }
        return tasks.first
    }

    private var selectedIndex: Int {
        guard let displayedTask else { return 0 }
        return tasks.firstIndex(where: { $0.id == displayedTask.id }) ?? 0
    }

    var body: some View {
        let cardShape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        ZStack(alignment: .topLeading) {
            if tasks.count > 1 {
                cardShape
                    .fill(Color.codexMist)
                    .overlay(cardShape.stroke(Color.codexLine, lineWidth: 0.7))
                    .frame(maxWidth: .infinity, minHeight: Self.cardHeight, maxHeight: Self.cardHeight)
                    .offset(x: 8, y: Self.stackOffset)
                    .allowsHitTesting(false)
            }

            taskCard
                .contentShape(cardShape)
                .overlay {
                    CodexMaterialWaveLayer(ripples: $ripples)
                    .clipShape(cardShape)
                }
                .coordinateSpace(name: Self.cardSpace)
                .gesture(
                    codexMaterialTapGesture(in: Self.cardSpace) { location in
                        ripples.spawnWave(at: location)
                        cycleTask()
                    }
                )
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(accessibilityText)
        }
        .padding(.trailing, tasks.count > 1 ? 8 : 0)
        .frame(
            height: tasks.count > 1 ? Self.cardHeight + Self.stackOffset : Self.cardHeight,
            alignment: .top
        )
    }

    private var taskCard: some View {
        let cardShape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                HStack(spacing: 7) {
                    BrandIconView(
                        asset: .agent(displayAgentID),
                        size: 18,
                        cornerRadius: 6
                    )
                    HStack(spacing: 5) {
                        Circle().fill(displayState.statusColor).frame(width: 8, height: 8)
                        Text(displayState.taskLabel)
                            .foregroundStyle(displayState.statusColor)
                            .fontWeight(.semibold)
                    }
                }
                Spacer()
                Text(tasks.isEmpty ? "\(snapshot.activeTaskCount) 个活跃任务" : "任务 \(selectedIndex + 1) / \(tasks.count)")
                    .foregroundStyle(Color.codexMuted)
            }
            .font(.system(size: 11))

            Text(displayTitle)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
            Text(displayDetail)
                .font(.system(size: 12))
                .foregroundStyle(Color.codexMuted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !displayMetadata.isEmpty {
                HStack(spacing: 10) {
                    ForEach(displayMetadata, id: \.value) { item in
                        Label(item.value, systemImage: item.icon)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.codexMuted)
            }

            Spacer(minLength: 2)
        }
        .padding(.horizontal, 13)
        .padding(.top, 13)
        .padding(.bottom, 39)
        .frame(
            maxWidth: .infinity,
            minHeight: Self.cardHeight,
            maxHeight: Self.cardHeight,
            alignment: .topLeading
        )
        .background(Color.codexCard, in: cardShape)
        .overlay(alignment: .bottom) {
            taskFooter
                .padding(.horizontal, 13)
        }
        .overlay(cardShape.stroke(Color.codexLine, lineWidth: 0.7))
        .contentShape(cardShape)
    }

    private var taskFooter: some View {
        HStack {
            Text(displayState.activityLabel)
            Spacer()
            if tasks.count > 1 {
                Text(selectedIndex + 1 == tasks.count ? "点击回到任务 1" : "点击查看任务 \(selectedIndex + 2)")
            } else {
                Text("更新于\(UsageDateFormat.relative(displayUpdatedAt))")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(Color.codexMuted)
        .frame(height: 39, alignment: .center)
        .overlay(alignment: .top) {
            CodexDivider()
        }
    }

    private var displayState: CodexActivityState { displayedTask?.state ?? snapshot.state }
    private var displayAgentID: AgentID {
        let agentName = displayedTask?.agentDisplayName ?? "Codex"
        return BuiltInAgentCatalog.prioritized
            .first(where: { $0.displayName == agentName })?.id ?? .codex
    }
    private var displayTitle: String {
        if let displayedTask { return displayedTask.title }
        return switch snapshot.state {
        case .idle: "暂时没有待跟进的任务"
        case .unavailable: "暂时无法读取 Codex 活动"
        case .waitingForUser: "需要批准一项操作"
        case .completed: "任务刚刚完成"
        case .interrupted: "任务已停止"
        default: snapshot.threadTitle ?? "Codex 正在处理任务"
        }
    }
    private var displayDetail: String {
        displayedTask?.detail ?? (snapshot.detail.isEmpty ? snapshot.state.hoverTitle : snapshot.detail)
    }
    private var displayUpdatedAt: Date { displayedTask?.updatedAt ?? snapshot.updatedAt }
    private var displayMetadata: [(icon: String, value: String)] {
        guard let displayedTask else { return [] }
        return [
            displayedTask.workspaceName.map { ("folder", $0) },
            displayedTask.gitBranch.map { ("arrow.triangle.branch", $0) },
            displayedTask.model.map { ("cpu", $0) }
        ].compactMap { $0 }
    }
    private var accessibilityText: String {
        tasks.count > 1
            ? "当前显示任务 \(selectedIndex + 1)，共 \(tasks.count) 个任务；点击查看下一个任务"
            : "\(displayState.taskLabel)：\(displayTitle)"
    }

    private func cycleTask() {
        guard tasks.count > 1 else { return }
        selectedTaskID = tasks[(selectedIndex + 1) % tasks.count].id
    }
}

struct QuotaCardsView: View {
    let snapshot: CodexUsageSnapshot
    let isLoggedIn: Bool

    var body: some View {
        HStack(spacing: DetachedWindowMetrics.quotaCardSpacing) {
            if snapshot.hasShortWindow, let short = snapshot.shortWindow {
                QuotaRingCard(window: short, tint: primaryHealth.color)
                    .frame(width: cardWidth)
            }
            if snapshot.hasWeeklyWindow {
                QuotaRingCard(
                    window: snapshot.weekly,
                    tint: snapshot.hasShortWindow ? Color.codexBlue : primaryHealth.color
                )
                .frame(width: cardWidth)
            }
            if !snapshot.hasShortWindow, !snapshot.hasWeeklyWindow {
                Text("额度暂不可用")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.codexMuted)
                    .frame(maxWidth: .infinity, minHeight: 61)
                    .background(Color.codexMist.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
            }
            if snapshot.hasShortWindow != snapshot.hasWeeklyWindow {
                Spacer(minLength: 0)
            }
        }
    }

    private var cardWidth: CGFloat { DetachedWindowMetrics.quotaCardWidth }

    private var primaryHealth: QuotaHealthLevel {
        QuotaHealthLevel.from(window: snapshot.primaryWindow, isLoggedIn: isLoggedIn)
    }
}

private struct QuotaRingCard: View {
    let window: UsageWindow
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color.codexTrack, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: window.percent)
                    .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 39, height: 39)

            VStack(alignment: .leading, spacing: 2) {
                Text(window.percentText)
                    .font(.system(size: 18, weight: .bold))
                    .monospacedDigit()
                Text(window.label == "周额度" ? "本周" : window.label)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 9)
        .frame(maxWidth: .infinity, minHeight: 61, alignment: .leading)
        .background(Color.codexCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.codexLine, lineWidth: 0.7))
    }
}

private struct DashboardProviderContext {
    let asset: BrandAssetID
    let title: String
    let subtitle: String
    let badge: String
    let badgeColor: Color
    let statusText: String
    let statusColor: Color
    let summaryText: String
    let accountLinkTitle: String
    let accountLinkURL: URL
    let officialLinkHelp: String
    let officialLinkURL: URL
    let syncState: String
    let syncedAt: Date
    let isRefreshing: Bool
    let emphasizesAccountLink: Bool
}

private enum DashboardProviderLinks {
    static let codexUsage = URL(string: "https://chatgpt.com/codex/settings/usage")!
    static let deepSeekUsage = URL(string: "https://platform.deepseek.com/usage")!
}

private struct SyncFooterView: View {
    let context: DashboardProviderContext
    let actions: UsageActions
    let showsDetachedButton: Bool
    var isCompact = false
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void

    @State private var showQuitConfirmation = false

    private var hasRefreshError: Bool {
        !["成功", "预览数据", "刷新中", "授权中"].contains(context.syncState)
    }

    /// 竖版底部只剩约 90pt，同步文案必须缩写，完整内容留在 tooltip。
    private var syncText: String {
        let lastSuccess = UsageDateFormat.syncTime(context.syncedAt)
        guard isCompact else {
            if context.isRefreshing { return "正在刷新…" }
            return hasRefreshError
                ? "\(context.syncState) · 上次成功：\(lastSuccess)"
                : "上次同步：\(lastSuccess)"
        }

        if context.isRefreshing { return "刷新中…" }
        if hasRefreshError { return context.syncState }
        let short = lastSuccess.hasPrefix("今天 ") ? String(lastSuccess.dropFirst(3)) : lastSuccess
        return "同步 \(short)"
    }

    private var syncHelpText: String {
        if hasRefreshError {
            return "\(context.syncState) · 上次成功：\(UsageDateFormat.syncTime(context.syncedAt))"
        }
        return "上次同步：\(UsageDateFormat.syncTime(context.syncedAt))"
    }

    var body: some View {
        HStack(spacing: isCompact ? 4 : 6) {
            Text(syncText)
                .font(.system(size: isCompact ? 10 : 11))
                .foregroundStyle(hasRefreshError ? Color.codexRed : Color.codexMuted)
                .lineLimit(1)
                .help(syncHelpText)
            Spacer(minLength: 3)
            HStack(spacing: isCompact ? 3 : 5) {
                Button { NSWorkspace.shared.open(context.officialLinkURL) } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                    .buttonStyle(DashboardIconButtonStyle(helpText: context.officialLinkHelp, isCompact: isCompact))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                Button(action: onOpenSettings) { Image(systemName: "gearshape") }
                    .buttonStyle(DashboardIconButtonStyle(helpText: "设置", isCompact: isCompact))
                if showsDetachedButton {
                    Button(action: actions.openDetachedWindow) { Image(systemName: "rectangle.on.rectangle.angled") }
                        .buttonStyle(DashboardIconButtonStyle(helpText: "打开分离窗口", isCompact: isCompact))
                }
            }
            Button {
                showQuitConfirmation = true
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(DashboardIconButtonStyle(helpText: "关闭软件", isCompact: isCompact))
            .accessibilityLabel("关闭软件")
            .padding(.leading, isCompact ? 1 : 2)
            Button(action: onRefresh) {
                if context.isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Color.codexOnPrimary)
                        .frame(width: isCompact ? 40 : 48)
                } else {
                    Text(isCompact ? "刷新" : "立即刷新")
                }
            }
            .buttonStyle(DashboardRefreshButtonStyle(isCompact: isCompact))
            .disabled(context.isRefreshing)
            .padding(.leading, isCompact ? 2 : 4)
        }
        .padding(.top, isCompact ? 11 : 14)
        .frame(height: isCompact ? 40 : 46, alignment: .bottom)
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .top) { CodexDivider() }
        .alert("确认关闭软件？", isPresented: $showQuitConfirmation) {
            Button("取消", role: .cancel) {}
            Button("关闭软件", role: .destructive, action: actions.quit)
        } message: {
            Text("Codexling 将完全退出，菜单栏图标也会消失。")
        }
    }
}


private struct DashboardIconButtonStyle: PrimitiveButtonStyle {
    var helpText: String = ""
    var isCompact = false

    func makeBody(configuration: Configuration) -> some View {
        CodexMaterialWaveButtonBody(
            action: { configuration.trigger() },
            cornerRadius: 8,
            ink: .adaptiveMint
        ) {
            configuration.label
                .font(.system(size: isCompact ? 12 : 13, weight: .medium))
                .foregroundStyle(Color.codexMuted)
                .frame(width: isCompact ? 28 : 32, height: isCompact ? 28 : 32)
                .background(Color.codexMist.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
        }
        .help(helpText)
    }
}

private struct DashboardRefreshButtonStyle: PrimitiveButtonStyle {
    var isCompact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        CodexMaterialWaveButtonBody(
            action: { configuration.trigger() },
            cornerRadius: 8,
            ink: .softLight
        ) {
            configuration.label
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.codexOnPrimary)
                .frame(minWidth: isCompact ? 52 : 65, minHeight: isCompact ? 28 : 31)
                .background(Color.codexPrimary, in: RoundedRectangle(cornerRadius: 8))
                .opacity(isEnabled ? 1 : 0.45)
        }
    }
}

extension CodexActivityState {
    var statusColor: Color { Color(nsColor: statusNSColor) }

    var companionText: String {
        switch self {
        case .unavailable: "状态不可用"
        case .idle: "安静待命"
        case .thinking: "正在思考"
        case .executing: "正在工作"
        case .reviewing: "正在检查"
        case .waitingForUser: "等待确认"
        case .completed: "刚刚完成"
        case .interrupted: "任务中止"
        }
    }

    var taskLabel: String {
        statusBarText ?? (self == .unavailable ? "状态不可用" : "状态正常")
    }

    var footnote: String {
        switch self {
        case .unavailable: "活动数据不可用"
        case .idle: "空闲 · 没有活跃任务"
        case .thinking: "分析任务 · 最近更新于刚刚"
        case .executing: "执行工具 · 最近更新于刚刚"
        case .reviewing: "检查改动 · 最近更新于刚刚"
        case .waitingForUser: "等待用户 · 确认后继续"
        case .completed: "任务完成 · 20 秒后回到空闲"
        case .interrupted: "任务中止 · 20 秒后回到空闲"
        }
    }

    var activityLabel: String {
        switch self {
        case .unavailable: "活动数据不可用"
        case .idle: "空闲"
        case .thinking: "分析任务"
        case .executing: "执行工具"
        case .reviewing: "检查改动"
        case .waitingForUser: "等待用户"
        case .completed: "任务完成"
        case .interrupted: "任务中止"
        }
    }
}

extension CodexActivitySnapshot {
    var dashboardTitle: String {
        if activeTaskCount > 0 { return "正在处理 \(activeTaskCount) 个任务" }
        return state.hoverTitle
    }

    var dashboardSubtitle: String {
        if let threadTitle, !threadTitle.isEmpty { return threadTitle }
        return detail.isEmpty ? state.hoverTitle : detail
    }
}

extension UsageDateFormat {
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let interval = max(0, now.timeIntervalSince(date))
        if interval < 60 { return "刚刚" }
        if interval < 3_600 { return "\(Int(interval / 60)) 分钟前" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "今天 HH:mm" : "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

extension Color {
    static let deepSeekBrand = Color(red: 0.302, green: 0.420, blue: 0.996)
    static let codexSidebarTop = codexDynamic(
        light: (0.973, 0.984, 0.978),
        dark: (0.145, 0.155, 0.151)
    )
    static let codexSidebarBottom = codexDynamic(
        light: (0.910, 0.941, 0.925),
        dark: (0.105, 0.116, 0.112)
    )
    static let codexGraphite = codexDynamic(
        light: (0.145, 0.169, 0.180),
        dark: (0.840, 0.860, 0.868)
    )
    static let codexOnGraphite = codexDynamic(
        light: (1.000, 1.000, 1.000),
        dark: (0.090, 0.100, 0.105)
    )
}
