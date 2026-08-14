import AppKit
import SwiftUI

// MARK: - 显示器红边预览

/// 选择显示器时，在目标屏幕边缘闪烁红边提示。
@MainActor
final class ScreenHighlightOverlay {
    private var activePanels: [NSPanel] = []

    func flash(on screen: NSScreen) {
        clearAll()
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: screen.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.contentViewController = NSHostingController(rootView: RedBorderView())
        panel.alphaValue = 0
        panel.setFrame(screen.frame, display: false)
        panel.orderFrontRegardless()
        activePanels.append(panel)

        panel.animator().alphaValue = 1

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            panel.animator().alphaValue = 0
            try? await Task.sleep(nanoseconds: 260_000_000)
            panel.orderOut(nil)
            self?.activePanels.removeAll { $0 === panel }
        }
    }

    func clearAll() {
        for panel in activePanels {
            panel.orderOut(nil)
        }
        activePanels.removeAll()
    }
}

private struct RedBorderView: View {
    var body: some View {
        Rectangle()
            .strokeBorder(Color.red, lineWidth: 6)
    }
}

// MARK: - 降级胶囊面板（非目标屏幕顶部居中悬浮胶囊）

@MainActor
final class LegacyCapsulePanelController {
    private let panel: NSPanel
    private let hosting: NSHostingController<LegacyCapsuleView>
    var onClick: (() -> Void)?

    init() {
        hosting = NSHostingController(rootView: LegacyCapsuleView())
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 30),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .statusBar
    }

    func update(text: String, indicatorColor: NSColor, showsWave: Bool) {
        hosting.rootView = LegacyCapsuleView(
            text: text,
            indicatorColor: indicatorColor,
            showsWave: showsWave,
            onClick: { [weak self] in self?.onClick?() }
        )
        // 固定尺寸，防止 NSHostingController 按空内容 fittingSize 把窗口缩成 38×26。
        panel.setContentSize(NSSize(width: 240, height: 30))
    }

    func show(on screen: NSScreen) {
        let size = NSSize(width: 240, height: 30)
        panel.setFrame(
            NSRect(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.maxY - 38,
                width: size.width,
                height: size.height
            ),
            display: false
        )
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private struct LegacyCapsuleView: View {
    var text: String = ""
    var indicatorColor: NSColor = .secondaryLabelColor
    var showsWave = false
    var onClick: (() -> Void)?

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color(nsColor: indicatorColor))
                .frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.black.opacity(0.78))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(Color.white.opacity(0.92), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
        .overlay {
            if showsWave {
                Capsule().strokeBorder(Color(nsColor: indicatorColor).opacity(0.6), lineWidth: 1)
            }
        }
        .contentShape(Capsule())
        .onTapGesture { onClick?() }
    }
}
