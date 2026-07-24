import AppKit
import SwiftUI

struct DetachedUsageWindowView: View {
    @Bindable var store: UsageSnapshotStore
    @Bindable var settings: AppSettingsStore
    @Bindable var activityStore: CodexActivityStore
    @Bindable var frameStore: PetFrameStore
    @Bindable var companionStatsStore: CompanionStatsStore
    @Bindable var updater: AppUpdateController
    let actions: UsageActions
    let onContentLayoutChanged: (DetachedWindowContentMode) -> Void
    @State private var showsSettings = false

    private var dashboardContentMode: DetachedWindowContentMode {
        .dashboard(isLoggedIn: store.isLoggedIn)
    }

    var body: some View {
        Group {
            if showsSettings {
                SettingsView(
                    store: store,
                    settings: settings,
                    updater: updater,
                    layout: .window,
                    onLogout: {
                        actions.disconnect()
                        showsSettings = false
                        onContentLayoutChanged(.dashboard(isLoggedIn: false))
                    }
                ) {
                    showsSettings = false
                    onContentLayoutChanged(dashboardContentMode)
                }
            } else {
                CompanionDashboardView(
                    store: store,
                    settings: settings,
                    activityStore: activityStore,
                    frameStore: frameStore,
                    companionStatsStore: companionStatsStore,
                    actions: actions,
                    layout: .window,
                    showsDetachedButton: false,
                    onOpenSettings: {
                        showsSettings = true
                        onContentLayoutChanged(.settings)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .preferredColorScheme(settings.resolvedColorScheme)
        .background(Color.codexBackground)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            onContentLayoutChanged(dashboardContentMode)
        }
        .onChange(of: store.snapshot.resetCoupons) { _, _ in
            guard !showsSettings else { return }
            onContentLayoutChanged(dashboardContentMode)
        }
        .onChange(of: store.isLoggedIn) { _, _ in
            guard !showsSettings else { return }
            onContentLayoutChanged(dashboardContentMode)
        }
    }
}

enum UsagePanelLayout {
    case compact
    case window
}

struct UsagePanel: View {
    let snapshot: CodexUsageSnapshot
    let isLoggedIn: Bool
    let actions: UsageActions
    let layout: UsagePanelLayout
    let showsDetachedButton: Bool
    let onOpenSettings: () -> Void

    @State private var showLogoutConfirmation = false

    private var totalCoupons: Int {
        snapshot.resetCoupons.reduce(0) { $0 + $1.count }
    }

    private var isAuthenticating: Bool {
        snapshot.refreshState == "授权中"
    }

    private var primaryHealth: QuotaHealthLevel {
        QuotaHealthLevel.from(window: snapshot.primaryWindow, isLoggedIn: isLoggedIn)
    }

    private var headerInsets: EdgeInsets {
        switch layout {
        case .compact:
            EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        case .window:
            EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        }
    }

    private var accountTitleLeadingPadding: CGFloat {
        switch layout {
        case .compact:
            0
        case .window:
            62
        }
    }

    private var accountTitleVerticalOffset: CGFloat {
        switch layout {
        case .compact:
            0
        case .window:
            -10
        }
    }

    private var accountDisplayName: String {
        if let name = snapshot.accountName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }

        let account = snapshot.accountEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty, account != "OpenAI 账号" else { return "Codexling" }
        return account.split(separator: "@", maxSplits: 1).first.map(String.init) ?? account
    }

    private var planBadgeText: String {
        snapshot.planName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var body: some View {
        Group {
            if isLoggedIn {
                loggedInContent
            } else {
                loginContent
            }
        }
        .foregroundStyle(Color.codexInk)
        .alert("确认退出登录？", isPresented: $showLogoutConfirmation) {
            Button("取消", role: .cancel) {}
            Button("退出登录", role: .destructive) {
                actions.disconnect()
            }
        } message: {
            Text("退出后需要重新授权才能查看用量。")
        }
    }

    private var loggedInContent: some View {
        Group {
            switch layout {
            case .compact:
                VStack(spacing: 0) {
                    loggedInHeader
                    loggedInBody
                    Spacer(minLength: 0)
                    actionsBar
                }
            case .window:
                VStack(spacing: 0) {
                    loggedInHeader
                    loggedInBody
                    Spacer(minLength: 0)
                    actionsBar
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private var loggedInBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            summary
            coupons
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loginContent: some View {
        Group {
            switch layout {
            case .compact:
                VStack(spacing: 0) {
                    loginHeader
                    loginBody
                    Spacer(minLength: 0)
                    loginActionsBar
                }
            case .window:
                VStack(spacing: 0) {
                    loginHeader
                    loginBody
                    Spacer(minLength: 0)
                    loginActionsBar
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private var loggedInHeader: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(accountDisplayName)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if snapshot.sourceURL == "preview" || !planBadgeText.isEmpty {
                        Text(snapshot.sourceURL == "preview" ? "preview" : planBadgeText)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(primaryHealth.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(primaryHealth.color.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }
                .padding(.leading, accountTitleLeadingPadding)
                .offset(y: accountTitleVerticalOffset)
                Text("\(snapshot.accountEmail) · \(snapshot.workspaceName)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                IconButton(
                    systemName: "person.crop.circle.badge.checkmark",
                    title: "退出登录",
                    action: { showLogoutConfirmation = true }
                )
                IconButton(systemName: "gearshape", title: "设置", action: onOpenSettings)
                if showsDetachedButton {
                    IconButton(systemName: "rectangle.on.rectangle.angled", title: "打开窗口", action: actions.openDetachedWindow)
                }
            }
        }
        .padding(headerInsets)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(headerBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.codexLine.opacity(0.74))
                .frame(height: 1)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var loginHeader: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Codexling")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.leading, accountTitleLeadingPadding)
                    .offset(y: accountTitleVerticalOffset)
                Text("连接 OpenAI 账号以查看额度")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.codexMuted)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                IconButton(systemName: "gearshape", title: "设置", action: onOpenSettings)
                if showsDetachedButton {
                    IconButton(systemName: "rectangle.on.rectangle.angled", title: "打开窗口", action: actions.openDetachedWindow)
                }
            }
        }
        .padding(headerInsets)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(headerBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.codexLine.opacity(0.74))
                .frame(height: 1)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var headerBackground: some View {
        CodexChromeBackground(intensity: .header)
    }

    private var loginBody: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text("登录 Codex 账号")
                    .font(.system(size: 20, weight: .semibold))

                Text("通过 ChatGPT / Codex 官方页面完成授权\n不保存账号密码或 MFA 信息")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.codexMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            VStack(alignment: .leading, spacing: 10) {
                LoginFeatureRow(icon: "checkmark.shield.fill", text: "官方 OAuth 授权，安全可控")
                LoginFeatureRow(icon: "gauge.with.dots.needle.67percent", text: "实时查看 5 小时与周额度")
                LoginFeatureRow(icon: "ticket.fill", text: "追踪重置券与过期时间")
            }
        .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .liquidGlassSurface(cornerRadius: 10, tint: Color.codexGlassTint, shadowOpacity: 0.04)

            if isAuthenticating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在打开授权页面，请在浏览器中完成登录…")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.codexMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if !snapshot.refreshState.isEmpty,
                      snapshot.refreshState != "预览数据",
                      snapshot.refreshState != "成功" {
                Text(snapshot.refreshState)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.codexAmber)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
    }

    private var loginActionsBar: some View {
        HStack(spacing: 8) {
            Button(action: actions.loginAndFetch) {
                Text(isAuthenticating ? "等待授权…" : "使用 OpenAI 账号登录")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isAuthenticating)

            IconButton(systemName: "power", title: "退出软件", action: actions.quit)
                .frame(width: 36)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(actionBarBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.codexLine)
                .frame(height: 1)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var summary: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.primaryWindow.percentText)
                    .font(.system(size: 40, weight: .bold, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(primaryHealth.color)
                Text("\(snapshot.primaryWindow.label)\n\(UsageDateFormat.dateAndTime(snapshot.primaryWindow.resetsAt)) 重置")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.codexMuted)
                    .lineSpacing(2)
            }
            .frame(width: 118, alignment: .leading)

            VStack(spacing: 8) {
                if snapshot.hasShortWindow, let shortWindow = snapshot.shortWindow {
                    QuotaRow(window: shortWindow, tint: primaryHealth.color)
                }
                if snapshot.hasWeeklyWindow {
                    QuotaRow(
                        window: snapshot.weekly,
                        tint: snapshot.hasShortWindow ? .codexBlue : primaryHealth.color
                    )
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .liquidGlassSurface(cornerRadius: 12, tint: Color.codexGlassTint, shadowOpacity: 0.06)
    }

    private var coupons: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("重置券 \(totalCoupons) 张")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("按过期时间从近到远")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.codexMuted)
            }

            ForEach(snapshot.resetCoupons) { coupon in
                CouponRow(coupon: coupon)
            }
        }
    }

    private var details: some View {
        VStack(spacing: 9) {
            if let detailWindow = snapshot.detailWindow {
                DetailLine(title: "\(detailWindow.label)重置", value: detailWindow.resetsAt)
            }
            RefreshStatusLine(date: snapshot.fetchedAt, state: snapshot.refreshState)
        }
        .font(.system(size: 13))
    }

    private var actionsBar: some View {
        VStack(spacing: 14) {
            details

            HStack(spacing: 8) {
                Button(action: actions.refresh) {
                    Text("刷新")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())

                IconButton(systemName: "network", title: "官方 Usage", action: actions.openUsagePage)
                    .frame(width: 36)

                IconButton(systemName: "power", title: "退出软件", action: actions.quit)
                    .frame(width: 36)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(actionBarBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.codexLine)
                .frame(height: 1)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var actionBarBackground: some View {
        CodexChromeBackground(intensity: .actionBar)
    }
}

struct CodexChromeBackground: View {
    enum Intensity {
        case header
        case actionBar
    }

    let intensity: Intensity
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        let topSheen: Double = {
            switch intensity {
            case .header:
                isDark ? 0.10 : 0.34
            case .actionBar:
                isDark ? 0.08 : 0.24
            }
        }()
        let edgeSheen: Double = isDark ? 0.08 : 0.26

        Group {
            if #available(macOS 26.0, *) {
                LinearGradient(
                    colors: [
                        Color.white.opacity(isDark ? 0.035 : 0.10),
                        Color.white.opacity(isDark ? 0.008 : 0.025)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else if isDark {
                Color.codexChrome
            } else {
                ZStack {
                    Rectangle()
                        .fill(Color.codexChrome)

                    LinearGradient(
                        colors: [
                            Color.white.opacity(topSheen),
                            Color.codexChrome,
                            Color.codexChrome
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    if intensity == .header {
                        LinearGradient(
                            colors: [Color.white.opacity(edgeSheen), Color.white.opacity(0)],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.34)
                        )
                    }
                }
            }
        }
    }
}

struct LoginFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.codexMuted)
                .frame(width: 18)

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Color.codexInk)
        }
    }
}

struct QuotaRow: View {
    let window: UsageWindow
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(window.label)
                .font(.system(size: 12))
                .foregroundStyle(Color.codexMuted)
                .frame(width: 58, alignment: .leading)

            if window.total > 0 {
                LiquidQuotaBar(value: window.percent, tint: tint)
                    .frame(height: 6)
                    .layoutPriority(0)

                Text(window.amountText)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
                    .layoutPriority(1)
            }
        }
        .frame(height: 24)
    }
}

struct CouponRow: View {
    let coupon: ResetCoupon
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(coupon.name)
                    .font(.system(size: 13, weight: .semibold))
                Text("\(coupon.expiresAt) 过期 · \(coupon.source)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.codexMuted)
            }

            Spacer(minLength: 8)

            Text("\(coupon.count) 张")
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.codexPink)
                .frame(minWidth: 38, minHeight: 30)
                .padding(.horizontal, 8)
                .background(Color.codexPink.opacity(colorScheme == .dark ? 0.16 : 0.07))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .liquidGlassSurface(cornerRadius: 10, tint: Color.codexGlassTint, shadowOpacity: 0.035)
    }
}

struct LiquidQuotaBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width * min(max(value, 0), 1), 8)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.codexTrack)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Color.codexLine.opacity(0.34), lineWidth: 0.7)
                    }

                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: width)
            }
        }
    }
}

struct DetailLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(Color.codexMuted)
            Spacer(minLength: 14)
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct RefreshStatusLine: View {
    let date: Date
    let state: String

    private var isLoading: Bool {
        state == "刷新中" || state == "授权中"
    }

    private var isSuccess: Bool {
        state == "成功" || state == "预览数据"
    }

    private var iconColor: Color {
        if isSuccess { return .codexGreen }
        if isLoading { return .codexMuted }
        return .codexRed
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("最近更新")
                .foregroundStyle(Color.codexMuted)
            Spacer(minLength: 14)
            HStack(spacing: 6) {
                statusIcon
                Text(UsageDateFormat.display(date))
                    .fontWeight(.medium)
                    .monospacedDigit()
            }
            .foregroundStyle(Color.codexInk)
            .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isLoading {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 13, height: 13)
        } else {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 13, height: 13)
        }
    }
}

struct IconButton: View {
    let systemName: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(IconButtonStyle())
        .help(title)
        .accessibilityLabel(title)
    }
}

enum CodexMaterialWaveInk: Equatable {
    case adaptiveMint
    case softLight

    func color(for colorScheme: ColorScheme) -> Color {
        switch self {
        case .adaptiveMint:
            colorScheme == .dark
                ? Color(red: 0.35, green: 0.92, blue: 0.62).opacity(0.28)
                : Color(red: 0.02, green: 0.55, blue: 0.34).opacity(0.18)
        case .softLight:
            Color.white.opacity(colorScheme == .dark ? 0.28 : 0.34)
        }
    }
}

struct CodexMaterialWaveToken: Identifiable, Equatable {
    let id = UUID()
    let location: CGPoint
}

/// Soft Material blot: expands from the tap point, then dissolves.
struct CodexMaterialWave: View {
    @Environment(\.colorScheme) private var colorScheme

    let origin: CGPoint
    let diameter: CGFloat
    var ink: CodexMaterialWaveInk = .adaptiveMint
    let onFinished: () -> Void
    @State private var scale: CGFloat = 0.04
    @State private var opacity: Double = 1

    var body: some View {
        Circle()
            .fill(ink.color(for: colorScheme))
            .frame(width: diameter, height: diameter)
            .scaleEffect(scale)
            .opacity(opacity)
            .position(origin)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 0.68)) {
                    scale = 1.0
                }
                withAnimation(.easeIn(duration: 0.50).delay(0.18)) {
                    opacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.74) {
                    onFinished()
                }
            }
    }
}

/// Text / light controls: Material wave only (no scale / opacity press).
struct CodexPressableStyle: PrimitiveButtonStyle {
    var cornerRadius: CGFloat = 8
    var ink: CodexMaterialWaveInk = .adaptiveMint

    func makeBody(configuration: Configuration) -> some View {
        CodexMaterialWaveButtonBody(
            action: { configuration.trigger() },
            cornerRadius: cornerRadius,
            ink: ink
        ) {
            configuration.label
        }
    }
}

/// Full cards / large hit targets: Material wave clipped to the card.
struct CodexPressableCardStyle: PrimitiveButtonStyle {
    var cornerRadius: CGFloat = 14
    var ink: CodexMaterialWaveInk = .adaptiveMint

    func makeBody(configuration: Configuration) -> some View {
        CodexMaterialWaveButtonBody(
            action: { configuration.trigger() },
            cornerRadius: cornerRadius,
            ink: ink
        ) {
            configuration.label
        }
    }
}

struct IconButtonStyle: PrimitiveButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let isDark = colorScheme == .dark
        let tint = isDark ? Color.white.opacity(0.05) : Color.white.opacity(0.08)

        CodexMaterialWaveButtonBody(
            action: { configuration.trigger() },
            cornerRadius: 9,
            ink: .adaptiveMint
        ) {
            configuration.label
                .foregroundStyle(Color.codexInk)
                .liquidGlassSurface(
                    cornerRadius: 9,
                    tint: tint,
                    shadowOpacity: isDark ? 0 : 0.035,
                    interactive: true
                )
        }
    }
}

struct PrimaryButtonStyle: PrimitiveButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        CodexMaterialWaveButtonBody(
            action: { configuration.trigger() },
            cornerRadius: 9,
            ink: .softLight
        ) {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(red: 0.096, green: 0.105, blue: 0.118))
                )
                .opacity(isEnabled ? 1 : 0.58)
        }
    }
}

struct SecondaryButtonStyle: PrimitiveButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let isDark = colorScheme == .dark
        let tint = isDark ? Color.white.opacity(0.05) : Color.white.opacity(0.08)

        CodexMaterialWaveButtonBody(
            action: { configuration.trigger() },
            cornerRadius: 9,
            ink: .adaptiveMint
        ) {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.codexInk)
                .frame(height: 36)
                .liquidGlassSurface(
                    cornerRadius: 9,
                    tint: tint,
                    shadowOpacity: isDark ? 0 : 0.035,
                    interactive: true
                )
        }
    }
}

struct CodexMaterialWaveButtonBody<Label: View>: View {
    let action: () -> Void
    var cornerRadius: CGFloat = 9
    var usesCapsule: Bool = false
    var ink: CodexMaterialWaveInk = .adaptiveMint
    @ViewBuilder var label: () -> Label

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ripples: [CodexMaterialWaveToken] = []
    @State private var boardSize: CGSize = .zero
    @State private var didSpawnForTouch = false

    var body: some View {
        Group {
            if usesCapsule {
                chrome(clippedBy: Capsule())
            } else {
                chrome(clippedBy: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
    }

    private func chrome<S: Shape>(clippedBy shape: S) -> some View {
        label()
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { boardSize = geo.size }
                        .onChange(of: geo.size) { _, size in
                            boardSize = size
                        }
                }
            }
            .overlay {
                let waveSize = resolvedBoardSize
                ZStack {
                    ForEach(ripples) { ripple in
                        CodexMaterialWave(
                            origin: ripple.location,
                            diameter: hypot(waveSize.width, waveSize.height) * 2.05,
                            ink: ink
                        ) {
                            ripples.removeAll { $0.id == ripple.id }
                        }
                    }
                }
                .allowsHitTesting(false)
            }
            .clipShape(shape)
            .contentShape(shape)
            .accessibilityAction(.default) {
                guard isEnabled else { return }
                action()
            }
            // Own the press end-to-end so macOS still fires the button action
            // while the material wave gesture can read the tap location.
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard isEnabled else { return }
                        guard !didSpawnForTouch else { return }
                        didSpawnForTouch = true
                        spawnRipple(at: value.startLocation)
                    }
                    .onEnded { value in
                        defer { didSpawnForTouch = false }
                        guard isEnabled else { return }
                        let size = resolvedBoardSize
                        let hit = CGRect(origin: .zero, size: size).insetBy(dx: -6, dy: -6)
                        if hit.contains(value.location) {
                            action()
                        }
                    }
            )
    }

    private var resolvedBoardSize: CGSize {
        boardSize == .zero ? CGSize(width: 44, height: 32) : boardSize
    }

    private func spawnRipple(at origin: CGPoint) {
        guard !reduceMotion else { return }
        let size = resolvedBoardSize
        let point = boardSize == .zero
            ? CGPoint(x: size.width / 2, y: size.height / 2)
            : origin
        ripples.append(CodexMaterialWaveToken(location: point))
    }
}

struct LiquidGlassBackdrop: View {
    let health: QuotaHealthLevel
    var topChromeHeight: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark

        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color.codexBackground.opacity(isDark ? 0.94 : 0.96)

            LinearGradient(
                colors: [
                    Color.white.opacity(isDark ? 0.10 : 0.28),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.42)
            )

            if topChromeHeight > 0 {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            Color.codexPopoverBeak.opacity(0.42),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: topChromeHeight)

                    Spacer(minLength: 0)
                }
            }
        }
    }
}

struct LiquidGlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color
    let shadowOpacity: Double
    let interactive: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        Group {
            if #available(macOS 26.0, *) {
                if interactive {
                    content
                        .glassEffect(.regular.tint(tint).interactive(), in: shape)
                } else {
                    content
                        .glassEffect(.regular.tint(tint), in: shape)
                }
            } else if isDark {
                content
                    .background {
                        shape.fill(Color.codexCard)
                    }
                    .clipShape(shape)
                    .overlay {
                        shape.stroke(Color.codexLine.opacity(0.72), lineWidth: 0.7)
                    }
            } else {
                let sheenTop = Color.white.opacity(0.32)
                let sheenBottom = Color.white.opacity(0.02)
                let edgeHighlight = Color.white.opacity(0.70)
                let shadowColor = Color.codexInk.opacity(shadowOpacity)

                content
                    .background {
                        shape
                            .fill(Color.codexCard)
                            .overlay {
                                shape
                                    .fill(
                                        LinearGradient(
                                            colors: [sheenTop, tint, sheenBottom],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                    }
                    .clipShape(shape)
                    .overlay {
                        shape.stroke(Color.codexLine, lineWidth: 0.7)
                    }
                    .overlay(alignment: .topLeading) {
                        shape
                            .stroke(
                                LinearGradient(
                                    colors: [edgeHighlight, Color.white.opacity(0.0)],
                                    startPoint: .topLeading,
                                    endPoint: .center
                                ),
                                lineWidth: 0.8
                            )
                            .padding(1)
                            .allowsHitTesting(false)
                    }
                    .shadow(color: shadowColor, radius: 10, x: 0, y: 3)
            }
        }
    }
}

extension View {
    func liquidGlassSurface(
        cornerRadius: CGFloat,
        tint: Color = .white.opacity(0.18),
        shadowOpacity: Double = 0.10,
        interactive: Bool = false
    ) -> some View {
        modifier(LiquidGlassSurfaceModifier(
            cornerRadius: cornerRadius,
            tint: tint,
            shadowOpacity: shadowOpacity,
            interactive: interactive
        ))
    }

    func rootLiquidGlass(
        cornerRadius: CGFloat,
        health: QuotaHealthLevel,
        topChromeHeight: CGFloat
    ) -> some View {
        modifier(RootLiquidGlassModifier(
            cornerRadius: cornerRadius,
            health: health,
            topChromeHeight: topChromeHeight
        ))
    }
}

private struct RootLiquidGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    let health: QuotaHealthLevel
    let topChromeHeight: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                // Keep this identical to PetHoverContentView so the large
                // surfaces retain the system's native refraction and highlights.
                .glassEffect(in: .rect(cornerRadius: cornerRadius))
        } else {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.stroke(Color.white.opacity(0.42), lineWidth: 0.8)
                }
                .shadow(color: Color.black.opacity(0.08), radius: 9, x: 0, y: 3)
        }
    }
}

extension NSColor {
    static func codexDynamic(
        light: (CGFloat, CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat, CGFloat)
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let components = isDark ? dark : light
            return NSColor(
                red: components.0,
                green: components.1,
                blue: components.2,
                alpha: components.3
            )
        }
    }
}

extension Color {
    static func codexDynamic(
        light: (CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(nsColor: .codexDynamic(
            light: (light.0, light.1, light.2, 1),
            dark: (dark.0, dark.1, dark.2, 1)
        ))
    }

    static let codexBackground = codexDynamic(
        light: (0.957, 0.957, 0.957),
        dark: (0.118, 0.118, 0.122)
    )
    static let codexSurface = codexDynamic(
        light: (0.957, 0.957, 0.957),
        dark: (0.118, 0.118, 0.122)
    )
    static let codexChrome = codexDynamic(
        light: (0.982, 0.982, 0.980),
        dark: (0.133, 0.133, 0.138)
    )
    static let codexCard = codexDynamic(
        light: (1.000, 1.000, 0.998),
        dark: (0.165, 0.165, 0.172)
    )
    static let codexMist = codexDynamic(
        light: (0.948, 0.954, 0.961),
        dark: (0.133, 0.133, 0.138)
    )
    static let codexPopoverBeak = codexDynamic(
        light: (0.930, 0.930, 0.930),
        dark: (0.118, 0.118, 0.122)
    )
    static let codexInk = codexDynamic(
        light: (0.142, 0.161, 0.184),
        dark: (0.925, 0.930, 0.940)
    )
    static let codexMuted = codexDynamic(
        light: (0.357, 0.397, 0.447),
        dark: (0.620, 0.645, 0.680)
    )
    static let codexLine = codexDynamic(
        light: (0.819, 0.851, 0.890),
        dark: (0.300, 0.310, 0.340)
    )
    static let codexTrack = codexDynamic(
        light: (0.918, 0.925, 0.933),
        dark: (0.250, 0.255, 0.270)
    )
    static let codexPrimary = codexDynamic(
        light: (0.096, 0.105, 0.118),
        dark: (0.920, 0.925, 0.935)
    )
    static let codexOnPrimary = codexDynamic(
        light: (1.000, 1.000, 1.000),
        dark: (0.096, 0.105, 0.118)
    )
    static let codexGlassTint = Color(nsColor: .codexDynamic(
        light: (1.000, 1.000, 1.000, 0.08),
        dark: (1.000, 1.000, 1.000, 0.05)
    ))
    static let codexGreen = Color(red: 0.157, green: 0.753, blue: 0.306)
    static let codexBlue = Color(red: 0.000, green: 0.478, blue: 1.000)
    static let codexRed = Color(red: 1.000, green: 0.373, blue: 0.373)
    static let codexPink = Color(red: 1.000, green: 0.373, blue: 0.373)
    static let codexAmber = Color(red: 1.000, green: 0.745, blue: 0.000)
}
