import AppKit
import CoreText
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let store: UsageSnapshotStore
    private let settings: AppSettingsStore
    private let activityStore: CodexActivityStore
    private let frameStore: PetFrameStore
    private let companionStatsStore: CompanionStatsStore
    private let actions: UsageActions
    private let hoverPanel = PetHoverPanelController()
    private var capsuleView: StatusCapsuleView?
    private var pendingHoverWorkItem: DispatchWorkItem?
    private var pendingHoverHideWorkItem: DispatchWorkItem?
    private var hoverSafeTriangle: HoverSafeTriangle?
    private var hoverSafeTriangleTimer: Timer?
    private var hoverSafeTriangleDeadline: Date?

    init(
        store: UsageSnapshotStore,
        settings: AppSettingsStore,
        activityStore: CodexActivityStore,
        frameStore: PetFrameStore,
        companionStatsStore: CompanionStatsStore,
        actions: UsageActions
    ) {
        self.store = store
        self.settings = settings
        self.activityStore = activityStore
        self.frameStore = frameStore
        self.companionStatsStore = companionStatsStore
        self.actions = actions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        hoverPanel.onMouseEntered = { [weak self] in
            self?.cancelHoverPanelHide()
        }
        hoverPanel.onMouseExited = { [weak self] in
            guard let self else { return }
            guard let statusFrame = self.statusCapsuleScreenFrame else {
                self.scheduleHoverPanelHide()
                return
            }
            self.scheduleHoverPanelHide(
                from: NSEvent.mouseLocation,
                toward: statusFrame
            )
        }
        hoverPanel.onClick = { [weak self] in
            self?.hideHoverPanel()
            actions.openDetachedWindow()
        }

        statusItem.isVisible = true
        frameStore.onFrameChanged = { [weak self] in
            self?.refreshPetFrame()
        }
        configureStatusButton()
        refreshStatusTitle()
    }

    func refreshThemeAppearance() {
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
                guard let self else { return }
                self.hideHoverPanel()
                self.actions.openDetachedWindow()
            }
            view.onMouseEntered = { [weak self] in self?.scheduleHoverPanel() }
            view.onMouseExited = { [weak self] in
                guard let self, self.hoverPanel.isVisible else {
                    self?.scheduleHoverPanelHide()
                    return
                }
                self.scheduleHoverPanelHide(
                    from: NSEvent.mouseLocation,
                    toward: self.hoverPanel.interactionFrame
                )
            }
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
        let quotaText = statusBarQuotaText(snapshot: snapshot, isLoggedIn: store.isLoggedIn)

        let activityState = activityStore.snapshot.state
        let health = QuotaHealthLevel.from(
            window: snapshot.primaryWindow,
            isLoggedIn: store.isLoggedIn
        )
        let background = settings.petBackgroundColor.resolved(for: health)
        let showsWave = settings.statusBarWaveEnabled
            && activityState != .idle
            && activityState != .unavailable
        let cornerRatio = CGFloat(settings.statusBarCornerPercent / 100)
        let compactText = activityState.statusBarText.map {
            "\($0)·\(quotaText)"
        } ?? quotaText

        // The final design reserves the leading dot for task state. Pet
        // animation remains available in the main window and hover card.
        capsuleView?.petImage = nil
        capsuleView?.update(
            background: background,
            text: compactText,
            foregroundColor: background.foregroundColor,
            showsPet: false,
            indicatorColor: activityState.statusNSColor,
            showsWave: showsWave,
            cornerRatio: cornerRatio
        )
        if let capsuleView {
            statusItem.length = capsuleView.preferredWidth
        }

        updateHoverContent(button: button)

    }

    private func refreshPetFrame() {
        // Hover always shows the selected Pet. The retired visibility toggle
        // must not leave existing users with the placeholder icon.
        let image = frameStore.currentFrame
        image?.isTemplate = false
        hoverPanel.updatePetFrame(image)
    }

    private func updateHoverContent(button: NSStatusBarButton) {
        guard store.isLoggedIn else {
            hoverPanel.update(
                title: "登录以查看 Codex 用量",
                detail: "连接 ChatGPT 账号后，即可查看额度与任务状态",
                meta: "点击打开窗口并登录"
            )
            button.toolTip = nil
            return
        }

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
        cancelHoverPanelHide()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let button = self.statusItem.button else { return }
            self.hoverPanel.show(relativeTo: button)
        }
        pendingHoverWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private func hideHoverPanel() {
        pendingHoverWorkItem?.cancel()
        pendingHoverWorkItem = nil
        cancelHoverPanelHide()
        hoverPanel.hide()
    }

    private func scheduleHoverPanelHide(
        from departurePoint: NSPoint? = nil,
        toward targetFrame: NSRect? = nil
    ) {
        if let departurePoint, let targetFrame, hoverPanel.isVisible {
            beginSafeTriangleTracking(from: departurePoint, toward: targetFrame)
            return
        }

        pendingHoverWorkItem?.cancel()
        pendingHoverWorkItem = nil
        pendingHoverHideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingHoverHideWorkItem = nil
            guard !self.pointerIsInsidePersistentHoverRegion() else { return }
            self.hoverPanel.hide()
        }
        pendingHoverHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
    }

    private func cancelHoverPanelHide() {
        pendingHoverHideWorkItem?.cancel()
        pendingHoverHideWorkItem = nil
        hoverSafeTriangleTimer?.invalidate()
        hoverSafeTriangleTimer = nil
        hoverSafeTriangle = nil
        hoverSafeTriangleDeadline = nil
    }

    private func beginSafeTriangleTracking(from departurePoint: NSPoint, toward targetFrame: NSRect) {
        cancelHoverPanelHide()
        hoverSafeTriangle = HoverSafeTriangle(
            origin: departurePoint,
            targetFrame: targetFrame,
            buffer: 8
        )
        // Avoid keeping the card alive forever if the pointer stops in the gap.
        hoverSafeTriangleDeadline = Date().addingTimeInterval(2)
        let timer = Timer(
            timeInterval: 1.0 / 60.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateSafeTrianglePointer()
            }
        }
        hoverSafeTriangleTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func evaluateSafeTrianglePointer() {
        let pointer = NSEvent.mouseLocation
        if pointerIsInsidePersistentHoverRegion(pointer) {
            return
        }

        if let hoverSafeTriangle,
           let hoverSafeTriangleDeadline,
           Date() < hoverSafeTriangleDeadline,
           hoverSafeTriangle.contains(pointer) {
            return
        }

        hideHoverPanel()
    }

    private func pointerIsInsidePersistentHoverRegion(
        _ pointer: NSPoint = NSEvent.mouseLocation
    ) -> Bool {
        if hoverPanel.isVisible, hoverPanel.interactionFrame.contains(pointer) {
            return true
        }

        return statusCapsuleScreenFrame?.contains(pointer) == true
    }

    private var statusCapsuleScreenFrame: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        let rectInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(rectInWindow)
    }

}

func statusBarQuotaText(snapshot: CodexUsageSnapshot, isLoggedIn: Bool) -> String {
    guard isLoggedIn else { return "未登录" }

    guard snapshot.hasShortWindow || snapshot.hasWeeklyWindow else { return "无额度" }

    if snapshot.hasShortWindow {
        let primaryText = "\(statusBarWindowLabel(snapshot.primaryWindow.label)) \(snapshot.primaryWindow.percentText)"
        return snapshot.hasWeeklyWindow
            ? "\(primaryText)·\(statusBarWindowLabel(snapshot.weekly.label)) \(snapshot.weekly.percentText)"
            : primaryText
    }

    return "\(statusBarWindowLabel(snapshot.weekly.label)) \(snapshot.weekly.percentText)"
}

func statusBarWindowLabel(_ label: String) -> String {
    switch label {
    case "5 小时":
        "5h"
    case "周额度":
        "周"
    default:
        label.replacingOccurrences(of: " ", with: "")
    }
}

struct HoverSafeTriangle {
    private let corners: [CGPoint]
    private let expandedTarget: CGRect

    init(origin: CGPoint, targetFrame: CGRect, buffer: CGFloat = 0) {
        let expandedTarget = targetFrame.insetBy(dx: -buffer, dy: -buffer)
        self.expandedTarget = expandedTarget

        if targetFrame.midY < origin.y {
            // Target is below: create a buffered trapezoid to its upper edge.
            corners = [
                CGPoint(x: origin.x - buffer, y: origin.y + buffer),
                CGPoint(x: origin.x + buffer, y: origin.y + buffer),
                CGPoint(x: expandedTarget.maxX, y: expandedTarget.maxY),
                CGPoint(x: expandedTarget.minX, y: expandedTarget.maxY)
            ]
        } else {
            // Target is above: mirror the same buffered corridor upward.
            corners = [
                CGPoint(x: origin.x - buffer, y: origin.y - buffer),
                CGPoint(x: expandedTarget.minX, y: expandedTarget.minY),
                CGPoint(x: expandedTarget.maxX, y: expandedTarget.minY),
                CGPoint(x: origin.x + buffer, y: origin.y - buffer)
            ]
        }
    }

    func contains(_ point: CGPoint) -> Bool {
        if expandedTarget.contains(point) { return true }

        var hasNegative = false
        var hasPositive = false
        for index in corners.indices {
            let first = corners[index]
            let second = corners[(index + 1) % corners.count]
            let area = signedArea(point, first, second)
            hasNegative = hasNegative || area < 0
            hasPositive = hasPositive || area > 0
            if hasNegative && hasPositive { return false }
        }
        return true
    }

    private func signedArea(_ point: CGPoint, _ first: CGPoint, _ second: CGPoint) -> CGFloat {
        (point.x - second.x) * (first.y - second.y)
            - (first.x - second.x) * (point.y - second.y)
    }
}

enum StatusPetBadgeRenderer {
    // Match the 22pt macOS status bar for a zero-inset comparison.
    static let size = NSSize(width: 22, height: 22)

    static func render(_ petImage: NSImage, cornerRatio: CGFloat = 0.5) -> NSImage {
        let result = NSImage(size: size)
        result.lockFocus()
        defer { result.unlockFocus() }

        let resolvedCornerRatio = min(max(cornerRatio, 0.2), 0.5)
        let badgeRect = NSRect(origin: .zero, size: size).insetBy(dx: 0.25, dy: 0.25)
        let badgePath = NSBezierPath(
            roundedRect: badgeRect,
            xRadius: badgeRect.height * resolvedCornerRatio,
            yRadius: badgeRect.height * resolvedCornerRatio
        )
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
        let maxPetSize = NSSize(width: 16, height: 15)
        let scale = min(
            maxPetSize.width / max(petImage.size.width, 1),
            maxPetSize.height / max(petImage.size.height, 1)
        )
        let petSize = NSSize(
            width: petImage.size.width * scale,
            height: petImage.size.height * scale
        )
        // Center the complete source frame without compensating for transparent
        // pixels inside an individual Pet asset.
        let petRect = centeredRect(
            contentSize: petSize,
            in: NSRect(origin: .zero, size: size)
        )
        NSBezierPath(
            roundedRect: petRect,
            xRadius: min(petRect.width, petRect.height) * resolvedCornerRatio,
            yRadius: min(petRect.width, petRect.height) * resolvedCornerRatio
        ).addClip()
        petImage.draw(in: petRect, from: .zero, operation: .sourceOver, fraction: 1)
        result.isTemplate = false
        return result
    }

    static func centeredRect(contentSize: NSSize, in container: NSRect) -> NSRect {
        NSRect(
            x: container.midX - contentSize.width / 2,
            y: container.midY - contentSize.height / 2,
            width: contentSize.width,
            height: contentSize.height
        )
    }
}

final class StatusCapsuleView: NSView {
    private static let leadingPadding: CGFloat = 7.5
    private static let indicatorTextGap: CGFloat = 8
    private static let trailingPadding: CGFloat = 10
    private static let inlineContentGap: CGFloat = 4
    private static let dotSize: CGFloat = 8
    private static let capsuleHeight: CGFloat = 24
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
    private var indicatorColor: NSColor?
    private var showsWave = false
    private var cornerRatio: CGFloat = 0.5
    private var isPressed = false
    private var isTrackingPress = false
    private var lastClickTimestamp: TimeInterval = -.infinity
    private var trackingAreaReference: NSTrackingArea?
    private var waveTimer: Timer?
    private var waveStartTime = ProcessInfo.processInfo.systemUptime

    var preferredWidth: CGFloat {
        let textWidth = ceil(attributedText.size().width)
        let indicatorWidth = showsPet ? StatusPetBadgeRenderer.size.width : Self.dotSize
        return indicatorPadding
            + indicatorWidth
            + Self.indicatorTextGap
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
        indicatorColor: NSColor?,
        showsWave: Bool,
        cornerRatio: CGFloat
    ) {
        self.background = background
        self.text = text
        self.foregroundColor = foregroundColor
        self.showsPet = showsPet
        self.indicatorColor = indicatorColor
        let waveVisibilityChanged = self.showsWave != showsWave
        self.showsWave = showsWave
        self.cornerRatio = min(max(cornerRatio, 0.2), 0.5)
        if waveVisibilityChanged {
            updateWaveAnimation()
        }
        setAccessibilityLabel("Codex \(text)")
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let outerRect = NSRect(
            x: 0.25,
            y: bounds.midY - Self.capsuleHeight / 2 + 0.25,
            width: max(0, bounds.width - 0.5),
            height: Self.capsuleHeight - 0.5
        )
        let outerPath = NSBezierPath(
            roundedRect: outerRect,
            xRadius: outerRect.height * cornerRatio,
            yRadius: outerRect.height * cornerRatio
        )
        background.nsColor.setFill()
        outerPath.fill()
        drawWave(clippedTo: outerPath)
        if isPressed {
            NSColor.black.withAlphaComponent(background == .neutral ? 0.13 : 0.17).setFill()
            outerPath.fill()
        }
        let borderColor = isPressed
            ? NSColor.black.withAlphaComponent(0.20)
            : NSColor.white.withAlphaComponent(background == .neutral ? 0.14 : 0.30)
        borderColor.setStroke()
        outerPath.lineWidth = isPressed ? 0.9 : (background == .neutral ? 0.45 : 0.55)
        outerPath.stroke()

        if isPressed {
            let insetRect = outerRect.insetBy(dx: 0.75, dy: 0.75)
            let insetPath = NSBezierPath(
                roundedRect: insetRect,
                xRadius: insetRect.height * cornerRatio,
                yRadius: insetRect.height * cornerRatio
            )
            NSColor.black.withAlphaComponent(0.08).setStroke()
            insetPath.lineWidth = 0.7
            insetPath.stroke()
        }

        let indicatorWidth: CGFloat
        if showsPet, let petImage {
            indicatorWidth = StatusPetBadgeRenderer.size.width
            let imageRect = NSRect(
                x: indicatorPadding,
                y: bounds.midY - StatusPetBadgeRenderer.size.height / 2,
                width: StatusPetBadgeRenderer.size.width,
                height: StatusPetBadgeRenderer.size.height
            )
            petImage.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            indicatorWidth = Self.dotSize
            let dotRect = NSRect(
                x: indicatorPadding,
                y: (bounds.height - Self.dotSize) / 2,
                width: Self.dotSize,
                height: Self.dotSize
            )
            let haloPath = NSBezierPath(ovalIn: dotRect.insetBy(dx: -1.2, dy: -1.2))
            NSColor.white.withAlphaComponent(0.58).setFill()
            haloPath.fill()

            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = NSColor.white.withAlphaComponent(0.72)
            glow.shadowBlurRadius = 2.2
            glow.shadowOffset = .zero
            glow.set()
            (indicatorColor ?? NSColor.secondaryLabelColor).setFill()
            let dotPath = NSBezierPath(ovalIn: dotRect)
            dotPath.fill()
            NSGraphicsContext.restoreGraphicsState()

            NSColor.white.withAlphaComponent(0.88).setStroke()
            dotPath.lineWidth = 0.7
            dotPath.stroke()
        }

        let title = attributedText
        let line = CTLineCreateWithAttributedString(title)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        if let context = NSGraphicsContext.current?.cgContext {
            let imageBounds = CTLineGetImageBounds(line, context)
            let visualMidY = imageBounds.isNull || imageBounds.height <= 0
                ? (ascent - descent) / 2
                : imageBounds.midY
            let unsnappedBaselineY = bounds.midY - visualMidY
            let backingScale = window?.backingScaleFactor
                ?? NSScreen.main?.backingScaleFactor
                ?? 2
            let baselineY = (unsnappedBaselineY * backingScale).rounded() / backingScale

            context.saveGState()
            context.textMatrix = .identity
            context.textPosition = CGPoint(
                x: indicatorPadding + indicatorWidth + Self.indicatorTextGap,
                y: baselineY
            )
            CTLineDraw(line, context)
            context.restoreGState()
        }
    }

    private var attributedText: NSAttributedString {
        let result = NSMutableAttributedString(
            string: text,
            attributes: [
                .foregroundColor: foregroundColor,
                .font: Self.font
            ]
        )
        let source = text as NSString
        var searchRange = NSRange(location: 0, length: source.length)
        while searchRange.length > 0 {
            let separator = source.range(of: "·", options: [], range: searchRange)
            guard separator.location != NSNotFound else { break }

            if separator.location > 0 {
                let precedingCharacter = source.rangeOfComposedCharacterSequence(
                    at: separator.location - 1
                )
                result.addAttribute(.kern, value: Self.inlineContentGap, range: precedingCharacter)
            }
            result.addAttribute(.kern, value: Self.inlineContentGap, range: separator)

            let nextLocation = NSMaxRange(separator)
            searchRange = NSRange(location: nextLocation, length: source.length - nextLocation)
        }
        return result
    }

    private var indicatorPadding: CGFloat {
        if showsPet {
            // Match the leading inset to the centered top and bottom insets.
            return max(0, (bounds.height - StatusPetBadgeRenderer.size.height) / 2)
        }
        return Self.leadingPadding
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateWaveAnimation()
    }

    private func updateWaveAnimation() {
        waveTimer?.invalidate()
        waveTimer = nil
        waveStartTime = ProcessInfo.processInfo.systemUptime

        guard showsWave, window != nil else {
            needsDisplay = true
            return
        }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            needsDisplay = true
            return
        }

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.needsDisplay = true
            }
        }
        waveTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func drawWave(clippedTo outerPath: NSBezierPath) {
        guard showsWave else { return }

        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let progress: CGFloat
        if reducedMotion {
            progress = 0.5
        } else {
            let elapsed = ProcessInfo.processInfo.systemUptime - waveStartTime
            progress = CGFloat(elapsed.truncatingRemainder(dividingBy: 1.8) / 1.8)
        }

        let waveWidth: CGFloat = 48
        let travelWidth = bounds.width + waveWidth * 2
        let centerX = bounds.minX - waveWidth + travelWidth * progress

        NSGraphicsContext.saveGraphicsState()
        outerPath.addClip()

        let waveRect = NSRect(
            x: centerX - waveWidth / 2,
            y: bounds.minY + 2,
            width: waveWidth,
            height: max(1, bounds.height - 4)
        )
        let wavePath = NSBezierPath(
            roundedRect: waveRect,
            xRadius: waveRect.height * cornerRatio,
            yRadius: waveRect.height * cornerRatio
        )
        wavePath.addClip()

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.white.withAlphaComponent(0.08)
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = .zero
        shadow.set()
        let gradient = NSGradient(colorsAndLocations:
            (NSColor.white.withAlphaComponent(0), 0),
            (NSColor.white.withAlphaComponent(0.04), 0.30),
            (NSColor.white.withAlphaComponent(0.17), 0.66),
            (NSColor.white.withAlphaComponent(0.08), 1)
        )
        gradient?.draw(
            in: waveRect,
            angle: 0
        )
        NSGraphicsContext.restoreGraphicsState()
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
        isTrackingPress = true
        isPressed = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isTrackingPress else { return }
        let pointerIsInside = bounds.contains(convert(event.locationInWindow, from: nil))
        guard isPressed != pointerIsInside else { return }
        isPressed = pointerIsInside
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let shouldTriggerClick = isTrackingPress && bounds.contains(
            convert(event.locationInWindow, from: nil)
        )
        isTrackingPress = false
        isPressed = false
        needsDisplay = true
        if shouldTriggerClick {
            triggerClick(timestamp: event.timestamp)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }

    @objc private func handleClick(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        triggerClick(
            timestamp: NSApp.currentEvent?.timestamp
                ?? ProcessInfo.processInfo.systemUptime
        )
    }

    private func triggerClick(timestamp: TimeInterval) {
        // mouseUp is the primary button path; the gesture recognizer is retained
        // as a fallback. Both can observe the same physical click, so deduplicate.
        guard timestamp - lastClickTimestamp > 0.08 else { return }
        lastClickTimestamp = timestamp
        onClick?()
    }
}

private final class PetHoverPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // AppKit normally keeps the complete panel inside visibleFrame. This
        // panel includes a transparent shadow canvas, so that behavior creates
        // a shadowInset-sized gap below the menu bar. Preserve AppKit's
        // horizontal constraint but allow the transparent top inset to overlap
        // the menu-bar window.
        let constrained = super.constrainFrameRect(frameRect, to: screen)
        return NSRect(
            x: constrained.origin.x,
            y: frameRect.origin.y,
            width: frameRect.width,
            height: frameRect.height
        )
    }
}

@MainActor
private final class PetHoverPanelController {
    private static let cardSize = NSSize(width: 340, height: 112)
    private static let shadowInset: CGFloat = 20
    private static let cardGapFromMenuBar: CGFloat = 4
    private let panel: NSPanel
    private let model = PetHoverViewModel()

    var onMouseEntered: (() -> Void)? {
        get { model.onMouseEntered }
        set { model.onMouseEntered = newValue }
    }

    var onMouseExited: (() -> Void)? {
        get { model.onMouseExited }
        set { model.onMouseExited = newValue }
    }

    var onClick: (() -> Void)? {
        get { model.onClick }
        set { model.onClick = newValue }
    }

    var isVisible: Bool { panel.isVisible }

    var interactionFrame: NSRect {
        panel.frame.insetBy(dx: Self.shadowInset, dy: Self.shadowInset)
    }

    init() {
        let panelSize = NSSize(
            width: Self.cardSize.width + Self.shadowInset * 2,
            height: Self.cardSize.height + Self.shadowInset * 2
        )
        panel = PetHoverPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        // Keep the hover card above normal windows but below the menu bar.
        // Its transparent shadow region can overlap the status item; using the
        // status-bar level would intermittently intercept capsule clicks.
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The system shadow follows the rectangular panel bounds and leaves dark,
        // square corners around a rounded visual-effect view. Draw one controlled
        // shadow around the rounded card instead.
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
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
        // Anchor the visible card—not its transparent shadow canvas—to the
        // actual menu-bar edge. The status button's local vertical bounds can
        // vary by OS version and previously produced a much larger visual gap.
        let menuBarBottom = window.frame.minY
        let y = menuBarBottom
            - Self.cardGapFromMenuBar
            - Self.cardSize.height
            - Self.shadowInset
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
    }

    func hide() {
        NSCursor.arrow.set()
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
    @ObservationIgnored var onMouseEntered: (() -> Void)?
    @ObservationIgnored var onMouseExited: (() -> Void)?
    @ObservationIgnored var onClick: (() -> Void)?
}

private struct PetHoverContentView: View {
    @Bindable var model: PetHoverViewModel
    let cardSize: NSSize
    let shadowInset: CGFloat

    var body: some View {
        glassSurface
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onHover { isHovered in
                if isHovered {
                    NSCursor.pointingHand.set()
                    model.onMouseEntered?()
                } else {
                    NSCursor.arrow.set()
                    model.onMouseExited?()
                }
            }
            .onTapGesture {
                model.onClick?()
            }
            .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 0)
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 0)
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
