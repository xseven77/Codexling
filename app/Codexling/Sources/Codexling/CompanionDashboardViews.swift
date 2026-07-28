import AppKit
import SwiftUI

struct CompanionDashboardView: View {
    @Bindable var store: UsageSnapshotStore
    @Bindable var settings: AppSettingsStore
    @Bindable var activityStore: CodexActivityStore
    @Bindable var frameStore: PetFrameStore
    @Bindable var companionStatsStore: CompanionStatsStore
    let actions: UsageActions
    let layout: UsagePanelLayout
    let showsDetachedButton: Bool
    let onOpenSettings: () -> Void
    /// 竖向布局的内容自然高度；窗口据此调整，横向布局不使用。
    var onMeasuredContentHeightChange: (CGFloat) -> Void = { _ in }

    @State private var selectedTaskID: String?

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
        .foregroundStyle(Color.codexInk)
        // 两种方向共用同一份任务选中态：被选中的任务消失后回退到第一个。
        .onChange(of: activityStore.snapshot.activeTasks.map(\.id)) { _, ids in
            if let selectedTaskID, !ids.contains(selectedTaskID) {
                self.selectedTaskID = ids.first
            }
        }
    }

    private var dashboard: some View {
        HStack(spacing: 0) {
            CompanionSidebar(
                snapshot: store.snapshot,
                activity: activityStore.snapshot,
                settings: settings,
                frameStore: frameStore,
                todayMinutes: companionStatsStore.todayMinutes
            )
            .frame(width: DetachedWindowMetrics.sidebarWidth)

            VStack(alignment: .leading, spacing: 0) {
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

                    quotaSection
                }
                .padding(.top, layout == .window ? 40 : 25)
                .padding(.horizontal, DetachedWindowMetrics.dashboardContentPadding)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                SyncFooterView(
                    snapshot: store.snapshot,
                    isRefreshing: store.snapshot.refreshState == "刷新中",
                    actions: actions,
                    showsDetachedButton: showsDetachedButton,
                    onOpenSettings: onOpenSettings
                )
                .padding(.horizontal, DetachedWindowMetrics.dashboardContentPadding)
                .padding(.bottom, 25)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.codexCard.opacity(0.96))
        }
        .frame(minHeight: 473, maxHeight: .infinity)
        .background(Color.codexCard)
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
        }
        .padding(.top, 18)
    }

    // MARK: - 竖向布局

    private var verticalDashboard: some View {
        VStack(spacing: 0) {
            CompanionPetHeader(
                activity: activityStore.snapshot,
                settings: settings,
                frameStore: frameStore,
                todayMinutes: companionStatsStore.todayMinutes
            )

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

                verticalQuotaSection
            }
            .padding(.top, 13)
            .padding(.horizontal, DetachedWindowMetrics.verticalContentPadding)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)

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
        .frame(maxWidth: .infinity, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.codexCard)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: DashboardMeasuredContentHeightKey.self,
                    value: geometry.size.height
                )
            }
        }
        .onPreferenceChange(DashboardMeasuredContentHeightKey.self) { height in
            guard height > 1 else { return }
            onMeasuredContentHeightChange(height)
        }
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
        }
        .padding(.top, 14)
    }
}

enum DashboardMeasuredContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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
    let petName: String?
    let height: CGFloat

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
        .background(Color.codexCard.opacity(0.92), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.72), lineWidth: 0.7))
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
                    petName: settings.selectedPet?.displayName,
                    height: 28
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
            Rectangle().fill(Color.codexLine.opacity(0.72)).frame(height: 1)
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
            Rectangle().fill(Color.codexLine.opacity(0.72)).frame(height: 0.7)
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

private struct ResetCouponDisplayTicket: Identifiable {
    let id: String
    let name: String
    let source: String
    let expiresAt: String
}

private struct ResetCouponSummaryView: View {
    let coupons: [ResetCoupon]

    private var tickets: [ResetCouponDisplayTicket] {
        coupons.flatMap { coupon in
            (0..<coupon.count).map { copyIndex in
                ResetCouponDisplayTicket(
                    id: "\(coupon.id)-\(copyIndex)",
                    name: coupon.name,
                    source: coupon.source,
                    expiresAt: coupon.expiresAt
                )
            }
        }
    }

    var body: some View {
        Group {
            if tickets.isEmpty {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.codexMist.opacity(0.65))
                            .frame(width: 34, height: 34)
                            .rotationEffect(.degrees(-8))
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.codexLine.opacity(0.55), style: StrokeStyle(lineWidth: 0.8, dash: [3, 2.5]))
                            .frame(width: 34, height: 34)
                            .rotationEffect(.degrees(-8))
                        Image(systemName: "ticket")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.codexMuted.opacity(0.72))
                            .rotationEffect(.degrees(-8))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("重置券 0 张")
                            .font(.system(size: 11, weight: .semibold))
                        Text("当前没有可用重置券")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.codexMuted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [Color.codexCard.opacity(0.92), Color.codexMist.opacity(0.42)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.codexLine.opacity(0.85), lineWidth: 0.7)
                )
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.35))
                        .frame(height: 0.6)
                        .padding(.horizontal, 12)
                }
            } else {
                ResetCouponTicketDeck(
                    tickets: tickets,
                    formattedExpiration: formattedExpiration
                )
            }
        }
    }

    private func formattedExpiration(_ value: String) -> String {
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let date = input.date(from: value) else { return value }

        let output = DateFormatter()
        output.locale = Locale(identifier: "zh_CN")
        output.dateFormat = "M月d日 HH:mm"
        return output.string(from: date)
    }
}

private struct ResetCouponTicketDeck: View {
    let tickets: [ResetCouponDisplayTicket]
    let formattedExpiration: (String) -> String

    @State private var selectedIndex = 0

    private var selectedTicket: ResetCouponDisplayTicket {
        tickets[selectedIndex]
    }

    /// 可见堆叠层数：1 张显示 1 层，2 张显示 2 层，3 张及以上最多 3 层。
    private var visibleStackCount: Int {
        min(ResetCouponTicketMetrics.maxStackLayers, tickets.count)
    }

    private var displayedBackLayerDepths: [Int] {
        guard tickets.count > 1 else { return [] }
        let backCount = visibleStackCount - 1
        guard backCount > 0 else { return [] }
        return Array(1...backCount)
    }

    private var restBackLayerDepths: [Int] {
        guard tickets.count > 1 else { return [] }
        return Array(1..<visibleStackCount)
    }

    private var deepestBackOffset: CGFloat {
        CGFloat(restBackLayerDepths.last ?? 0) * ResetCouponTicketMetrics.stackOffsetY
    }

    private var deckHeight: CGFloat {
        ResetCouponTicketMetrics.cardHeight + deepestBackOffset + (restBackLayerDepths.isEmpty ? 4 : 8)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(displayedBackLayerDepths.reversed(), id: \.self) { depth in
                ResetCouponStackLayer(depth: depth, totalBackLayers: restBackLayerDepths.count)
                    .scaleEffect(
                        1 - CGFloat(depth) * ResetCouponTicketMetrics.stackScaleStep,
                        anchor: .topLeading
                    )
                    .offset(
                        x: CGFloat(depth) * ResetCouponTicketMetrics.stackOffsetX,
                        y: CGFloat(depth) * ResetCouponTicketMetrics.stackOffsetY
                    )
                    .zIndex(Double(depth))
            }

            ResetCouponDeckTicket(
                ticket: selectedTicket,
                position: selectedIndex + 1,
                total: tickets.count,
                formattedExpiration: formattedExpiration,
                isFront: true,
                onSwitch: tickets.count > 1 ? { cycleTicket() } : nil
            )
            .zIndex(Double(visibleStackCount + 1))
        }
        .padding(.bottom, restBackLayerDepths.isEmpty ? 6 : 8)
        .frame(height: deckHeight, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("重置券 \(tickets.count) 张，当前第 \(selectedIndex + 1) 张")
        .onChange(of: tickets.map(\.id)) { _, ids in
            if ids.isEmpty || selectedIndex >= ids.count {
                selectedIndex = 0
            }
        }
    }

    private func cycleTicket() {
        guard tickets.count > 1 else { return }
        selectedIndex = (selectedIndex + 1) % tickets.count
    }
}

private struct ResetCouponDeckTicket: View {
    let ticket: ResetCouponDisplayTicket
    let position: Int
    let total: Int
    let formattedExpiration: (String) -> String
    let isFront: Bool
    let onSwitch: (() -> Void)?

    var body: some View {
        ResetCouponTicketCard(
            name: ticket.name,
            source: ticket.source,
            expiresAt: formattedExpiration(ticket.expiresAt),
            position: position,
            total: total,
            stackDepth: 0,
            isFront: isFront,
            onSwitch: onSwitch
        )
    }
}

private enum ResetCouponTicketMetrics {
    static let cardHeight: CGFloat = 82
    static let stubWidth: CGFloat = 88
    static let stubHorizontalPadding: CGFloat = 12
    static let perforationNotchRadius: CGFloat = 4
    static let maxStackLayers = 3
    static let stackOffsetX: CGFloat = 2.5
    static let stackOffsetY: CGFloat = 5
    static let stackScaleStep: CGFloat = 0.016
}

private struct ResetCouponTicketShape: Shape {
    var cornerRadius: CGFloat = 12
    var edgeNotchRadius: CGFloat = 4.5
    var perforationNotchRadius: CGFloat = ResetCouponTicketMetrics.perforationNotchRadius
    var perforationInset: CGFloat = ResetCouponTicketMetrics.stubWidth

    func path(in rect: CGRect) -> Path {
        let perforationX = rect.maxX - perforationInset
        var path = Path()

        path.move(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: perforationX - perforationNotchRadius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: perforationX, y: rect.minY),
            radius: perforationNotchRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )

        let rightNotchY = rect.midY
        path.addLine(to: CGPoint(x: rect.maxX, y: rightNotchY - edgeNotchRadius))
        path.addArc(
            center: CGPoint(x: rect.maxX, y: rightNotchY),
            radius: edgeNotchRadius,
            startAngle: .degrees(-90),
            endAngle: .degrees(90),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addArc(
            center: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        path.addLine(to: CGPoint(x: perforationX + perforationNotchRadius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: perforationX, y: rect.maxY),
            radius: perforationNotchRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(180),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        let leftNotchY = rect.midY
        path.addLine(to: CGPoint(x: rect.minX, y: leftNotchY + edgeNotchRadius))
        path.addArc(
            center: CGPoint(x: rect.minX, y: leftNotchY),
            radius: edgeNotchRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(-90),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        path.addArc(
            center: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(-90),
            clockwise: false
        )

        path.closeSubpath()
        return path
    }
}

private struct ResetCouponPaperTexture: View {
    let isDark: Bool

    var body: some View {
        Canvas { context, size in
            let lineColor = Color.black.opacity(isDark ? 0.06 : 0.018)
            var y: CGFloat = 3
            while y < size.height {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(lineColor), lineWidth: 0.35)
                y += 5.5
            }

            let speckColor = Color.black.opacity(isDark ? 0.05 : 0.012)
            let specks: [(CGFloat, CGFloat)] = [
                (0.12, 0.18), (0.28, 0.42), (0.46, 0.24), (0.63, 0.58),
                (0.78, 0.31), (0.88, 0.72), (0.34, 0.81), (0.55, 0.67)
            ]
            for (xFactor, yFactor) in specks {
                let rect = CGRect(
                    x: size.width * xFactor,
                    y: size.height * yFactor,
                    width: 0.7,
                    height: 0.7
                )
                context.fill(Path(ellipseIn: rect), with: .color(speckColor))
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ResetCouponPerforation: View {
    let tone: Color
    let isDark: Bool
    var height: CGFloat = ResetCouponTicketMetrics.cardHeight

    var body: some View {
        ZStack {
            Rectangle()
                .stroke(
                    tone.opacity(isDark ? 0.18 : 0.10),
                    style: StrokeStyle(lineWidth: 0.5, dash: [1.5, 3.5])
                )
                .frame(width: 0.5, height: height)

            VStack(spacing: 4.2) {
                ForEach(0..<perforationDotCount, id: \.self) { index in
                    Circle()
                        .fill(tone.opacity(index.isMultiple(of: 2) ? 0.82 : 0.58))
                        .frame(width: 1.6, height: 1.6)
                }
            }
            .frame(height: height - ResetCouponTicketMetrics.perforationNotchRadius * 2)
        }
        .frame(width: 2, height: height)
        .allowsHitTesting(false)
    }

    private var perforationDotCount: Int {
        max(7, Int((height - ResetCouponTicketMetrics.perforationNotchRadius * 2) / 5.8))
    }
}

private struct ResetCouponStackLayer: View {
    let depth: Int
    let totalBackLayers: Int
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    private var layerOpacity: Double {
        switch totalBackLayers {
        case 1: 0.92
        case 2 where depth == 1: 0.88
        default: depth == 1 ? 0.86 : 0.74
        }
    }

    private var edgeOpacity: Double {
        depth == totalBackLayers ? 0.58 : (depth == 1 ? 0.72 : 0.64)
    }

    private var surfaceTop: Color {
        isDark
            ? Color(red: 0.138, green: 0.145, blue: 0.148)
            : Color(red: 0.972, green: 0.978, blue: 0.958)
    }

    private var surfaceBottom: Color {
        isDark
            ? Color(red: 0.108, green: 0.115, blue: 0.118)
            : Color(red: 0.928, green: 0.942, blue: 0.932)
    }

    private var edge: Color {
        isDark
            ? Color(red: 0.240, green: 0.255, blue: 0.250)
            : Color(red: 0.790, green: 0.812, blue: 0.800)
    }

    var body: some View {
        ResetCouponTicketShape()
            .fill(
                LinearGradient(
                    colors: [surfaceTop, surfaceBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                ResetCouponTicketShape()
                    .stroke(edge.opacity(edgeOpacity), lineWidth: 0.75)
            }
            .frame(maxWidth: .infinity, minHeight: ResetCouponTicketMetrics.cardHeight, maxHeight: ResetCouponTicketMetrics.cardHeight)
            .opacity(layerOpacity)
    }
}

private struct ResetCouponStubSection: View {
    let position: Int
    let total: Int
    let source: String
    let isFront: Bool
    let isDark: Bool
    let coordinateSpaceName: String
    let onStubTap: ((CGPoint) -> Void)?

    var body: some View {
        ZStack {
            stubContent
                .allowsHitTesting(false)

            if total > 1, onStubTap != nil {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        codexMaterialTapGesture(in: coordinateSpaceName) { location in
                            onStubTap?(location)
                        }
                    )
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("切换查看，当前第 \(position) 张，共 \(total) 张")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stubContent: some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(
                        Color.codexGreen.opacity(isDark ? 0.42 : 0.34),
                        style: StrokeStyle(lineWidth: 0.9, dash: [2.5, 1.8])
                    )
                    .background(
                        Color.codexGreen.opacity(isDark ? 0.08 : 0.05),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
                HStack(spacing: 4) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text(String(format: "%02d", position))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(Color.codexGreen)
                .rotationEffect(.degrees(-7))
            }
            .frame(width: 58, height: 26)

            Text(isFront && total > 1 ? "切换查看" : "可用券")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.codexMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.9)

            if !source.isEmpty {
                Text(source)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.codexMuted.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(.horizontal, ResetCouponTicketMetrics.stubHorizontalPadding)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct ResetCouponTicketShadow: ViewModifier {
    let isFront: Bool
    let isDark: Bool

    func body(content: Content) -> some View {
        if isFront {
            content
                .shadow(
                    color: Color.black.opacity(isDark ? 0.11 : 0.042),
                    radius: 12,
                    x: 0,
                    y: 5
                )
                .shadow(
                    color: Color.black.opacity(isDark ? 0.05 : 0.018),
                    radius: 3,
                    x: 0,
                    y: 1
                )
        } else {
            content
        }
    }
}

private struct ResetCouponTicketCard: View {
    private static let ticketSpace = "resetCouponTicket"

    let name: String
    let source: String
    let expiresAt: String
    let position: Int
    let total: Int
    let stackDepth: Int
    let isFront: Bool
    let onSwitch: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @State private var ripples: [CodexMaterialWaveToken] = []

    private var isDark: Bool { colorScheme == .dark }

    private var ticketSurfaceTop: Color {
        isDark
            ? Color(red: 0.158, green: 0.165, blue: 0.168)
            : Color(red: 0.998, green: 0.993, blue: 0.968)
    }

    private var ticketSurfaceBottom: Color {
        isDark
            ? Color(red: 0.118, green: 0.125, blue: 0.128)
            : Color(red: 0.958, green: 0.968, blue: 0.952)
    }

    private var stubSurface: Color {
        isDark
            ? Color(red: 0.132, green: 0.139, blue: 0.142)
            : Color(red: 0.978, green: 0.984, blue: 0.972)
    }

    private var ticketEdge: Color {
        isDark
            ? Color(red: 0.255, green: 0.270, blue: 0.266)
            : Color(red: 0.805, green: 0.828, blue: 0.815)
    }

    private var edgeStrokeOpacity: Double { 0.95 }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 11) {
                resetIcon

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(name.isEmpty ? "Codex 重置券" : name)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Text("\(position) / \(total)")
                            .font(.system(size: 8, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.codexGreen)
                            .padding(.horizontal, 6)
                            .frame(height: 17)
                            .background(
                                LinearGradient(
                                    colors: isDark
                                        ? [Color(red: 0.105, green: 0.235, blue: 0.145), Color(red: 0.085, green: 0.195, blue: 0.120)]
                                        : [Color(red: 0.905, green: 0.978, blue: 0.922), Color(red: 0.865, green: 0.958, blue: 0.895)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                in: Capsule()
                            )
                            .overlay(Capsule().stroke(Color.codexGreen.opacity(isFront ? 0.22 : 0.14), lineWidth: 0.6))
                    }
                    Label("\(expiresAt) 到期", systemImage: "calendar.badge.clock")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.codexMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 6)
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .allowsHitTesting(false)

            stubSection
                .frame(width: ResetCouponTicketMetrics.stubWidth)
        }
        .frame(maxWidth: .infinity, minHeight: ResetCouponTicketMetrics.cardHeight, maxHeight: ResetCouponTicketMetrics.cardHeight)
        .background { ticketBackground }
        .clipShape(ResetCouponTicketShape())
        .overlay {
            ResetCouponTicketShape()
                .stroke(
                    LinearGradient(
                        colors: [
                            ticketEdge.opacity(edgeStrokeOpacity),
                            ticketEdge.opacity(edgeStrokeOpacity * 0.62)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.85
                )
        }
        .overlay {
            GeometryReader { geometry in
                ResetCouponPerforation(tone: ticketEdge, isDark: isDark)
                    .position(
                        x: geometry.size.width - ResetCouponTicketMetrics.stubWidth,
                        y: geometry.size.height / 2
                    )
            }
            .allowsHitTesting(false)
        }
        .overlay { innerHighlight }
        .overlay {
            CodexMaterialWaveLayer(ripples: $ripples)
            .clipShape(ResetCouponTicketShape())
        }
        .coordinateSpace(name: Self.ticketSpace)
        .modifier(ResetCouponTicketShadow(isFront: isFront, isDark: isDark))
    }

    private var resetIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isDark
                            ? [Color.codexGreen.opacity(0.18), Color.codexGreen.opacity(0.08)]
                            : [Color.codexGreen.opacity(0.11), Color.codexGreen.opacity(0.045)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.codexGreen.opacity(isDark ? 0.36 : 0.24),
                            Color.codexGreen.opacity(isDark ? 0.18 : 0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.codexGreen)
        }
        .frame(width: 32, height: 32)
        .shadow(color: Color.codexGreen.opacity(isDark ? 0.08 : 0.06), radius: 3, y: 1)
    }

    private var stubSection: some View {
        ResetCouponStubSection(
            position: position,
            total: total,
            source: source,
            isFront: isFront,
            isDark: isDark,
            coordinateSpaceName: Self.ticketSpace,
            onStubTap: onSwitch == nil ? nil : { location in
                ripples.spawnWave(at: location)
                onSwitch?()
            }
        )
    }

    @ViewBuilder
    private var ticketBackground: some View {
        ZStack {
            LinearGradient(
                colors: [ticketSurfaceTop, ticketSurfaceBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(spacing: 0) {
                Color.clear
                LinearGradient(
                    colors: [
                        stubSurface.opacity(0.15),
                        stubSurface,
                        stubSurface.opacity(isDark ? 0.88 : 0.96)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: ResetCouponTicketMetrics.stubWidth)
            }

            ResetCouponPaperTexture(isDark: isDark)
                .blendMode(isDark ? .plusLighter : .multiply)
                .opacity(isDark ? 0.35 : 0.55)
        }
    }

    private var innerHighlight: some View {
        ResetCouponTicketShape()
            .stroke(Color.white.opacity(isDark ? 0.06 : 0.38), lineWidth: 0.6)
            .blur(radius: 0.2)
            .padding(0.6)
            .mask {
                ResetCouponTicketShape()
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
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
    @State private var ripples: [CodexMaterialWaveToken] = []
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.codexSidebarTop, Color.codexSidebarBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Wave sits on the sidebar background, beneath pet and chrome.
            CodexMaterialWaveLayer(ripples: $ripples)

            petView
                .frame(width: 145, height: 218)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
            Rectangle().fill(Color.codexLine.opacity(0.72)).frame(width: 1)
        }
    }

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            CompanionStatusCapsule(
                activity: activity,
                petName: settings.selectedPet?.displayName,
                height: 30
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

            Rectangle()
                .fill(Color.codexLine.opacity(0.72))
                .frame(height: 0.7)

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
            Rectangle()
                .fill(Color.codexLine)
                .frame(height: 0.7)
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
        .overlay(alignment: .top) { Rectangle().fill(Color.codexLine).frame(height: 0.7) }
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
