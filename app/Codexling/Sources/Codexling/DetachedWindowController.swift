import AppKit
import SwiftUI

enum DetachedWindowContentMode: Equatable {
    case dashboard(isLoggedIn: Bool)
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

    static let maxWidth: CGFloat = 680
    static let minHeight: CGFloat = 420
    static let maxHeight: CGFloat = 960
    static let loginDashboardHeight: CGFloat = 440
    static let loggedInDashboardHeight: CGFloat = 510
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

    static func fixedDashboardContentSize(isLoggedIn: Bool, screen: NSScreen? = nil) -> NSSize {
        let dynamicMaxHeight = maximumContentHeight(for: screen)
        let height = min(dashboardHeight(isLoggedIn: isLoggedIn), dynamicMaxHeight)
        return NSSize(width: dashboardWidth, height: height)
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
    private var contentMode: DetachedWindowContentMode = .dashboard(isLoggedIn: true)
    private var isProgrammaticResize = false
    private var settingsMeasuredContentHeight: CGFloat?

    init(
        store: UsageSnapshotStore,
        settings: AppSettingsStore,
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
                }
            )
        )
        window.title = "Codexling"
        applyWindowChrome()
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.isOpaque = false
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentViewController = hostingController
        contentMode = .dashboard(isLoggedIn: true)
        applyContentSizeLimits(for: contentMode)
        var initialFrame = window.frame
        initialFrame.size = DetachedWindowMetrics.fixedDashboardContentSize(isLoggedIn: true)
        window.setFrame(initialFrame, display: false)
        window.delegate = self
        window.isReleasedWhenClosed = false
        // The status-bar capsule is a direct action. Avoid AppKit's default
        // document-window reveal animation so the result follows mouse-up.
        window.animationBehavior = .none
        window.center()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func refreshThemeAppearance() {
        applyWindowChrome()
    }

    private func applyContentLayout(_ mode: DetachedWindowContentMode) {
        let enteringSettings = contentMode != .settings && mode == .settings
        if enteringSettings {
            settingsMeasuredContentHeight = nil
        }
        contentMode = mode
        applyContentSizeLimits(for: mode)

        let targetSize: NSSize = switch mode {
        case let .dashboard(isLoggedIn):
            DetachedWindowMetrics.fixedDashboardContentSize(
                isLoggedIn: isLoggedIn,
                screen: window.screen
            )
        case .settings:
            DetachedWindowMetrics.preferredSettingsWindowSize(
                contentHeight: settingsMeasuredContentHeight
                    ?? DetachedWindowMetrics.settingsWindowProvisionalHeight(screen: window.screen),
                screen: window.screen
            )
        }

        resizeWindow(to: targetSize, animate: false)
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

    /// 以窗口顶边为锚点调整尺寸，避免关闭设置页时窗口从下往上“弹回”。
    private func resizeWindow(to targetSize: NSSize, animate: Bool) {
        guard window.frame.size != targetSize else { return }

        var frame = window.frame
        frame.origin.y += frame.size.height - targetSize.height
        frame.size = targetSize

        isProgrammaticResize = true
        window.setFrame(frame, display: true, animate: animate)
        isProgrammaticResize = false
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        switch contentMode {
        case let .dashboard(isLoggedIn):
            DetachedWindowMetrics.fixedDashboardContentSize(isLoggedIn: isLoggedIn, screen: sender.screen)
        case .settings:
            DetachedWindowMetrics.clampSettingsContentSize(frameSize, screen: sender.screen)
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard !isProgrammaticResize, let window = notification.object as? NSWindow else { return }

        switch contentMode {
        case let .dashboard(isLoggedIn):
            let clampedFrameSize = DetachedWindowMetrics.fixedDashboardContentSize(
                isLoggedIn: isLoggedIn,
                screen: window.screen
            )
            resizeWindow(to: clampedFrameSize, animate: false)
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
        guard notification.object is NSWindow else { return }
        applyContentSizeLimits(for: contentMode)
        applyContentLayout(contentMode)
    }

    private func applyWindowChrome(for theme: AppThemePreference? = nil) {
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // The detached window contains sliders and other drag-driven controls.
        // Background window dragging competes with SwiftUI's Slider gesture and
        // makes the whole window move instead of the thumb. Keep dragging on
        // the standard title-bar region and let content own its pointer input.
        window.isMovableByWindowBackground = false
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = true
        window.appearance = (theme ?? settings.theme).nsAppearance
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(type)?.isHidden = false
        }
    }

    private func applyContentSizeLimits(for mode: DetachedWindowContentMode) {
        let frameMin: NSSize
        let frameMax: NSSize

        switch mode {
        case let .dashboard(isLoggedIn):
            let fixedSize = DetachedWindowMetrics.fixedDashboardContentSize(
                isLoggedIn: isLoggedIn,
                screen: window.screen
            )
            frameMin = fixedSize
            frameMax = fixedSize
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
