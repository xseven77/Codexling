import AppKit
import SwiftUI

enum DetachedWindowMetrics {
    static let minWidth: CGFloat = 520
    static let maxWidth: CGFloat = 680
    // Heights describe the complete native window frame. The content uses a
    // full-size transparent title bar, so this maps directly to the HTML box.
    static let minHeight: CGFloat = 420
    static let maxHeight: CGFloat = 960
    static let defaultWidth: CGFloat = 580
    static let defaultHeight: CGFloat = 495
    static let dashboardHeight: CGFloat = 495
    static let dashboardVisualHeight: CGFloat = 493
    static let settingsHeight: CGFloat = 860
    static let chromeHeaderHeight: CGFloat = 38

    static func maximumContentHeight(for screen: NSScreen?) -> CGFloat {
        let visibleHeight = screen?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height
            ?? maxHeight
        return min(maxHeight, max(1, visibleHeight - 32))
    }

    static func clampContentSize(_ size: NSSize, screen: NSScreen? = nil) -> NSSize {
        let dynamicMaxHeight = maximumContentHeight(for: screen)
        return NSSize(
            width: min(max(size.width, minWidth), maxWidth),
            height: min(max(size.height, min(minHeight, dynamicMaxHeight)), dynamicMaxHeight)
        )
    }
}

@MainActor
final class DetachedWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private var hostingController: NSHostingController<DetachedUsageWindowView>!
    private let settings: AppSettingsStore
    private let onClose: (() -> Void)?

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
                onPreferredHeightChanged: { [weak self] height in
                    self?.setPreferredContentHeight(height)
                }
            )
        )

        window.title = "Codexling"
        applyWindowChrome()
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.isOpaque = false
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentViewController = hostingController
        applyContentSizeLimits(to: window)
        var initialFrame = window.frame
        initialFrame.size = NSSize(
            width: DetachedWindowMetrics.defaultWidth,
            height: DetachedWindowMetrics.defaultHeight
        )
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

    private func setPreferredContentHeight(_ requestedHeight: CGFloat) {
        let target = min(requestedHeight, DetachedWindowMetrics.maximumContentHeight(for: window.screen))
        let current = window.frame.height
        guard abs(current - target) > 1 else { return }

        var frame = window.frame
        frame.origin.y += frame.height - target
        frame.size.height = target
        window.setFrame(frame, display: true, animate: true)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        DetachedWindowMetrics.clampContentSize(frameSize, screen: sender.screen)
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        let clampedFrameSize = DetachedWindowMetrics.clampContentSize(window.frame.size, screen: window.screen)
        guard window.frame.size != clampedFrameSize else { return }
        var frame = window.frame
        frame.size = clampedFrameSize
        window.setFrame(frame, display: true)
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        applyContentSizeLimits(to: window)
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

    private func applyContentSizeLimits(to window: NSWindow) {
        let dynamicMaxHeight = DetachedWindowMetrics.maximumContentHeight(for: window.screen)
        let dynamicMinHeight = min(DetachedWindowMetrics.minHeight, dynamicMaxHeight)
        let frameMin = NSSize(
            width: DetachedWindowMetrics.minWidth,
            height: dynamicMinHeight
        )
        let frameMax = NSSize(
            width: DetachedWindowMetrics.maxWidth,
            height: dynamicMaxHeight
        )

        window.minSize = frameMin
        window.maxSize = frameMax

        let currentFrameSize = window.frame.size
        let clampedFrameSize = DetachedWindowMetrics.clampContentSize(currentFrameSize, screen: window.screen)
        if currentFrameSize != clampedFrameSize {
            var frame = window.frame
            frame.size = clampedFrameSize
            window.setFrame(frame, display: false)
        }
    }
}
