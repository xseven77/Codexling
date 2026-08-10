import AppKit
import SwiftUI

enum DetachedWindowContentMode: Equatable {
    case dashboard(isLoggedIn: Bool, orientation: DashboardOrientation)
    case settings
}

enum DetachedWindowMetrics {
    static let quotaCardWidth: CGFloat = 169
    static let quotaCardSpacing: CGFloat = 9
    static let sidebarWidth: CGFloat = 188
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

    static let maxWidth: CGFloat = 680
    static let minHeight: CGFloat = 420
    static let maxHeight: CGFloat = 960
    static let loginDashboardHeight: CGFloat = 440
    /// 横版已登录：包含 M1 重置券融合区；略微收紧券卡与底部工具栏之间的留白。
    static let loggedInDashboardHeight: CGFloat = 658
    static let horizontalMinHeight: CGFloat = 420

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
    /// 设置页首次打开时先用屏幕允许的最大高度布局，避免在滚动模式下测不准内容高度。
    static func settingsWindowProvisionalHeight(screen: NSScreen? = nil) -> CGFloat {
        maximumSettingsWindowHeight(for: screen)
    }
    /// 用户手动缩小时的下限；低于内容高度时 SwiftUI 才启用滚动。
    static let settingsMinWindowHeight: CGFloat = 400
    static let chromeHeaderHeight: CGFloat = 38

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
        return max(1, visibleHeight - 32)
    }

    static func clampSettingsContentSize(_ size: NSSize, screen: NSScreen? = nil) -> NSSize {
        let dynamicMaxHeight = maximumSettingsWindowHeight(for: screen)
        return NSSize(
            width: min(max(size.width, dashboardWidth), maxWidth),
            height: min(max(size.height, min(minHeight, dynamicMaxHeight)), dynamicMaxHeight)
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
            maxHeight = min(measuredContentHeight, dynamicMaxHeight)
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
    private var settingsMeasuredContentHeight: CGFloat?
    private var titleControlsHostingView: NSHostingView<WindowTitleControls>!

    init(
        store: UsageSnapshotStore,
        settings: AppSettingsStore,
        multiAgentSettings: MultiAgentSettingsStore,
        activityStore: CodexActivityStore,
        frameStore: PetFrameStore,
        companionStatsStore: CompanionStatsStore,
        updater: AppUpdateController,
        actions: UsageActions,
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
                onSettingsMeasuredHeight: { [weak self] height in
                    guard let self else { return }
                    if height < 0 {
                        invalidateSettingsMeasuredHeight()
                    } else if height > 1 {
                        commitSettingsMeasuredContentHeight(height)
                    } else {
                        scheduleSettingsHeightMeasurement()
                    }
                },
                onDashboardMeasuredHeight: { [weak self] height in
                    guard let self else { return }
                    if height > 1 {
                        self.commitDashboardMeasuredHeight(height)
                    }
                }
            )
        )
        window.title = "Codexling"
        contentMode = .dashboard(isLoggedIn: true, orientation: settings.dashboardOrientation)
        applyWindowChrome()
        installTitleControls()
        applyAlwaysOnTop()
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.isOpaque = false
        hostingController.view.layer?.backgroundColor = NSColor.codexDashboardChrome.cgColor
        window.contentViewController = hostingController
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
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .right

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 66, height: 28))
        let hostingView = NSHostingView(
            rootView: makeTitleControls()
        )
        hostingView.frame = NSRect(x: 3, y: 0, width: 60, height: 28)
        container.addSubview(hostingView)

        accessory.view = container
        window.addTitlebarAccessoryViewController(accessory)
        titleControlsHostingView = hostingView
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
        guard let titleControlsHostingView else { return }
        titleControlsHostingView.rootView = makeTitleControls()
    }

    private func makeTitleControls() -> WindowTitleControls {
        let orientation: DashboardOrientation?
        if case let .dashboard(_, dashboardOrientation) = contentMode {
            orientation = dashboardOrientation
        } else {
            orientation = nil
        }

        return WindowTitleControls(
            orientation: orientation,
            isPinned: settings.windowAlwaysOnTop,
            onToggleOrientation: { [weak self] in
                self?.toggleDashboardOrientation()
            },
            onTogglePin: { [weak self] in
                self?.toggleAlwaysOnTop()
            }
        )
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
        DispatchQueue.main.async { [weak self] in
            guard let self, case .settings = contentMode else { return }
            // 仅在尚未完成首次测量时临时拉高窗口；切勿在 commit 后再扩高，否则会与 Preference 形成 resize 死循环。
            guard settingsMeasuredContentHeight == nil else { return }
            let provisional = DetachedWindowMetrics.settingsWindowProvisionalHeight(screen: window.screen)
            if window.frame.size.height + 1 < provisional {
                resizeWindow(
                    to: NSSize(width: DetachedWindowMetrics.dashboardWidth, height: provisional),
                    animate: false
                )
            }
        }
    }

    /// 竖向 / 横版 Preference 收敛窗口高度（拖动期间不 commit）。
    private func commitDashboardMeasuredHeight(_ height: CGFloat) {
        guard case let .dashboard(isLoggedIn, orientation) = contentMode, isLoggedIn else {
            return
        }

        let floor = DetachedWindowMetrics.verticalMinHeight
        let measured = max(floor, ceil(height))
        guard measured > 1 else { return }

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
        let delay: TimeInterval
        if dashboardMeasuredHeight == nil {
            // 首次切换需等待 330pt 宽度完成布局，不能提交旧横版宽度下的瞬态高度。
            delay = 0.35
        } else {
            delay = measured < dashboardMeasuredHeight! ? 1.4 : 0.15
        }
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
        let provisional = DetachedWindowMetrics.settingsWindowProvisionalHeight(screen: window.screen)
        resizeWindow(
            to: NSSize(width: DetachedWindowMetrics.dashboardWidth, height: provisional),
            animate: false
        )
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

    /// 横/竖主界面：`setContentSize` 锁定内容区尺寸。
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

        let topY = window.frame.maxY
        isProgrammaticResize = true
        window.setContentSize(contentSize)
        var frame = window.frame
        frame.origin.y = topY - frame.size.height
        window.setFrameOrigin(frame.origin)
        isProgrammaticResize = false
        applyContentSizeLimits(for: .dashboard(isLoggedIn: isLoggedIn, orientation: orientation))
    }

    func windowWillClose(_ notification: Notification) {
        endUserMoveTracking()
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
        guard !isProgrammaticResize, let window = notification.object as? NSWindow else { return }

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
            // Buttons and other controls keep their own pointer handling;
            // unhandled content and card backgrounds move the main window.
            window.isMovableByWindowBackground = true
        case .settings:
            // Settings contains drag-sensitive controls, so it retains normal
            // content interaction and uses the title bar for window movement.
            window.isMovableByWindowBackground = false
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

private struct WindowTitleControls: View {
    let orientation: DashboardOrientation?
    let isPinned: Bool
    let onToggleOrientation: () -> Void
    let onTogglePin: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            if let orientation {
                let target = orientation == .horizontal
                    ? DashboardOrientation.vertical
                    : DashboardOrientation.horizontal
                Button(action: onToggleOrientation) {
                    Image(systemName: target.symbolName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.codexInk)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(CodexPressableStyle(cornerRadius: 8))
                .help("切换到\(target.title)版")
                .accessibilityLabel("切换到\(target.title)版")
            }

            Button(action: onTogglePin) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.codexInk)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(CodexPressableStyle(cornerRadius: 8))
            .help(isPinned ? "取消置顶" : "置顶窗口")
            .accessibilityLabel(isPinned ? "取消窗口置顶" : "窗口置顶")
        }
        .frame(width: 60, height: 28, alignment: .trailing)
    }
}
