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
            .frame(width: DetachedWindowMetrics.sidebarWidth)

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
    @State private var outgoingIndex: Int?
    @State private var shuffleProgress: CGFloat = 0
    @State private var stackReduced = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isShuffling: Bool { outgoingIndex != nil }

    private var selectedTicket: ResetCouponDisplayTicket {
        tickets[selectedIndex]
    }

    /// 可见堆叠层数：1 张显示 1 层，2 张显示 2 层，3 张及以上最多 3 层。
    private var visibleStackCount: Int {
        min(ResetCouponTicketMetrics.maxStackLayers, tickets.count)
    }

    /// 静止时背景层；切换离场时少 1 层，模拟顶部券被抽出。
    private var displayedBackLayerDepths: [Int] {
        guard tickets.count > 1 else { return [] }
        let backCount = stackReduced
            ? max(0, visibleStackCount - 2)
            : visibleStackCount - 1
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

    private var shuffleAnimation: Animation {
        .spring(response: 0.38, dampingFraction: 0.86)
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
                onSwitch: tickets.count > 1 && !isShuffling ? { cycleTicket() } : nil
            )
            .zIndex(Double(visibleStackCount + 1))

            if let outgoingIndex {
                ResetCouponDeckTicket(
                    ticket: tickets[outgoingIndex],
                    position: outgoingIndex + 1,
                    total: tickets.count,
                    formattedExpiration: formattedExpiration,
                    isFront: true,
                    onSwitch: nil
                )
                .modifier(ResetCouponShuffleOutgoing(progress: shuffleProgress))
                .zIndex(Double(visibleStackCount + 2))
                .allowsHitTesting(false)
            }
        }
        .animation(shuffleAnimation, value: displayedBackLayerDepths)
        .padding(.bottom, restBackLayerDepths.isEmpty ? 6 : 8)
        .frame(height: deckHeight, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("重置券 \(tickets.count) 张，当前第 \(selectedIndex + 1) 张")
        .onChange(of: tickets.map(\.id)) { _, ids in
            if ids.isEmpty || selectedIndex >= ids.count {
                selectedIndex = 0
                outgoingIndex = nil
                shuffleProgress = 0
                stackReduced = false
            }
        }
    }

    private func cycleTicket() {
        guard tickets.count > 1, outgoingIndex == nil else { return }

        if reduceMotion {
            selectedIndex = (selectedIndex + 1) % tickets.count
            return
        }

        let previousIndex = selectedIndex
        outgoingIndex = previousIndex
        selectedIndex = (previousIndex + 1) % tickets.count
        shuffleProgress = 0

        withAnimation(shuffleAnimation) {
            stackReduced = true
            shuffleProgress = 1
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(390))
            var cleanup = Transaction()
            cleanup.disablesAnimations = true
            withTransaction(cleanup) {
                outgoingIndex = nil
                shuffleProgress = 0
            }
            withAnimation(shuffleAnimation) {
                stackReduced = false
            }
        }
    }
}

private struct ResetCouponShuffleOutgoing: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(1 - 0.024 * progress, anchor: .topLeading)
            .rotationEffect(
                .degrees(Double(ResetCouponTicketMetrics.shuffleRotation * progress)),
                anchor: .topLeading
            )
            .offset(
                x: ResetCouponTicketMetrics.shuffleSlideX * progress,
                y: ResetCouponTicketMetrics.shuffleSlideY * progress
            )
            .opacity(Double(1 - progress))
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
    static let shuffleSlideX: CGFloat = 46
    static let shuffleSlideY: CGFloat = 11
    static let shuffleRotation: CGFloat = 7
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
    let onSwitch: (() -> Void)?

    var body: some View {
        ZStack {
            stubContent

            if total > 1, let onSwitch {
                Button(action: onSwitch) {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
    let name: String
    let source: String
    let expiresAt: String
    let position: Int
    let total: Int
    let stackDepth: Int
    let isFront: Bool
    let onSwitch: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme

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
                }

                Spacer(minLength: 6)
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)

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
        .modifier(ResetCouponTicketShadow(isFront: isFront, isDark: isDark))
    }

    private var resetIcon: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: isDark
                            ? [Color(red: 0.120, green: 0.280, blue: 0.165), Color(red: 0.065, green: 0.175, blue: 0.095)]
                            : [Color(red: 0.930, green: 0.990, blue: 0.940), Color(red: 0.845, green: 0.955, blue: 0.875)],
                        center: .init(x: 0.32, y: 0.28),
                        startRadius: 2,
                        endRadius: 20
                    )
                )
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isDark ? 0.18 : 0.65),
                            Color.codexGreen.opacity(0.28),
                            Color.black.opacity(isDark ? 0.22 : 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.codexGreen.opacity(0.95),
                            Color(red: 0.110, green: 0.620, blue: 0.255)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.white.opacity(isDark ? 0.08 : 0.35), radius: 0.4, x: -0.3, y: -0.3)
        }
        .frame(width: 36, height: 36)
    }

    private var stubSection: some View {
        ResetCouponStubSection(
            position: position,
            total: total,
            source: source,
            isFront: isFront,
            isDark: isDark,
            onSwitch: onSwitch
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
