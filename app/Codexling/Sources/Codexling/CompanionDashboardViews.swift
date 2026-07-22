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

    @State private var selectedTaskID: String?

    var body: some View {
        Group {
            if store.isLoggedIn {
                dashboard
            } else {
                CompanionLoginView(
                    isAuthenticating: store.snapshot.refreshState == "授权中",
                    statusText: store.snapshot.refreshState,
                    actions: actions
                )
            }
        }
        .foregroundStyle(Color.codexInk)
    }

    private var dashboard: some View {
        HStack(spacing: 0) {
            CompanionSidebar(
                snapshot: store.snapshot,
                activity: activityStore.snapshot,
                settings: settings,
                frame: frameStore.currentFrame,
                todayMinutes: companionStatsStore.todayMinutes
            )
            .frame(width: 188)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ActivityHeading(snapshot: activityStore.snapshot)

                    TaskStackView(
                        snapshot: activityStore.snapshot,
                        selectedTaskID: $selectedTaskID
                    )
                    .padding(.top, 19)

                    quotaSection
                }
                .padding(.top, 25)
                .padding(.horizontal, 22)
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
                .padding(.horizontal, 22)
                .padding(.bottom, 25)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.codexCard.opacity(0.96))
        }
        .frame(minHeight: 473, maxHeight: .infinity)
        .background(Color.codexCard)
        .onChange(of: activityStore.snapshot.activeTasks.map(\.id)) { _, ids in
            if let selectedTaskID, !ids.contains(selectedTaskID) {
                self.selectedTaskID = ids.first
            }
        }
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
}

private struct ResetCouponSummaryView: View {
    let coupons: [ResetCoupon]
    @State private var selectedIndex = 0

    private struct Ticket: Identifiable {
        let id: String
        let name: String
        let source: String
        let expiresAt: String
    }

    private var tickets: [Ticket] {
        coupons.flatMap { coupon in
            (0..<coupon.count).map { copyIndex in
                Ticket(
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
                HStack(spacing: 9) {
                    Image(systemName: "ticket")
                        .foregroundStyle(Color.codexMuted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("重置券 0 张")
                            .font(.system(size: 11, weight: .semibold))
                        Text("当前没有可用重置券")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.codexMuted)
                    }
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.codexCard.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.codexLine, lineWidth: 0.7))
            } else {
                Button(action: showNextTicket) {
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(visibleDepths.reversed()), id: \.self) { depth in
                            let ticketIndex = (selectedIndex + depth) % tickets.count
                            ResetCouponTicketCard(
                                name: tickets[ticketIndex].name,
                                source: tickets[ticketIndex].source,
                                expiresAt: formattedExpiration(tickets[ticketIndex].expiresAt),
                                position: ticketIndex + 1,
                                total: tickets.count,
                                isFront: depth == 0
                            )
                            .scaleEffect(1 - CGFloat(depth) * 0.012, anchor: .top)
                            .offset(y: CGFloat(depth) * 3)
                            .zIndex(Double(visibleDepths.count - depth))
                        }
                    }
                    .frame(height: 84, alignment: .top)
                    .clipped()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("重置券 \(tickets.count) 张，当前第 \(selectedIndex + 1) 张，点击查看下一张")
            }
        }
        .onChange(of: tickets.map(\.id)) { _, ids in
            if ids.isEmpty || selectedIndex >= ids.count {
                selectedIndex = 0
            }
        }
    }

    private var visibleDepths: Range<Int> {
        0..<min(3, tickets.count)
    }

    private func showNextTicket() {
        guard !tickets.isEmpty else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            selectedIndex = (selectedIndex + 1) % tickets.count
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

private struct ResetCouponTicketCard: View {
    let name: String
    let source: String
    let expiresAt: String
    let position: Int
    let total: Int
    let isFront: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var ticketSurface: Color {
        if colorScheme == .dark {
            return isFront
                ? Color(red: 0.145, green: 0.151, blue: 0.154)
                : Color(red: 0.118, green: 0.125, blue: 0.127)
        }
        return isFront
            ? Color(red: 0.997, green: 0.994, blue: 0.976)
            : Color(red: 0.942, green: 0.952, blue: 0.945)
    }

    private var ticketEdge: Color {
        colorScheme == .dark
            ? Color(red: 0.255, green: 0.270, blue: 0.266)
            : Color(red: 0.835, green: 0.855, blue: 0.845)
    }

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(
                        colorScheme == .dark
                            ? Color(red: 0.075, green: 0.210, blue: 0.125)
                            : Color(red: 0.884, green: 0.968, blue: 0.900)
                    )
                Circle()
                    .stroke(Color.codexGreen.opacity(0.34), lineWidth: 0.8)
                    .padding(2)
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.codexGreen)
            }
            .frame(width: 34, height: 34)

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
                            colorScheme == .dark
                                ? Color(red: 0.105, green: 0.235, blue: 0.145)
                                : Color(red: 0.895, green: 0.970, blue: 0.915),
                            in: Capsule()
                        )
                }
                Label("\(expiresAt) 到期", systemImage: "calendar.badge.clock")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.codexMuted)
            }

            Spacer(minLength: 8)

            VStack(spacing: 3) {
                ForEach(0..<10, id: \.self) { _ in
                    Circle()
                        .fill(ticketEdge.opacity(0.72))
                        .frame(width: 1.4, height: 1.4)
                }
            }
            .frame(width: 1.5, height: 45)

            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text(String(format: "%02d", position))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(Color.codexGreen)
                Text(isFront && total > 1 ? "点击切换" : "可用券")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.codexMuted)
                if !source.isEmpty {
                    Text(source)
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(Color.codexMuted.opacity(0.78))
                        .lineLimit(1)
                    }
            }
            .frame(width: 52)
        }
        .opacity(isFront ? 1 : 0)
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity, minHeight: 78, maxHeight: 78)
        .background(
            LinearGradient(
                colors: colorScheme == .dark
                    ? [ticketSurface, Color(red: 0.125, green: 0.132, blue: 0.134)]
                    : [ticketSurface, Color(red: 0.973, green: 0.980, blue: 0.969)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isFront ? ticketEdge : ticketEdge.opacity(0.72), lineWidth: 0.8)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.codexGreen)
                .frame(width: 3, height: 48)
                .padding(.leading, 4)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(colorScheme == .dark ? 0.055 : 0.72))
                .frame(height: 0.7)
                .padding(.horizontal, 13)
        }
        .overlay(alignment: .leading) {
            Circle().fill(Color.codexCard).frame(width: 8, height: 8).offset(x: -4)
        }
        .overlay(alignment: .trailing) {
            Circle().fill(Color.codexCard).frame(width: 8, height: 8).offset(x: 4)
        }
        .shadow(
            color: isFront ? Color.black.opacity(colorScheme == .dark ? 0.10 : 0.045) : .clear,
            radius: isFront ? 2 : 0,
            y: isFront ? 1 : 0
        )
    }
}

private struct CompanionSidebar: View {
    let snapshot: CodexUsageSnapshot
    let activity: CodexActivitySnapshot
    @Bindable var settings: AppSettingsStore
    let frame: NSImage?
    let todayMinutes: Int

    private var accountName: String {
        if let name = snapshot.accountName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return snapshot.accountEmail.split(separator: "@").first.map(String.init) ?? "Codex"
    }

    private var planBadgeText: String {
        snapshot.planName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var todayDurationText: String {
        guard todayMinutes >= 60 else { return "\(todayMinutes) 分钟" }
        let hours = todayMinutes / 60
        let minutes = todayMinutes % 60
        return minutes == 0
            ? "\(hours) 小时"
            : "\(hours) 小时 \(minutes) 分钟"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.codexSidebarTop, Color.codexSidebarBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                accountSummary
                    .padding(.top, 45)
                    .padding(.horizontal, 16)

                Spacer(minLength: 8)

                petView
                    .frame(width: 145, height: 218)

                Spacer(minLength: 4)

                HStack(spacing: 5) {
                    Circle()
                        .fill(activity.state.statusColor)
                        .frame(width: 8, height: 8)
                    Text("\(settings.selectedPet?.displayName ?? "Pet") · \(activity.state.companionText)")
                        .lineLimit(1)
                }
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Color.codexCard.opacity(0.92), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.72), lineWidth: 0.7))

                Text("今天一起工作 \(todayDurationText)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.codexMuted)
                    .padding(.top, 9)
                    .padding(.bottom, 19)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.codexLine.opacity(0.72)).frame(width: 1)
        }
    }

    private var accountSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(accountName)
                        .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                if !planBadgeText.isEmpty {
                    Text(planBadgeText)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.codexGreen)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.codexGreen.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            Text(snapshot.accountEmail)
                .lineLimit(1)
            Text("\(snapshot.workspaceName) · \(snapshot.planName)")
                .lineLimit(1)
        }
            .font(.system(size: 10))
            .foregroundStyle(Color.codexMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("当前账号 \(accountName)")
    }

    @ViewBuilder
    private var petView: some View {
        if let frame {
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
    let snapshot: CodexActivitySnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.dashboardTitle)
                    .font(.system(size: 20, weight: .semibold))
                    .lineLimit(1)
                Text(snapshot.dashboardSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Label("刚刚更新", systemImage: "arrow.clockwise")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 10))
                .foregroundStyle(Color.codexMuted)
        }
    }
}

private struct TaskStackView: View {
    let snapshot: CodexActivitySnapshot
    @Binding var selectedTaskID: String?

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
        Button(action: cycleTask) {
            ZStack(alignment: .topLeading) {
                if tasks.count > 1 {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.codexMist)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.codexLine, lineWidth: 0.7)
                        )
                        .frame(maxWidth: .infinity, minHeight: 134, maxHeight: 134)
                        .offset(x: 8, y: 9)
                }
                taskCard
            }
            .padding(.trailing, tasks.count > 1 ? 8 : 0)
            .frame(height: tasks.count > 1 ? 143 : 134, alignment: .top)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }

    private var taskCard: some View {
        VStack(alignment: .leading, spacing: 7) {
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
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 4)

            HStack {
                Text(displayState.footnote)
                Spacer()
                if tasks.count > 1 {
                    Text(selectedIndex + 1 == tasks.count ? "点击回到任务 1" : "点击查看任务 \(selectedIndex + 2)")
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(Color.codexMuted)
            .padding(.top, 7)
            .overlay(alignment: .top) { Rectangle().fill(Color.codexLine).frame(height: 0.7) }
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 134, maxHeight: 134, alignment: .topLeading)
        .background(Color.codexCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.codexLine, lineWidth: 0.7))
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
        HStack(spacing: 9) {
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

    private var cardWidth: CGFloat { 169 }

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
    let onOpenSettings: () -> Void

    private var hasRefreshError: Bool {
        !["成功", "预览数据", "刷新中", "授权中"].contains(snapshot.refreshState)
    }

    private var syncText: String {
        if isRefreshing {
            return "正在刷新…"
        }
        let lastSuccess = UsageDateFormat.relative(snapshot.fetchedAt)
        return hasRefreshError
            ? "\(snapshot.refreshState) · 上次成功：\(lastSuccess)"
            : "上次同步：\(lastSuccess)"
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(syncText)
                .font(.system(size: 11))
                .foregroundStyle(hasRefreshError ? Color.codexRed : Color.codexMuted)
                .lineLimit(1)
                .help(hasRefreshError ? snapshot.refreshState : syncText)
            Spacer(minLength: 4)
            Button(action: actions.openUsagePage) { Image(systemName: "arrow.up.right.square") }
                .buttonStyle(DashboardIconButtonStyle())
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .help("跳转到官方 Usage 页面")
            Button(action: onOpenSettings) { Image(systemName: "gearshape") }
                .buttonStyle(DashboardIconButtonStyle())
                .help("设置")
            if showsDetachedButton {
                Button(action: actions.openDetachedWindow) { Image(systemName: "rectangle.on.rectangle.angled") }
                    .buttonStyle(DashboardIconButtonStyle())
                    .help("打开分离窗口")
            }
            Button(action: actions.refresh) {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Color.codexOnPrimary)
                        .frame(width: 48)
                } else {
                    Text("立即刷新")
                }
            }
            .buttonStyle(DashboardRefreshButtonStyle())
            .disabled(isRefreshing)
        }
        .padding(.top, 14)
        .frame(height: 46, alignment: .bottom)
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .top) { Rectangle().fill(Color.codexLine).frame(height: 0.7) }
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
                Text("登录信息仅保存在本机 Keychain")
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

private struct DashboardIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.codexMuted)
            .frame(width: 32, height: 32)
            .background(Color.codexMist.opacity(configuration.isPressed ? 1 : 0.65), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DashboardRefreshButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.codexOnPrimary)
            .frame(minWidth: 65, minHeight: 31)
            .background(Color.codexPrimary.opacity(configuration.isPressed ? 0.86 : 1), in: RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? 1 : 0.45)
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
