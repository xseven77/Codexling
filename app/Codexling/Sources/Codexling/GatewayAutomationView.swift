import SwiftUI

@MainActor
public struct GatewayAutomationView: View {
    @Bindable var store: GatewayStore
    var supervisor: GatewaySupervisor = .shared
    var settingsStore: MultiAgentSettingsStore?
    var onToast: GatewayToastHandler

    @State private var isCreatingTask = false
    @State private var editingTask: GatewayAutomationTask? = nil
    @State private var runningTaskIDs: Set<String> = []

    init(
        store: GatewayStore,
        supervisor: GatewaySupervisor = .shared,
        settingsStore: MultiAgentSettingsStore? = nil,
        onToast: @escaping GatewayToastHandler
    ) {
        self.store = store
        self.supervisor = supervisor
        self.settingsStore = settingsStore
        self.onToast = onToast
    }

    private func toast(_ message: String, systemImage: String = "checkmark.circle.fill", isSuccess: Bool = true) {
        onToast(message, systemImage, isSuccess)
    }

    private var activeTasksCount: Int {
        store.automationTasks.filter { $0.enabled }.count
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 顶栏操作区与启动配置条
            headerBar

            if store.automationTasks.isEmpty {
                emptyStateView
            } else {
                tasksListView
            }
        }
        .sheet(isPresented: $isCreatingTask) {
            AutomationTaskEditorSheet(
                task: nil,
                store: store,
                onSave: { newTask in
                    store.addAutomationTask(newTask)
                    toast("已创建自动化任务: \(newTask.name)")
                }
            )
        }
        .sheet(item: $editingTask) { task in
            AutomationTaskEditorSheet(
                task: task,
                store: store,
                onSave: { updated in
                    store.updateAutomationTask(updated)
                    toast("已更新自动化任务: \(updated.name)")
                }
            )
        }
    }

    // MARK: - 顶栏
    private var headerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.codexPrimary.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: "clock.arrow.2.circlepath")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.codexPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("自动化任务编排")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.codexInk)

                    Text("共 \(store.automationTasks.count) 个计划 · \(activeTasksCount) 个已启用")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.codexLine.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.codexMuted)
                }

                Text("按计划在本地自动执行模型巡检与各类自动化工作流")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.codexMuted)
            }

            Spacer()

            Button {
                isCreatingTask = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("新建自动化任务")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Color.codexPrimary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.codexCard)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 2, x: 0, y: 1)
    }

    // MARK: - 空状态
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.codexPrimary.opacity(0.08))
                    .frame(width: 64, height: 64)
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.codexPrimary)
            }

            VStack(spacing: 6) {
                Text("暂无自动化巡检任务")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.codexInk)

                Text("您可以按需设置每天哪几个小时对哪些供应商或账号进行自动巡检，\n确保模型健康探测井然有序，或通过定时探针提前对齐 5 小时额度刷新窗口。")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.codexMuted)
                    .multilineTextAlignment(.center)
            }

            // 推荐方案卡片组
            VStack(spacing: 8) {
                // 推荐 1: 5小时额度窗口对齐 (社区精选)
                Button {
                    let task = GatewayAutomationTask(
                        name: "5小时额度对齐巡检 (05, 10, 15, 20点)",
                        taskType: .modelHealthCheck,
                        enabled: true,
                        providers: ["openai", "google"],
                        allAccounts: true,
                        hours: [5, 10, 15, 20]
                    )
                    store.addAutomationTask(task)
                    toast("已应用推荐：5小时额度对齐巡检")
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.codexPrimary.opacity(0.12))
                                .frame(width: 32, height: 32)
                            Image(systemName: "bolt.badge.clock")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.codexPrimary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("应用「5小时额度对齐」巡检")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color.codexInk)

                                Text("推荐 · 社区最佳实践")
                                    .font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.codexPrimary.opacity(0.15), in: Capsule())
                                    .foregroundStyle(Color.codexPrimary)
                            }

                            Text("每天 05:00 / 10:00 / 15:00 / 20:00 自动探针，在上午上班与下午高峰前校准滚动窗口")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.codexMuted)
                        }

                        Spacer()

                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.codexPrimary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.codexBackground.opacity(0.8), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.codexPrimary.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                // 推荐 2 & 3 横排轻量选项
                HStack(spacing: 8) {
                    Button {
                        let task = GatewayAutomationTask(
                            name: "工作时段常规巡检 (09, 13, 18点)",
                            taskType: .modelHealthCheck,
                            enabled: true,
                            providers: ["openai", "google"],
                            allAccounts: true,
                            hours: [9, 13, 18]
                        )
                        store.addAutomationTask(task)
                        toast("已应用：工作时段常规巡检")
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "briefcase")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.codexMuted)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("工作时段打卡 (09, 13, 18点)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.codexInk)
                                Text("早午晚3次，不打扰夜间休眠")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.codexMuted)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.codexBackground.opacity(0.5), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.codexLine.opacity(0.2), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        let task = GatewayAutomationTask(
                            name: "高频全天候巡检 (每4小时)",
                            taskType: .modelHealthCheck,
                            enabled: true,
                            providers: ["openai", "google"],
                            allAccounts: true,
                            hours: [0, 4, 8, 12, 16, 20]
                        )
                        store.addAutomationTask(task)
                        toast("已应用：高频全天候巡检")
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.2.circlepath")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.codexMuted)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("高频全天候 (每4小时一次)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.codexInk)
                                Text("全天6次循环，适合多账号监控")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.codexMuted)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.codexBackground.opacity(0.5), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.codexLine.opacity(0.2), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 500)

            // 自定义创建计划入口
            Button {
                isCreatingTask = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11))
                    Text("自定义创建计划...")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(Color.codexLine.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .foregroundStyle(Color.codexInk)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(Color.codexCard)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.codexLine.opacity(0.35), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 2, x: 0, y: 1)
    }

    // MARK: - 任务列表
    private var tasksListView: some View {
        VStack(spacing: 12) {
            ForEach(store.automationTasks) { task in
                taskCard(task)
            }
        }
    }

    private func taskCard(_ task: GatewayAutomationTask) -> some View {
        let isRunning = runningTaskIDs.contains(task.id) || (store.isModelCheckRunning && task.lastRunStatus == "running")

        return VStack(alignment: .leading, spacing: 12) {
            // 卡片头部
            HStack(alignment: .center, spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { task.enabled },
                    set: { _ in store.toggleAutomationTask(id: task.id) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.8)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(task.name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(task.enabled ? Color.codexInk : Color.codexMuted)

                        HStack(spacing: 4) {
                            Image(systemName: task.taskType.iconName)
                                .font(.system(size: 9))
                            Text(task.taskType.title)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Color.codexPrimary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .foregroundStyle(Color.codexPrimary)
                    }

                    if !task.enabled {
                        Text("计划已暂停，不会按时自动触发")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.codexMuted)
                    }
                }

                Spacer()

                // 执行状态标签
                statusBadge(task: task, isRunning: isRunning)
            }

            Divider()
                .overlay(Color.codexLine.opacity(0.2))

            // 属性详情网格
            VStack(alignment: .leading, spacing: 8) {
                // 1. 计划时间点
                HStack(alignment: .top, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text("每天时间点:")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.codexMuted)
                    .frame(width: 90, alignment: .leading)

                    if task.hours.isEmpty {
                        Text("未设置时间")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.red.opacity(0.8))
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(task.hours.sorted(), id: \.self) { hour in
                                    Text(String(format: "%02d:00", hour))
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.codexPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                        .foregroundStyle(Color.codexPrimary)
                                }
                            }
                        }
                    }
                }

                // 2. 供应商范围
                HStack(alignment: .center, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 10))
                        Text("目标供应商:")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.codexMuted)
                    .frame(width: 90, alignment: .leading)

                    if task.providers.isEmpty {
                        Text("全部供应商")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.codexInk)
                    } else {
                        FlowLayout(spacing: 5) {
                            ForEach(task.providers, id: \.self) { p in
                                providerBadge(p)
                            }
                        }
                    }
                }

                // 3. 账号范围
                HStack(alignment: .center, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 10))
                        Text("账号范围:")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.codexMuted)
                    .frame(width: 90, alignment: .leading)

                    if task.allAccounts {
                        Text("所选供应商下的全部账号 (自动包含新增账号)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.codexInk)
                    } else {
                        Text("指定 \(task.accountIds.count) 个特定账号")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.codexInk)
                    }
                }

                // 4. 最近执行记录
                if let lastRunAt = task.lastRunDate {
                    HStack(alignment: .center, spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                            Text("上次触发:")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(Color.codexMuted)
                        .frame(width: 90, alignment: .leading)

                        HStack(spacing: 6) {
                            Text(lastRunAt.formatted(date: .numeric, time: .standard))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.codexMuted)

                            if let summary = task.lastRunSummary, !summary.isEmpty {
                                Text("·  \(summary)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.codexInk)
                            }
                        }
                    }
                }
            }

            Divider()
                .overlay(Color.codexLine.opacity(0.15))

            // 卡片底部操作按钮
            HStack(spacing: 8) {
                Button {
                    runningTaskIDs.insert(task.id)
                    Task {
                        let res = await store.runAutomationTaskNow(task)
                        runningTaskIDs.remove(task.id)
                        toast(res.message, systemImage: res.success ? "checkmark.circle.fill" : "exclamationmark.circle.fill", isSuccess: res.success)
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isRunning {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9))
                        }
                        Text(isRunning ? "探测进行中..." : "立即运行一次")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Color.codexPrimary.opacity(isRunning ? 0.05 : 0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .foregroundStyle(Color.codexPrimary)
                }
                .buttonStyle(.plain)
                .disabled(isRunning)

                Spacer()

                Button {
                    editingTask = task
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                        Text("编辑")
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Color.codexLine.opacity(0.1), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .foregroundStyle(Color.codexInk)
                }
                .buttonStyle(.plain)

                Button {
                    store.deleteAutomationTask(id: task.id)
                    toast("已删除任务: \(task.name)")
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                        Text("删除")
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .foregroundStyle(Color.red.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.codexCard)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(task.enabled ? Color.codexLine.opacity(0.35) : Color.codexLine.opacity(0.18), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 2, x: 0, y: 1)
    }

    private func providerBadge(_ provider: String) -> some View {
        let (title, icon) = providerInfo(provider)
        return HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(title)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.codexLine.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .foregroundStyle(Color.codexInk)
    }

    private func providerInfo(_ provider: String) -> (String, String) {
        let p = provider.lowercased()
        if p == "openai" || p == "codex" {
            return ("OpenAI / Codex", "apple.terminal")
        } else if p == "google" || p == "gemini" {
            return ("Google Gemini", "sparkles")
        } else if p == "deepseek" {
            return ("DeepSeek", "bolt.horizontal.circle")
        } else if p == "opencode" {
            return ("OpenCode", "network")
        }
        return (provider, "server.rack")
    }

    private func statusBadge(task: GatewayAutomationTask, isRunning: Bool) -> some View {
        HStack(spacing: 4) {
            if isRunning {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.65)
                Text("巡检进行中")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.blue)
            } else if task.lastRunStatus == "success" {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.green)
                Text("运行正常")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.green)
            } else if task.lastRunStatus == "failed" {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.red)
                Text("执行失败")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.red)
            } else {
                Text("等待下个周期")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.codexMuted)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(
            isRunning ? Color.blue.opacity(0.10) :
            (task.lastRunStatus == "success" ? Color.green.opacity(0.10) :
            (task.lastRunStatus == "failed" ? Color.red.opacity(0.10) : Color.codexLine.opacity(0.12))),
            in: Capsule()
        )
    }
}

// MARK: - 任务创建与编辑弹窗
@MainActor
public struct AutomationTaskEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    var originalTask: GatewayAutomationTask?
    var store: GatewayStore
    var onSave: (GatewayAutomationTask) -> Void

    @State private var name: String = ""
    @State private var taskType: AutomationTaskType = .modelHealthCheck
    @State private var enabled: Bool = true
    @State private var selectedProviders: Set<String> = []
    @State private var allAccounts: Bool = true
    @State private var selectedAccountIds: Set<String> = []
    @State private var selectedHours: Set<Int> = [8, 14, 21]

    private let availableProviders = [
        ("openai", "OpenAI / Codex", "apple.terminal"),
        ("google", "Google Gemini", "sparkles"),
        ("deepseek", "DeepSeek 官方", "bolt.horizontal.circle"),
        ("opencode", "OpenCode 聚合平台", "network"),
    ]

    public init(
        task: GatewayAutomationTask?,
        store: GatewayStore,
        onSave: @escaping (GatewayAutomationTask) -> Void
    ) {
        self.originalTask = task
        self.store = store
        self.onSave = onSave

        if let task {
            _name = State(initialValue: task.name)
            _taskType = State(initialValue: task.taskType)
            _enabled = State(initialValue: task.enabled)
            _selectedProviders = State(initialValue: Set(task.providers))
            _allAccounts = State(initialValue: task.allAccounts)
            _selectedAccountIds = State(initialValue: Set(task.accountIds))
            _selectedHours = State(initialValue: Set(task.hours))
        } else {
            _name = State(initialValue: "定时模型健康巡检")
            _selectedProviders = State(initialValue: ["openai", "google"])
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Sheet Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.codexPrimary.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: originalTask == nil ? "plus.circle.fill" : "slider.horizontal.3")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.codexPrimary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(originalTask == nil ? "新建自动化任务" : "编辑自动化任务")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.codexInk)
                    Text("设定每天特定触发时点、巡检的供应商与账号范围")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.codexMuted)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.codexMuted.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color.codexCard)

            Divider()
                .overlay(Color.codexLine.opacity(0.3))

            // Form Body
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // 1. 任务基础名称
                    VStack(alignment: .leading, spacing: 6) {
                        Text("任务名称")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.codexInk)

                        TextField("如：Codex 每日三检、全量夜间巡检", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // 2. 任务类型 (扩展槽位)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("任务类型")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.codexInk)

                        HStack(spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "stethoscope")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.codexPrimary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("模型健康巡检")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.codexInk)
                                    Text("定时发起小包探测，自动更新并持久化模型可用性与延时指标")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.codexMuted)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.codexPrimary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.codexPrimary.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }

                    // 3. 24 小时触发时点选择器
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("每天触发时点 (小时)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.codexInk)

                            Spacer()

                            // 快捷选择预设
                            HStack(spacing: 4) {
                                presetButton("5小时额度对齐 (5,10,15,20)", hours: [5, 10, 15, 20])
                                presetButton("工作时段 (9,13,18)", hours: [9, 13, 18])
                                presetButton("每4小时", hours: [0, 4, 8, 12, 16, 20])
                                presetButton("全选", hours: Array(0...23))
                                presetButton("清空", hours: [])
                            }
                        }

                        // 24小时矩阵格子 (4行 x 6列)
                        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(0..<24, id: \.self) { hour in
                                let isSelected = selectedHours.contains(hour)
                                Button {
                                    if isSelected {
                                        selectedHours.remove(hour)
                                    } else {
                                        selectedHours.insert(hour)
                                    }
                                } label: {
                                    Text(String(format: "%02d:00", hour))
                                        .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .monospaced))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 28)
                                        .background(
                                            isSelected ? Color.codexPrimary : Color.codexLine.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        )
                                        .foregroundStyle(isSelected ? Color.white : Color.codexInk)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text("已选 \(selectedHours.count) 个时间点：\(selectedHoursSummary)")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.codexMuted)
                    }

                    // 4. 目标供应商 (多选)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("目标供应商 (支持多选)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.codexInk)

                        FlowLayout(spacing: 8) {
                            ForEach(availableProviders, id: \.0) { key, title, icon in
                                let isSelected = selectedProviders.contains(key)
                                Button {
                                    if isSelected {
                                        selectedProviders.remove(key)
                                    } else {
                                        selectedProviders.insert(key)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                            .font(.system(size: 12))
                                            .foregroundStyle(isSelected ? Color.codexPrimary : Color.codexMuted)
                                        Image(systemName: icon)
                                            .font(.system(size: 11))
                                        Text(title)
                                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                            .lineLimit(1)
                                            .fixedSize()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        isSelected ? Color.codexPrimary.opacity(0.10) : Color.codexLine.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(isSelected ? Color.codexPrimary.opacity(0.4) : Color.codexLine.opacity(0.2), lineWidth: 1)
                                    )
                                    .foregroundStyle(isSelected ? Color.codexInk : Color.codexMuted)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if selectedProviders.isEmpty {
                            Text("⚠️ 未选择供应商时，巡检将默认涵盖所有可用供应商")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.orange)
                        }
                    }

                    // 5. 账号范围 (全量 vs 指定)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("账号范围")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.codexInk)

                        HStack(spacing: 16) {
                            Button {
                                allAccounts = true
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: allAccounts ? "largecircle.fill.circle" : "circle")
                                        .font(.system(size: 12))
                                        .foregroundStyle(allAccounts ? Color.codexPrimary : Color.codexMuted)
                                    Text("所选供应商下的全部账号 (推荐，包含未来新增账号)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.codexInk)
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                allAccounts = false
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: !allAccounts ? "largecircle.fill.circle" : "circle")
                                        .font(.system(size: 12))
                                        .foregroundStyle(!allAccounts ? Color.codexPrimary : Color.codexMuted)
                                    Text("仅巡检指定账号")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.codexInk)
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        if !allAccounts {
                            accountSelectorView
                        }
                    }

                    // 6. 任务启用开关
                    Toggle(isOn: $enabled) {
                        Text("创建后立即启用此计划")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.codexInk)
                    }
                    .toggleStyle(.checkbox)
                }
                .padding(18)
            }

            Divider()
                .overlay(Color.codexLine.opacity(0.3))

            // Footer Actions
            HStack {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .frame(height: 28)
                .padding(.horizontal, 14)
                .background(Color.codexLine.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .foregroundStyle(Color.codexInk)

                Spacer()

                Button {
                    let task = GatewayAutomationTask(
                        id: originalTask?.id ?? UUID().uuidString,
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "自动化巡检计划" : name,
                        taskType: taskType,
                        enabled: enabled,
                        providers: Array(selectedProviders).sorted(),
                        allAccounts: allAccounts,
                        accountIds: allAccounts ? [] : Array(selectedAccountIds),
                        hours: Array(selectedHours).sorted(),
                        lastRunAt: originalTask?.lastRunAt,
                        lastRunStatus: originalTask?.lastRunStatus,
                        lastRunSummary: originalTask?.lastRunSummary
                    )
                    onSave(task)
                    dismiss()
                } label: {
                    Text(originalTask == nil ? "立即创建" : "保存修改")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 16)
                        .frame(height: 28)
                        .background(Color.codexPrimary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(selectedHours.isEmpty)
            }
            .padding(14)
            .background(Color.codexCard)
        }
        .frame(width: 580)
        .frame(minHeight: 520, maxHeight: max(520, (NSApp.keyWindow?.frame.height ?? 720) - 48))
    }

    private var selectedHoursSummary: String {
        if selectedHours.isEmpty { return "无" }
        if selectedHours.count == 24 { return "全天候 (每小时)" }
        return selectedHours.sorted().map { String(format: "%02d:00", $0) }.joined(separator: ", ")
    }

    private func presetButton(_ label: String, hours: [Int]) -> some View {
        Button {
            selectedHours = Set(hours)
        } label: {
            Text(label)
                .font(.system(size: 10))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.codexLine.opacity(0.1), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .foregroundStyle(Color.codexInk)
        }
        .buttonStyle(.plain)
    }

    // 账号选择列表
    private var accountSelectorView: some View {
        let matchingAccounts = store.accountModelGroups.filter { group in
            if selectedProviders.isEmpty { return true }
            return selectedProviders.contains(where: { p in
                group.id.lowercased().hasPrefix(p.lowercased())
            })
        }

        return VStack(alignment: .leading, spacing: 6) {
            Text("勾选需要巡检的账号:")
                .font(.system(size: 10))
                .foregroundStyle(Color.codexMuted)

            if matchingAccounts.isEmpty {
                Text("所选供应商下暂无已连接的账号")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.codexMuted)
                    .padding(8)
            } else {
                VStack(spacing: 4) {
                    ForEach(matchingAccounts) { acc in
                        let cid = acc.connectionID?.rawValue.uuidString ?? acc.id
                        let isChecked = selectedAccountIds.contains(cid)

                        Button {
                            if isChecked {
                                selectedAccountIds.remove(cid)
                            } else {
                                selectedAccountIds.insert(cid)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 12))
                                    .foregroundStyle(isChecked ? Color.codexPrimary : Color.codexMuted)

                                Image(systemName: acc.iconName)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.codexInk)

                                Text(acc.accountName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.codexInk)

                                if let email = acc.email, !email.isEmpty {
                                    Text("(\(email))")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.codexMuted)
                                }

                                Spacer()

                                Text(acc.providerTitle)
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.codexMuted)
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                            .background(isChecked ? Color.codexPrimary.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color.codexLine.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }
}

// MARK: - 自适应内容长度自动换行流式布局 (FlowLayout)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentRowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var currentRowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRowWidth + size.width > maxWidth, currentRowWidth > 0 {
                // 换行
                totalHeight += currentRowHeight + spacing
                currentRowWidth = size.width + spacing
                currentRowHeight = size.height
            } else {
                currentRowWidth += size.width + spacing
                currentRowHeight = max(currentRowHeight, size.height)
            }
        }

        totalHeight += currentRowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : currentRowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var currentRowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                // 自动折行到下一行
                x = bounds.minX
                y += currentRowHeight + spacing
                currentRowHeight = 0
            }

            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
    }
}

