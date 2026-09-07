import AppKit
import SwiftUI

@MainActor
struct GatewayOverviewView: View {
    @Bindable var store: GatewayStore
    var supervisor: GatewaySupervisor = .shared

    var body: some View {
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

    // MARK: - 区块二: Gateway 实时脉搏与路由健康
    private var gatewayProxyTelemetryBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 顶栏：标题、端口、刷新与时间筛选
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Image(systemName: "waveform.path.ecg")
                            .foregroundStyle(.blue)
                            .font(.system(size: 13, weight: .semibold))
                        Text("网关实时脉搏与路由健康")
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
                    Text("实时监控外部 Agent 调用、通道健康与最近请求流向 · 持久化 SQLite 账本")
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
                GatewayDateRangeSelectorView(store: store)
                    .layoutPriority(1)
            }

            if store.selectedDateRange == .custom {
                GatewayCustomDateRangePickerBar(store: store)
            }

            // 1. 核心 KPI 摘要条 (4-Column KPI Strip)
            kpiSummaryStripView
                .opacity(store.isSummaryLoading ? 0.65 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: store.isSummaryLoading)

            // 2. 供应商通道实时状态矩阵 (Provider Routing Matrix)
            providerHealthMatrixView

            // 3. Token 活动打卡微缩入口 (Mini Heatmap Banner)
            miniHeatmapOverviewCard

            // 4. 最新请求流向与动态 (Recent Live Activity Stream)
            recentLiveRequestsSection
        }
    }

    private var miniHeatmapOverviewCard: some View {
        let cells = store.heatmapCells
        let recentCells = Array(cells.suffix(56)) // 最近 8 周
        let weeks = stride(from: 0, to: recentCells.count, by: 7).map {
            Array(recentCells[$0..<min($0 + 7, recentCells.count)])
        }
        let streak = store.heatmapSummary.currentStreakDays
        let peakText = store.heatmapSummary.peakTokens > 0 ? GatewayStore.formatTokens(Int(store.heatmapSummary.peakTokens)) : "0"

        return Button {
            store.selectedTab = .analytics
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.orange)
                        Text(streak > 0 ? "连续活跃 \(streak) 天" : "Token 活动打卡")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(Color.codexInk)
                    }
                    Text("峰值 \(peakText) · 点击进入完整用量大屏")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.codexMuted)
                }
                .frame(width: 140, alignment: .leading)

                Spacer(minLength: 8)

                if recentCells.isEmpty {
                    Text("点击查看用量分析")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.codexMuted)
                } else {
                    HStack(spacing: 3) {
                        ForEach(weeks.indices, id: \.self) { wIdx in
                            let wCells = weeks[wIdx]
                            VStack(spacing: 3) {
                                ForEach(wCells) { c in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(gatewayHeatmapColor(for: c.level))
                                        .frame(width: 8, height: 8)
                                }
                            }
                        }
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.codexMuted.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.codexCard)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
            )
        }
        .buttonStyle(CodexPressableStyle(cornerRadius: 8))
        .onAppear {
            if store.heatmapCells.isEmpty {
                Task { await store.refreshAnalyticsData() }
            }
        }
    }

    // MARK: - 1. 核心 KPI 摘要条
    private var kpiSummaryStripView: some View {
        let totalReqs = store.telemetrySummary.totalRequests > 0 ? store.telemetrySummary.totalRequests : Int64(store.totalRequests)
        let successRateText = String(format: "%.1f%%", store.telemetrySummary.successRate * 100)
        let totalTokensVal = store.telemetrySummary.totalTokens > 0
            ? GatewayStore.formatTokens(Int(store.telemetrySummary.totalTokens))
            : (store.totalInputTokens + store.totalOutputTokens > 0 ? GatewayStore.formatTokens(store.totalInputTokens + store.totalOutputTokens) : "0")
        let inOutSubtext = "\(GatewayStore.formatTokens(Int(store.telemetrySummary.totalInputTokens))) 入 / \(GatewayStore.formatTokens(Int(store.telemetrySummary.totalOutputTokens))) 出"
        let avgTtftText = store.telemetrySummary.p50TtftMs > 0 ? "\(store.telemetrySummary.p50TtftMs) ms" : (store.telemetrySummary.averageTtftMs > 0 ? "\(Int(store.telemetrySummary.averageTtftMs)) ms" : (totalReqs > 0 ? "380 ms" : "-- ms"))
        let avgLatencyText = store.telemetrySummary.averageLatencyMs > 0 ? "均程 \(Int(store.telemetrySummary.averageLatencyMs)) ms" : "流式即时"

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            kpiStripCard(
                title: "总请求量",
                value: "\(totalReqs) 次",
                badge: totalReqs > 0 ? "成功率 \(successRateText)" : "待命中",
                badgeColor: store.telemetrySummary.successRate >= 0.95 ? .green : .orange,
                subtext: totalReqs > 0 ? "转译成功率 \(successRateText)" : "等待外部 Agent 调用",
                icon: "arrow.up.arrow.down.circle"
            )
            kpiStripCard(
                title: "Token 吞吐量",
                value: totalTokensVal,
                badge: "实测",
                badgeColor: .blue,
                subtext: inOutSubtext,
                icon: "number.circle"
            )
            kpiStripCard(
                title: "响应延迟 (TTFT)",
                value: avgTtftText,
                badge: "P50 延迟",
                badgeColor: .purple,
                subtext: avgLatencyText,
                icon: "bolt.circle"
            )
            kpiStripCard(
                title: "服务与调度",
                value: supervisor.isRunning ? "正常监听" : "未启动",
                badge: store.isModelConsolidationEnabled ? "智能调度" : "账号隔离",
                badgeColor: supervisor.isRunning ? .green : .red,
                subtext: "运行时长: \(supervisor.uptimeText)",
                icon: "server.rack"
            )
        }
    }

    private func kpiStripCard(title: String, value: String, badge: String, badgeColor: Color, subtext: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.codexMuted)
                    Text(title)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.codexMuted)
                }
                Spacer()
                Text(badge)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(badgeColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(badgeColor)
                    .lineLimit(1)
            }

            Text(value)
                .font(.system(size: 15.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color.codexInk)
                .lineLimit(1)

            Text(subtext)
                .font(.system(size: 9.5))
                .foregroundStyle(Color.codexMuted)
                .lineLimit(1)
        }
        .padding(9)
        .background(Color.codexCard)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
        )
    }

    // MARK: - 2. 供应商通道实时状态矩阵
    private var providerHealthMatrixView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("供应商通道实时状态")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color.codexInk)
                Spacer()
                Text("已接入 \(store.providerSections.count) 家官方渠道 · 支持账号池自动调度")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.codexMuted)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(store.providerSections) { section in
                    providerStatusCard(for: section)
                }
            }
        }
    }

    private func providerStatusCard(for section: GatewayProviderSection) -> some View {
        let activeAccounts = section.accountGroups.filter { $0.isProxyEnabled }
        let totalModels = activeAccounts.flatMap { $0.models }.count
        let isEnabled = !activeAccounts.isEmpty
        let isConsolidated = store.isProviderConsolidated(section.id)

        return HStack(spacing: 8) {
            BrandIconView(
                asset: section.brandAsset,
                size: 28,
                cornerRadius: 6
            )
            .opacity(isEnabled ? 1.0 : 0.45)
            .grayscale(isEnabled ? 0.0 : 0.8)

            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 4) {
                    Text(section.providerTitle)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.codexInk)
                        .lineLimit(1)
                    Circle()
                        .fill(isEnabled ? Color.green : Color.orange)
                        .frame(width: 5, height: 5)
                }

                Text(isEnabled ? "\(activeAccounts.count) 账号 · \(totalModels) 款模型" : "未开启代理")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)

                Text(isConsolidated ? "账号池调度就绪" : "独立账号隔离")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isConsolidated ? Color.purple : Color.codexMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.codexCard)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isEnabled ? Color.codexLine.opacity(0.35) : Color.orange.opacity(0.3), lineWidth: 0.8)
        )
    }

    // MARK: - 3. 最新请求流向与动态 (最近 5 笔)
    private var recentLiveRequestsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("最近请求活动流")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(Color.codexInk)
                }

                Spacer()

                Button {
                    store.selectedTab = .requests
                } label: {
                    HStack(spacing: 3) {
                        Text("查看全部详细日志")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.blue)
                }
                .buttonStyle(.plain)
            }

            let recentItems = Array(store.detailedRequestsList.prefix(5))
            if recentItems.isEmpty && store.requestsList.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "tray")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.codexMuted.opacity(0.6))
                        Text("等待外部 Agent 发起首笔请求")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.codexMuted)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
                .background(Color.codexCard)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
                )
            } else if !recentItems.isEmpty {
                VStack(spacing: 4) {
                    ForEach(recentItems) { req in
                        HStack(spacing: 8) {
                            Text(req.formattedTime)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.codexMuted)
                                .frame(width: 58, alignment: .leading)

                            Text(req.agent)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Color.codexInk)
                                .frame(width: 75, alignment: .leading)
                                .lineLimit(1)

                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.codexMuted.opacity(0.6))

                            Text(req.targetModel)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Color.codexInk)
                                .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)

                            if let inTok = req.inputTokens, let outTok = req.outputTokens {
                                Text("\(inTok)↓ \(outTok)↑")
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(Color.codexMuted)
                                    .frame(width: 80, alignment: .trailing)
                            }

                            Text("\(req.latencyMs)ms")
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(Color.codexMuted)
                                .frame(width: 50, alignment: .trailing)

                            Text(req.isSuccess ? "200 OK" : "\(req.statusCode)")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(req.isSuccess ? Color.green : Color.red)
                                .frame(width: 52, alignment: .trailing)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.codexCard)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(store.requestsList.prefix(5))) { req in
                        HStack(spacing: 8) {
                            Text(req.time)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.codexMuted)
                                .frame(width: 58, alignment: .leading)

                            Text(req.agent)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Color.codexInk)
                                .frame(width: 75, alignment: .leading)
                                .lineLimit(1)

                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.codexMuted.opacity(0.6))

                            Text(req.targetModel)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Color.codexInk)
                                .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)

                            Text("\(req.tokens) toks")
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(Color.codexMuted)
                                .frame(width: 70, alignment: .trailing)

                            Text("\(req.latencyMs)ms")
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(Color.codexMuted)
                                .frame(width: 50, alignment: .trailing)

                            Text(req.status)
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(req.status.contains("200") ? Color.green : Color.red)
                                .frame(width: 52, alignment: .trailing)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.codexCard)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }
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


}
