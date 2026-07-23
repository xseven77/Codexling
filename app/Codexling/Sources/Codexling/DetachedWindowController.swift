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
    static let settingsHeight: CGFloat = 860
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

    static func clampSettingsContentSize(_ size: NSSize, screen: NSScreen? = nil) -> NSSize {
        let dynamicMaxHeight = maximumContentHeight(for: screen)
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
}

@MainActor
final class DetachedWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private var hostingController: NSHostingController<DetachedUsageWindowView>!
    private let settings: AppSettingsStore
    private let onClose: (() -> Void)?
    private var contentMode: DetachedWindowContentMode = .dashboard(isLoggedIn: true)
    private var isProgrammaticResize = false

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
        contentMode = mode
        applyContentSizeLimits(for: mode)

        let targetSize: NSSize = switch mode {
        case let .dashboard(isLoggedIn):
            DetachedWindowMetrics.fixedDashboardContentSize(
                isLoggedIn: isLoggedIn,
                screen: window.screen
            )
        case .settings:
            NSSize(
                width: DetachedWindowMetrics.dashboardWidth,
                height: min(
                    DetachedWindowMetrics.settingsHeight,
                    DetachedWindowMetrics.maximumContentHeight(for: window.screen)
                )
            )
        }

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

        let clampedFrameSize: NSSize = switch contentMode {
        case let .dashboard(isLoggedIn):
            DetachedWindowMetrics.fixedDashboardContentSize(isLoggedIn: isLoggedIn, screen: window.screen)
        case .settings:
            DetachedWindowMetrics.clampSettingsContentSize(window.frame.size, screen: window.screen)
        }

        resizeWindow(to: clampedFrameSize, animate: false)
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
        let dynamicMaxHeight = DetachedWindowMetrics.maximumContentHeight(for: window.screen)
        let dynamicMinHeight = min(DetachedWindowMetrics.minHeight, dynamicMaxHeight)

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
            frameMin = NSSize(
                width: DetachedWindowMetrics.dashboardWidth,
                height: dynamicMinHeight
            )
            frameMax = NSSize(
                width: DetachedWindowMetrics.maxWidth,
                height: dynamicMaxHeight
            )
        }

        window.minSize = frameMin
        window.maxSize = frameMax
    }
}
