import AppKit
import SwiftUI

enum DetachedWindowContentMode: Equatable {
    case dashboard(isLoggedIn: Bool, orientation: DashboardOrientation)
    case settings
}

enum DetachedWindowMetrics {
    static let quotaCardWidth: CGFloat = 169
    static let quotaCardSpacing: CGFloat = 9
    static let sidebarWidth: CGFloat = 290
    static let dashboardContentPadding: CGFloat = 22

    /// 主界面固定宽度：侧栏 + 内容区内边距 + 两张额度卡。
    static var dashboardWidth: CGFloat {
        sidebarWidth
            + dashboardContentPadding * 2
            + quotaCardWidth * 2
            + quotaCardSpacing
    }

    /// 竖向布局：单列宽度，与 ui-vertical.html 的设计稿一致。
    static let verticalDashboardWidth: CGFloat = 330
    static let verticalContentPadding: CGFloat = 14
    /// 竖向独立窗口首帧占位（测出后 `setContentSize` 收敛）。
    /// 不低于横版高度，避免方向切换期间短暂塌成只显示任务卡的窗口。
    static var verticalProvisionalHeight: CGFloat { loggedInDashboardHeight }
    static let verticalMinHeight: CGFloat = 360

    static let maxWidth: CGFloat = 800
    static let minHeight: CGFloat = 420
    static let maxHeight: CGFloat = 960
    static let loginDashboardHeight: CGFloat = 440
    /// 横版已登录：连接栏、账号上下文、任务、额度、重置券与底部工具栏完整可见。
    static let loggedInDashboardHeight: CGFloat = 550
    static let horizontalMinHeight: CGFloat = 480

    static func dashboardWidth(for orientation: DashboardOrientation) -> CGFloat {
        switch orientation {
        case .horizontal: dashboardWidth
        case .vertical: verticalDashboardWidth
        }
    }

    static func isValidVerticalMeasurement(_ size: CGSize) -> Bool {
        size.height > 1
            && abs(size.width - verticalDashboardWidth) < 1
    }
    /// 设置页先以紧凑高度出现；右侧内容的自然高度测出后再一次性收敛。
    static func settingsWindowProvisionalHeight(screen: NSScreen? = nil) -> CGFloat {
        min(560, maximumSettingsWindowHeight(for: screen))
    }
    /// 用户手动缩小时的下限；低于内容高度时 SwiftUI 才启用滚动。
    static let settingsMinWindowHeight: CGFloat = 560

    static var defaultWidth: CGFloat { dashboardWidth }
    static var defaultHeight: CGFloat { loggedInDashboardHeight }

    static func dashboardHeight(isLoggedIn: Bool) -> CGFloat {
        isLoggedIn ? loggedInDashboardHeight : loginDashboardHeight
    }

    static func maximumContentHeight(for screen: NSScreen?) -> CGFloat {
        let visibleHeight = screen?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height
            ?? maxHeight
        return min(maxHeight, max(1, visibleHeight - 32))
    }

    /// 设置页允许占满当前屏幕可视高度（不受主界面 960 上限约束）。
    static func maximumSettingsWindowHeight(for screen: NSScreen?) -> CGFloat {
        let visibleHeight = screen?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height
            ?? maxHeight
        return max(1, visibleHeight)
    }

    static func clampSettingsContentSize(_ size: NSSize, screen: NSScreen? = nil) -> NSSize {
        let dynamicMaxHeight = maximumSettingsWindowHeight(for: screen)
        return NSSize(
            width: min(max(size.width, dashboardWidth), maxWidth),
            height: min(
                max(size.height, min(settingsMinWindowHeight, dynamicMaxHeight)),
                dynamicMaxHeight
            )
        )
    }

    static func fixedDashboardContentSize(
        isLoggedIn: Bool,
        orientation: DashboardOrientation = .horizontal,
        measuredHeight: CGFloat? = nil,
        screen: NSScreen? = nil
    ) -> NSSize {
        dashboardContentSize(
            isLoggedIn: isLoggedIn,
            orientation: orientation,
            measuredHeight: measuredHeight,
            screen: screen
        )
    }

    /// 主界面 **内容区** 尺寸（`setContentSize` / SwiftUI GeometryReader 用，不是 window frame）。
    static func dashboardContentSize(
        isLoggedIn: Bool,
        orientation: DashboardOrientation = .horizontal,
        measuredHeight: CGFloat? = nil,
        screen: NSScreen? = nil
    ) -> NSSize {
        let dynamicMaxHeight = maximumContentHeight(for: screen)

        switch orientation {
        case .horizontal:
            let natural = isLoggedIn
                ? loggedInDashboardHeight
                : loginDashboardHeight
            let height = min(max(ceil(natural), horizontalMinHeight), dynamicMaxHeight)
            return NSSize(width: dashboardWidth, height: height)
        case .vertical:
            let natural = isLoggedIn
                ? (measuredHeight ?? verticalProvisionalHeight)
                : loginDashboardHeight
            let height = min(max(ceil(natural), verticalMinHeight), dynamicMaxHeight)
            return NSSize(width: verticalDashboardWidth, height: height)
        }
    }

    @MainActor
    static func dashboardFrameSize(
        for contentSize: NSSize,
        on window: NSWindow
    ) -> NSSize {
        window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
    }

    @MainActor
    static func fixedDashboardFrameSize(
        isLoggedIn: Bool,
        orientation: DashboardOrientation = .horizontal,
        measuredHeight: CGFloat? = nil,
        screen: NSScreen? = nil,
        on window: NSWindow
    ) -> NSSize {
        dashboardFrameSize(
            for: dashboardContentSize(
                isLoggedIn: isLoggedIn,
                orientation: orientation,
                measuredHeight: measuredHeight,
                screen: screen
            ),
            on: window
        )
    }

    static func preferredSettingsWindowSize(contentHeight: CGFloat, screen: NSScreen? = nil) -> NSSize {
        let dynamicMaxHeight = maximumSettingsWindowHeight(for: screen)
        let height = min(max(contentHeight, settingsMinWindowHeight), dynamicMaxHeight)
        return NSSize(width: dashboardWidth, height: height)
    }

    static func settingsWindowSizeLimits(measuredContentHeight: CGFloat?, screen: NSScreen? = nil) -> (min: NSSize, max: NSSize) {
        let dynamicMaxHeight = maximumSettingsWindowHeight(for: screen)
        let minHeight = min(settingsMinWindowHeight, dynamicMaxHeight)
        let maxHeight: CGFloat
        if let measuredContentHeight, measuredContentHeight > 0 {
            maxHeight = max(minHeight, min(measuredContentHeight, dynamicMaxHeight))
        } else {
            maxHeight = dynamicMaxHeight
        }
        return (
            NSSize(width: dashboardWidth, height: minHeight),
            NSSize(width: maxWidth, height: maxHeight)
        )
    }
}

@MainActor
final class DetachedWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private var hostingController: NSHostingController<DetachedUsageWindowView>!
    private let settings: AppSettingsStore
    private let onClose: (() -> Void)?
    private var contentMode: DetachedWindowContentMode = .dashboard(isLoggedIn: true, orientation: .horizontal)
    private var isProgrammaticResize = false
    private var isRelocatingToScreen = false
    private var isWindowMoving = false
    private var pendingDashboardHeightWorkItem: DispatchWorkItem?
    /// 使已经取消但仍进入执行队列的旧测高任务失效。
    private var dashboardHeightCommitGeneration = 0
    private var userMoveMouseUpMonitor: Any?
    /// 用户拖窗结束后短暂禁止改高度，避免顶边锚定 resize 造成松手瞬移。
    private var suppressDashboardHeightCommitUntil: Date?
    /// 竖向实测内容高度。
    private var dashboardMeasuredHeight: CGFloat?
    /// 测高所对应的账号/内容身份，防止不同连接共用同一缓存。
    private var dashboardMeasurementIdentity: String?
    private var settingsMeasuredContentHeight: CGFloat?
    private var titleControlsView: TitleControlsView!
    private var connectionSwitcherHoverObserver: Any?

    init(
        store: UsageSnapshotStore,
        settings: AppSettingsStore,
        multiAgentSettings: MultiAgentSettingsStore,
        activityStore: CodexActivityStore,
        frameStore: PetFrameStore,
        companionStatsStore: CompanionStatsStore,
        updater: AppUpdateController,
        actions: UsageActions,
        onOpenSettings: @escaping () -> Void,
        onClose: (() -> Void)? = nil
    ) {
        self.settings = settings
        self.onClose = onClose
        window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: DetachedWindowMetrics.defaultWidth,
                height: DetachedWindowMetrics.defaultHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        hostingController = NSHostingController(
            rootView: DetachedUsageWindowView(
                store: store,
                settings: settings,
                multiAgentSettings: multiAgentSettings,
                activityStore: activityStore,
                frameStore: frameStore,
                companionStatsStore: companionStatsStore,
                updater: updater,
                actions: actions,
                onContentLayoutChanged: { [weak self] mode in
                    self?.applyContentLayout(mode)
                },
                onOpenSettings: onOpenSettings,
                onDashboardMeasuredHeight: { [weak self] height, identity in
                    guard let self else { return }
                    if height > 1 {
                        self.commitDashboardMeasuredHeight(height, identity: identity)
                    }
                }
            )
        )
        window.title = "Codexling"
        contentMode = .dashboard(isLoggedIn: true, orientation: settings.dashboardOrientation)
        applyWindowChrome()
        applyAlwaysOnTop()
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.isOpaque = false
        hostingController.view.layer?.backgroundColor = NSColor.codexDashboardChrome.cgColor
        window.contentViewController = hostingController
        installTitleControls()
        applyWindowInteraction(for: contentMode)
        applyWindowSurface(for: contentMode)
        applyContentSizeLimits(for: contentMode)
        resizeWindowToDashboardContent(
            isLoggedIn: true,
            orientation: settings.dashboardOrientation,
            measuredHeight: nil
        )
        window.delegate = self
        window.isReleasedWhenClosed = false
        installConnectionSwitcherHoverObserver()
        installRightColumnTitlebarBlocker()
        // The status-bar capsule is a direct action. Avoid AppKit's default
        // document-window reveal animation so the result follows mouse-up.
        window.animationBehavior = .none
        window.center()
    }

    func show(on screen: NSScreen? = nil) {
        if let screen, window.screen !== screen {
            moveToCenter(of: screen)
        }
        if case let .dashboard(isLoggedIn, orientation) = contentMode {
            resizeWindowToDashboardContent(
                isLoggedIn: isLoggedIn,
                orientation: orientation,
                measuredHeight: orientation == .vertical ? dashboardMeasuredHeight : nil
            )
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func moveToCenter(of screen: NSScreen) {
        let targetSize: NSSize
        switch contentMode {
        case let .dashboard(isLoggedIn, orientation):
            targetSize = DetachedWindowMetrics.fixedDashboardFrameSize(
                isLoggedIn: isLoggedIn,
                orientation: orientation,
                measuredHeight: orientation == .vertical ? dashboardMeasuredHeight : nil,
                screen: screen,
                on: window
            )
        case .settings:
            targetSize = DetachedWindowMetrics.clampSettingsContentSize(
                window.frame.size,
                screen: screen
            )
        }

        let visibleFrame = screen.visibleFrame
        let centeredFrame = NSRect(
            x: visibleFrame.midX - targetSize.width / 2,
            y: visibleFrame.midY - targetSize.height / 2,
            width: targetSize.width,
            height: targetSize.height
        )

        isRelocatingToScreen = true
        window.setFrame(centeredFrame, display: false)
        isRelocatingToScreen = false
        applyContentSizeLimits(for: contentMode)
    }

    func refreshThemeAppearance() {
        applyWindowChrome()
        updateTitleControlsAppearance()
    }

    func refreshAlwaysOnTop() {
        applyAlwaysOnTop()
    }

    var currentScreen: NSScreen? { window.screen }

    @objc private func toggleDashboardOrientation() {
        guard case let .dashboard(_, orientation) = contentMode else { return }
        settings.dashboardOrientation = orientation == .horizontal ? .vertical : .horizontal
        updateTitleControlsAppearance()
    }

    @objc private func toggleAlwaysOnTop() {
        settings.windowAlwaysOnTop.toggle()
        applyAlwaysOnTop()
    }

    private func installTitleControls() {
        let controlsView = TitleControlsView(
            onToggleOrientation: { [weak self] in
                self?.toggleDashboardOrientation()
            },
            onTogglePin: { [weak self] in
                self?.toggleAlwaysOnTop()
            }
        )
        controlsView.frame = NSRect(x: 0, y: 0, width: 66, height: 28)
        controlsView.autoresizingMask = []
        if let frameView = window.contentView?.superview {
            frameView.addSubview(controlsView, positioned: .above, relativeTo: nil)
        }
        titleControlsView = controlsView
        updateTitleControlsAppearance()
        updateTitleControlsPlacement()
    }

    private func applyAlwaysOnTop() {
        // Keep the detached window managed by Mission Control in both modes.
        // A pinned window stays above normal windows on its current Space,
        // rather than behaving like an all-Spaces/full-screen auxiliary panel.
        window.collectionBehavior.remove([
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .stationary,
        ])
        window.collectionBehavior.insert(.managed)

        if settings.windowAlwaysOnTop {
            window.level = .floating
        } else {
            window.level = .normal
        }
        updateTitleControlsAppearance()
    }

    private func updateTitleControlsAppearance() {
        guard let titleControlsView else { return }
        let orientation: DashboardOrientation?
        if case let .dashboard(_, dashboardOrientation) = contentMode {
            orientation = dashboardOrientation
        } else {
            orientation = nil
        }
        titleControlsView.update(
            orientation: orientation,
            isPinned: settings.windowAlwaysOnTop,
            appearance: window.effectiveAppearance
        )
        updateTitleControlsPlacement()
    }

    private func updateTitleControlsPlacement() {
        guard let titleControlsView,
              let frameView = window.contentView?.superview else { return }

        let usesPetColumn = if case .dashboard(_, .horizontal) = contentMode { true } else { false }
        let showsOrientationToggle = if case .dashboard = contentMode { true } else { false }
        let controlWidth: CGFloat = showsOrientationToggle ? 66 : 28
        let trailingInset: CGFloat = 2
        let x: CGFloat
        if usesPetColumn {
            // Horizontal dashboard: align with the right edge of the generic
            // Pet column, not the window's account-content edge.
            x = DetachedWindowMetrics.sidebarWidth - controlWidth - trailingInset
        } else {
            // Vertical dashboard and settings: pin directly to the window's
            // visual trailing edge. This avoids AppKit's unreliable `.right`
            // titlebar accessory hit-test path.
            x = frameView.bounds.width - controlWidth - trailingInset
        }

        // Use a stable top inset instead of reading standard-button frames
        // while AppKit is in the middle of an orientation resize.
        // Keep the controls just below the absolute titlebar edge so their
        // optical center follows the traffic lights without looking top-heavy.
        let topInset: CGFloat = 4
        titleControlsView.frame = NSRect(
            x: round(x),
            y: round(frameView.bounds.maxY - topInset - 28),
            width: controlWidth,
            height: 28
        )
        frameView.addSubview(titleControlsView, positioned: .above, relativeTo: nil)
    }

    private func applyContentLayout(_ mode: DetachedWindowContentMode) {
        let enteringSettings = contentMode != .settings && mode == .settings
        if enteringSettings {
            settingsMeasuredContentHeight = nil
        }
        if contentMode != mode {
            cancelPendingDashboardHeightCommit()
        }
        if case let .dashboard(isLoggedIn, _) = mode, !isLoggedIn {
            dashboardMeasuredHeight = nil
            dashboardMeasurementIdentity = nil
        }
        contentMode = mode
        updateTitleControlsAppearance()
        applyWindowInteraction(for: mode)
        applyBackgroundDragging(for: mode)
        applyWindowSurface(for: mode)

        // 等 SwiftUI 完成 dashboard ↔ settings 切换后再改 frame，避免 NSHostingView 约束异常闪退。
        DispatchQueue.main.async { [weak self] in
            self?.finishApplyContentLayout(mode)
        }
    }

    private func finishApplyContentLayout(_ mode: DetachedWindowContentMode) {
        guard contentMode == mode else { return }

        switch mode {
        case let .dashboard(isLoggedIn, orientation):
            resizeWindowToDashboardContent(
                isLoggedIn: isLoggedIn,
                orientation: orientation,
                measuredHeight: orientation == .vertical ? dashboardMeasuredHeight : nil,
                animate: false
            )
        case .settings:
            applyContentSizeLimits(for: mode)
            resizeWindow(
                to: DetachedWindowMetrics.preferredSettingsWindowSize(
                    contentHeight: settingsMeasuredContentHeight
                        ?? DetachedWindowMetrics.settingsWindowProvisionalHeight(screen: window.screen),
                    screen: window.screen
                ),
                animate: false
            )
            scheduleSettingsHeightMeasurement()
        }
        updateTitleControlsPlacement()
    }

    private func applyWindowInteraction(for mode: DetachedWindowContentMode) {
        switch mode {
        case .dashboard:
            // 主界面尺寸已锁死；保留 resizable 会与背景拖窗抢手势。
            window.styleMask.remove(.resizable)
        case .settings:
            window.styleMask.insert(.resizable)
        }
    }

    private func applyWindowSurface(for mode: DetachedWindowContentMode) {
        switch mode {
        case .dashboard:
            window.backgroundColor = .codexDashboardChrome
            hostingController.view.layer?.backgroundColor = NSColor.codexDashboardChrome.cgColor
        case .settings:
            window.backgroundColor = .codexWindowBackground
            hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    private func scheduleSettingsHeightMeasurement() {
        // The settings ScrollView measures its child rather than its viewport,
        // so it no longer needs to expand to full-screen before measurement.
        DispatchQueue.main.async { [weak self] in
            guard let self, case .settings = contentMode else { return }
            hostingController.view.needsLayout = true
            hostingController.view.layoutSubtreeIfNeeded()
        }
    }

    /// 竖向 / 横版 Preference 收敛窗口高度（拖动期间不 commit）。
    private func commitDashboardMeasuredHeight(_ height: CGFloat, identity: String) {
        guard case let .dashboard(isLoggedIn, orientation) = contentMode, isLoggedIn else {
            return
        }

        let floor = DetachedWindowMetrics.verticalMinHeight
        let measured = max(floor, ceil(height))
        guard measured > 1 else { return }

        if dashboardMeasurementIdentity != identity {
            cancelPendingDashboardHeightCommit()
            dashboardMeasurementIdentity = identity
            dashboardMeasuredHeight = nil
        }

        // 横版时只缓存 330pt 竖版的预排版高度，不改变当前窗口。
        if orientation == .horizontal {
            cancelPendingDashboardHeightCommit()
            dashboardMeasuredHeight = measured
            return
        }

        guard !isWindowMoving else { return }
        if let until = suppressDashboardHeightCommitUntil, Date() < until {
            return
        }

        cancelPendingDashboardHeightCommit()
        guard dashboardMeasuredHeight != measured else { return }
        let generation = dashboardHeightCommitGeneration

        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isWindowMoving else { return }
            guard self.dashboardHeightCommitGeneration == generation else { return }
            if let until = self.suppressDashboardHeightCommitUntil, Date() < until {
                return
            }
            guard case let .dashboard(isLoggedIn, orientation) = self.contentMode,
                  isLoggedIn, orientation == .vertical else {
                return
            }

            guard self.dashboardMeasuredHeight != measured else { return }

            self.dashboardMeasuredHeight = measured
            self.pendingDashboardHeightWorkItem = nil
            self.resizeWindowToDashboardContent(
                isLoggedIn: true,
                orientation: .vertical,
                measuredHeight: measured,
                animate: false
            )
        }
        pendingDashboardHeightWorkItem = work
        // SwiftUI may publish more than once while the selected connection is
        // swapping its card. A short symmetric debounce keeps only the latest
        // geometry without leaving the previous account's height visible.
        let delay: TimeInterval = dashboardMeasuredHeight == nil ? 0.22 : 0.15
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPendingDashboardHeightCommit() {
        dashboardHeightCommitGeneration &+= 1
        pendingDashboardHeightWorkItem?.cancel()
        pendingDashboardHeightWorkItem = nil
    }

    private func invalidateSettingsMeasuredHeight() {
        guard case .settings = contentMode else { return }
        settingsMeasuredContentHeight = nil
        applyContentSizeLimits(for: .settings)
        scheduleSettingsHeightMeasurement()
    }

    private func commitSettingsMeasuredContentHeight(_ height: CGFloat) {
        guard case .settings = contentMode else { return }
        let measured = ceil(height)
        guard measured > 1 else { return }
        guard settingsMeasuredContentHeight != measured else { return }

        settingsMeasuredContentHeight = measured
        applyContentSizeLimits(for: .settings)

        let targetSize = DetachedWindowMetrics.preferredSettingsWindowSize(
            contentHeight: measured,
            screen: window.screen
        )
        resizeWindow(to: targetSize, animate: false)
    }

    /// 以顶边为锚调整尺寸，避免关闭设置页时窗口从下往上“弹回”。
    private func resizeWindow(to targetFrameSize: NSSize, animate: Bool) {
        guard !isWindowMoving else { return }
        guard window.frame.size != targetFrameSize else { return }

        var frame = window.frame
        frame.origin.y += frame.size.height - targetFrameSize.height
        frame.size = targetFrameSize

        isProgrammaticResize = true
        window.setFrame(frame, display: true, animate: animate)
        isProgrammaticResize = false
    }

    /// 横/竖主界面：解除上一布局的尺寸锁后，一次性更新 frame，再锁定新尺寸。
    private func resizeWindowToDashboardContent(
        isLoggedIn: Bool,
        orientation: DashboardOrientation,
        measuredHeight: CGFloat? = nil,
        animate: Bool = false
    ) {
        guard !isWindowMoving else { return }

        let contentSize = DetachedWindowMetrics.dashboardContentSize(
            isLoggedIn: isLoggedIn,
            orientation: orientation,
            measuredHeight: measuredHeight,
            screen: window.screen
        )

        let targetFrameSize = DetachedWindowMetrics.dashboardFrameSize(
            for: contentSize,
            on: window
        )
        var targetFrame = window.frame
        targetFrame.origin.y = targetFrame.maxY - targetFrameSize.height
        targetFrame.size = targetFrameSize

        isProgrammaticResize = true
        // The previous orientation/settings mode may have a fixed size that
        // rejects the new frame before AppKit gets a chance to apply it.
        window.minSize = .zero
        window.maxSize = NSSize(width: 10_000, height: 10_000)
        window.setFrame(targetFrame, display: true, animate: animate)
        isProgrammaticResize = false
        applyContentSizeLimits(for: .dashboard(isLoggedIn: isLoggedIn, orientation: orientation))
    }

    func windowWillClose(_ notification: Notification) {
        endUserMoveTracking()
        if let observer = connectionSwitcherHoverObserver {
            NotificationCenter.default.removeObserver(observer)
            connectionSwitcherHoverObserver = nil
        }
        if let blocker = rightColumnTitlebarBlocker {
            NSEvent.removeMonitor(blocker)
            rightColumnTitlebarBlocker = nil
        }
        onClose?()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        switch contentMode {
        case let .dashboard(isLoggedIn, orientation):
            return DetachedWindowMetrics.fixedDashboardFrameSize(
                isLoggedIn: isLoggedIn,
                orientation: orientation,
                measuredHeight: orientation == .vertical ? dashboardMeasuredHeight : nil,
                screen: sender.screen,
                on: sender
            )
        case .settings:
            return DetachedWindowMetrics.clampSettingsContentSize(frameSize, screen: sender.screen)
        }
    }

    func windowWillMove(_ notification: Notification) {
        guard !isProgrammaticResize else { return }
        beginUserMoveTracking()
    }

    func windowDidMove(_ notification: Notification) {
        guard !isProgrammaticResize else { return }
    }

    private func beginUserMoveTracking() {
        isWindowMoving = true
        cancelPendingDashboardHeightCommit()
        guard userMoveMouseUpMonitor == nil else { return }
        userMoveMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.endUserMoveTracking()
            return event
        }
    }

    private func endUserMoveTracking() {
        if let monitor = userMoveMouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            userMoveMouseUpMonitor = nil
        }
        suppressDashboardHeightCommitUntil = Date().addingTimeInterval(0.65)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.isWindowMoving = false
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        updateTitleControlsPlacement()
        guard !isProgrammaticResize else { return }

        switch contentMode {
        case .dashboard:
            // 主界面 min/max 已锁死尺寸，无需在 resize 回调里再次 setFrame（会与拖动打架）。
            break
        case .settings:
            let clamped = DetachedWindowMetrics.clampSettingsContentSize(
                window.frame.size,
                screen: window.screen
            )
            guard clamped != window.frame.size else { return }
            resizeWindow(to: clamped, animate: false)
        }
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard notification.object is NSWindow, !isRelocatingToScreen else { return }
        applyContentSizeLimits(for: contentMode)
        applyContentLayout(contentMode)
    }

    private func applyWindowChrome(for theme: AppThemePreference? = nil) {
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        applyBackgroundDragging(for: contentMode)
        window.isOpaque = true
        applyWindowSurface(for: contentMode)
        window.hasShadow = true
        window.appearance = (theme ?? settings.theme).nsAppearance
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(type)?.isHidden = false
        }
    }

    private func applyBackgroundDragging(for mode: DetachedWindowContentMode) {
        switch mode {
        case .dashboard:
            window.isMovableByWindowBackground = true
        case .settings:
            window.isMovableByWindowBackground = false
        }
    }

    /// 监听连接切换器的 hover 状态：鼠标在切换器上时禁用窗口背景拖拽，
    /// 防止拖拽排序 logo 时误触发窗口移动。
    /// 退出 hover 时加短延迟，避免拖拽过程中鼠标短暂离开区域导致窗口跳动。
    private func installConnectionSwitcherHoverObserver() {
        connectionSwitcherHoverObserver = NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConnectionSwitcherHover(_:)),
            name: .connectionSwitcherHoverChanged,
            object: nil
        )
    }

    @MainActor
    @objc private func handleConnectionSwitcherHover(_ notification: Notification) {
        guard case .dashboard = contentMode,
              let hovering = notification.userInfo?["hovering"] as? Bool
        else { return }

        window.isMovableByWindowBackground = !hovering
    }

    // MARK: - Right column titlebar blocker

    /// 只拦截右侧内容区顶部 22pt 的标题栏拖拽，不碰左侧 Pet 区和窗口按钮。
    private var rightColumnTitlebarBlocker: Any?

    private func installRightColumnTitlebarBlocker() {
        rightColumnTitlebarBlocker = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            guard let self,
                  case .dashboard(isLoggedIn: _, orientation: _) = self.contentMode,
                  let contentView = self.window.contentView
            else { return event }

            let point = contentView.convert(event.locationInWindow, from: nil)
            let sidebarWidth = DetachedWindowMetrics.sidebarWidth

            // 置顶 / 方向切换按钮必须保持可点：命中标题栏控件区域时直接放行。
            // 竖版布局下按钮贴窗口右缘（x > sidebarWidth 且顶部 22pt），
            // 否则会被下面的拦截逻辑吞掉，表现为「点不了」。
            if let titleControlsView {
                let localPoint = titleControlsView.convert(event.locationInWindow, from: nil)
                if titleControlsView.bounds.contains(localPoint) {
                    return event
                }
            }

            // 只处理右侧区域（x > sidebarWidth）的标题栏高度（y <= 22）
            guard point.x > sidebarWidth, point.y <= 22 else { return event }

            // 吞掉事件，阻止标题栏拖拽
            return nil
        }
    }

    private func applyContentSizeLimits(for mode: DetachedWindowContentMode) {
        let frameMin: NSSize
        let frameMax: NSSize

        switch mode {
        case let .dashboard(isLoggedIn, orientation):
            let frameSize = DetachedWindowMetrics.fixedDashboardFrameSize(
                isLoggedIn: isLoggedIn,
                orientation: orientation,
                measuredHeight: orientation == .vertical ? dashboardMeasuredHeight : nil,
                screen: window.screen,
                on: window
            )
            frameMin = frameSize
            frameMax = frameSize
        case .settings:
            let limits = DetachedWindowMetrics.settingsWindowSizeLimits(
                measuredContentHeight: settingsMeasuredContentHeight,
                screen: window.screen
            )
            frameMin = limits.min
            frameMax = limits.max
        }

        window.minSize = frameMin
        window.maxSize = frameMax
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private var hostingController: NSHostingController<SettingsView>!
    private let settings: AppSettingsStore
    private let onClose: () -> Void
    private var measuredContentHeight: CGFloat?
    private var isProgrammaticResize = false

    init(
        store: UsageSnapshotStore,
        settings: AppSettingsStore,
        multiAgentSettings: MultiAgentSettingsStore,
        updater: AppUpdateController,
        actions: UsageActions,
        onClose: @escaping () -> Void
    ) {
        self.settings = settings
        self.onClose = onClose
        window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: DetachedWindowMetrics.dashboardWidth,
                height: DetachedWindowMetrics.settingsWindowProvisionalHeight()
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        hostingController = NSHostingController(
            rootView: SettingsView(
                store: store,
                settings: settings,
                multiAgentSettings: multiAgentSettings,
                updater: updater,
                layout: .window,
                onLogout: actions.disconnect,
                onMeasuredContentHeightChange: { [weak self] height in
                    self?.handleMeasuredContentHeight(height)
                }
            )
        )

        window.title = "Codexling 设置"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.delegate = self
        window.contentViewController = hostingController
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.isOpaque = false
        applyWindowAppearance()
        applySizeLimits()
        window.center()
    }

    func show(on screen: NSScreen? = nil) {
        if let screen, window.screen !== screen, !window.isVisible {
            let size = window.frame.size
            let visible = screen.visibleFrame
            window.setFrameOrigin(NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2
            ))
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func refreshThemeAppearance() {
        applyWindowAppearance()
    }

    private func handleMeasuredContentHeight(_ height: CGFloat) {
        if height < 0 {
            measuredContentHeight = nil
            applySizeLimits()
            scheduleContentMeasurement()
        } else if height > 1 {
            commitMeasuredContentHeight(height)
        } else {
            scheduleContentMeasurement()
        }
    }

    private func scheduleContentMeasurement() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            hostingController.view.needsLayout = true
            hostingController.view.layoutSubtreeIfNeeded()
        }
    }

    private func commitMeasuredContentHeight(_ height: CGFloat) {
        let measured = ceil(height)
        guard measured > 1, measuredContentHeight != measured else { return }
        measuredContentHeight = measured
        applySizeLimits()
        resizeWindow(
            to: DetachedWindowMetrics.preferredSettingsWindowSize(
                contentHeight: measured,
                screen: window.screen
            )
        )
    }

    private func resizeWindow(to targetSize: NSSize) {
        guard window.frame.size != targetSize else { return }
        var frame = window.frame
        frame.origin.y += frame.height - targetSize.height
        frame.size = targetSize
        isProgrammaticResize = true
        window.setFrame(frame, display: true, animate: false)
        isProgrammaticResize = false
    }

    private func applySizeLimits() {
        let limits = DetachedWindowMetrics.settingsWindowSizeLimits(
            measuredContentHeight: measuredContentHeight,
            screen: window.screen
        )
        window.minSize = limits.min
        window.maxSize = limits.max
    }

    private func applyWindowAppearance() {
        window.backgroundColor = .codexWindowBackground
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        window.appearance = settings.theme.nsAppearance
        window.hasShadow = true
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(type)?.isHidden = false
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard !isProgrammaticResize else { return }
        let clamped = DetachedWindowMetrics.clampSettingsContentSize(
            window.frame.size,
            screen: window.screen
        )
        guard clamped != window.frame.size else { return }
        resizeWindow(to: clamped)
    }

    func windowDidChangeScreen(_ notification: Notification) {
        applySizeLimits()
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

final class TitleControlsView: NSView {
    private let orientationButton = TitleMaterialWaveButton(frame: .zero)
    private let pinButton = TitleMaterialWaveButton(frame: .zero)
    private let onToggleOrientation: () -> Void
    private let onTogglePin: () -> Void

    init(onToggleOrientation: @escaping () -> Void, onTogglePin: @escaping () -> Void) {
        self.onToggleOrientation = onToggleOrientation
        self.onTogglePin = onTogglePin
        super.init(frame: .zero)

        orientationButton.target = self
        orientationButton.action = #selector(toggleOrientation)
        pinButton.target = self
        pinButton.action = #selector(togglePin)
        addSubview(orientationButton)
        addSubview(pinButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func update(orientation: DashboardOrientation?, isPinned: Bool, appearance: NSAppearance) {
        self.appearance = appearance
        orientationButton.isHidden = orientation == nil

        if let orientation {
            let target = orientation == .horizontal
                ? DashboardOrientation.vertical
                : DashboardOrientation.horizontal
            orientationButton.frame = NSRect(x: 0, y: 0, width: 32, height: 28)
            orientationButton.update(
                symbolName: target.symbolName,
                help: "切换到\(target.title)版"
            )
            pinButton.frame = NSRect(x: 34, y: 0, width: 32, height: 28)
        } else {
            pinButton.frame = NSRect(x: 0, y: 0, width: 28, height: 28)
        }

        pinButton.update(
            symbolName: isPinned ? "pin.fill" : "pin",
            help: isPinned ? "取消窗口置顶" : "窗口置顶"
        )
    }

    @objc private func toggleOrientation() {
        onToggleOrientation()
    }

    @objc private func togglePin() {
        onTogglePin()
    }
}

private final class TitleMaterialWaveButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func update(symbolName: String, help: String) {
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: help)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        contentTintColor = .labelColor
        toolTip = help
        setAccessibilityLabel(help)
    }

    override func mouseDown(with event: NSEvent) {
        addMaterialWave(at: convert(event.locationInWindow, from: nil))
        super.mouseDown(with: event)
    }

    private func addMaterialWave(at point: NSPoint) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        wantsLayer = true
        guard let layer else { return }

        let diameter = hypot(bounds.width, bounds.height) * 2.1
        let ripple = CAShapeLayer()
        ripple.frame = bounds
        ripple.path = CGPath(
            ellipseIn: CGRect(
                x: point.x - diameter / 2,
                y: point.y - diameter / 2,
                width: diameter,
                height: diameter
            ),
            transform: nil
        )
        ripple.fillColor = NSColor.systemGreen.withAlphaComponent(0.18).cgColor
        layer.addSublayer(ripple)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.04
        scale.toValue = 1.0
        scale.duration = 0.42
        scale.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 1.0
        opacity.toValue = 0.0
        opacity.beginTime = CACurrentMediaTime() + 0.12
        opacity.duration = 0.42
        opacity.fillMode = .forwards
        opacity.isRemovedOnCompletion = false

        ripple.add(scale, forKey: "scale")
        ripple.add(opacity, forKey: "opacity")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
            ripple.removeFromSuperlayer()
        }
    }
}
