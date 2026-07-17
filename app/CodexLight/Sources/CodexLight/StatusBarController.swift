import AppKit
import CoreText
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let popoverWidth: CGFloat = 414
    private let popoverViewportMargin: CGFloat = 28
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var hostingController: NSHostingController<UsagePopoverView>!
    private let store: UsageSnapshotStore
    private let settings: AppSettingsStore
    private let activityStore: CodexActivityStore
    private let animationPlayer = PetAnimationPlayer()
    private let hoverPanel = PetHoverPanelController()
    private var capsuleView: StatusCapsuleView?
    private var pendingHoverWorkItem: DispatchWorkItem?

    init(
        store: UsageSnapshotStore,
        settings: AppSettingsStore,
        activityStore: CodexActivityStore,
        updater: AppUpdateController,
        actions: UsageActions
    ) {
        self.store = store
        self.settings = settings
        self.activityStore = activityStore
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        super.init()

        hostingController = NSHostingController(
            rootView: UsagePopoverView(
                store: store,
                settings: settings,
                updater: updater,
                actions: actions,
                onLayoutChanged: { [weak self] in self?.schedulePopoverSizeUpdate() }
            )
        )

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: popoverWidth, height: 1)
        hostingController.sizingOptions = [.intrinsicContentSize]
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.isOpaque = false
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        popover.contentViewController = hostingController

        statusItem.isVisible = true
        animationPlayer.onFrame = { [weak self] image in
            self?.applyPetFrame(image)
        }
        configureStatusButton()
        refreshStatusTitle()
    }

    func refreshThemeAppearance() {
        applyPopoverWindowAppearance()
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

        button.target = nil
        button.action = nil
        button.image = nil
        button.attributedTitle = NSAttributedString(string: "")
        button.isBordered = false
        button.showsBorderOnlyWhileMouseInside = false
        button.focusRingType = .none
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.clear.cgColor
        if let cell = button.cell as? NSButtonCell {
            cell.highlightsBy = []
            cell.showsStateBy = []
            cell.focusRingType = .none
        }

        if capsuleView == nil {
            let view = StatusCapsuleView(frame: button.bounds)
            view.autoresizingMask = [.width, .height]
            view.onClick = { [weak self] in
                guard let self, let button = self.statusItem.button else { return }
                self.togglePopover(button)
            }
            view.onMouseEntered = { [weak self] in self?.scheduleHoverPanel() }
            view.onMouseExited = { [weak self] in self?.hideHoverPanel() }
            button.addSubview(view)
            capsuleView = view
        }
    }

    func refreshStatusTitle() {
        guard let button = statusItem.button else {
            DispatchQueue.main.async { [weak self] in
                self?.refreshStatusTitle()
            }
            return
        }

        let snapshot = store.snapshot
        let quotaText: String = if store.isLoggedIn {
            snapshot.hasShortWindow
                ? "5h \(snapshot.primaryWindow.percentText) · 周 \(snapshot.weekly.percentText)"
                : "周 \(snapshot.weekly.percentText)"
        } else {
            "未登录"
        }

        let activityState = activityStore.snapshot.state
        let background = settings.petBackgroundColor.resolved(for: activityState)
        let compactText = activityState.statusBarText.map {
            "\($0)\u{2009}·\u{2009}\(quotaText)"
        } ?? quotaText

        if settings.petsEnabled, let pet = settings.selectedPet {
            animationPlayer.setPet(pet)
            animationPlayer.setState(activityState.petAnimationState)
            capsuleView?.update(
                background: background,
                text: compactText,
                foregroundColor: background.foregroundColor,
                showsPet: true,
                healthColor: nil
            )
        } else {
            animationPlayer.setPet(nil)
            let health = QuotaHealthLevel.from(
                window: snapshot.primaryWindow,
                isLoggedIn: store.isLoggedIn
            )
            capsuleView?.petImage = nil
            capsuleView?.update(
                background: background,
                text: compactText,
                foregroundColor: background.foregroundColor,
                showsPet: false,
                healthColor: health.nsColor
            )
        }
        if let capsuleView {
            statusItem.length = capsuleView.preferredWidth
        }

        updateHoverContent(button: button)

        if popover.isShown {
            schedulePopoverSizeUpdate()
        }
    }

    private func applyPetFrame(_ image: NSImage?) {
        guard settings.petsEnabled, settings.selectedPet != nil,
              statusItem.button != nil else { return }
        image?.isTemplate = false
        capsuleView?.petImage = image.map(StatusPetBadgeRenderer.render)
        hoverPanel.updatePetFrame(image)
    }

    private func updateHoverContent(button: NSStatusBarButton) {
        let activity = activityStore.snapshot
        let countText = activity.activeTaskCount > 0
            ? "\(activity.activeTaskCount) 个活跃任务"
            : "没有活跃任务"
        let stateText = activity.state.statusBarText ?? "空闲"
        hoverPanel.update(
            title: activity.hoverDisplayTitle,
            detail: activity.hoverSubtitle,
            meta: "\(stateText) · \(countText)"
        )
        button.toolTip = nil
    }

    private func scheduleHoverPanel() {
        pendingHoverWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let button = self.statusItem.button, !self.popover.isShown else { return }
            self.hoverPanel.show(relativeTo: button)
        }
        pendingHoverWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private func hideHoverPanel() {
        pendingHoverWorkItem?.cancel()
        pendingHoverWorkItem = nil
        hoverPanel.hide()
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        hideHoverPanel()
        sender.highlight(false)
        if popover.isShown {
            popover.performClose(sender)
        } else {
            updatePopoverSize(relativeTo: sender)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            DispatchQueue.main.async { [weak self] in
                sender.highlight(false)
                self?.applyPopoverWindowAppearance()
                self?.popover.contentViewController?.view.window?.makeKey()
            }
        }
    }

    private func applyPopoverWindowAppearance() {
        guard let window = popover.contentViewController?.view.window else { return }

        window.appearance = settings.theme.nsAppearance
        window.isOpaque = false
        // Dynamic NSColor follows system appearance; avoid freezing a resolved CGColor on the layer.
        window.backgroundColor = .clear
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
            ?? 720
        hostingController.view.invalidateIntrinsicContentSize()
        hostingController.view.layoutSubtreeIfNeeded()
        let intrinsicHeight = hostingController.view.intrinsicContentSize.height
        let measuredHeight = intrinsicHeight > 0 && intrinsicHeight.isFinite
            ? intrinsicHeight
            : DetachedWindowMetrics.minHeight
        let targetHeight = PopoverMetrics.targetHeight(
            contentHeight: measuredHeight,
            visibleHeight: screenHeight,
            margin: popoverViewportMargin,
            minimumHeight: DetachedWindowMetrics.minHeight
        )

        popover.contentSize = NSSize(
            width: popoverWidth,
            height: targetHeight
        )
    }
}

enum PopoverMetrics {
    static func targetHeight(
        contentHeight: CGFloat,
        visibleHeight: CGFloat,
        margin: CGFloat,
        minimumHeight: CGFloat
    ) -> CGFloat {
        let viewportHeight = max(1, visibleHeight - margin)
        return min(max(contentHeight, minimumHeight), viewportHeight)
    }
}

enum StatusPetBadgeRenderer {
    static let size = NSSize(width: 23, height: 23)

    static func render(_ petImage: NSImage) -> NSImage {
        let result = NSImage(size: size)
        result.lockFocus()
        defer { result.unlockFocus() }

        let badgeRect = NSRect(x: 1.5, y: 1.5, width: 20, height: 20)
        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 7, yRadius: 7)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.08)
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.set()
        NSColor.white.withAlphaComponent(0.72).setFill()
        badgePath.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.48).setStroke()
        badgePath.lineWidth = 0.6
        badgePath.stroke()

        NSGraphicsContext.current?.imageInterpolation = .none
        let maxPetSize = NSSize(width: 18, height: 17)
        let scale = min(
            maxPetSize.width / max(petImage.size.width, 1),
            maxPetSize.height / max(petImage.size.height, 1)
        )
        let petSize = NSSize(
            width: petImage.size.width * scale,
            height: petImage.size.height * scale
        )
        let petRect = NSRect(
            x: (size.width - petSize.width) / 2,
            y: (size.height - petSize.height) / 2,
            width: petSize.width,
            height: petSize.height
        )
        petImage.draw(in: petRect, from: .zero, operation: .sourceOver, fraction: 1)
        result.isTemplate = false
        return result
    }
}

final class StatusCapsuleView: NSView {
    private static let leadingPadding: CGFloat = 0.5
    private static let trailingPadding: CGFloat = 5
    private static let contentGap: CGFloat = 3
    private static let dotSize: CGFloat = 9
    private static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)

    var onClick: (() -> Void)?
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    var petImage: NSImage? {
        didSet { needsDisplay = true }
    }

    private var background = StatusBarPetBackgroundColor.neutral
    private var text = ""
    private var foregroundColor = NSColor.labelColor
    private var showsPet = true
    private var healthColor: NSColor?
    private var isPressed = false
    private var trackingAreaReference: NSTrackingArea?

    var preferredWidth: CGFloat {
        let textWidth = ceil(attributedText.size().width)
        let indicatorWidth = showsPet ? StatusPetBadgeRenderer.size.width : Self.dotSize
        return Self.leadingPadding
            + indicatorWidth
            + Self.contentGap
            + textWidth
            + Self.trailingPadding
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:))))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        background: StatusBarPetBackgroundColor,
        text: String,
        foregroundColor: NSColor,
        showsPet: Bool,
        healthColor: NSColor?
    ) {
        self.background = background
        self.text = text
        self.foregroundColor = foregroundColor
        self.showsPet = showsPet
        self.healthColor = healthColor
        setAccessibilityLabel("Codex \(text)")
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let outerRect = bounds.insetBy(dx: 0.25, dy: 0.25)
        let outerPath = NSBezierPath(roundedRect: outerRect, xRadius: 7, yRadius: 7)
        background.nsColor.setFill()
        outerPath.fill()
        NSColor.white.withAlphaComponent(background == .neutral ? 0.14 : 0.30).setStroke()
        outerPath.lineWidth = background == .neutral ? 0.45 : 0.55
        outerPath.stroke()
        if isPressed {
            NSColor.white.withAlphaComponent(0.16).setFill()
            outerPath.fill()
        }

        let indicatorWidth: CGFloat
        if showsPet, let petImage {
            indicatorWidth = StatusPetBadgeRenderer.size.width
            let imageRect = NSRect(
                x: Self.leadingPadding,
                y: (bounds.height - StatusPetBadgeRenderer.size.height) / 2,
                width: StatusPetBadgeRenderer.size.width,
                height: StatusPetBadgeRenderer.size.height
            )
            petImage.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            indicatorWidth = Self.dotSize
            let dotRect = NSRect(
                x: Self.leadingPadding,
                y: (bounds.height - Self.dotSize) / 2,
                width: Self.dotSize,
                height: Self.dotSize
            )
            (healthColor ?? NSColor.secondaryLabelColor).setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }

        let title = attributedText
        let line = CTLineCreateWithAttributedString(title)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let baselineY = round(bounds.midY - (ascent - descent) / 2)
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.textMatrix = .identity
            context.textPosition = CGPoint(
                x: Self.leadingPadding + indicatorWidth + Self.contentGap,
                y: baselineY
            )
            CTLineDraw(line, context)
            context.restoreGState()
        }
    }

    private var attributedText: NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: foregroundColor,
                .font: Self.font
            ]
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        isPressed = false
        needsDisplay = true
        onMouseExited?()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        needsDisplay = true
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }

    @objc private func handleClick(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        onClick?()
    }
}

@MainActor
private final class PetHoverPanelController {
    private static let cardSize = NSSize(width: 340, height: 112)
    private static let shadowInset: CGFloat = 10
    private let panel: NSPanel
    private let model = PetHoverViewModel()

    init() {
        let panelSize = NSSize(
            width: Self.cardSize.width + Self.shadowInset * 2,
            height: Self.cardSize.height + Self.shadowInset * 2
        )
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The system shadow follows the rectangular panel bounds and leaves dark,
        // square corners around a rounded visual-effect view. Draw one controlled
        // shadow around the rounded card instead.
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.transient, .canJoinAllSpaces, .fullScreenAuxiliary]

        let hoverView = PetHoverContentView(
            model: model,
            cardSize: Self.cardSize,
            shadowInset: Self.shadowInset
        )
        let hostingView = NSHostingView(rootView: hoverView)
        hostingView.frame = NSRect(origin: .zero, size: panelSize)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
    }

    func update(title: String, detail: String, meta: String) {
        model.title = title
        model.detail = detail
        model.meta = meta
    }

    func updatePetFrame(_ image: NSImage?) {
        model.petFrame = image
    }

    func show(relativeTo button: NSStatusBarButton) {
        guard let window = button.window else { return }
        let rectInWindow = button.convert(button.bounds, to: nil)
        let anchor = window.convertToScreen(rectInWindow)
        let size = panel.frame.size
        let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var x = anchor.midX - size.width / 2
        x = min(max(x, screenFrame.minX + 8), screenFrame.maxX - size.width - 8)
        let y = anchor.minY - size.height + Self.shadowInset - 7
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

@MainActor
@Observable
private final class PetHoverViewModel {
    var title = ""
    var detail = ""
    var meta = ""
    var petFrame: NSImage?
}

private struct PetHoverContentView: View {
    @Bindable var model: PetHoverViewModel
    let cardSize: NSSize
    let shadowInset: CGFloat

    var body: some View {
        glassSurface
            .padding(shadowInset)
            .frame(
                width: cardSize.width + shadowInset * 2,
                height: cardSize.height + shadowInset * 2
            )
            .background(Color.clear)
    }

    @ViewBuilder
    private var glassSurface: some View {
        if #available(macOS 26.0, *) {
            cardContent
                .glassEffect(in: .rect(cornerRadius: 16))
        } else {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            cardContent
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.stroke(Color.white.opacity(0.42), lineWidth: 0.8)
                }
                .shadow(color: Color.black.opacity(0.08), radius: 9, x: 0, y: 3)
        }
    }

    private var cardContent: some View {
        HStack(spacing: 13) {
            if let petFrame = model.petFrame {
                Image(nsImage: petFrame)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 58, height: 68)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.codexPrimary)
                    .frame(width: 58, height: 68)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(model.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.codexInk)
                    .lineLimit(1)
                Text(model.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(2)
                Text(model.meta)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.codexMuted.opacity(0.72))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 13)
        .frame(width: cardSize.width, height: cardSize.height)
    }
}

extension NSColor {
    static let codexPopoverChrome = NSColor.codexDynamic(
        light: (0.902, 0.906, 0.910, 1),
        dark: (0.118, 0.118, 0.122, 1)
    )

    static let codexWindowBackground = NSColor.codexDynamic(
        light: (0.957, 0.957, 0.957, 1),
        dark: (0.118, 0.118, 0.122, 1)
    )
}
