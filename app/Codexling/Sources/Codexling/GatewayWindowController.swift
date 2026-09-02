import AppKit
import SwiftUI

/// Window controller for the independent, detached Gateway management window.
/// Closing this window hides it without terminating the background Gateway process.
@MainActor
public final class GatewayWindowController: NSObject, NSWindowDelegate {
    public static let shared = GatewayWindowController()

    public static let minWindowWidth: CGFloat = 860
    public static let minWindowHeight: CGFloat = 600

    private let window: NSWindow
    private var hostingController: NSHostingController<GatewayView>!

    /// Set by AppDelegate after init so GatewayView can forward proxy toggles
    /// through MultiAgentSettingsStore (the owner of in-memory account state).
    var multiAgentSettingsStore: MultiAgentSettingsStore? {
        didSet { hostingController?.rootView = GatewayView(settingsStore: multiAgentSettingsStore) }
    }

    public static func defaultWindowSize(for screen: NSScreen? = nil) -> NSSize {
        let currentScreen = screen ?? NSScreen.main
        let visibleFrame = currentScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width: CGFloat = minWindowWidth
        // 显示器视窗允许的情况下，默认打开时尽量占满可用高度（上下各留 20pt 呼吸边距），
        // 充分展示多账号与模型长列表，减少不必要的滚动。
        let maxAvailableHeight = max(minWindowHeight, visibleFrame.height - 40)
        return NSSize(width: width, height: maxAvailableHeight)
    }

    public override init() {
        let size = Self.defaultWindowSize()

        window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: size.width,
                height: size.height
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        hostingController = NSHostingController(rootView: GatewayView())

        window.title = "Codexling Gateway"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.minSize = NSSize(width: Self.minWindowWidth, height: Self.minWindowHeight)
        window.contentMinSize = NSSize(width: Self.minWindowWidth, height: Self.minWindowHeight)
        window.delegate = self
        window.contentViewController = hostingController

        WindowDraggingPolicy.apply(to: window)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.isOpaque = false
        window.backgroundColor = .codexWindowBackground
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        window.hasShadow = true
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(type)?.isHidden = false
        }
        window.center()
    }

    public func show(on screen: NSScreen? = nil) {
        let targetScreen = screen ?? window.screen ?? NSScreen.main
        let idealSize = Self.defaultWindowSize(for: targetScreen)

        if !window.isVisible || window.frame.height < idealSize.height {
            window.setContentSize(idealSize)
        }

        if let targetScreen {
            let visible = targetScreen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2
            ))
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    public func close() {
        window.orderOut(nil)
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide window instead of deallocating so Gateway supervisor continues running
        window.orderOut(nil)
        return false
    }

    public func windowDidResize(_ notification: Notification) {
        var frame = window.frame
        var needsResize = false
        if frame.width < Self.minWindowWidth {
            frame.size.width = Self.minWindowWidth
            needsResize = true
        }
        if frame.height < Self.minWindowHeight {
            frame.size.height = Self.minWindowHeight
            needsResize = true
        }
        if needsResize {
            window.setFrame(frame, display: true)
        }
    }
}
