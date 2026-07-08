import SwiftUI

struct UsagePopoverView: View {
    @Bindable var store: UsageSnapshotStore
    let actions: UsageActions

    var body: some View {
        UsagePanel(
            snapshot: store.snapshot,
            isLoggedIn: store.isLoggedIn,
            actions: actions,
            layout: .compact,
            showsDetachedButton: true
        )
        .frame(width: 414)
        .frame(height: 720)
        .background(
            LiquidGlassBackdrop(
                health: QuotaHealthLevel.from(shortWindow: store.snapshot.shortWindow, isLoggedIn: store.isLoggedIn),
                topChromeHeight: 96
            )
        )
    }
}

struct DetachedUsageWindowView: View {
    @Bindable var store: UsageSnapshotStore
    let actions: UsageActions

    var body: some View {
        UsagePanel(
            snapshot: store.snapshot,
            isLoggedIn: store.isLoggedIn,
            actions: actions,
            layout: .window,
            showsDetachedButton: false
        )
        .frame(
            minWidth: DetachedWindowMetrics.minWidth,
            maxWidth: DetachedWindowMetrics.maxWidth,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LiquidGlassBackdrop(
                health: QuotaHealthLevel.from(shortWindow: store.snapshot.shortWindow, isLoggedIn: store.isLoggedIn),
                topChromeHeight: 0
            )
        )
        .ignoresSafeArea(.container, edges: .top)
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

    @State private var showLogoutConfirmation = false

    private var totalCoupons: Int {
        snapshot.resetCoupons.reduce(0) { $0 + $1.count }
    }

    private var isAuthenticating: Bool {
        snapshot.refreshState == "授权中"
    }

    private var shortHealth: QuotaHealthLevel {
        QuotaHealthLevel.from(shortWindow: snapshot.shortWindow, isLoggedIn: isLoggedIn)
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
        guard !account.isEmpty, account != "OpenAI 账号" else { return "Codex Light" }
        return account.split(separator: "@", maxSplits: 1).first.map(String.init) ?? account
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
                    Text(snapshot.sourceURL == "preview" ? "PREVIEW" : "API")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(shortHealth.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(shortHealth.color.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .padding(.leading, accountTitleLeadingPadding)
                .offset(y: accountTitleVerticalOffset)
                Text("\(snapshot.accountEmail) · \(snapshot.workspaceName) · \(snapshot.planName)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                IconButton(systemName: "arrow.clockwise", title: "刷新", action: actions.refresh)
                IconButton(
                    systemName: "person.crop.circle.badge.checkmark",
                    title: "退出登录",
                    action: { showLogoutConfirmation = true }
                )
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
                Text("Codex Light")
                    .font(.system(size: 15, weight: .semibold))
                Text("连接 OpenAI 账号以查看额度")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.codexMuted)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
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
        ZStack {
            Rectangle()
                .fill(Color.codexChrome)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.34),
                    Color.codexChrome,
                    Color.codexChrome
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                colors: [Color.white.opacity(0.26), Color.white.opacity(0)],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.34)
            )
        }
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
            .liquidGlassSurface(cornerRadius: 10, tint: .white.opacity(0.08), shadowOpacity: 0.04)

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
                Text(snapshot.shortWindow.percentText)
                    .font(.system(size: 40, weight: .bold, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(shortHealth.color)
                Text("5 小时额度\n\(UsageDateFormat.timeOnly(snapshot.shortWindow.resetsAt)) 重置")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.codexMuted)
                    .lineSpacing(2)
            }
            .frame(width: 118, alignment: .leading)

            VStack(spacing: 8) {
                QuotaRow(window: snapshot.shortWindow, tint: shortHealth.color)
                QuotaRow(window: snapshot.weekly, tint: .codexBlue)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .liquidGlassSurface(cornerRadius: 12, tint: .white.opacity(0.06), shadowOpacity: 0.06)
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
            DetailLine(title: "周额度重置", value: snapshot.weekly.resetsAt)
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
        ZStack {
            Rectangle()
                .fill(Color.codexChrome)
            LinearGradient(
                colors: [Color.white.opacity(0.24), Color.white.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
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

            LiquidQuotaBar(value: window.percent, tint: tint)
                .frame(height: 6)

            Text(window.amountText)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }
        .frame(height: 24)
    }
}

struct CouponRow: View {
    let coupon: ResetCoupon

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
                .background(Color.codexPink.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .liquidGlassSurface(cornerRadius: 10, tint: .white.opacity(0.05), shadowOpacity: 0.035)
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

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.codexInk)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .liquidGlassSurface(
                cornerRadius: 9,
                tint: configuration.isPressed ? Color.black.opacity(0.04) : Color.white.opacity(0.08),
                shadowOpacity: 0.035
            )
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(height: 36)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(configuration.isPressed ? Color.codexPrimary.opacity(0.86) : Color.codexPrimary)
                        .opacity(isEnabled ? 1 : 0.45)
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.codexInk)
            .frame(height: 36)
            .liquidGlassSurface(
                cornerRadius: 9,
                tint: configuration.isPressed ? Color.black.opacity(0.04) : Color.white.opacity(0.08),
                shadowOpacity: 0.035
            )
    }
}

struct LiquidGlassBackdrop: View {
    let health: QuotaHealthLevel
    var topChromeHeight: CGFloat = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.codexSurface, Color.codexBackground],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [Color.white.opacity(0.32), Color.white.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )

            if topChromeHeight > 0 {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            Color.codexPopoverBeak,
                            Color.codexSurface,
                            Color.codexSurface.opacity(0.0)
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

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.codexCard)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.32),
                                        tint,
                                        Color.white.opacity(0.02)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.codexLine, lineWidth: 0.7)
            }
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.70), Color.white.opacity(0.0)],
                            startPoint: .topLeading,
                            endPoint: .center
                        ),
                        lineWidth: 0.8
                    )
                    .padding(1)
                    .allowsHitTesting(false)
            }
            .shadow(color: Color.codexInk.opacity(shadowOpacity), radius: 10, x: 0, y: 3)
    }
}

extension View {
    func liquidGlassSurface(cornerRadius: CGFloat, tint: Color = .white.opacity(0.18), shadowOpacity: Double = 0.10) -> some View {
        modifier(LiquidGlassSurfaceModifier(cornerRadius: cornerRadius, tint: tint, shadowOpacity: shadowOpacity))
    }
}

extension Color {
    static let codexBackground = Color(red: 0.957, green: 0.957, blue: 0.957)
    static let codexSurface = Color(red: 0.957, green: 0.957, blue: 0.957)
    static let codexChrome = Color(red: 0.982, green: 0.982, blue: 0.980)
    static let codexCard = Color(red: 1.000, green: 1.000, blue: 0.998)
    static let codexMist = Color(red: 0.948, green: 0.954, blue: 0.961)
    static let codexPopoverBeak = Color(red: 0.930, green: 0.930, blue: 0.930)
    static let codexInk = Color(red: 0.142, green: 0.161, blue: 0.184)
    static let codexMuted = Color(red: 0.357, green: 0.397, blue: 0.447)
    static let codexLine = Color(red: 0.819, green: 0.851, blue: 0.890)
    static let codexTrack = Color(red: 0.918, green: 0.925, blue: 0.933)
    static let codexPrimary = Color(red: 0.096, green: 0.105, blue: 0.118)
    static let codexGreen = Color(red: 0.157, green: 0.753, blue: 0.306)
    static let codexBlue = Color(red: 0.000, green: 0.478, blue: 1.000)
    static let codexRed = Color(red: 1.000, green: 0.373, blue: 0.373)
    static let codexPink = Color(red: 1.000, green: 0.373, blue: 0.373)
    static let codexAmber = Color(red: 1.000, green: 0.745, blue: 0.000)
}
