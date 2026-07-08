import AppKit
import SwiftUI

enum DetachedWindowMetrics {
    static let minWidth: CGFloat = 414
    static let maxWidth: CGFloat = 560
    static let minHeight: CGFloat = 760
    static let maxHeight: CGFloat = 960
    static let defaultWidth: CGFloat = 460
    static let defaultHeight: CGFloat = 840

    static func clampContentSize(_ size: NSSize) -> NSSize {
        NSSize(
            width: min(max(size.width, minWidth), maxWidth),
            height: min(max(size.height, minHeight), maxHeight)
        )
    }
}

@MainActor
final class DetachedWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let hostingController: NSHostingController<DetachedUsageWindowView>

    init(store: UsageSnapshotStore, actions: UsageActions) {
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
            rootView: DetachedUsageWindowView(store: store, actions: actions)
        )

        super.init()

        window.title = "Codex Light"
        applyWindowChrome()
        applyContentSizeLimits(to: window)
        hostingController.sizingOptions = [.minSize, .maxSize]
        window.contentViewController = hostingController
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let contentSize = sender.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize)).size
        let clampedContent = DetachedWindowMetrics.clampContentSize(contentSize)
        return sender.frameRect(forContentRect: NSRect(origin: .zero, size: clampedContent)).size
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        let contentSize = window.contentView?.frame.size ?? .zero
        let clampedContent = DetachedWindowMetrics.clampContentSize(contentSize)
        guard contentSize != clampedContent else { return }

        var frame = window.frame
        let currentContentHeight = window.contentRect(forFrameRect: frame).height
        let currentContentWidth = window.contentRect(forFrameRect: frame).width
        frame.size.width += clampedContent.width - currentContentWidth
        frame.size.height += clampedContent.height - currentContentHeight
        window.setFrame(frame, display: true)
    }

    private func applyWindowChrome() {
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(red: 0.957, green: 0.957, blue: 0.957, alpha: 1)
    }

    private func applyContentSizeLimits(to window: NSWindow) {
        let contentMin = NSSize(
            width: DetachedWindowMetrics.minWidth,
            height: DetachedWindowMetrics.minHeight
        )
        let contentMax = NSSize(
            width: DetachedWindowMetrics.maxWidth,
            height: DetachedWindowMetrics.maxHeight
        )

        window.contentMinSize = contentMin
        window.contentMaxSize = contentMax
        window.minSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentMin)).size
        window.maxSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentMax)).size
    }
}
