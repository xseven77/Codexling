import AppKit
import SwiftUI
import Observation

/// 独立 Pet 吸附的屏幕边缘。
enum StandalonePetEdge: String, CaseIterable, Identifiable, Sendable {
    case top
    case right
    case bottom
    case left

    var id: String { rawValue }

    var title: String {
        switch self {
        case .top: "靠上"
        case .right: "靠右"
        case .bottom: "靠下"
        case .left: "靠左"
        }
    }

    var symbolName: String {
        switch self {
        case .top: "arrow.up.to.line"
        case .right: "arrow.right.to.line"
        case .bottom: "arrow.down.to.line"
        case .left: "arrow.left.to.line"
        }
    }

    var isVertical: Bool {
        switch self {
        case .top, .bottom: true
        case .left, .right: false
        }
    }
}

/// 独立 Pet 窗口的尺寸契约。`scale` 只缩放 Pet 本身，任务栈与窗口留白保持固定。
enum StandalonePetLayout {
    static let basePetHeight: CGFloat = 120
    static let edgeGap: CGFloat = 14
    /// 缩放区间（设置里的 slider 与这里保持一致）。
    static let scaleRange: ClosedRange<Double> = 0.8...1.25

    /// 任务栈几何（固定，不随 scale 变化）。
    static let taskRowHeight: CGFloat = 50
    static let taskRowSpacing: CGFloat = 12
    static let taskStackPadding: CGFloat = 12
    static let maxVisibleTaskRows = 4
    static let stackToPetSpacing: CGFloat = 10
    /// Pet 与窗口边缘、任务栈与窗口边缘的统一留白（固定）。
    static let outerPadding: CGFloat = 10
    /// 收起态顶部给角标预留的高度（固定）。
    static let badgeClearance: CGFloat = 34
    /// 展开态任务栈的固定尺寸。
    static let expandedVerticalWidth: CGFloat = 316
    static let expandedHorizontalStackWidth: CGFloat = 316
    static let expandedHorizontalHeight: CGFloat = 260

    static func petDisplayHeight(scale: Double) -> CGFloat {
        basePetHeight * scale
    }

    static func petDisplayWidth(scale: Double) -> CGFloat {
        petDisplayHeight(scale: scale) * CGFloat(PetSpriteSheet.cellWidth) / CGFloat(PetSpriteSheet.cellHeight)
    }

    /// 收起态窗口：只装 Pet，随 Pet 一起缩放。
    static func collapsedSize(scale: Double) -> NSSize {
        NSSize(
            width: petDisplayWidth(scale: scale) + outerPadding * 2,
            height: petDisplayHeight(scale: scale) + outerPadding + badgeClearance
        )
    }

    /// 任务栈内容高度：空态用固定高度，否则按「最多 4 条」的行数计算，超出的内部滚动。
    static func stackHeight(taskCount: Int) -> CGFloat {
        if taskCount <= 0 { return 84 }
        let rows = min(taskCount, maxVisibleTaskRows)
        return CGFloat(rows) * (taskRowHeight + taskRowSpacing)
            - taskRowSpacing
            + taskStackPadding * 2
    }

    /// 展开态窗口：任务栈尺寸固定，只有 Pet 随 scale 缩放。
    static func expandedSize(edge: StandalonePetEdge, scale: Double, taskCount: Int) -> NSSize {
        switch edge {
        case .top, .bottom:
            return NSSize(
                width: expandedVerticalWidth,
                height: outerPadding * 2 + petDisplayHeight(scale: scale) + stackToPetSpacing + stackHeight(taskCount: taskCount)
            )
        case .left, .right:
            return NSSize(
                width: outerPadding * 2 + petDisplayWidth(scale: scale) + stackToPetSpacing + expandedHorizontalStackWidth,
                height: expandedHorizontalHeight
            )
        }
    }
}

/// 独立 Pet 的交互状态。任务数据与 Pet 帧来自 CodexActivityStore / PetFrameStore，
/// 这里只保存「位置、缩放、展开」等 UI 状态。
@MainActor
@Observable
final class StandalonePetViewModel {
    var edge: StandalonePetEdge = .bottom
    var freeOrigin: NSPoint?
    var scale: Double = 1.0
    var isExpanded = false

    /// 自由拖拽时固定按「靠下」布局展开（任务栈在 Pet 上方），吸附时跟随所选边。
    var effectiveEdge: StandalonePetEdge {
        freeOrigin != nil ? .bottom : edge
    }

    @ObservationIgnored var onLayoutChange: (() -> Void)?
    @ObservationIgnored var onEdgeChange: ((StandalonePetEdge) -> Void)?
    @ObservationIgnored var onHide: (() -> Void)?
    @ObservationIgnored var onBeginDrag: (() -> Void)?
    @ObservationIgnored var onDragChange: (() -> Void)?
    @ObservationIgnored var onEndDrag: (() -> Void)?
    @ObservationIgnored var onOpenTask: ((CodexTaskActivity) -> Void)?
    @ObservationIgnored var onTaskCountChanged: ((Int) -> Void)?

    func toggleExpanded() {
        let expanding = !isExpanded
        withAnimation(.easeOut(duration: 0.2)) {
            isExpanded.toggle()
        }
        if expanding {
            // 展开：窗口立即放大，气泡淡入。
            onLayoutChange?()
        } else {
            // 收起：等气泡淡出完成后再缩小窗口，避免缩窗裁剪导致的残影。
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                self?.onLayoutChange?()
            }
        }
    }

    func setEdge(_ newEdge: StandalonePetEdge) {
        guard edge != newEdge || freeOrigin != nil else { return }
        edge = newEdge
        freeOrigin = nil
        onEdgeChange?(newEdge)
        onLayoutChange?()
    }

    func openTask(_ task: CodexTaskActivity) {
        onOpenTask?(task)
    }

    func taskCountDidChange(_ count: Int) {
        onTaskCountChanged?(count)
    }

    // MARK: 拖拽

    func beginDrag() {
        onBeginDrag?()
    }

    func updateDrag() {
        onDragChange?()
    }

    func endDrag() {
        onEndDrag?()
    }
}

/// 打开任务所属 Agent 的路由：优先打开对应 session，其次打开 Agent 应用；
/// 都不支持时返回 false（调用方据此去掉点击与小箭头）。
enum StandalonePetOpenRouter {
    static func canOpen(_ task: CodexTaskActivity) -> Bool {
        switch task.agentDisplayName {
        case "Codex": true
        default: false
        }
    }

    @discardableResult
    static func open(_ task: CodexTaskActivity) -> Bool {
        switch task.agentDisplayName {
        case "Codex":
            let threadID = task.id
            NSLog("[StandalonePet] 打开 Codex 任务 id=%@", threadID)
            if let url = URL(string: "codex://threads/\(threadID)"),
               NSWorkspace.shared.open(url) {
                NSLog("[StandalonePet] 深链已打开: %@", url.absoluteString)
                return true
            }
            let opened = openCodexApplication()
            NSLog("[StandalonePet] 回退打开 ChatGPT.app: %@", opened ? "成功" : "失败")
            return opened
        default:
            return false
        }
    }

    private static func openCodexApplication() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            URL(fileURLWithPath: "/Applications/ChatGPT.app"),
            URL(fileURLWithPath: "/Applications/Codex.app"),
            home.appendingPathComponent("Applications/ChatGPT.app"),
            home.appendingPathComponent("Applications/Codex.app"),
        ]
        guard let appURL = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("Contents/Info.plist").path)
        }) else {
            NSLog("[StandalonePet] 未找到 ChatGPT.app / Codex.app")
            return false
        }
        NSLog("[StandalonePet] 打开应用: %@", appURL.path)
        return NSWorkspace.shared.open(appURL)
    }
}

/// 独立 Pet 窗口：一个 borderless、置顶、跨 Space 的悬浮 NSPanel，
/// 承载 Pet 动画与任务状态门户。支持四边吸附与自由拖拽，均可持久化。
@MainActor
final class StandalonePetWindowController {
    private let panel: NSPanel
    private let model: StandalonePetViewModel
    private let hostingController: NSHostingController<StandalonePetView>
    private let settings: AppSettingsStore
    private let activityStore: CodexActivityStore
    private var mouseDownScreenLocation: NSPoint?
    private var windowOriginAtDragStart: NSPoint?

    init(
        activityStore: CodexActivityStore,
        frameStore: PetFrameStore,
        settings: AppSettingsStore
    ) {
        self.settings = settings
        self.activityStore = activityStore
        model = StandalonePetViewModel()
        model.edge = settings.standalonePetEdge
        model.freeOrigin = settings.standalonePetFreeOrigin
        model.scale = settings.standalonePetScale
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: StandalonePetLayout.collapsedSize(scale: model.scale)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces]
        panel.animationBehavior = .none

        let view = StandalonePetView(
            activityStore: activityStore,
            frameStore: frameStore,
            model: model
        )
        hostingController = NSHostingController(rootView: view)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentViewController = hostingController

        model.onLayoutChange = { [weak self] in
            // 窗口尺寸立即到位，由 SwiftUI transition 负责气泡丝滑滑出，避免窗口动画与内容动画双重错位。
            self?.relayout(animated: false)
        }
        model.onEdgeChange = { [weak self] edge in
            self?.settings.standalonePetEdge = edge
            self?.settings.standalonePetFreeOrigin = nil
        }
        model.onHide = { [weak self] in
            self?.settings.standalonePetEnabled = false
        }
        model.onBeginDrag = { [weak self] in
            self?.mouseDownScreenLocation = NSEvent.mouseLocation
            self?.windowOriginAtDragStart = self?.panel.frame.origin
        }
        model.onDragChange = { [weak self] in
            self?.applyDrag()
        }
        model.onEndDrag = { [weak self] in
            self?.finishDrag()
        }
        model.onOpenTask = { task in
            _ = StandalonePetOpenRouter.open(task)
        }
        model.onTaskCountChanged = { [weak self] _ in
            self?.relayout(animated: false)
        }

        settings.onStandalonePetSettingsChanged = { [weak self] in
            self?.settingsDidChange()
        }
    }

    var isVisible: Bool { panel.isVisible }

    func show() {
        syncModelFromSettings()
        relayout(animated: false)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private var taskCount: Int {
        activityStore.snapshot.activeTasks.count
    }

    private func syncModelFromSettings() {
        model.edge = settings.standalonePetEdge
        model.freeOrigin = settings.standalonePetFreeOrigin
        model.scale = settings.standalonePetScale
    }

    private func settingsDidChange() {
        syncModelFromSettings()
        relayout(animated: true)
    }

    // MARK: - 布局

    private func relayout(animated: Bool) {
        let size: NSSize
        if model.isExpanded {
            size = StandalonePetLayout.expandedSize(
                edge: model.effectiveEdge,
                scale: model.scale,
                taskCount: taskCount
            )
        } else {
            size = StandalonePetLayout.collapsedSize(scale: model.scale)
        }

        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let frame: NSRect
        if let freeOrigin = model.freeOrigin {
            frame = Self.freeFrame(
                size: size,
                collapsedSize: StandalonePetLayout.collapsedSize(scale: model.scale),
                freeOrigin: freeOrigin,
                in: visible
            )
        } else {
            frame = Self.edgeFrame(size: size, edge: model.edge, in: visible)
        }
        panel.setFrame(frame, display: true, animate: animated)
    }

    private static func edgeFrame(size: NSSize, edge: StandalonePetEdge, in visible: NSRect) -> NSRect {
        switch edge {
        case .bottom:
            return NSRect(
                x: round(visible.midX - size.width / 2),
                y: visible.minY + StandalonePetLayout.edgeGap,
                width: size.width,
                height: size.height
            )
        case .top:
            return NSRect(
                x: round(visible.midX - size.width / 2),
                y: visible.maxY - size.height - StandalonePetLayout.edgeGap,
                width: size.width,
                height: size.height
            )
        case .left:
            return NSRect(
                x: visible.minX + StandalonePetLayout.edgeGap,
                y: round(visible.midY - size.height / 2),
                width: size.width,
                height: size.height
            )
        case .right:
            return NSRect(
                x: visible.maxX - size.width - StandalonePetLayout.edgeGap,
                y: round(visible.midY - size.height / 2),
                width: size.width,
                height: size.height
            )
        }
    }

    /// 自由拖拽位置：以收起态 origin 为锚点，展开时水平居中、垂直方向底部固定向上生长。
    private static func freeFrame(
        size: NSSize,
        collapsedSize: NSSize,
        freeOrigin: NSPoint,
        in visible: NSRect
    ) -> NSRect {
        var origin = freeOrigin
        origin.x -= (size.width - collapsedSize.width) / 2
        // origin.y 保持不变：Pet 贴底，向上生长，不把 Pet 往下推。

        let minX = visible.minX + StandalonePetLayout.edgeGap
        let minY = visible.minY + StandalonePetLayout.edgeGap
        let maxX = visible.maxX - size.width - StandalonePetLayout.edgeGap
        let maxY = visible.maxY - size.height - StandalonePetLayout.edgeGap
        origin.x = min(max(origin.x, minX), maxX)
        origin.y = min(max(origin.y, minY), maxY)

        return NSRect(origin: origin, size: size)
    }

    // MARK: - 拖拽

    /// 用屏幕坐标系下的鼠标绝对位置计算位移（而非 SwiftUI 手势的相对 translation），
    /// 避免窗口在拖动中移动导致 translation 基准漂移、拖起来“不跟手”。
    private func applyDrag() {
        guard let mouseDown = mouseDownScreenLocation,
              let start = windowOriginAtDragStart else { return }
        let current = NSEvent.mouseLocation
        let deltaX = current.x - mouseDown.x
        let deltaY = current.y - mouseDown.y
        panel.setFrameOrigin(NSPoint(x: start.x + deltaX, y: start.y + deltaY))
    }

    private func finishDrag() {
        defer {
            mouseDownScreenLocation = nil
            windowOriginAtDragStart = nil
        }
        let collapsedSize = StandalonePetLayout.collapsedSize(scale: model.scale)
        let currentSize = panel.frame.size
        let origin = panel.frame.origin
        let collapsedOrigin = NSPoint(
            x: origin.x + (currentSize.width - collapsedSize.width) / 2,
            y: origin.y
        )
        settings.standalonePetFreeOrigin = collapsedOrigin
    }
}

/// 独立 Pet 的 SwiftUI 内容。收起显示 Pet + 任务数角标，展开时任务栈从 Pet 一侧丝滑滑出。
private struct StandalonePetView: View {
    @Bindable var activityStore: CodexActivityStore
    @Bindable var frameStore: PetFrameStore
    @Bindable var model: StandalonePetViewModel

    @State private var isHoveringPet = false
    @State private var isDragging = false

    private var tasks: [CodexTaskActivity] {
        activityStore.snapshot.activeTasks
    }

    var body: some View {
        ZStack {
            if model.isExpanded {
                taskStack
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: stackAlignment)
                    .padding(stackInsets)
                    .transition(stackTransition)
                    .zIndex(0)
            }
            petControl
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: petAlignment)
                .padding(petInsets)
                .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: tasks.count) { _, newCount in
            model.taskCountDidChange(newCount)
        }
    }

    // MARK: - 布局对齐（按 effectiveEdge）

    private var petAlignment: Alignment {
        switch model.effectiveEdge {
        case .bottom: .bottom
        case .top: .top
        case .left: .leading
        case .right: .trailing
        }
    }

    private var stackAlignment: Alignment {
        switch model.effectiveEdge {
        case .bottom: .top
        case .top: .bottom
        case .left: .trailing
        case .right: .leading
        }
    }

    private var stackInsets: EdgeInsets {
        let petHeight = StandalonePetLayout.petDisplayHeight(scale: model.scale)
        let petWidth = StandalonePetLayout.petDisplayWidth(scale: model.scale)
        let spacing = StandalonePetLayout.stackToPetSpacing
        let outer = StandalonePetLayout.outerPadding
        switch model.effectiveEdge {
        case .bottom:
            return EdgeInsets(top: outer, leading: 0, bottom: outer + petHeight + spacing, trailing: 0)
        case .top:
            return EdgeInsets(top: outer + petHeight + spacing, leading: 0, bottom: outer, trailing: 0)
        case .left:
            return EdgeInsets(top: 0, leading: outer + petWidth + spacing, bottom: 0, trailing: outer)
        case .right:
            return EdgeInsets(top: 0, leading: outer, bottom: 0, trailing: outer + petWidth + spacing)
        }
    }

    private var petInsets: EdgeInsets {
        let outer = StandalonePetLayout.outerPadding
        switch model.effectiveEdge {
        case .bottom:
            return EdgeInsets(top: 0, leading: 0, bottom: outer, trailing: 0)
        case .top:
            return EdgeInsets(top: outer, leading: 0, bottom: 0, trailing: 0)
        case .left:
            return EdgeInsets(top: 0, leading: outer, bottom: 0, trailing: 0)
        case .right:
            return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: outer)
        }
    }

    private var stackTransition: AnyTransition {
        // 气泡式出现：淡入 + 轻微放大，不做任何方向位移，避免把 Pet 推挤。
        .opacity.combined(with: .scale(scale: 0.94, anchor: transitionAnchor))
    }

    private var transitionAnchor: UnitPoint {
        switch model.effectiveEdge {
        case .bottom: .bottom
        case .top: .top
        case .left: .leading
        case .right: .trailing
        }
    }

    // MARK: - Pet

    private var petControl: some View {
        ZStack(alignment: .topTrailing) {
            petImage
                .scaleEffect(isHoveringPet && !isDragging ? 1.05 : 1)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.14)) { isHoveringPet = hovering }
                    if hovering && !isDragging { NSCursor.pointingHand.set() } else if !isDragging { NSCursor.arrow.set() }
                }
                .gesture(petDragGesture)
                .contextMenu { petContextMenu }

            if !model.isExpanded && !tasks.isEmpty {
                taskCountBadge
            }
        }
        .frame(
            width: StandalonePetLayout.petDisplayWidth(scale: model.scale),
            height: StandalonePetLayout.petDisplayHeight(scale: model.scale),
            alignment: .center
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Codexling Pet · \(tasks.count) 个任务")
        .accessibilityAddTraits(.isButton)
    }

    private var petDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let distance = hypot(value.translation.width, value.translation.height)
                if !isDragging && distance > 6 {
                    isDragging = true
                    NSCursor.closedHand.set()
                    model.beginDrag()
                }
                if isDragging {
                    model.updateDrag()
                }
            }
            .onEnded { _ in
                if isDragging {
                    model.endDrag()
                    NSCursor.arrow.set()
                } else {
                    model.toggleExpanded()
                }
                isDragging = false
            }
    }

    @ViewBuilder
    private var petImage: some View {
        if let frame = frameStore.currentFrame {
            Image(nsImage: frame)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Color.codexPrimary)
        }
    }

    private var taskCountBadge: some View {
        Text("\(tasks.count)")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: 22)
            .background(Color.accentColor, in: Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1))
            .offset(x: 6, y: -6)
    }

    @ViewBuilder
    private var petContextMenu: some View {
        ForEach(StandalonePetEdge.allCases) { edge in
            Button {
                model.setEdge(edge)
            } label: {
                Label(edge.title, systemImage: edge.symbolName)
            }
        }
        Divider()
        Button {
            model.onHide?()
        } label: {
            Label("隐藏独立 Pet", systemImage: "eye.slash")
        }
    }

    // MARK: - Task stack

    private var taskStack: some View {
        ScrollView {
            LazyVStack(spacing: StandalonePetLayout.taskRowSpacing) {
                if tasks.isEmpty {
                    emptyState
                } else {
                    ForEach(tasks) { task in
                        taskRow(task)
                            .frame(height: StandalonePetLayout.taskRowHeight)
                    }
                }
            }
            .padding(.vertical, StandalonePetLayout.taskStackPadding)
            .padding(.horizontal, 8)
        }
        .scrollIndicators(.never)
    }

    private var emptyState: some View {
        fluidGlass(
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.codexMuted)
                Text("暂无进行中的任务")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.codexMuted)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 60)
        )
    }

    @ViewBuilder
    private func taskRow(_ task: CodexTaskActivity) -> some View {
        let row = taskRowContent(task)
        if StandalonePetOpenRouter.canOpen(task) {
            Button {
                model.openTask(task)
            } label: {
                row
            }
            .buttonStyle(CodexPressableCardStyle(cornerRadius: 14))
            .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
        } else {
            row
                .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
        }
    }

    private func taskRowContent(_ task: CodexTaskActivity) -> some View {
        let content = HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                BrandIconView(
                    asset: BrandAssetID.forAgentDisplayName(task.agentDisplayName),
                    size: 30,
                    cornerRadius: 9
                )
                Circle()
                    .fill(task.state.statusColor)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                    .offset(x: 2, y: 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(task.title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.codexInk)
                        .lineLimit(1)
                    Text(task.agentDisplayName)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Color.codexMuted)
                        .lineLimit(1)
                }
                Text("\(task.state.taskLabel) · \(task.detail)")
                    .font(.system(size: 8.5))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if StandalonePetOpenRouter.canOpen(task) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.codexMuted.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)

        return fluidGlass(content, cornerRadius: 14)
    }

    /// 流体玻璃质感：macOS 26 用 Liquid Glass，旧系统用磨砂兜底，并叠加顶部高光 + 描边。
    @ViewBuilder
    private func fluidGlass<Content: View>(_ content: Content, cornerRadius: CGFloat = 14) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content
                .glassEffect(in: .rect(cornerRadius: cornerRadius))
                .overlay { shape.strokeBorder(Color.white.opacity(0.30), lineWidth: 0.6) }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay { shape.strokeBorder(Color.white.opacity(0.30), lineWidth: 0.6) }
        }
    }
}
