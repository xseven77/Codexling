import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let popoverWidth: CGFloat = 414
    private let preferredPopoverHeight: CGFloat = 720
    private let minimumPopoverHeight: CGFloat = 600
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let hostingController: NSHostingController<UsagePopoverView>
    private let store: UsageSnapshotStore

    init(store: UsageSnapshotStore, settings: AppSettingsStore, actions: UsageActions) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        hostingController = NSHostingController(
            rootView: UsagePopoverView(store: store, settings: settings, actions: actions)
        )
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: popoverWidth, height: 1)
        hostingController.sizingOptions = [.intrinsicContentSize]
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.isOpaque = false
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        popover.contentViewController = hostingController

        statusItem.isVisible = true
        configureStatusButton()
        refreshStatusTitle()
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else {
            DispatchQueue.main.async { [weak self] in
                self?.configureStatusButton()
                self?.refreshStatusTitle()
            }
            return
        }

        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])
    }

    func refreshStatusTitle() {
        guard let button = statusItem.button else {
            DispatchQueue.main.async { [weak self] in
                self?.refreshStatusTitle()
            }
            return
        }

        let snapshot = store.snapshot
        let text = store.isLoggedIn
            ? "  Codex 5h \(snapshot.shortWindow.percentText) · 周 \(snapshot.weekly.percentText)  "
            : "  Codex 未登录  "
        let health = QuotaHealthLevel.from(shortWindow: snapshot.shortWindow, isLoggedIn: store.isLoggedIn)
        let statusColor = health.nsColor
        let attributedTitle = NSMutableAttributedString(
            string: "●",
            attributes: [
                .foregroundColor: statusColor,
                .font: NSFont.systemFont(ofSize: 12, weight: .bold)
            ]
        )

        attributedTitle.append(NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
            ]
        ))

        button.attributedTitle = attributedTitle

        if popover.isShown {
            schedulePopoverSizeUpdate()
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            updatePopoverSize(relativeTo: sender)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            DispatchQueue.main.async { [weak self] in
                self?.applyPopoverWindowAppearance()
                self?.popover.contentViewController?.view.window?.makeKey()
            }
        }
    }

    private func applyPopoverWindowAppearance() {
        guard let window = popover.contentViewController?.view.window else { return }

        window.isOpaque = false
        // Dynamic NSColor follows system appearance; avoid freezing a resolved CGColor on the layer.
        window.backgroundColor = NSColor.codexPopoverChrome
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.isOpaque = false
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.isOpaque = false
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    private func schedulePopoverSizeUpdate() {
        // Wait one run loop so SwiftUI finishes layout after snapshot changes.
        DispatchQueue.main.async { [weak self] in
            self?.updatePopoverSize(relativeTo: self?.statusItem.button)
        }
    }

    private func updatePopoverSize(relativeTo button: NSStatusBarButton? = nil) {
        let screenHeight = button?.window?.screen?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height
            ?? preferredPopoverHeight
        let maxPopoverHeight = max(minimumPopoverHeight, screenHeight - 112)
        let targetHeight = min(preferredPopoverHeight, maxPopoverHeight)

        popover.contentSize = NSSize(
            width: popoverWidth,
            height: targetHeight
        )
    }
}

extension NSColor {
    static let codexPopoverChrome = NSColor.codexDynamic(
        light: (0.902, 0.906, 0.910, 1),
        dark: (0.145, 0.145, 0.155, 1)
    )

    static let codexWindowBackground = NSColor.codexDynamic(
        light: (0.957, 0.957, 0.957, 1),
        dark: (0.118, 0.118, 0.128, 1)
    )
}
