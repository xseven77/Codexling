import AppKit
import SwiftUI

enum DetachedWindowMetrics {
    static let minWidth: CGFloat = 414
    static let maxWidth: CGFloat = 560
    static let minHeight: CGFloat = 760
    static let maxHeight: CGFloat = 960
    static let defaultWidth: CGFloat = 460
    static let defaultHeight: CGFloat = 840

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
    private let hostingController: NSHostingController<DetachedUsageWindowView>
    private let settings: AppSettingsStore
    private let onClose: (() -> Void)?

    init(
        store: UsageSnapshotStore,
        settings: AppSettingsStore,
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
        hostingController = NSHostingController(
            rootView: DetachedUsageWindowView(
                store: store,
                settings: settings,
                updater: updater,
                actions: actions
            )
        )

        super.init()

        window.title = "Codex Light"
        applyWindowChrome()
        applyContentSizeLimits(to: window)
        hostingController.sizingOptions = [.minSize, .maxSize]
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.isOpaque = false
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentViewController = hostingController
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

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let contentSize = sender.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize)).size
        let clampedContent = DetachedWindowMetrics.clampContentSize(contentSize, screen: sender.screen)
        return sender.frameRect(forContentRect: NSRect(origin: .zero, size: clampedContent)).size
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        let contentSize = window.contentView?.frame.size ?? .zero
        let clampedContent = DetachedWindowMetrics.clampContentSize(contentSize, screen: window.screen)
        guard contentSize != clampedContent else { return }

        var frame = window.frame
        let currentContentHeight = window.contentRect(forFrameRect: frame).height
        let currentContentWidth = window.contentRect(forFrameRect: frame).width
        frame.size.width += clampedContent.width - currentContentWidth
        frame.size.height += clampedContent.height - currentContentHeight
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
    }

    private func applyContentSizeLimits(to window: NSWindow) {
        let dynamicMaxHeight = DetachedWindowMetrics.maximumContentHeight(for: window.screen)
        let dynamicMinHeight = min(DetachedWindowMetrics.minHeight, dynamicMaxHeight)
        let contentMin = NSSize(
            width: DetachedWindowMetrics.minWidth,
            height: dynamicMinHeight
        )
        let contentMax = NSSize(
            width: DetachedWindowMetrics.maxWidth,
            height: dynamicMaxHeight
        )

        window.contentMinSize = contentMin
        window.contentMaxSize = contentMax
        window.minSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentMin)).size
        window.maxSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentMax)).size

        let currentContent = window.contentRect(forFrameRect: window.frame).size
        let clampedContent = DetachedWindowMetrics.clampContentSize(currentContent, screen: window.screen)
        if currentContent != clampedContent {
            window.setContentSize(clampedContent)
        }
    }
}
