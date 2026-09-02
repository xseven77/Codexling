import AppKit
import SwiftUI

private enum GatewayLayoutMetrics {
    static let sidebarWidth: CGFloat = 166
    static let sidebarTopInset: CGFloat = 14
    static let windowTopInset: CGFloat = 14
    static let windowBottomInset: CGFloat = 12
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

private enum GatewayHeaderMinYKey: PreferenceKey {
    static let defaultValue = CGFloat.greatestFiniteMagnitude

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
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
    @State private var expandedGroupIds: Set<String> = []
    @State private var selectedAccountBySection: [String: String] = [:]
    @State private var showsStickyTitle: Bool = false
    @State private var agentConfigMessage: String? = nil
    @State private var agentConfigSucceeded = true
    @State private var configuringAgent: GatewayAgentConnectTarget? = nil

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
            Text(store.selectedTab.rawValue)
                .font(.system(size: 20, weight: .bold))
            Text(store.selectedTab.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Color.codexMuted)
        }
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
            // 区块二：本地对外标准网关与遥测 (127.0.0.1:58349)
            // ==========================================
            gatewayProxyTelemetryBlock
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
            HStack(alignment: .center) {
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
                    Text("经由本地网关中继转译的实际 API 调用、Token 消耗与流式延迟")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.codexMuted)
                        .lineLimit(1)
                }
                Spacer()
            }

            // 9-Grid Telemetry
            LazyVGrid(columns: [GridItem(.flexible(minimum: 180)), GridItem(.flexible(minimum: 180)), GridItem(.flexible(minimum: 180))], spacing: 8) {
                ForEach(store.telemetryItems) { item in
                    telemetryCard(for: item)
                }
            }

            // Bridge Flow
            bridgeTopologyFlowSection
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
                        let isEnabled = activeGroup.isProxyEnabled
                        let isAllowed = activeGroup.isProxyAllowed
                        let circleColor = isEnabled ? Color.green : (isAllowed ? Color.codexMuted : Color.orange)
                        let textColor = isEnabled ? Color.green : (isAllowed ? Color.codexMuted : Color.orange)
                        let btnTitle = isEnabled ? "代理已开启" : (isAllowed ? "代理已关闭" : "OAuth 未就绪")
                        let btnBg = isEnabled ? Color.green.opacity(0.12) : (isAllowed ? Color.codexMist : Color.orange.opacity(0.12))

                        Button {
                            guard isAllowed else { return }
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if let ss = settingsStore {
                                    // Use the state rendered in this view as the source of
                                    // truth. A toggle can write the opposite value when the
                                    // Gateway cache and settings-store cache were loaded at
                                    // different times.
                                    ss.setConnectionProxyEnabled(id: connID, enabled: !isEnabled)
                                    store.toggleConnectionProxy(id: connID)
                                } else {
                                    store.toggleConnectionProxy(id: connID)
                                }
                            }
                        } label: {
                            HStack(spacing: 4.5) {
                                Circle()
                                    .fill(circleColor)
                                    .frame(width: 5.5, height: 5.5)
                                Text(btnTitle)
                            }
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                            .background(btnBg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .foregroundStyle(textColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(isEnabled ? Color.green.opacity(0.3) : (isAllowed ? Color.codexLine.opacity(0.4) : Color.orange.opacity(0.4)), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(CodexPressableStyle(cornerRadius: 6))
                        .help(!isAllowed ? "请重新登录 Google OAuth 账号后再开启代理" : (isEnabled ? "点击关闭该账号的网关代理" : "点击开启该账号的网关代理"))
                        .disabled(!isAllowed)
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

                // Paused Banner when proxy is disabled
                if !activeGroup.isProxyEnabled {
                    HStack(spacing: 8) {
                        Image(systemName: activeGroup.isProxyAllowed ? "pause.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(activeGroup.isProxyAllowed ? "该账号已关闭网关代理" : "Google OAuth 未就绪")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.codexInk)

                            Text(activeGroup.isProxyAllowed ? "该账号的所有模型已在网关模型列表 (/v1/models) 中隐藏，且不再参与网关路由分流。" : "请重新登录 Google 账号；Gateway 只使用 OAuth 凭证出流。")
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

    // MARK: - Tab 3: Requests Content
    private var requestsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.requestsList.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "waveform.path.badge.plus")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.codexMuted)
                    Text("暂无外部 Agent 反代流水")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.codexInk)
                        .lineLimit(1)
                    Text("本地多协议网关已在 http://127.0.0.1:\(String(supervisor.port)) 准备就绪。\n当第三方 Agent 发送请求时，协议转换、TTFT 延迟与 Token 消耗将在此实时记录。")
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
            } else {
                VStack(spacing: 6) {
                    ForEach(store.requestsList) { req in
                        HStack(spacing: 10) {
                            Text(req.time)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.codexMuted)
                                .lineLimit(1)
                            Text(req.agent)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Color.codexInk)
                                .frame(width: 80, alignment: .leading)
                                .lineLimit(1)
                            Text(req.ingressProtocol)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.codexMuted)
                                .frame(width: 130, alignment: .leading)
                                .lineLimit(1)
                            Text(req.targetModel)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.codexInk)
                                .frame(width: 140, alignment: .leading)
                                .lineLimit(1)
                            Spacer()
                            Text("\(req.latencyMs)ms")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Color.codexInk)
                                .lineLimit(1)
                            Text(req.fidelity)
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12), in: Capsule())
                                .foregroundStyle(.blue)
                                .lineLimit(1)
                            Text(req.status)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.green)
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
                }
            }
        }
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
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.orange.opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 14))
                            .foregroundStyle(.orange)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text("Hermes Agent")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.codexInk)
                            if store.isHermesInstalled() {
                                Text("已检测到配置")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.green.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.green)
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
                    Button {
                        guard configuringAgent == nil else { return }
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
                                Text("一键接入 Gateway")
                            }
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .frame(minWidth: 118)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.codexPrimary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .foregroundStyle(Color.codexOnPrimary)
                    }
                    .buttonStyle(.plain)
                    .disabled(configuringAgent != nil)
                    .opacity(configuringAgent != nil && configuringAgent != .hermes ? 0.55 : 1)
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
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.purple.opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.purple)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text("Pi Agent")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.codexInk)
                            if store.isPiInstalled() {
                                Text("已检测到环境")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.green.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.green)
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
                    Button {
                        guard configuringAgent == nil else { return }
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
                                Text("一键接入 Gateway")
                            }
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .frame(minWidth: 118)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.codexPrimary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .foregroundStyle(Color.codexOnPrimary)
                    }
                    .buttonStyle(.plain)
                    .disabled(configuringAgent != nil)
                    .opacity(configuringAgent != nil && configuringAgent != .pi ? 0.55 : 1)
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
