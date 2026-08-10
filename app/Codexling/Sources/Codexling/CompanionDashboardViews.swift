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
    var onMeasuredContentHeightChange: (CGFloat) -> Void = { _ in }

    @State private var selectedTaskID: String?
    @State private var showsConnectionSheet = false

    var body: some View {
        Group {
            if store.isLoggedIn {
                switch settings.dashboardOrientation {
                case .horizontal:
                    dashboard
                case .vertical:
                    verticalDashboard
                }
            } else {
                CompanionLoginView(
                    isAuthenticating: store.snapshot.refreshState == "授权中",
                    statusText: store.snapshot.refreshState,
                    actions: actions
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.codexInk)
        .overlay(alignment: .topLeading) {
            if store.isLoggedIn, layout == .window {
                verticalDashboardHeightProbe
            }
        }
        .onPreferenceChange(DashboardMeasuredContentSizeKey.self) { size in
            guard layout == .window,
                  DetachedWindowMetrics.isValidVerticalMeasurement(size) else {
                return
            }
            onMeasuredContentHeightChange(size.height)
        }
        .onChange(of: activityStore.snapshot.activeTasks.map(\.id)) { _, ids in
            if let selectedTaskID, !ids.contains(selectedTaskID) {
                self.selectedTaskID = ids.first
            }
        }
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
            VStack(spacing: 0) {
                dashboardConnectionBar
                HStack(alignment: .top, spacing: 0) {
                    CompanionSidebar(
                        snapshot: store.snapshot,
                        activity: activityStore.snapshot,
                        settings: settings,
                        frameStore: frameStore,
                        todayMinutes: companionStatsStore.todayMinutes,
                        fillColumnHeight: true
                    )
                    .frame(width: DetachedWindowMetrics.sidebarWidth)

                    VStack(spacing: 0) {
                        horizontalDashboardMainContent
                            .layoutPriority(1)
                        Spacer(minLength: 0)
                        horizontalDashboardSyncFooter
                            .layoutPriority(1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(Color.codexCard.opacity(0.96))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .background {
                DashboardWindowChromeBackground()
            }
        }
    }

    private var horizontalDashboardCompactLayout: some View {
        VStack(spacing: 0) {
            dashboardConnectionBar
            HStack(alignment: .top, spacing: 0) {
                CompanionSidebar(
                    snapshot: store.snapshot,
                    activity: activityStore.snapshot,
                    settings: settings,
                    frameStore: frameStore,
                    todayMinutes: companionStatsStore.todayMinutes,
                    expandsVertically: false
                )
                .frame(width: DetachedWindowMetrics.sidebarWidth)

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
        .padding(.top, layout == .window ? 40 : 25)
        .padding(.horizontal, DetachedWindowMetrics.dashboardContentPadding)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dashboardConnectionBar: some View {
        DashboardConnectionSwitcher(
            snapshot: store.snapshot,
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
            snapshot: store.snapshot,
            isRefreshing: store.snapshot.refreshState == "刷新中",
            actions: actions,
            showsDetachedButton: showsDetachedButton,
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
                settings: settings,
                frameStore: frameStore,
                todayMinutes: companionStatsStore.todayMinutes
            )

            DashboardConnectionSwitcher(
                snapshot: store.snapshot,
                store: multiAgentSettings,
                onAdd: { showsConnectionSheet = true },
                compact: true
            )
            .padding(.horizontal, DetachedWindowMetrics.verticalContentPadding)
            .frame(height: 59)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.codexCard.opacity(0.96))
            .overlay(alignment: .bottom) { Color.codexLine.frame(height: 1) }

            CompanionAccountRow(snapshot: store.snapshot)

            VStack(alignment: .leading, spacing: 0) {
                ActivityHeading(
                    activity: activityStore.snapshot,
                    usage: store.snapshot,
                    isLoggedIn: store.isLoggedIn,
                    isCompact: true
                )

                if store.snapshot.showsSubscriptionExpiryReminder,
                   let message = store.snapshot.subscriptionExpiryReminderMessage {
                    SubscriptionExpiryReminderBanner(message: message)
                        .padding(.top, 11)
                }

                TaskStackView(
                    snapshot: activityStore.snapshot,
                    selectedTaskID: $selectedTaskID
                )
                .padding(.top, 15)

                selectedVerticalConnectionSection
            }
            .padding(.top, 13)
            .padding(.horizontal, DetachedWindowMetrics.verticalContentPadding)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var verticalDashboardSyncFooter: some View {
        SyncFooterView(
            snapshot: store.snapshot,
            isRefreshing: store.snapshot.refreshState == "刷新中",
            actions: actions,
            showsDetachedButton: showsDetachedButton,
            isCompact: true,
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
            coupons,
            store.snapshot.subscriptionExpiryReminderMessage ?? "",
            store.snapshot.hasShortWindow ? "1" : "0",
            store.snapshot.hasWeeklyWindow ? "1" : "0",
            String(activityStore.snapshot.activeTasks.count),
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
        .padding(.top, 14)
    }

    @ViewBuilder
    private var selectedConnectionSection: some View {
        if let connection = multiAgentSettings.selectedDeepSeekConnection {
            DeepSeekDashboardCard(connection: connection) {
                Task { await multiAgentSettings.refreshDeepSeekConnection(connection) }
            }
            .padding(.top, 18)
        } else if let connection = multiAgentSettings.selectedCodexAccount {
            ManagedCodexDashboardCard(connection: connection, store: multiAgentSettings)
                .padding(.top, 18)
        } else {
            quotaSection
        }
    }

    @ViewBuilder
    private var selectedVerticalConnectionSection: some View {
        if let connection = multiAgentSettings.selectedDeepSeekConnection {
            DeepSeekDashboardCard(connection: connection) {
                Task { await multiAgentSettings.refreshDeepSeekConnection(connection) }
            }
            .padding(.top, 14)
        } else if let connection = multiAgentSettings.selectedCodexAccount {
            ManagedCodexDashboardCard(connection: connection, store: multiAgentSettings)
                .padding(.top, 14)
        } else {
            verticalQuotaSection
        }
    }
}

private struct DashboardConnectionSwitcher: View {
    let snapshot: CodexUsageSnapshot
    @Bindable var store: MultiAgentSettingsStore
    let onAdd: () -> Void
    var compact = false

    var body: some View {
        HStack(spacing: 7) {
            if !compact {
                Text("我的连接")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.codexMuted)
                    .textCase(.uppercase)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    connectionButton(
                        asset: .codex,
                        title: "Codex",
                        subtitle: snapshot.companionAccountName,
                        color: Color.codexGreen,
                        selected: store.selectedConnectionKey == MultiAgentSettingsStore.currentCodexConnectionKey
                    ) { store.selectCurrentCodexConnection() }
                    ForEach(store.codexAccounts) { connection in
                        connectionButton(
                            asset: .codex,
                            title: "Codex",
                            subtitle: connection.label,
                            color: Color.codexGreen,
                            selected: store.isSelected(connection),
                            needsAttention: connection.authenticationState != .connected
                        ) { store.selectCodexConnection(connection) }
                    }
                    ForEach(store.deepSeekConnections) { connection in
                        connectionButton(
                            asset: .deepSeek,
                            title: "DeepSeek",
                            subtitle: connection.label,
                            color: .blue,
                            selected: store.isSelected(connection),
                            needsAttention: connection.authenticationState != .connected
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
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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
        needsAttention: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                BrandIconView(
                    asset: asset,
                    size: 32,
                    cornerRadius: 11
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 10, weight: .bold))
                    Text(subtitle).font(.system(size: 8)).foregroundStyle(Color.codexMuted).lineLimit(1)
                }
                if needsAttention {
                    Circle().fill(Color.codexAmber).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background(selected ? color.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(selected ? color.opacity(0.25) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(subtitle)")
        .accessibilityValue(selected ? "已选择" : "未选择")
    }
}

private struct ManagedCodexDashboardCard: View {
    let connection: CodexAccountConnection
    @Bindable var store: MultiAgentSettingsStore

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
                         : "使用官方 codex login，不读取或复制其他账号的 token")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.codexMuted)
                }
                .frame(maxWidth: .infinity, minHeight: 94)
                HStack {
                    Button("检查登录") { Task { await store.refreshCodexAccounts() } }
                        .buttonStyle(.bordered)
                    Spacer()
                    if connection.authenticationState != .connected {
                        Button("官方登录") { store.launchCodexLogin(for: connection) }
                            .buttonStyle(.borderedProminent)
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
                    Text("来源：Codex App Server")
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
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                BrandIconView(asset: .deepSeek, size: 40, cornerRadius: 11)
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
                        .padding(.top, 4)
                    Text("充值 \(NSDecimalNumber(decimal: balance.toppedUp).stringValue) · 赠送 \(NSDecimalNumber(decimal: balance.granted).stringValue)")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.codexMuted)
                        .padding(.top, 2)
                } else {
                    Text("—").font(.system(size: 36, weight: .bold)).foregroundStyle(Color.codexMuted).padding(.top, 4)
                }
                HStack(spacing: 8) {
                    Button(action: onRefresh) {
                        Label("查询余额", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button(action: {}) { Image(systemName: "gearshape") }
                        .buttonStyle(.bordered)
                        .disabled(true)
                }
                .padding(.top, 16)
            }
            .padding(20)
            .background(
                LinearGradient(colors: [Color.purple.opacity(0.07), Color.codexCard], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(Color.purple.opacity(0.15)) }
            .padding(.top, 20)

            Label("Key 保存在 macOS Keychain，只用于查询 DeepSeek 官方余额接口；余额属于账户，并非此 Key 独享。", systemImage: "checkmark.shield")
                .font(.system(size: 9))
                .foregroundStyle(Color.codexMuted)
                .padding(.top, 12)
        }
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

/// 陪伴胶囊：Pet 名 + 当前活动状态，横竖两版只有高度不同。
private struct CompanionStatusCapsule: View {
    let activity: CodexActivitySnapshot
    let quotaHealth: QuotaHealthLevel
    let petName: String?
    let height: CGFloat
    let waveEnabled: Bool
    let waveColorMode: StatusCapsuleColorMode
    @Environment(\.colorScheme) private var colorScheme

    private var showsActivityFlow: Bool {
        waveEnabled && activity.state.showsActivityWave
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(activity.state.statusColor)
                .frame(width: 8, height: 8)
            Text("\(petName ?? "Pet") · \(activity.state.companionText)")
                .lineLimit(1)
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
    }

    private var waveInk: NSColor {
        waveColorMode.resolvedNSColor(
            activityState: activity.state,
            quotaHealth: quotaHealth
        ) ?? (colorScheme == .dark
            ? NSColor.white.withAlphaComponent(0.18)
            : NSColor.black.withAlphaComponent(0.10))
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
    @Bindable var settings: AppSettingsStore
    @Bindable var frameStore: PetFrameStore
    let todayMinutes: Int
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
                    petName: settings.selectedPet?.displayName,
                    height: 28,
                    waveEnabled: settings.statusBarWaveEnabled,
                    waveColorMode: settings.statusBarWaveColorMode
                )

                Text("今天一起工作 \(CompanionCopy.todayDuration(minutes: todayMinutes))")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.codexMuted)
                    .padding(.top, 8)
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
        .clipped()
        .overlay(alignment: .bottom) {
            CodexDivider()
        }
    }
}

/// 竖向布局的账号行：把侧栏那块两行账号信息压成一条。
private struct CompanionAccountRow: View {
    let snapshot: CodexUsageSnapshot
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(snapshot.companionAccountName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.codexInk)
                        .lineLimit(1)
                    if !snapshot.companionPlanBadgeText.isEmpty {
                        Text(snapshot.companionPlanBadgeText)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.codexGreen)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.codexGreen.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(snapshot.accountEmail)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let summaryLine = snapshot.subscriptionCompactSummaryLine {
                ChatGPTBillingCompactLink(
                    title: summaryLine,
                    emphasizesExpiry: snapshot.showsSubscriptionExpiryReminder
                ) {
                    openURL(ChatGPTWebLinks.billingPage)
                }
            } else {
                ChatGPTBillingCompactLink(title: "订阅与账单") {
                    openURL(ChatGPTWebLinks.billingPage)
                }
            }
        }
        .padding(.horizontal, DetachedWindowMetrics.verticalContentPadding)
        .frame(height: 46)
        .overlay(alignment: .bottom) {
            CodexDivider()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("当前账号 \(snapshot.companionAccountName)")
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
    private static let accountTopPadding: CGFloat = 45

    let snapshot: CodexUsageSnapshot
    let activity: CodexActivitySnapshot
    @Bindable var settings: AppSettingsStore
    @Bindable var frameStore: PetFrameStore
    let todayMinutes: Int
    /// 在父级 HStack 已确定行高时铺满侧栏（独立横版）。
    var fillColumnHeight = false
    var expandsVertically = true
    @State private var ripples: [CodexMaterialWaveToken] = []
    @Environment(\.openURL) private var openURL

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
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            accountSummary
                .padding(.top, Self.accountTopPadding)
                .padding(.horizontal, 16)
                .frame(width: DetachedWindowMetrics.sidebarWidth, alignment: .leading)
        }
        .companionPetInteraction(
            space: Self.sidebarSpace,
            frameStore: frameStore,
            ripples: $ripples,
            fallbackRippleLocation: CGPoint(x: 94, y: 220)
        )
        .clipped()
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
                petName: settings.selectedPet?.displayName,
                height: 30,
                waveEnabled: settings.statusBarWaveEnabled,
                waveColorMode: settings.statusBarWaveColorMode
            )

            Text("今天一起工作 \(CompanionCopy.todayDuration(minutes: todayMinutes))")
                .font(.system(size: 11))
                .foregroundStyle(Color.codexMuted)
                .padding(.top, 9)
                .padding(.bottom, 19)
        }
    }

    private var accountSummary: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(snapshot.companionAccountName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.codexInk)
                        .lineLimit(1)
                    if !snapshot.companionPlanBadgeText.isEmpty {
                        Text(snapshot.companionPlanBadgeText)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.codexGreen)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.codexGreen.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(snapshot.accountEmail)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.system(size: 10))
            .foregroundStyle(Color.codexMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)

            CodexDivider()

            Group {
                if let summaryLine = snapshot.subscriptionCompactSummaryLine {
                    ChatGPTBillingCompactLink(
                        title: summaryLine,
                        emphasizesExpiry: snapshot.showsSubscriptionExpiryReminder
                    ) {
                        openURL(ChatGPTWebLinks.billingPage)
                    }
                } else {
                    ChatGPTBillingCompactLink(title: "订阅与账单") {
                        openURL(ChatGPTWebLinks.billingPage)
                    }
                }
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("当前账号 \(snapshot.companionAccountName)")
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
                HStack(spacing: 5) {
                    Circle().fill(displayState.statusColor).frame(width: 8, height: 8)
                    Text(displayState.taskLabel)
                        .foregroundStyle(displayState.statusColor)
                        .fontWeight(.semibold)
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

private struct SyncFooterView: View {
    let snapshot: CodexUsageSnapshot
    let isRefreshing: Bool
    let actions: UsageActions
    let showsDetachedButton: Bool
    var isCompact = false
    let onOpenSettings: () -> Void

    @State private var showQuitConfirmation = false

    private var hasRefreshError: Bool {
        !["成功", "预览数据", "刷新中", "授权中"].contains(snapshot.refreshState)
    }

    /// 竖版底部只剩约 90pt，同步文案必须缩写，完整内容留在 tooltip。
    private var syncText: String {
        let lastSuccess = UsageDateFormat.syncTime(snapshot.fetchedAt)
        guard isCompact else {
            if isRefreshing { return "正在刷新…" }
            return hasRefreshError
                ? "\(snapshot.refreshState) · 上次成功：\(lastSuccess)"
                : "上次同步：\(lastSuccess)"
        }

        if isRefreshing { return "刷新中…" }
        if hasRefreshError { return snapshot.refreshState }
        let short = lastSuccess.hasPrefix("今天 ") ? String(lastSuccess.dropFirst(3)) : lastSuccess
        return "同步 \(short)"
    }

    private var syncHelpText: String {
        if hasRefreshError {
            return "\(snapshot.refreshState) · 上次成功：\(UsageDateFormat.syncTime(snapshot.fetchedAt))"
        }
        return "上次同步：\(UsageDateFormat.syncTime(snapshot.fetchedAt))"
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
                Button(action: onOpenSettings) { Image(systemName: "gearshape") }
                    .buttonStyle(DashboardIconButtonStyle(helpText: "设置", isCompact: isCompact))
                Button(action: actions.openUsagePage) { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(DashboardIconButtonStyle(helpText: "打开官方 Usage", isCompact: isCompact))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
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
            Button(action: actions.refresh) {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Color.codexOnPrimary)
                        .frame(width: isCompact ? 40 : 48)
                } else {
                    Text(isCompact ? "刷新" : "立即刷新")
                }
            }
            .buttonStyle(DashboardRefreshButtonStyle(isCompact: isCompact))
            .disabled(isRefreshing)
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

private struct CompanionLoginView: View {
    let isAuthenticating: Bool
    let statusText: String
    let actions: UsageActions

    private var logoImage: NSImage {
        guard let url = Bundle.main.url(forResource: "codexling-logo", withExtension: "webp"),
              let image = NSImage(contentsOf: url) else {
            return NSApp.applicationIconImage
        }
        return image
    }

    var body: some View {
        ZStack {
            Color.white

            VStack(spacing: 0) {
                Spacer(minLength: 50)
                Image(nsImage: logoImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 58, height: 58)
                Text("登录后查看你的 Codex")
                    .font(.system(size: 19, weight: .semibold))
                    .padding(.top, 17)
                Text("查看当前任务、精灵状态和额度。\n授权会在官方 ChatGPT / Codex 页面完成。")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.codexMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.top, 10)
                Button(action: actions.loginAndFetch) {
                    HStack(spacing: 7) {
                        if isAuthenticating { ProgressView().controlSize(.small) }
                        Text(isAuthenticating ? "等待授权…" : "登录并同步额度")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isAuthenticating)
                .frame(maxWidth: 292)
                .padding(.top, 22)
                Text("授权 token 仅保存在本机 Application Support")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.codexMuted)
                    .padding(.top, 12)
                if !isAuthenticating, !["预览数据", "成功", "已退出登录"].contains(statusText) {
                    Text(statusText)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.codexAmber)
                        .padding(.top, 6)
                }
                Spacer(minLength: 50)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(Color(red: 0.096, green: 0.105, blue: 0.118))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
