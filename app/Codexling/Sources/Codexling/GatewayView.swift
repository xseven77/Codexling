import AppKit
import SwiftUI

private enum GatewayLayoutMetrics {
    static let sidebarWidth: CGFloat = 166
    static let sidebarTopInset: CGFloat = 14
    static let windowTopInset: CGFloat = 14
    static let windowBottomInset: CGFloat = 26
    static let minWindowWidth: CGFloat = 860
    static let minWindowHeight: CGFloat = 600
}

private enum GatewayScrollCoordinateSpace {
    static let name = "gateway-content-scroll"
}

private enum GatewayAgentConnectTarget {
    case hermes
    case pi
}

private struct GatewayTableWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private enum GatewayHeaderMinYKey: PreferenceKey {
    static let defaultValue = CGFloat.greatestFiniteMagnitude

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

private struct GatewayToast: Equatable {
    let message: String
    let systemImage: String
    let isSuccess: Bool
}

public struct GatewayView: View {
    @State private var store = GatewayStore.shared
    @State private var supervisor = GatewaySupervisor.shared
    @State private var copiedEndpoint = false
    @State private var copiedKey = false
    @State private var copiedAllModels = false
    @State private var copiedGroupId: String?
    @State private var copiedModelId: String?
    @State private var addingModelGroupId: String?
    @State private var customModelInput: String = ""
    @State private var tableContainerWidth: CGFloat = 0
    @State private var expandedGroupIds: Set<String> = []
    @State private var selectedAccountBySection: [String: String] = [:]
    @State private var showsStickyTitle: Bool = false
    @State private var agentConfigMessage: String? = nil
    @State private var agentConfigSucceeded = true
    @State private var configuringAgent: GatewayAgentConnectTarget? = nil
    @State private var unconfiguringAgent: GatewayAgentConnectTarget? = nil
    @State private var syncingConnectionIDs: Set<ConnectionID> = []
    @State private var toast: GatewayToast? = nil
    @State private var toastDismissGeneration: Int = 0

    /// Injected by GatewayWindowController; used to route proxy toggles through
    /// MultiAgentSettingsStore so in-memory account state stays consistent.
    var settingsStore: MultiAgentSettingsStore?

    public init() {}

    init(settingsStore: MultiAgentSettingsStore?) {
        self.settingsStore = settingsStore
    }


    public var body: some View {
        HStack(spacing: 0) {
            gatewaySidebar
                .frame(width: GatewayLayoutMetrics.sidebarWidth)

            CodexDivider(.vertical)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    tabHeader

                    switch store.selectedTab {
                    case .connect:
                        connectContent
                    case .agents:
                        agentsContent
                    case .overview:
                        overviewContent
                    case .requests:
                        requestsContent
                    case .doctor:
                        doctorContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, GatewayLayoutMetrics.windowTopInset)
                .padding(.bottom, GatewayLayoutMetrics.windowBottomInset)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(ScrollIndicatorHider())
            }
            .coordinateSpace(name: GatewayScrollCoordinateSpace.name)
            .onPreferenceChange(GatewayHeaderMinYKey.self) { minY in
                if showsStickyTitle {
                    if minY > -44 {
                        showsStickyTitle = false
                    }
                } else if minY < -72 {
                    showsStickyTitle = true
                }
            }
            .scrollIndicators(.hidden)
            .background {
                ZStack {
                    Color.codexBackground.opacity(0.50)
                    ScrollIndicatorHider()
                }
            }
        }
        .frame(minWidth: GatewayLayoutMetrics.minWindowWidth, minHeight: GatewayLayoutMetrics.minWindowHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(Color.codexInk)
        .overlay(alignment: .top) {
            if showsStickyTitle {
                HStack(alignment: .top, spacing: 0) {
                    Color.clear
                        .frame(width: GatewayLayoutMetrics.sidebarWidth + 1, height: 110)
                    stickyGatewayTitle
                }
                .offset(y: -34)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: showsStickyTitle)
        .overlay(alignment: .bottom) {
            if let toast {
                HStack(spacing: 8) {
                    Image(systemName: toast.systemImage)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(toast.isSuccess ? Color.green : (toast.systemImage.contains("triangle") ? Color.orange : Color.red))
                    Text(toast.message)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Color.black.opacity(0.88), in: Capsule(style: .continuous))
                .shadow(color: Color.black.opacity(0.20), radius: 10, x: 0, y: 4)
                .padding(.bottom, 22)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityLabel(toast.message)
                .allowsHitTesting(false)
                .zIndex(1000)
            }
        }
        .animation(.easeOut(duration: 0.18), value: toast)
        .sheet(isPresented: Binding(
            get: { store.isColumnSettingsPresented },
            set: { store.isColumnSettingsPresented = $0 }
        )) {
            GatewayColumnSettingsSheet(store: store)
        }
    }

    private func showToast(_ message: String, systemImage: String = "checkmark.circle.fill", isSuccess: Bool = true) {
        toastDismissGeneration += 1
        let generation = toastDismissGeneration
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            toast = GatewayToast(message: message, systemImage: systemImage, isSuccess: isSuccess)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            guard generation == toastDismissGeneration else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                toast = nil
            }
        }
    }

    private var stickyGatewayTitle: some View {
        Text(store.selectedTab.rawValue)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Color.codexInk)
            .padding(.horizontal, 20)
            .padding(.top, 19)
            .frame(height: 110, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                LinearGradient(
                    stops: [
                        .init(color: Color.codexBackground, location: 0),
                        .init(color: Color.codexBackground, location: 0.48),
                        .init(color: Color.codexBackground.opacity(0.72), location: 0.72),
                        .init(color: Color.codexBackground.opacity(0), location: 1),
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomTrailing
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: - Header
    private var tabHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(store.selectedTab.rawValue)
                    .font(.system(size: 20, weight: .bold))

                if (store.selectedTab == .overview && (store.isTelemetryLoading || store.isSummaryLoading || store.isBreakdownLoading)) ||
                   (store.selectedTab == .requests && (store.isRequestsLoading || store.isTelemetryLoading)) {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("正在加载...")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.codexMuted)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.codexMist.opacity(0.8), in: Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            Text(store.selectedTab.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Color.codexMuted)
        }
        .animation(.easeInOut(duration: 0.2), value: store.isTelemetryLoading || store.isRequestsLoading || store.isBreakdownLoading)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: GatewayHeaderMinYKey.self,
                    value: geometry.frame(in: .named(GatewayScrollCoordinateSpace.name)).minY
                )
            }
        }
    }

    // MARK: - Sidebar
    private var gatewaySidebar: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("GATEWAY")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Color.codexMuted)
                .padding(.horizontal, 10)
                .padding(.bottom, 5)

            ForEach(GatewayNavTab.allCases) { tab in
                Button {
                    // Changing tabs can replace a dense provider/model tree.
                    // Animating that entire tree forces SwiftUI to lay out the
                    // old and new pages together, which made navigation feel
                    // stalled as the discovered catalog grew.
                    store.selectedTab = tab
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: tab.symbolName)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 18)
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: store.selectedTab == tab ? .semibold : .medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)

                        if (tab == .overview && (store.isTelemetryLoading || store.isSummaryLoading)) ||
                           (tab == .requests && (store.isRequestsLoading || store.isTelemetryLoading)) {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                    .foregroundStyle(store.selectedTab == tab ? Color.codexInk : Color.codexMuted)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .contentShape(Rectangle())
                    .background(
                        store.selectedTab == tab ? Color.codexPrimary.opacity(0.10) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                }
                .buttonStyle(CodexPressableStyle(cornerRadius: 8))
                .accessibilityValue(store.selectedTab == tab ? "已选择" : "")
            }

            Spacer(minLength: 12)

            // Status Card at Footer
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(supervisor.isRunning ? Color.green : Color.red)
                        .frame(width: 7, height: 7)
                    Text(supervisor.isRunning ? "网关运行中" : "网关已停止")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(supervisor.isRunning ? Color.green : Color.red)
                        .lineLimit(1)
                }
                Text(verbatim: "端口: \(supervisor.port)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.codexCard)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
            )

            Text("Codexling Gateway")
                .font(.system(size: 9))
                .foregroundStyle(Color.codexMuted.opacity(0.82))
                .padding(.top, 2)
        }
        .padding(.horizontal, 10)
        .padding(.top, GatewayLayoutMetrics.sidebarTopInset)
        .padding(.bottom, 14)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.codexCard.opacity(0.72))
    }

    // MARK: - Tab 1: Overview Content
    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            // ==========================================
            // 区块一：本地 Agent 活动与伴侣观测 (Hook 监听)
            // ==========================================
            hookedAgentActivityBlock

            CodexDivider(.horizontal)

            // ==========================================
            // 区块二：本地对外标准网关与持久化遥测 (127.0.0.1:58349)
            // ==========================================
            gatewayProxyTelemetryBlock

            CodexDivider(.horizontal)

            // ==========================================
            // 区块三：维度透视与用量分解 (Breakdown)
            // ==========================================
            telemetryBreakdownSection
        }
    }

    // MARK: - 区块一：本地 Agent 活动与伴侣观测 (2x2 Grid)
    private var hookedAgentActivityBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Image(systemName: "macbook.and.iphone")
                            .foregroundStyle(.purple)
                            .font(.system(size: 13, weight: .semibold))
                        Text("本地 Agent 活动与伴侣观测")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(Color.codexInk)
                            .lineLimit(1)
                        Text("Hook 监听")
                            .font(.system(size: 9.5, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.12), in: Capsule())
                            .foregroundStyle(.purple)
                    }
                    Text("通过本地系统事件与会话日志实时感知 · 无需开启反代即可观测")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.codexMuted)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("今日伴侣工作总时长")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.codexMuted)
                        .lineLimit(1)
                    Text(store.todayCompanionDurationText)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.purple)
                        .lineLimit(1)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(minimum: 280)), GridItem(.flexible(minimum: 280))], spacing: 8) {
                ForEach(store.hookedAgentRows) { agent in
                    HStack(spacing: 10) {
                        Image(systemName: agent.iconName)
                            .font(.system(size: 13))
                            .frame(width: 26, height: 26)
                            .background(Color.purple.opacity(0.10))
                            .foregroundStyle(.purple)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(agent.agentName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.codexInk)
                                    .lineLimit(1)
                                Text(agent.durationText)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.purple)
                                    .lineLimit(1)
                            }
                            Text(agent.detailText)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.codexMuted)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(agent.statusBadge)
                                .font(.system(size: 9.5, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(agent.statusBadge == "运行中" ? Color.green.opacity(0.12) : Color.codexMuted.opacity(0.12), in: Capsule())
                                .foregroundStyle(agent.statusBadge == "运行中" ? Color.green : Color.codexMuted)
                                .lineLimit(1)
                            Text("\(agent.tasksCount) 任务")
                                .font(.system(size: 9.5))
                                .foregroundStyle(Color.codexMuted)
                                .lineLimit(1)
                        }
                    }
                    .padding(10)
                    .background(Color.codexCard)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
                    )
                }
            }
        }
    }

    // MARK: - 区块二: Gateway 流量遥测与桥接拓扑
    private var gatewayProxyTelemetryBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Image(systemName: "waveform.path.ecg")
                            .foregroundStyle(.blue)
                            .font(.system(size: 13, weight: .semibold))
                        Text("外部 Agent 调用与流量指标")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(Color.codexInk)
                            .lineLimit(1)
                        Text(verbatim: "127.0.0.1:\(supervisor.port)")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                    Text("经由本地网关中继转译的实际 API 调用、Token 消耗与流式延迟 · 持久化 SQLite 账本")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.codexMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .layoutPriority(0)

                Spacer(minLength: 6)

                // 手动刷新按钮
                Button {
                    Task {
                        await store.refreshTelemetryAnalytics()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(store.isSummaryLoading ? 360 : 0))
                            .animation(store.isSummaryLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: store.isSummaryLoading)
                        Text("刷新")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(Color.codexMist, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .foregroundStyle(Color.codexInk)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.7)
                    )
                }
                .buttonStyle(CodexPressableStyle(cornerRadius: 5))
                .disabled(store.isSummaryLoading || store.isTelemetryLoading)
                .help("刷新遥测指标与图表")

                // 日期范围切换 Picker
                dateRangeSelectorView
                    .layoutPriority(1)
            }

            if store.selectedDateRange == .custom {
                customDateRangePickerBar
            }

            // 7-Grid Telemetry
            LazyVGrid(columns: [GridItem(.flexible(minimum: 150)), GridItem(.flexible(minimum: 150)), GridItem(.flexible(minimum: 150))], spacing: 8) {
                ForEach(store.telemetryItems) { item in
                    telemetryCard(for: item)
                }
            }
            .opacity(store.isSummaryLoading ? 0.65 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: store.isSummaryLoading)

            // Bridge Flow
            bridgeTopologyFlowSection
        }
    }

    // MARK: - 区块三: 维度透视与用量分解 (Breakdown)
    private var telemetryBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("用量与性能维度分析")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.codexInk)
                            .lineLimit(1)

                        if store.isBreakdownLoading {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                    Text("按 Agent、供应商、账号或模型细分统计消耗与首字延迟")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.codexMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .layoutPriority(0)

                Spacer(minLength: 6)

                Picker("", selection: Binding(
                    get: { store.selectedBreakdownDimension },
                    set: { newValue in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            store.selectedBreakdownDimension = newValue
                        }
                    }
                )) {
                    ForEach(GatewayBreakdownDimension.allCases) { dim in
                        Text(dim.rawValue).tag(dim)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 220)
                .layoutPriority(1)
            }

            if store.isBreakdownLoading && store.breakdownItems.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在加载 \(store.selectedBreakdownDimension.rawValue) 数据...")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.codexMuted)
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
                .background(Color.codexCard)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if store.breakdownItems.isEmpty {
                HStack {
                    Spacer()
                    Text("所选时间段暂无统计数据")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.codexMuted)
                        .padding(.vertical, 16)
                    Spacer()
                }
                .background(Color.codexCard)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ZStack {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Text(store.selectedBreakdownDimension.rawValue)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Color.codexMuted)
                                .frame(minWidth: 90, maxWidth: .infinity, alignment: .leading)
                            Text("总请求")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Color.codexMuted)
                                .frame(minWidth: 50, maxWidth: 70, alignment: .trailing)
                            Text("输入 Tokens")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Color.codexMuted)
                                .frame(minWidth: 70, maxWidth: 90, alignment: .trailing)
                            Text("输出 Tokens")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Color.codexMuted)
                                .frame(minWidth: 70, maxWidth: 90, alignment: .trailing)
                            Text("平均 TTFT")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Color.codexMuted)
                                .frame(minWidth: 55, maxWidth: 75, alignment: .trailing)
                            Text("成功率")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Color.codexMuted)
                                .frame(minWidth: 45, maxWidth: 65, alignment: .trailing)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)

                        ForEach(store.breakdownItems) { item in
                            HStack(spacing: 6) {
                                Text(item.key)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Color.codexInk)
                                    .frame(minWidth: 90, maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text("\(item.totalRequests)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.codexInk)
                                    .frame(minWidth: 50, maxWidth: 70, alignment: .trailing)
                                    .lineLimit(1)
                                Text(GatewayStore.formatTokens(Int(item.inputTokens)))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.codexInk)
                                    .frame(minWidth: 70, maxWidth: 90, alignment: .trailing)
                                    .lineLimit(1)
                                Text(GatewayStore.formatTokens(Int(item.outputTokens)))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.codexInk)
                                    .frame(minWidth: 70, maxWidth: 90, alignment: .trailing)
                                    .lineLimit(1)
                                Text(item.avgTtftMs > 0 ? "\(Int(item.avgTtftMs))ms" : "--")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.codexInk)
                                    .frame(minWidth: 55, maxWidth: 75, alignment: .trailing)
                                    .lineLimit(1)
                                Text(String(format: "%.0f%%", item.successRate * 100))
                                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(item.successRate >= 0.95 ? Color.green : Color.orange)
                                    .frame(minWidth: 45, maxWidth: 65, alignment: .trailing)
                                    .lineLimit(1)
                            }
                            .padding(10)
                            .background(Color.codexCard)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                    .opacity(store.isBreakdownLoading ? 0.45 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: store.isBreakdownLoading)

                    if store.isBreakdownLoading {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("正在更新 \(store.selectedBreakdownDimension.rawValue)...")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.codexInk)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.codexCard.opacity(0.95))
                        .clipShape(Capsule())
                        .shadow(color: Color.black.opacity(0.12), radius: 6, y: 2)
                        .overlay(
                            Capsule()
                                .stroke(Color.codexLine.opacity(0.4), lineWidth: 0.8)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
            }
        }
    }

    private var heroControlCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(supervisor.isRunning ? Color.green : Color.red)
                        .frame(width: 7, height: 7)
                    Text(supervisor.statusText)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(supervisor.isRunning ? Color.green : Color.red)
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(supervisor.isRunning ? Color.green.opacity(0.12) : Color.red.opacity(0.12), in: Capsule())

                Spacer()

                Button {
                    supervisor.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: supervisor.isRunning ? "stop.fill" : "play.fill")
                        Text(supervisor.isRunning ? "停止服务" : "启动服务")
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(supervisor.isRunning ? Color.red.opacity(0.88) : Color.codexPrimary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .foregroundStyle(Color.white)
                }
                .buttonStyle(CodexPressableStyle(cornerRadius: 6))
            }

            CodexDivider(.horizontal)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("对外标准 API 端点")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.codexMuted)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(store.openAIBaseURL)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.codexInk)
                            .lineLimit(1)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(store.openAIBaseURL, forType: .string)
                            copiedEndpoint = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedEndpoint = false
                            }
                        } label: {
                            Image(systemName: copiedEndpoint ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10.5))
                                .foregroundStyle(copiedEndpoint ? Color.green : Color.codexMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("活跃调用")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.codexMuted)
                            .lineLimit(1)
                        Text("\(supervisor.activeRequests)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.codexInk)
                            .lineLimit(1)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("外部总请求")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.codexMuted)
                            .lineLimit(1)
                        Text("\(supervisor.todayRequests)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.codexInk)
                            .lineLimit(1)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("网关运行时间")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.codexMuted)
                            .lineLimit(1)
                        Text(supervisor.uptimeText)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.codexInk)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.codexCard)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
        )
    }

    private func telemetryCard(for item: GatewayTelemetryItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(item.title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)
                Spacer()
                Text(item.sourceTag)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color(nsColor: item.sourceTagColor).opacity(0.12), in: Capsule())
                    .foregroundStyle(Color(nsColor: item.sourceTagColor))
                    .lineLimit(1)
            }

            Text(item.value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.codexInk)
                .lineLimit(1)

            Text(item.note)
                .font(.system(size: 9.5))
                .foregroundStyle(Color.codexMuted)
                .lineLimit(1)
        }
        .padding(10)
        .background(Color.codexCard)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
        )
    }

    private var bridgeTopologyFlowSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("账号能力桥接拓扑")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(Color.codexInk)
                .lineLimit(1)

            HStack(spacing: 10) {
                flowBox(title: "外部 Agent 消费", detail: "Cursor / Claude Code\nHermes / Aider / Cline\n终端脚本 / Python SDK", color: .blue)
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.codexMuted)
                flowBox(title: "Codexling 协议桥接中枢", detail: "OpenAI ↔ Anthropic 转译\n全量模型动态透传解析\n127.0.0.1 环回鉴权保护", color: .purple)
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.codexMuted)
                flowBox(title: "已登录供应商账号池", detail: "Google Gemini (支持 3.7 Flash)\nDeepSeek (支持 V4 Pro / R1)\nOpenCode / Codex 账号", color: .green)
            }
        }
    }

    private func flowBox(title: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(Color.codexMuted)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.codexCard)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
        )
    }

    // MARK: - Tab 1: Connect / Models & Integration Content (按供应商聚合模块化显示)
    private var connectContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 本地网关服务控制 (运行状态 / 开启/停止服务)
            heroControlCard

            // 顶部通用标准接入配置
            universalConnectionBar

            CodexDivider(.horizontal)

            // 供应商聚合模块列表 (彻底解决换行与多账号重复卡片问题)
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("按供应商聚合 · 快速接入方案与全量模型")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(Color.codexInk)
                    Text("所有账号已自动桥接为标准 OpenAI 与 Anthropic API 格式，点击模型卡片即可一键复制。")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.codexMuted)
                }

                ForEach(store.providerSections) { section in
                    providerSectionCard(section)
                }
            }
        }
    }

    // MARK: - 顶部通用连接参数条
    private var universalConnectionBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "network.badge.shield.half.filled")
                        .foregroundStyle(Color.codexInk)
                        .font(.system(size: 14, weight: .semibold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("通用网关接入参数")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.codexInk)
                        Text("兼容 99% 的 AI Agent 客户端（如 Cursor、Hermes、Aider、Claude Code 等）")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.codexMuted)
                    }
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.allModelNamesListString, forType: .string)
                    copiedAllModels = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedAllModels = false
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: copiedAllModels ? "checkmark" : "doc.on.doc")
                        Text(copiedAllModels ? "已复制全量模型名" : "复制全部可用模型名")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.codexMist, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .foregroundStyle(copiedAllModels ? Color.green : Color.codexInk)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                // OpenAI Base URL
                connectionTile(
                    title: "OpenAI 兼容 Base URL (推荐)",
                    value: store.openAIBaseURL,
                    isCopied: copiedEndpoint
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.openAIBaseURL, forType: .string)
                    copiedEndpoint = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedEndpoint = false
                    }
                }

                // Anthropic Base URL
                connectionTile(
                    title: "Anthropic Messages 端点",
                    value: store.anthropicBaseURL,
                    isCopied: false
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.anthropicBaseURL, forType: .string)
                }

                // API Key
                connectionTile(
                    title: "本地授权 API Key",
                    value: store.localToken,
                    isCopied: copiedKey
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.localToken, forType: .string)
                    copiedKey = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedKey = false
                    }
                }
            }

            // Minimal dynamic pass-through footer
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                Text("全量模型动态透传已生效：直接在客户端指定上游支持的任意模型名即可原生调用。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.codexMuted)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(Color.codexCard)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
        )
    }

    private func connectionTile(title: String, value: String, isCopied: Bool, copyAction: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Color.codexMuted)
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.codexInk)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 2)

                Button(action: copyAction) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(isCopied ? Color.green : Color.codexMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.codexBackground.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.codexLine.opacity(0.25), lineWidth: 0.6)
        )
    }

    // MARK: - 供应商聚合模块卡片 (多账号切换 + 2列防折叠模型矩阵)
    private func providerSectionCard(_ section: GatewayProviderSection) -> some View {
        let activeGroup = section.accountGroups.first(where: { $0.id == selectedAccountBySection[section.id] }) ?? section.accountGroups[0]
        let isExpanded = expandedGroupIds.contains(activeGroup.id)
        let totalModelsCount = section.accountGroups.reduce(0) { $0 + $1.models.count }

        return VStack(alignment: .leading, spacing: 12) {
            // Header Row
            HStack(spacing: 10) {
                BrandIconView(
                    asset: section.brandAsset,
                    size: 34,
                    cornerRadius: 8
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(section.providerTitle)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.codexInk)

                        Text("\(section.accountGroups.count) 个已连接账号 · 共 \(totalModelsCount) 款模型")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.codexPrimary.opacity(0.06), in: Capsule())
                            .foregroundStyle(Color.codexInk)
                    }

                    Text(section.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.codexMuted)
                        .lineLimit(1)
                }

                Spacer()

                // 供应商独立模型聚合与额度调度开关
                HStack(spacing: 8) {
                    VStack(alignment: .trailing, spacing: 1.5) {
                        HStack(spacing: 4) {
                            Image(systemName: store.isProviderConsolidated(section.id) ? "square.stack.3d.up.fill" : "square.stack.3d.up")
                                .font(.system(size: 10))
                                .foregroundStyle(store.isProviderConsolidated(section.id) ? Color.purple : Color.codexMuted)
                            Text("账号池聚合")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.codexInk)
                        }
                        Text(store.isProviderConsolidated(section.id) ? "额度健康调度 · 故障转移" : "逐账号独立隔离")
                            .font(.system(size: 9.5))
                            .foregroundStyle(store.isProviderConsolidated(section.id) ? Color.purple : Color.codexMuted)
                    }

                    Toggle("", isOn: Binding(
                        get: { store.isProviderConsolidated(section.id) },
                        set: { store.setProviderConsolidated(section.id, enabled: $0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    store.isProviderConsolidated(section.id)
                        ? Color.purple.opacity(0.06)
                        : Color.codexMist.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            store.isProviderConsolidated(section.id)
                                ? Color.purple.opacity(0.25)
                                : Color.codexLine.opacity(0.3),
                            lineWidth: 0.8
                        )
                )
            }

            // Account Switcher Bar (Only shown when multiple accounts exist)
            if section.accountGroups.count > 1 {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(section.accountGroups) { grp in
                                let isSelected = activeGroup.id == grp.id
                                Button {
                                    selectedAccountBySection[section.id] = grp.id
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        proxy.scrollTo(grp.id, anchor: .center)
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Circle()
                                            .fill(grp.isProxyEnabled ? (isSelected ? Color.green : Color.green.opacity(0.7)) : Color.codexMuted.opacity(0.4))
                                            .frame(width: 5.5, height: 5.5)

                                        Text(grp.accountName)
                                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                            .lineLimit(1)

                                        Text(grp.isProxyEnabled ? grp.badgeText : "已停用")
                                            .font(.system(size: 9.5))
                                            .opacity(isSelected ? 0.9 : 0.65)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 10)
                                    .frame(height: 27)
                                    .background(
                                        isSelected ? Color.codexPrimary : Color.codexMist.opacity(0.55),
                                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    )
                                    .foregroundStyle(isSelected ? Color.codexOnPrimary : (grp.isProxyEnabled ? Color.codexInk : Color.codexMuted))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(isSelected ? Color.clear : Color.codexLine.opacity(0.3), lineWidth: 0.6)
                                    )
                                }
                                .id(grp.id)
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 1)
                        .background(ScrollIndicatorHider())
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: activeGroup.id) { _, newID in
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                    }
                }
            }

            // Active Account Workspace (Clean, spacious, responsive)
            VStack(alignment: .leading, spacing: 10) {
                // Info & Primary Actions Row
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2.5) {
                        HStack(spacing: 6) {
                            Text("当前选定账号:")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(Color.codexMuted)

                            Text(activeGroup.accountName)
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundStyle(Color.codexInk)
                                .lineLimit(1)

                            Text(activeGroup.isProxyEnabled ? activeGroup.badgeText : "代理已停用")
                                .font(.system(size: 9.5, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(activeGroup.isProxyEnabled ? Color.green.opacity(0.12) : Color.codexMist, in: Capsule())
                                .foregroundStyle(activeGroup.isProxyEnabled ? Color.green : Color.codexMuted)
                                .lineLimit(1)
                        }

                        if let email = activeGroup.email, !email.isEmpty {
                            Text(email)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.codexMuted)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if let connID = activeGroup.connectionID {
                        let isSyncing = syncingConnectionIDs.contains(connID)
                        let isEnabled = activeGroup.isProxyEnabled
                        let isAllowed = activeGroup.isProxyAllowed
                        let circleColor = isSyncing ? Color.orange : (isEnabled ? Color.green : (isAllowed ? Color.codexMuted : Color.orange))
                        let textColor = isSyncing ? Color.orange : (isEnabled ? Color.green : (isAllowed ? Color.codexMuted : Color.orange))
                        let btnTitle = isSyncing ? (isEnabled ? "正在开启..." : "正在同步...") : (isEnabled ? "代理已开启" : (isAllowed ? "代理已关闭" : "OAuth 未就绪"))
                        let btnBg = isSyncing ? Color.orange.opacity(0.12) : (isEnabled ? Color.green.opacity(0.12) : (isAllowed ? Color.codexMist : Color.orange.opacity(0.12)))

                        Button {
                            guard isAllowed, !isSyncing else { return }
                            let willEnable = !isEnabled
                            if willEnable {
                                syncingConnectionIDs.insert(connID)
                                Task { @MainActor in
                                    if let ss = settingsStore {
                                        ss.setConnectionProxyEnabled(id: connID, enabled: true)
                                        store.toggleConnectionProxy(id: connID)

                                        let result = await ss.syncConnectionModels(id: connID)
                                        store.toggleConnectionProxy(id: connID)
                                        syncingConnectionIDs.remove(connID)

                                        switch result {
                                        case let .success(count, _):
                                            showToast("已开启 [\(activeGroup.accountName)] 代理 · 同步到 \(count) 款可用模型", systemImage: "checkmark.circle.fill", isSuccess: true)
                                        case let .warning(msg):
                                            showToast("已开启代理 · \(msg)", systemImage: "exclamationmark.triangle.fill", isSuccess: true)
                                        case let .failure(errMsg):
                                            ss.setConnectionProxyEnabled(id: connID, enabled: false)
                                            store.toggleConnectionProxy(id: connID)
                                            showToast("开启代理失败：\(errMsg)", systemImage: "xmark.circle.fill", isSuccess: false)
                                        }
                                    } else {
                                        store.toggleConnectionProxy(id: connID)
                                        syncingConnectionIDs.remove(connID)
                                        showToast("已开启网关代理", systemImage: "checkmark.circle.fill", isSuccess: true)
                                    }
                                }
                            } else {
                                if let ss = settingsStore {
                                    ss.setConnectionProxyEnabled(id: connID, enabled: false)
                                }
                                store.toggleConnectionProxy(id: connID)
                                showToast("已关闭 [\(activeGroup.accountName)] 网关代理", systemImage: "pause.circle.fill", isSuccess: true)
                            }
                        } label: {
                            HStack(spacing: 4.5) {
                                if isSyncing {
                                    ProgressView()
                                        .controlSize(.mini)
                                } else {
                                    Circle()
                                        .fill(circleColor)
                                        .frame(width: 5.5, height: 5.5)
                                }
                                Text(btnTitle)
                            }
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                            .background(btnBg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .foregroundStyle(textColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(isSyncing ? Color.orange.opacity(0.4) : (isEnabled ? Color.green.opacity(0.3) : (isAllowed ? Color.codexLine.opacity(0.4) : Color.orange.opacity(0.4))), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(CodexPressableStyle(cornerRadius: 6))
                        .help(!isAllowed ? "请重新登录 OAuth 账号后再开启代理" : (isSyncing ? "正在验证授权并同步可用模型..." : (isEnabled ? "点击关闭该账号的网关代理" : "点击开启该账号的网关代理并同步模型")))
                        .disabled(!isAllowed || isSyncing)
                    }

                    // One-Click Copy Parameters Button (Codex Primary Black button)
                    if activeGroup.isProxyEnabled {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(activeGroup.sampleConfigSnippet, forType: .string)
                            copiedGroupId = activeGroup.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedGroupId = nil
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: copiedGroupId == activeGroup.id ? "checkmark" : "doc.on.doc")
                                Text(copiedGroupId == activeGroup.id ? "已复制接入参数" : "一键复制接入参数")
                            }
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(copiedGroupId == activeGroup.id ? Color.green : Color.codexPrimary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .foregroundStyle(Color.codexOnPrimary)
                        }
                        .buttonStyle(CodexPressableStyle(cornerRadius: 6))

                        // Expand Drawer Button
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                if isExpanded {
                                    expandedGroupIds.remove(activeGroup.id)
                                } else {
                                    expandedGroupIds.insert(activeGroup.id)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(isExpanded ? "收起" : "全部模型 (\(activeGroup.models.count))")
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            }
                            .font(.system(size: 10.5, weight: .medium))
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                            .background(Color.codexMist, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .foregroundStyle(Color.codexInk)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(CodexPressableStyle(cornerRadius: 6))
                    }
                }

                // Syncing In-Progress Banner
                if let connID = activeGroup.connectionID, syncingConnectionIDs.contains(connID) {
                    HStack(spacing: 9) {
                        ProgressView()
                            .controlSize(.small)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("正在验证授权并同步可用模型目录...")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.codexInk)
                            Text("正在向官方服务验证 OAuth 凭据并拉取可用模型配额，首次或重连通常需要 1~2 秒，完成后将自动刷新网关模型路由。")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.codexMuted)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.purple.opacity(0.25), lineWidth: 0.8)
                    )
                } else if !activeGroup.isProxyEnabled {
                    // Paused Banner when proxy is disabled
                    HStack(spacing: 8) {
                        Image(systemName: activeGroup.isProxyAllowed ? "pause.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(activeGroup.isProxyAllowed ? "该账号已关闭网关代理" : "OAuth 未就绪")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.codexInk)

                            Text(activeGroup.isProxyAllowed ? "该账号的所有模型已在网关模型列表 (/v1/models) 中隐藏，且不再参与网关路由分流。" : "请重新登录账号；Gateway 只使用有效凭据出流。")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.codexMuted)
                        }

                        Spacer()
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.orange.opacity(0.25), lineWidth: 0.8)
                    )
                } else if activeGroup.models.isEmpty, let connID = activeGroup.connectionID {
                    // Enabled but 0 models banner with one-click re-sync
                    HStack(spacing: 9) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("代理已开启 · 暂未发现可用模型")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.codexInk)

                            Text("官方授权已连接，但尚未拉取到可用的模型列表。点击右侧按钮可重新同步，或在下方手动添加自定义透传模型。")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.codexMuted)
                        }

                        Spacer()

                        Button {
                            syncingConnectionIDs.insert(connID)
                            Task { @MainActor in
                                if let ss = settingsStore {
                                    let result = await ss.syncConnectionModels(id: connID)
                                    store.toggleConnectionProxy(id: connID)
                                    syncingConnectionIDs.remove(connID)
                                    switch result {
                                    case let .success(count, _):
                                        showToast("已成功同步 \(count) 款可用模型", systemImage: "checkmark.circle.fill", isSuccess: true)
                                    case let .warning(msg):
                                        showToast(msg, systemImage: "exclamationmark.triangle.fill", isSuccess: true)
                                    case let .failure(errMsg):
                                        showToast("同步失败：\(errMsg)", systemImage: "xmark.circle.fill", isSuccess: false)
                                    }
                                } else {
                                    syncingConnectionIDs.remove(connID)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text("立即同步模型")
                            }
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 9)
                            .frame(height: 25)
                            .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .foregroundStyle(Color.orange)
                        }
                        .buttonStyle(CodexPressableStyle(cornerRadius: 5))
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.orange.opacity(0.25), lineWidth: 0.8)
                    )
                }

                // Recommended Model Grid (2 Columns, spacious tiles, ZERO WRAPPING!)
                if activeGroup.isProxyEnabled && !activeGroup.recommendedModels.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(activeGroup.recommendedModels, id: \.self) { modelId in
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(modelId, forType: .string)
                                copiedModelId = modelId
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    copiedModelId = nil
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: copiedModelId == modelId ? "checkmark.circle.fill" : "cube.fill")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(copiedModelId == modelId ? Color.green : Color.codexMuted)

                                    Text(modelId)
                                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(copiedModelId == modelId ? Color.green : Color.codexInk)
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    Spacer(minLength: 0)

                                    Image(systemName: copiedModelId == modelId ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 9))
                                        .foregroundStyle(copiedModelId == modelId ? Color.green : Color.codexMuted.opacity(0.7))
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 7)
                                .background(Color.codexBackground.opacity(0.75), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(copiedModelId == modelId ? Color.green.opacity(0.6) : Color.codexLine.opacity(0.3), lineWidth: 0.6)
                                )
                            }
                            .buttonStyle(.plain)
                            .help("点击复制 \(modelId)")
                        }
                    }
                }

                // Expanded Drawer (Models Table)
                if activeGroup.isProxyEnabled && isExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        CodexDivider(.horizontal)

                        // Quick Connect Tip
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.orange)
                                .padding(.top, 1)
                            Text(activeGroup.quickConnectTip)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Color.codexInk)
                                .lineSpacing(2)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.codexPrimary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        // Custom Model Input & Models Table
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("可访问模型全量清单 (\(activeGroup.models.count))")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.codexInk)

                                Spacer()

                                Button {
                                    if addingModelGroupId == activeGroup.id {
                                        addingModelGroupId = nil
                                    } else {
                                        addingModelGroupId = activeGroup.id
                                        customModelInput = ""
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: addingModelGroupId == activeGroup.id ? "xmark" : "plus.circle")
                                        Text(addingModelGroupId == activeGroup.id ? "取消" : "添加/自定义透传模型")
                                    }
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.codexInk)
                                }
                                .buttonStyle(.plain)
                            }

                            if addingModelGroupId == activeGroup.id {
                                HStack(spacing: 6) {
                                    TextField("输入模型 ID (例如 gemini-3.7-flash, deepseek-v4-pro...)", text: $customModelInput)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 10.5, design: .monospaced))

                                    Button("添加") {
                                        let trimmed = customModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !trimmed.isEmpty {
                                            store.addCustomModel(trimmed, toGroupId: activeGroup.id)
                                            addingModelGroupId = nil
                                            customModelInput = ""
                                        }
                                    }
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .frame(height: 24)
                                    .background(Color.codexPrimary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                                    .foregroundStyle(Color.codexOnPrimary)
                                    .buttonStyle(CodexPressableStyle(cornerRadius: 5))
                                }
                                .padding(.vertical, 4)
                            }

                            ForEach(activeGroup.models) { model in
                                HStack(spacing: 8) {
                                    Text(model.modelName)
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Color.codexInk)
                                        .frame(width: 190, alignment: .leading)
                                        .lineLimit(1)

                                    Text(model.capability)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color.codexMuted)
                                        .frame(width: 150, alignment: .leading)
                                        .lineLimit(1)

                                    Text(model.description)
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.codexMuted)
                                        .lineLimit(1)

                                    Spacer(minLength: 4)

                                    if model.isCustom {
                                        Button {
                                            store.removeCustomModel(model.modelName, fromGroupId: activeGroup.id)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 9))
                                                .foregroundStyle(Color.red.opacity(0.7))
                                        }
                                        .buttonStyle(.plain)
                                        .help("移除自定义透传模型")
                                    }

                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(model.modelName, forType: .string)
                                        copiedModelId = model.id
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                            copiedModelId = nil
                                        }
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: copiedModelId == model.id ? "checkmark" : "doc.on.doc")
                                            Text(copiedModelId == model.id ? "已复制" : "复制")
                                        }
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(copiedModelId == model.id ? Color.green : Color.codexMuted)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.codexBackground.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(10)
            .background(Color.codexBackground.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.codexLine.opacity(0.25), lineWidth: 0.6)
            )
        }
        .padding(12)
        .background(Color.codexCard)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
        )
    }

    // MARK: - Tab 3: Requests Content (实时流 + 账本历史追溯)
    private var requestsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Gateway 请求流与明细")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.codexInk)
                            .lineLimit(1)

                        if store.isRequestsLoading {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                    Text("记录入向协议、出向路由、TTFT 首字延迟、真实/估算 Token 保真度及错误状态")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.codexMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .layoutPriority(0)

                Spacer(minLength: 6)

                // 列设置按钮
                Button {
                    store.isColumnSettingsPresented = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 10, weight: .semibold))
                        Text("列设置")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(Color.codexMist, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .foregroundStyle(Color.codexInk)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.7)
                    )
                }
                .buttonStyle(CodexPressableStyle(cornerRadius: 5))
                .help("自定义请求流列表显示列（勾选/取消字段）")

                // 手动刷新按钮
                Button {
                    Task {
                        await store.refreshRequestsList()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(store.isRequestsLoading ? 360 : 0))
                            .animation(store.isRequestsLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: store.isRequestsLoading)
                        Text("刷新")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(Color.codexMist, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .foregroundStyle(Color.codexInk)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.7)
                    )
                }
                .buttonStyle(CodexPressableStyle(cornerRadius: 5))
                .disabled(store.isRequestsLoading)
                .help("手动刷新请求列表与状态")

                dateRangeSelectorView
                    .layoutPriority(1)
            }

            if store.selectedDateRange == .custom {
                customDateRangePickerBar
            }

            if store.isRequestsLoading && store.detailedRequestsList.isEmpty && store.requestsList.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("正在查询请求流与明细日志...")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.codexInk)
                        .lineLimit(1)
                    Text("正在连接本地 SQLite 遥测账本检索数据...")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.codexMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(Color.codexCard)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
                )
            } else if store.detailedRequestsList.isEmpty && store.requestsList.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "waveform.path.badge.plus")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.codexMuted)
                    Text("暂无外部 Agent 反代流水")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.codexInk)
                        .lineLimit(1)
                    Text("本地多协议网关已在 http://127.0.0.1:\(String(supervisor.port)) 准备就绪。\n当第三方 Agent 发送请求时，协议转换、TTFT 延迟与 Token 消耗将在此实时记录并持久化。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.codexMuted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(Color.codexCard)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
                )
            } else if !store.detailedRequestsList.isEmpty {
                ZStack {
                    VStack(alignment: .leading, spacing: 6) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 6) {
                                requestsTableHeaderView

                                VStack(spacing: 6) {
                                    ForEach(store.detailedRequestsList) { req in
                                        detailedRequestRow(for: req)
                                    }
                                }
                            }
                            .frame(width: effectiveTableWidth, alignment: .leading)
                        }

                        requestsPaginationBar
                    }
                    .opacity(store.isRequestsLoading ? 0.45 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: store.isRequestsLoading)

                    if store.isRequestsLoading {
                        HStack(spacing: 7) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在加载第 \(store.requestsCurrentPage) 页...")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Color.codexInk)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.codexCard.opacity(0.95))
                        .clipShape(Capsule())
                        .shadow(color: Color.black.opacity(0.12), radius: 8, y: 3)
                        .overlay(
                            Capsule()
                                .stroke(Color.codexLine.opacity(0.4), lineWidth: 0.8)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
            } else {
                // Table Header / Column Titles for In-memory Fallback List
                ZStack {
                    VStack(alignment: .leading, spacing: 6) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 6) {
                                requestsTableHeaderView

                                VStack(spacing: 6) {
                                    ForEach(store.requestsList) { req in
                                        fallbackRequestRow(for: req)
                                    }
                                }
                            }
                            .frame(width: effectiveTableWidth, alignment: .leading)
                        }
                    }
                    .opacity(store.isRequestsLoading ? 0.45 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: store.isRequestsLoading)

                    if store.isRequestsLoading {
                        HStack(spacing: 7) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在更新请求数据...")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Color.codexInk)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.codexCard.opacity(0.95))
                        .clipShape(Capsule())
                        .shadow(color: Color.black.opacity(0.12), radius: 8, y: 3)
                        .overlay(
                            Capsule()
                                .stroke(Color.codexLine.opacity(0.4), lineWidth: 0.8)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
            }

            Spacer(minLength: 16)
        }
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: GatewayTableWidthKey.self, value: geo.size.width)
            }
        }
        .onPreferenceChange(GatewayTableWidthKey.self) { newWidth in
            if newWidth > 0 && abs(tableContainerWidth - newWidth) > 1 {
                tableContainerWidth = newWidth
            }
        }
    }

    // MARK: - 请求流动态列渲染组件

    private var minTableWidth: CGFloat {
        let colWidths = store.orderedVisibleColumns.reduce(CGFloat(0)) { $0 + $1.minWidth }
        let spacing = CGFloat(max(0, store.orderedVisibleColumns.count - 1)) * 6.0
        return colWidths + spacing + 20.0
    }

    private var effectiveTableWidth: CGFloat {
        max(minTableWidth, tableContainerWidth)
    }

    private func columnWidth(for col: GatewayRequestColumn) -> CGFloat {
        let base = col.minWidth
        let availableExtra = max(0, effectiveTableWidth - minTableWidth)
        let totalFlexWeight = store.orderedVisibleColumns.reduce(CGFloat(0)) { $0 + $1.flexWeight }
        guard availableExtra > 0, totalFlexWeight > 0 else {
            return base
        }
        return base + (col.flexWeight / totalFlexWeight) * availableExtra
    }

    private var requestsTableHeaderView: some View {
        HStack(spacing: 6) {
            ForEach(store.orderedVisibleColumns) { col in
                requestHeaderCell(for: col)
            }
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(Color.codexMuted)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: effectiveTableWidth, alignment: .leading)
        .background(Color.codexMist.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.codexLine.opacity(0.4), lineWidth: 0.8)
        )
    }

    @ViewBuilder
    private func requestHeaderCell(for column: GatewayRequestColumn) -> some View {
        Text(column.title)
            .frame(width: columnWidth(for: column), alignment: column.alignment)
            .lineLimit(1)
    }

    @ViewBuilder
    private func detailedRequestRow(for req: GatewayTelemetryEventDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(store.orderedVisibleColumns) { col in
                    detailedRequestCell(for: col, req: req)
                }
            }

            if let err = req.errorMessage, !err.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9.5))
                    Text(err)
                        .font(.system(size: 10))
                }
                .foregroundStyle(Color.red)
                .lineLimit(1)
            }
        }
        .padding(10)
        .frame(width: effectiveTableWidth, alignment: .leading)
        .background(Color.codexCard)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
        )
    }

    @ViewBuilder
    private func detailedRequestCell(for column: GatewayRequestColumn, req: GatewayTelemetryEventDetail) -> some View {
        Group {
            switch column {
            case .time:
                Text(req.formattedTime)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)
                    .help(req.formattedDateTime)

            case .id:
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(req.id, forType: .string)
                } label: {
                    HStack(spacing: 2) {
                        Text(String(req.id.suffix(7)))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.codexMuted)
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.codexMuted.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
                .help("请求 ID: \(req.id)\n点击复制")

            case .agent:
                Text(req.agent)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.codexInk)
                    .lineLimit(1)
                    .truncationMode(.tail)

            case .ingressProtocol:
                Text(req.ingressProtocol)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)

            case .provider:
                Text(req.provider.isEmpty ? "-" : req.provider)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.codexInk)
                    .lineLimit(1)
                    .truncationMode(.tail)

            case .account:
                Text(req.account.isEmpty ? "-" : req.account)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)

            case .targetModel:
                Text(req.targetModel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.codexInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(req.modelAlias.isEmpty || req.modelAlias == req.targetModel ? req.targetModel : "请求别名: \(req.modelAlias)\n目标模型: \(req.targetModel)")

            case .stream:
                Text(req.isStream ? "SSE" : "Sync")
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(req.isStream ? Color.blue.opacity(0.12) : Color.codexMuted.opacity(0.12), in: Capsule())
                    .foregroundStyle(req.isStream ? Color.blue : Color.codexMuted)
                    .lineLimit(1)

            case .tokens:
                Group {
                    if let inTok = req.inputTokens, let outTok = req.outputTokens {
                        Text("\(inTok)↓ \(outTok)↑")
                    } else if let total = req.totalTokens, total > 0 {
                        Text("\(total) toks")
                    } else {
                        Text("-")
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.codexInk)
                .lineLimit(1)

            case .cacheTokens:
                Group {
                    if let read = req.cacheReadTokens, read > 0 {
                        Text("读:\(read)")
                    } else if let write = req.cacheWriteTokens, write > 0 {
                        Text("写:\(write)")
                    } else {
                        Text("-")
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.codexMuted)
                .lineLimit(1)

            case .tools:
                Group {
                    if req.toolCallsCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.system(size: 8))
                            Text("\(req.toolCallsCount)")
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        }
                        .foregroundStyle(Color.purple)
                    } else {
                        Text("-")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.codexMuted)
                    }
                }
                .lineLimit(1)

            case .cost:
                Group {
                    if let cost = req.estimatedCost, cost > 0 {
                        Text("$\(String(format: "%.4f", cost))")
                    } else {
                        Text("-")
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.codexInk)
                .lineLimit(1)

            case .ttft:
                Group {
                    if let ttft = req.ttftMs {
                        Text("\(ttft)ms")
                    } else {
                        Text("-")
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.codexMuted)
                .lineLimit(1)

            case .latency:
                Text("\(req.latencyMs)ms")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color.codexInk)
                    .lineLimit(1)

            case .fidelity:
                Text(req.fidelity == "actual" ? "实际" : (req.fidelity == "estimated" ? "估算" : "无"))
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(req.fidelity == "actual" ? Color.green.opacity(0.12) : Color.orange.opacity(0.12), in: Capsule())
                    .foregroundStyle(req.fidelity == "actual" ? Color.green : Color.orange)
                    .lineLimit(1)

            case .status:
                Text(req.isSuccess ? "200 OK" : "\(req.statusCode)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(req.isSuccess ? Color.green : Color.red)
                    .lineLimit(1)
            }
        }
        .frame(width: columnWidth(for: column), alignment: column.alignment)
    }

    @ViewBuilder
    private func fallbackRequestRow(for req: GatewayRequestRow) -> some View {
        HStack(spacing: 6) {
            ForEach(store.orderedVisibleColumns) { col in
                fallbackRequestCell(for: col, req: req)
            }
        }
        .padding(10)
        .frame(width: effectiveTableWidth, alignment: .leading)
        .background(Color.codexCard)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
        )
    }

    @ViewBuilder
    private func fallbackRequestCell(for column: GatewayRequestColumn, req: GatewayRequestRow) -> some View {
        Group {
            switch column {
            case .time:
                Text(req.time)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)

            case .id:
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(req.id, forType: .string)
                } label: {
                    HStack(spacing: 2) {
                        Text(String(req.id.suffix(7)))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.codexMuted)
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.codexMuted.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
                .help("请求 ID: \(req.id)\n点击复制")

            case .agent:
                Text(req.agent)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.codexInk)
                    .lineLimit(1)
                    .truncationMode(.tail)

            case .ingressProtocol:
                Text(req.ingressProtocol)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)

            case .provider:
                Text(req.targetProvider.isEmpty ? "-" : req.targetProvider)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.codexInk)
                    .lineLimit(1)
                    .truncationMode(.tail)

            case .account:
                Text("-")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)

            case .targetModel:
                Text(req.targetModel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.codexInk)
                    .lineLimit(1)
                    .truncationMode(.middle)

            case .stream:
                Text("Sync")
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(Color.codexMuted.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)

            case .tokens:
                Group {
                    if req.tokens > 0 {
                        Text("\(req.tokens) toks")
                    } else {
                        Text("-")
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.codexInk)
                .lineLimit(1)

            case .cacheTokens:
                Text("-")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)

            case .tools:
                Text("-")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)

            case .cost:
                Text("-")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.codexInk)
                    .lineLimit(1)

            case .ttft:
                Group {
                    if req.ttftMs > 0 {
                        Text("\(req.ttftMs)ms")
                    } else {
                        Text("-")
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.codexMuted)
                .lineLimit(1)

            case .latency:
                Text("\(req.latencyMs)ms")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color.codexInk)
                    .lineLimit(1)

            case .fidelity:
                Text(req.fidelity == "actual" ? "实际" : (req.fidelity == "estimated" ? "估算" : req.fidelity))
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.blue)
                    .lineLimit(1)

            case .status:
                Text(req.status)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.green)
                    .lineLimit(1)
            }
        }
        .frame(width: columnWidth(for: column), alignment: column.alignment)
    }

    // MARK: - 共享日期筛选组件与分页栏

    private var dateRangeSelectorView: some View {
        HStack(spacing: 2) {
            ForEach(GatewayDateRange.allCases) { r in
                let isSelected = store.selectedDateRange == r
                Button {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                        store.selectedDateRange = r
                    }
                } label: {
                    HStack(spacing: 3) {
                        if r == .custom {
                            Image(systemName: "slider.horizontal.below.rectangle")
                                .font(.system(size: 9))
                        }
                        Text(r.shortLabel)
                            .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                    }
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(
                        isSelected
                            ? Color.codexCard
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    )
                    .shadow(color: isSelected ? Color.black.opacity(0.08) : Color.clear, radius: 1.5, y: 0.5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .stroke(isSelected ? Color.codexLine.opacity(0.4) : Color.clear, lineWidth: 0.6)
                    )
                    .foregroundStyle(isSelected ? Color.codexInk : Color.codexMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2.5)
        .background(Color.codexMist, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.7)
        )
    }

    private var customDateRangePickerBar: some View {
        HStack(spacing: 8) {
            // 左侧：时间区间选择胶囊
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.codexPrimary)

                HStack(spacing: 4) {
                    Text("从")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.codexMuted)
                    DatePicker("", selection: $store.customStartDate, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .controlSize(.small)
                }

                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.codexMuted.opacity(0.8))

                HStack(spacing: 4) {
                    Text("至")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.codexMuted)
                    DatePicker("", selection: $store.customEndDate, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.codexMist.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
            )

            // 应用筛选按钮
            Button {
                store.applyCustomDateRange(start: store.customStartDate, end: store.customEndDate)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                    Text("应用")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Color.codexPrimary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .foregroundStyle(.white)
            }
            .buttonStyle(CodexPressableStyle(cornerRadius: 6))

            Spacer(minLength: 8)

            // 快捷区间预设
            HStack(spacing: 4) {
                customPresetChip("近1小时", hours: 1)
                customPresetChip("近6小时", hours: 6)
                customPresetChip("近24小时", hours: 24)
                customPresetChip("近3天", days: 3)
                customPresetChip("近7天", days: 7)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.codexCard)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.codexLine.opacity(0.4), lineWidth: 0.8)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func customPresetChip(_ label: String, hours: Int? = nil, days: Int? = nil) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                if let hours {
                    store.setCustomPreset(hours: hours)
                } else if let days {
                    store.setCustomPreset(days: days)
                }
            }
        } label: {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Color.codexMist, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .foregroundStyle(Color.codexInk)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color.codexLine.opacity(0.3), lineWidth: 0.6)
                )
        }
        .buttonStyle(.plain)
    }

    private var requestsPaginationBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("共 \(store.requestsTotalCount) 条记录")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)

                if store.isRequestsLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
            }

            Spacer(minLength: 6)

            HStack(spacing: 4) {
                Text("每页")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)

                Picker("", selection: Binding(
                    get: { store.requestsPageSize },
                    set: { store.setPageSize($0) }
                )) {
                    Text("10 条").tag(10)
                    Text("20 条").tag(20)
                    Text("50 条").tag(50)
                    Text("100 条").tag(100)
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 80)
                .disabled(store.isRequestsLoading)
            }

            Divider()
                .frame(height: 14)

            HStack(spacing: 4) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.goToPage(1)
                    }
                }) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 10))
                        .padding(4)
                }
                .disabled(store.requestsCurrentPage <= 1 || store.isRequestsLoading)
                .buttonStyle(.plain)
                .foregroundStyle((store.requestsCurrentPage <= 1 || store.isRequestsLoading) ? Color.codexMuted.opacity(0.35) : Color.codexInk)

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.prevPage()
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(4)
                }
                .disabled(store.requestsCurrentPage <= 1 || store.isRequestsLoading)
                .buttonStyle(.plain)
                .foregroundStyle((store.requestsCurrentPage <= 1 || store.isRequestsLoading) ? Color.codexMuted.opacity(0.35) : Color.codexInk)

                Text("第 \(store.requestsCurrentPage) / \(store.requestsTotalPages) 页")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.codexInk)
                    .padding(.horizontal, 4)
                    .lineLimit(1)

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.nextPage()
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(4)
                }
                .disabled(store.requestsCurrentPage >= store.requestsTotalPages || store.isRequestsLoading)
                .buttonStyle(.plain)
                .foregroundStyle((store.requestsCurrentPage >= store.requestsTotalPages || store.isRequestsLoading) ? Color.codexMuted.opacity(0.35) : Color.codexInk)

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.goToPage(store.requestsTotalPages)
                    }
                }) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 10))
                        .padding(4)
                }
                .disabled(store.requestsCurrentPage >= store.requestsTotalPages || store.isRequestsLoading)
                .buttonStyle(.plain)
                .foregroundStyle((store.requestsCurrentPage >= store.requestsTotalPages || store.isRequestsLoading) ? Color.codexMuted.opacity(0.35) : Color.codexInk)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(Color.codexCard)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
        )
    }

    // MARK: - Tab: Agents Content (Hermes & Pi 一键接入)
    private var agentsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let msg = agentConfigMessage {
                HStack(spacing: 8) {
                    Image(systemName: agentConfigSucceeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(agentConfigSucceeded ? Color.green : Color.red)
                    Text(msg)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.codexInk)
                    Spacer()
                    Button {
                        agentConfigMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.codexMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background((agentConfigSucceeded ? Color.green : Color.red).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            // Hermes Agent Card
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    BrandIconView(asset: .hermesAgent, size: 34, cornerRadius: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text("Hermes Agent")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.codexInk)
                            if !store.hasLoadedAgentIntegrationStatus || store.isRefreshingAgentIntegrationStatus {
                                Text("正在检测…")
                                    .font(.system(size: 9.5))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.codexMuted.opacity(0.12), in: Capsule())
                                    .foregroundStyle(Color.codexMuted)
                            } else if store.hermesAgentConfigured {
                                Text("已接入 Gateway")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.green.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.green)
                            } else if store.hermesAgentInstalled {
                                Text("已安装 / 未接入")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.blue.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.blue)
                            } else {
                                Text("未检测到 ~/.hermes")
                                    .font(.system(size: 9.5))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.codexMuted.opacity(0.12), in: Capsule())
                                    .foregroundStyle(Color.codexMuted)
                            }
                        }
                        Text("自主 Coding Agent，支持 Hooks 监控、网页端与 CLI TUI 交互")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.codexMuted)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        if store.hermesAgentConfigured {
                            Button {
                                guard configuringAgent == nil && unconfiguringAgent == nil else { return }
                                unconfiguringAgent = .hermes
                                agentConfigMessage = nil
                                Task {
                                    let result = await store.unconfigureHermesAgent()
                                    agentConfigSucceeded = result.success
                                    agentConfigMessage = result.message
                                    unconfiguringAgent = nil
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    if unconfiguringAgent == .hermes {
                                        ProgressView().controlSize(.small)
                                        Text("移除中…")
                                    } else {
                                        Image(systemName: "trash")
                                            .font(.system(size: 10))
                                        Text("移除")
                                    }
                                }
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .foregroundStyle(Color.red.opacity(0.9))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(Color.red.opacity(0.25), lineWidth: 0.8)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(configuringAgent != nil || unconfiguringAgent != nil)
                        }

                        Button {
                            guard configuringAgent == nil && unconfiguringAgent == nil else { return }
                            configuringAgent = .hermes
                            agentConfigMessage = nil
                            Task {
                                let res = await store.configureHermesAgent()
                                agentConfigSucceeded = res.success
                                agentConfigMessage = res.message
                                configuringAgent = nil
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if configuringAgent == .hermes {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(Color.codexOnPrimary)
                                    Text("接入中…")
                                } else {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 10))
                                    Text(store.hermesAgentConfigured ? "更新接入配置" : "一键接入 Gateway")
                                }
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .frame(minWidth: store.hermesAgentConfigured ? 92 : 118)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.codexPrimary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .foregroundStyle(Color.codexOnPrimary)
                        }
                        .buttonStyle(.plain)
                        .disabled(configuringAgent != nil || unconfiguringAgent != nil)
                        .opacity(configuringAgent != nil && configuringAgent != .hermes ? 0.55 : 1)
                    }
                }

                CodexDivider(.horizontal)

                VStack(alignment: .leading, spacing: 6) {
                    Text("接入配置参数")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.codexInk)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Provider:")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Color.codexMuted)
                                .frame(width: 80, alignment: .leading)
                            Text("Codexling")
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.codexInk)
                        }
                        HStack {
                            Text("Base URL:")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Color.codexMuted)
                                .frame(width: 80, alignment: .leading)
                            Text("http://127.0.0.1:\(String(supervisor.port))/v1")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Color.codexInk)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.codexBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .padding(14)
            .background(Color.codexCard)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
            )

            // Pi Agent Card
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    BrandIconView(asset: .piAgent, size: 34, cornerRadius: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text("Pi Agent")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.codexInk)
                            if !store.hasLoadedAgentIntegrationStatus || store.isRefreshingAgentIntegrationStatus {
                                Text("正在检测…")
                                    .font(.system(size: 9.5))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.codexMuted.opacity(0.12), in: Capsule())
                                    .foregroundStyle(Color.codexMuted)
                            } else if store.piAgentConfigured {
                                Text("已接入 Gateway")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.green.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.green)
                            } else if store.piAgentInstalled {
                                Text("已安装 / 未接入")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.blue.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.blue)
                            } else {
                                Text("未检测到 ~/.pi")
                                    .font(.system(size: 9.5))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.codexMuted.opacity(0.12), in: Capsule())
                                    .foregroundStyle(Color.codexMuted)
                            }
                        }
                        Text("极简轻量级终端 Coding Agent，支持流式交互与多模型热切")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.codexMuted)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        if store.piAgentConfigured {
                            Button {
                                guard configuringAgent == nil && unconfiguringAgent == nil else { return }
                                unconfiguringAgent = .pi
                                agentConfigMessage = nil
                                Task {
                                    let result = await store.unconfigurePiAgent()
                                    agentConfigSucceeded = result.success
                                    agentConfigMessage = result.message
                                    unconfiguringAgent = nil
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    if unconfiguringAgent == .pi {
                                        ProgressView().controlSize(.small)
                                        Text("移除中…")
                                    } else {
                                        Image(systemName: "trash")
                                            .font(.system(size: 10))
                                        Text("移除")
                                    }
                                }
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .foregroundStyle(Color.red.opacity(0.9))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(Color.red.opacity(0.25), lineWidth: 0.8)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(configuringAgent != nil || unconfiguringAgent != nil)
                        }

                        Button {
                            guard configuringAgent == nil && unconfiguringAgent == nil else { return }
                            configuringAgent = .pi
                            agentConfigMessage = nil
                            Task {
                                let res = await store.configurePiAgent()
                                agentConfigSucceeded = res.success
                                agentConfigMessage = res.message
                                configuringAgent = nil
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if configuringAgent == .pi {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(Color.codexOnPrimary)
                                    Text("接入中…")
                                } else {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 10))
                                    Text(store.piAgentConfigured ? "更新接入配置" : "一键接入 Gateway")
                                }
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .frame(minWidth: store.piAgentConfigured ? 92 : 118)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.codexPrimary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .foregroundStyle(Color.codexOnPrimary)
                        }
                        .buttonStyle(.plain)
                        .disabled(configuringAgent != nil || unconfiguringAgent != nil)
                        .opacity(configuringAgent != nil && configuringAgent != .pi ? 0.55 : 1)
                    }
                }

                CodexDivider(.horizontal)

                VStack(alignment: .leading, spacing: 6) {
                    Text("模型注册: ~/.pi/agent/models.json · 默认模型: ~/.pi/agent/settings.json")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.codexMuted)
                }
            }
            .padding(14)
            .background(Color.codexCard)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
            )

            // 通用环境变量一键复制
            VStack(alignment: .leading, spacing: 10) {
                Text("通用 Agent / Cursor / Cline 环境变量")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.codexInk)

                HStack {
                    Text("export OPENAI_BASE_URL=http://127.0.0.1:\(String(supervisor.port))/v1\nexport OPENAI_API_KEY=\(supervisor.localToken)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Color.codexInk)
                        .lineSpacing(4)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("export OPENAI_BASE_URL=http://127.0.0.1:\(supervisor.port)/v1\nexport OPENAI_API_KEY=\(supervisor.localToken)", forType: .string)
                        agentConfigMessage = "已复制通用环境变量！可在任何终端直接贴入生效。"
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text("复制")
                        }
                        .font(.system(size: 10.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.codexCard)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(Color.codexBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .padding(14)
            .background(Color.codexCard)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
            )
        }
        .task {
            await store.refreshAgentIntegrationStatus()
        }
    }

    // MARK: - Tab 4: Doctor Content
    private var doctorContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 8) {
                ForEach(store.doctorChecks) { check in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: check.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(check.isSuccess ? .green : .orange)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(check.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.codexInk)
                                    .lineLimit(1)
                                Spacer()
                                Text(check.status)
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(check.isSuccess ? Color.green.opacity(0.12) : Color.orange.opacity(0.12), in: Capsule())
                                    .foregroundStyle(check.isSuccess ? Color.green : Color.orange)
                                    .lineLimit(1)
                            }
                            Text(check.detail)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Color.codexMuted)
                        }
                    }
                    .padding(11)
                    .background(Color.codexCard)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
                    )
                }
            }
        }
    }

}
