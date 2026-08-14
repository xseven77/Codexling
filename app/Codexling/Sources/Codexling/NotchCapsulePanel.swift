import AppKit
import SwiftUI
import Observation

/// 刘海面板轮廓：顶部横边完整贴住屏幕顶边，左上/右上使用「反向圆角」，
/// 底部为普通圆角。几何逻辑参考 Apache-2.0 的 Ping Island `NotchShape.swift`。
private struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = min(topCornerRadius, rect.width / 2)
        let bottom = min(bottomCornerRadius, rect.height / 2)

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// 刘海面板的稳定数据模型：rootView 只创建一次，数据变化由观察驱动。
@Observable
final class NotchCapsuleViewModel {
    var agentTicks: [StatusBarAgentTick] = []
    var providerTicks: [StatusBarProviderTick] = []
    var agentIndex = 0
    var providerIndex = 0
    var activeAgentCount = 0
    var waitingCount = 0
    var isExpanded = false
    /// 收起态胶囊高度（= 状态栏/刘海高度，动态计算）
    var closedHeight: CGFloat = 32
    /// 收起态胶囊宽度（= 刘海宽度 + 左右翼，动态计算）
    var closedWidth: CGFloat = 310
    /// 中央摄像头避让区宽度（= 物理刘海宽度）
    var notchWidth: CGFloat = 104
    /// 当前所在显示器名称
    var screenName: String = ""

    // 交互回调（由 Controller 注入）
    var onClick: (() -> Void)?
    var onSelectAgent: ((Int) -> Void)?
    var onSelectProvider: ((Int) -> Void)?
    var onOpenCurrentTask: (() -> Void)?
    var onAgentHover: ((Bool) -> Void)?
    var onProviderHover: ((Bool) -> Void)?
}

/// 自定义命中视图：透明区域返回 nil 让鼠标事件穿透到下层，
/// 只对收起胶囊 / 展开面板区域拦截点击。
final class NotchHitTestView: NSView {
    /// 命中判定（点坐标为视图 bounds 坐标，原点在左下角）。
    var shouldHit: (NSPoint) -> Bool = { _ in true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        shouldHit(point) ? super.hitTest(point) : nil
    }
}

/// 刘海屏伴侣面板：固定尺寸透明 NSPanel 顶部贴主屏顶边，内容在窗口内顶部居中。
/// 收起态只拦截顶部胶囊的点击（点击展开），展开态拦截整个面板；鼠标移出或 Esc 收起。
@MainActor
final class NotchCapsulePanelController {
    private static let openedSize = NSSize(width: 700, height: 330)
    private static let windowSize = NSSize(width: 700, height: 330)

    private let panel: NSPanel
    private let viewModel = NotchCapsuleViewModel()
    private let hosting: NSHostingController<NotchCapsuleView>
    private let hitTestView = NotchHitTestView()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var screen: NSScreen?
    private var collapseWorkItem: DispatchWorkItem?

    var onClick: (() -> Void)?
    var onSelectAgent: ((Int) -> Void)?
    var onSelectProvider: ((Int) -> Void)?
    var onOpenCurrentTask: (() -> Void)?
    var onAgentHover: ((Bool) -> Void)?
    var onProviderHover: ((Bool) -> Void)?

    init() {
        hosting = NSHostingController(rootView: NotchCapsuleView(viewModel: viewModel))
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // 用自定义命中视图包裹 SwiftUI 内容：透明区域穿透鼠标，胶囊/面板区域拦截点击。
        panel.contentView = hitTestView
        hosting.view.frame = NSRect(origin: .zero, size: Self.windowSize)
        hosting.view.autoresizingMask = [.width, .height]
        hitTestView.addSubview(hosting.view)

        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .mainMenu + 3
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = false
        updateHitTestPolicy()

        // self 完全初始化后再注入回调，转发到公开属性。
        viewModel.onSelectAgent = { [weak self] index in self?.onSelectAgent?(index) }
        viewModel.onSelectProvider = { [weak self] index in self?.onSelectProvider?(index) }
        viewModel.onOpenCurrentTask = { [weak self] in self?.onOpenCurrentTask?() }
        viewModel.onAgentHover = { [weak self] hovering in self?.onAgentHover?(hovering) }
        viewModel.onProviderHover = { [weak self] hovering in self?.onProviderHover?(hovering) }
    }

    func update(
        agentTicks: [StatusBarAgentTick],
        providerTicks: [StatusBarProviderTick],
        agentIndex: Int,
        providerIndex: Int,
        activeAgentCount: Int,
        waitingCount: Int
    ) {
        viewModel.agentTicks = agentTicks
        viewModel.providerTicks = providerTicks
        viewModel.agentIndex = agentIndex
        viewModel.providerIndex = providerIndex
        viewModel.activeAgentCount = activeAgentCount
        viewModel.waitingCount = waitingCount
    }

    func show(on screen: NSScreen? = nil) {
        self.screen = screen ?? NSScreen.main ?? NSScreen.screens.first
        // 动态计算：收起态高度 = 刘海/状态栏高度，宽度 = 刘海宽度 + 左右翼。
        let notchWidth = self.screen?.notchWidth ?? 104
        let safeTop = self.screen?.notchHeight ?? 24
        viewModel.notchWidth = notchWidth
        viewModel.closedWidth = notchWidth + 230
        viewModel.closedHeight = safeTop
        viewModel.screenName = self.screen?.displayName ?? "显示器"
        updateHitTestPolicy()
        positionPanel()
        panel.orderFrontRegardless()
        installMonitors()
    }

    func hide() {
        removeMonitors()
        cancelCollapse()
        viewModel.isExpanded = false
        panel.orderOut(nil)
    }

    var isVisible: Bool { panel.isVisible }

    // MARK: - 展开 / 收起

    private func setExpanded(_ expanded: Bool) {
        guard expanded != viewModel.isExpanded else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
            viewModel.isExpanded = expanded
        }
        updateHitTestPolicy()
    }

    private func closePanel() {
        cancelCollapse()
        setExpanded(false)
    }

    /// 更新命中区域：展开态拦截整个面板；收起态只拦截顶部收起胶囊，其余透明区域穿透。
    private func updateHitTestPolicy() {
        let closedWidth = viewModel.closedWidth
        let closedHeight = viewModel.closedHeight
        hitTestView.shouldHit = { [weak self] point in
            guard let self else { return false }
            if self.viewModel.isExpanded { return true }
            let bounds = self.hitTestView.bounds
            let capsuleRect = NSRect(
                x: (bounds.width - closedWidth) / 2,
                y: bounds.height - closedHeight,
                width: closedWidth,
                height: closedHeight
            )
            return capsuleRect.contains(point)
        }
    }

    private func positionPanel() {
        guard let screen else { return }
        let size = Self.windowSize
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: - 鼠标 / 键盘监控

    private func installMonitors() {
        removeMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown]
        ) { [weak self] event in
            DispatchQueue.main.async { self?.handleEvent(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .mouseMoved, .leftMouseDragged]
        ) { [weak self] event in
            if event.type == .keyDown, event.keyCode == 53 { // Esc
                DispatchQueue.main.async { self?.closePanel() }
                return nil
            }
            DispatchQueue.main.async { self?.handleEvent(event) }
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handleEvent(_ event: NSEvent) {
        guard screen != nil else { return }
        if event.type == .leftMouseDown {
            handleClick()
        } else {
            handleMouseMove()
        }
    }

    /// 收起态点击刘海胶囊展开；展开态点击面板外部收起。
    private func handleClick() {
        if viewModel.isExpanded {
            if !isPointerInsideOpenedRect() {
                cancelCollapse()
                setExpanded(false)
            }
        } else if isPointerInsideClosedRect() {
            setExpanded(true)
        }
    }

    /// 展开态下鼠标移出面板后自动收起。
    private func handleMouseMove() {
        guard viewModel.isExpanded else { return }
        if !isPointerInsideOpenedRect() {
            scheduleCollapse()
        } else {
            cancelCollapse()
        }
    }

    /// 收起前短暂延迟，消除「一出现马上缩小又展开」的抖动。
    private func scheduleCollapse() {
        guard collapseWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseWorkItem = nil
            self.setExpanded(false)
        }
        collapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func cancelCollapse() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
    }

    private func isPointerInsideClosedRect() -> Bool {
        closedScreenRect().contains(NSEvent.mouseLocation)
    }

    private func isPointerInsideOpenedRect() -> Bool {
        openedScreenRect().contains(NSEvent.mouseLocation)
    }

    private func closedScreenRect() -> NSRect {
        guard let screen else { return .zero }
        let size = NSSize(width: viewModel.closedWidth, height: viewModel.closedHeight)
        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func openedScreenRect() -> NSRect {
        guard let screen else { return .zero }
        let size = Self.openedSize
        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}

// MARK: - SwiftUI 视图

private struct NotchCapsuleView: View {
    let viewModel: NotchCapsuleViewModel

    private var agent: StatusBarAgentTick? {
        viewModel.agentTicks.indices.contains(viewModel.agentIndex)
            ? viewModel.agentTicks[viewModel.agentIndex] : nil
    }
    private var provider: StatusBarProviderTick? {
        viewModel.providerTicks.indices.contains(viewModel.providerIndex)
            ? viewModel.providerTicks[viewModel.providerIndex] : nil
    }
    private var topCornerRadius: CGFloat { viewModel.isExpanded ? 19 : 6 }
    private var bottomCornerRadius: CGFloat { viewModel.isExpanded ? 24 : 14 }
    private var panelWidth: CGFloat { viewModel.isExpanded ? 700 : viewModel.closedWidth }
    private var panelHeight: CGFloat { viewModel.isExpanded ? 330 : viewModel.closedHeight }

    var body: some View {
        ZStack {
            // 同一容器：尺寸与圆角随展开态连续插值（形变动画，而非视图切换渐变）
            NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius)
                .fill(Color.black.opacity(0.97))
            if viewModel.isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else {
                collapsedContent
                    .transition(.opacity)
            }
        }
        .frame(width: panelWidth, height: panelHeight)
        .clipShape(NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius))
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: viewModel.isExpanded)
    }

    // MARK: 收起态

    private var collapsedContent: some View {
        HStack(spacing: 0) {
            // 左翼：Agent logo + 状态圆点 + 状态文字，贴左
            HStack(spacing: 6) {
                if let agent {
                    StatusBarBrandBadge(asset: agent.asset, size: 14)
                    Circle().fill(Color(nsColor: agent.state.statusNSColor)).frame(width: 6, height: 6)
                    Text(agent.statusText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                } else {
                    Circle().fill(Color.gray.opacity(0.8)).frame(width: 6, height: 6)
                    Text("空闲")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 中央：摄像头避让（= 物理刘海宽度）
            Color.clear.frame(width: viewModel.notchWidth)

            // 右翼：供应商 logo + 额度，贴右
            HStack(spacing: 6) {
                if let provider {
                    Text(provider.quotaText)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                    StatusBarBrandBadge(asset: provider.asset, size: 14)
                } else {
                    Text("未登录")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
    }

    // MARK: 展开态

    private var expandedContent: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 26)

            bodyColumns
                .padding(.top, 18)
                .frame(maxHeight: .infinity, alignment: .top)

            footer
                .padding(.top, 16)
                .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5) }
                .padding(.top, 16)
        }
        .padding(.horizontal, 40)
        .padding(.top, 18)
        .padding(.bottom, 26)
    }

    private var codexlingLogoImage: Image {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("logo.svg"),
           let nsImage = NSImage(contentsOf: url) {
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "sparkles")
    }

    private var header: some View {
        HStack {
            HStack(spacing: 7) {
                codexlingLogoImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                Text("CODEXLING · \(viewModel.screenName)")
            }
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(Color.green).frame(width: 7, height: 7)
                Text("\(viewModel.providerTicks.count) 个数据源在线")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.white.opacity(0.45))
    }

    private var bodyColumns: some View {
        HStack(alignment: .top, spacing: 24) {
            agentColumn
            providerColumn
        }
    }

    private var agentColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let agent {
                HStack(spacing: 7) {
                    StatusBarBrandBadge(asset: agent.asset, size: 22)
                    Text("\(agent.name)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                HStack(spacing: 7) {
                    Circle().fill(Color(nsColor: agent.state.statusNSColor)).frame(width: 7, height: 7)
                    Text(agent.statusText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 12)
                Text(agent.taskTitle.isEmpty ? "当前没有运行任务" : agent.taskTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.top, 10)
                if !agent.taskDetail.isEmpty {
                    Text(agent.taskDetail)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .padding(.top, 6)
                }
            } else {
                // 空态：暂无进行中的 Agent
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white.opacity(0.32))
                    Text("暂无进行中的 Agent")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Text("Agent 开始工作后，任务状态会显示在这里")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            if !viewModel.agentTicks.isEmpty {
                HStack {
                    Button(action: {
                        viewModel.onSelectAgent?((viewModel.agentIndex - 1 + max(viewModel.agentTicks.count, 1)) % max(viewModel.agentTicks.count, 1))
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("\(viewModel.agentIndex + 1) / \(viewModel.agentTicks.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.40))
                    Spacer()
                    Button(action: {
                        viewModel.onSelectAgent?((viewModel.agentIndex + 1) % viewModel.agentTicks.count)
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.white.opacity(0.60))
                .padding(.top, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 24)
        .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.10)).frame(width: 0.5) }
        .onHover { hovering in viewModel.onAgentHover?(hovering) }
    }

    private var providerColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let provider {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(provider.providerName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(provider.accountName)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    StatusBarBrandBadge(asset: provider.asset, size: 26)
                }
                Text("可用额度")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 12)
                Text(provider.quotaText)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.top, 8)
                if !provider.detailText.isEmpty {
                    Text(provider.detailText)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .padding(.top, 4)
                }
            } else {
                // 空态：暂无额度数据
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "creditcard")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white.opacity(0.32))
                    Text("暂无额度数据")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Text("登录账号或配置 API Key 后显示")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            if !viewModel.providerTicks.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(viewModel.providerTicks.enumerated()), id: \.element.id) { index, tick in
                        Button(action: { viewModel.onSelectProvider?(index) }) {
                            StatusBarBrandBadge(asset: tick.asset, size: 24)
                                .padding(4)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(index == viewModel.providerIndex ? Color.white.opacity(0.15) : Color.white.opacity(0.04))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(index == viewModel.providerIndex ? Color.white.opacity(0.25) : .clear, lineWidth: 1)
                                )
                                .overlay(alignment: .bottom) {
                                    if index == viewModel.providerIndex {
                                        Circle().fill(.white).frame(width: 5, height: 5).offset(y: -2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 16)
            }
        }
        .frame(width: 200)
        .onHover { hovering in viewModel.onProviderHover?(hovering) }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 12) {
                Text("\(viewModel.activeAgentCount) 个本地任务")
                if viewModel.waitingCount > 0 {
                    HStack(spacing: 5) {
                        Circle().fill(Color.orange).frame(width: 6, height: 6)
                        Text("\(viewModel.waitingCount) 个待确认")
                    }
                }
            }
            Spacer()
            HStack(spacing: 10) {
                Button(action: { viewModel.onOpenCurrentTask?() }) {
                    HStack(spacing: 4) {
                        Text("打开窗口")
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
                HStack(spacing: 4) {
                    Image(systemName: "cursorarrow.motionlines").font(.system(size: 10))
                    Text("移开自动收起")
                }
                .foregroundStyle(.white.opacity(0.45))
                .opacity(0.7)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.white.opacity(0.45))
    }
}

/// 小尺寸品牌徽标。
private struct StatusBarBrandBadge: View {
    let asset: BrandAssetID
    let size: CGFloat

    var body: some View {
        Group {
            if let image = BrandAssetCatalog.image(for: asset) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.08)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(Color.codexMuted)
            }
        }
        .frame(width: size, height: size)
        .background(Color.white, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}
