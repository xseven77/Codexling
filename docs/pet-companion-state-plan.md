# Codexling 精灵状态与陪伴统计方案

## 产品边界

精灵不模拟或推断用户情绪。界面只表达两类可验证数据：

1. **Codex 任务状态**：从本地 Codex 线程事件得出，决定精灵当下动作和状态文案。
2. **陪伴时间**：由 Codexling 将有效的 Codex 活跃时段累计到本地，展示“今天一起工作 X 分钟”。

“今天一起工作”表示 Codex 有活跃任务的累计时长，不等同于用户的屏幕时间或生产力。

## 当前 Pet 的来源与主窗口展示

主窗口左侧的 Pet **必须是设置页“状态与 Pets”当前选中的 Pet**，而不是固定展示 Codexling 吉祥物。它可以是 Codex 内置 Pet，也可以是用户放在 `~/.codex/pets` 的自定义 Pet。

主窗口只负责复用设置，不提供第二套选择状态：

```text
AppSettingsStore.selectedPetID
        ↓
AppSettingsStore.selectedPet
        ↓
PetAnimationPlayer.setPet(selectedPet)
        ↓
主窗口 / 状态栏 / 悬停卡片渲染同一帧
```

概念稿中暂以 `Codexling` 展示，这是当前设置选择它时的样例；实际界面应展示 `selectedPet.displayName`，例如 `Dewey · 正在工作`。

### 现有 App 中的实现位置

这条逻辑已经在状态栏中实际运行：`StatusBarController.refreshStatusTitle()` 读取 `settings.selectedPet`，依次调用 `animationPlayer.setPet(pet)` 与 `animationPlayer.setState(activityState.petAnimationState)`，并把输出帧同时送给状态栏胶囊和 hover 卡片。

分离窗口目前仍是 `DetachedUsageWindowView → UsagePanel`，只接收额度 `UsageSnapshotStore`，尚未接入活动 Store 或 Pet 帧。因此把相同展示放进主窗口是**可二次开发**，而不是现成可见功能；应复用现有播放器，而不是复制一套图集裁剪和计时逻辑。

建议接入方式：

```text
AppDelegate 持有 activityStore
  → DetachedWindowController 注入 activityStore
  → DetachedUsageWindowView 观察 activityStore 与 settings
  → CompanionStatusView 接收 selectedPet、当前动画帧、活动快照
```

为避免状态栏与窗口各自计时造成不同步，可让 `PetAnimationPlayer` 或一个新的 `PetFrameStore` 作为共享帧源；窗口关闭时仅取消窗口订阅，不能停止仍服务于状态栏的播放器。

### 资源与降级规则

1. 设置变更 `selectedPetID` 后，主窗口立即调用 `PetAnimationPlayer.setPet`，从新图集的状态首帧重新开始播放。
2. 任务状态变更时，只调用 `setState`，保留当前选择的 Pet，不会切回默认形象。
3. 当选中的资源丢失或重扫后不兼容时，`AppSettingsStore.reloadPets()` 会将选择回退到第一个有效 Pet；若一个有效 Pet 都没有，则主窗口显示静态额度健康圆点和“未找到可用 Pet”。
4. `petsEnabled = false` 时，状态栏按既有实现显示额度健康圆灯；主窗口建议仍保留任务与额度信息，并以非动画的健康圆点替代左侧 Pet 区。
5. 开启“减少动态效果”时，播放器只显示对应状态的首帧，状态文字和数据继续更新。

## 状态设计与切换

| 精灵展示 | 任务状态 | 触发事件 / 条件 | Pet 动画 | 停留规则 |
|---|---|---|---|---|
| 安静待命 | `idle` | 无活跃任务 | `idle` | 持续 |
| 正在思考 | `thinking` | `task_started`、推理中且没有工具调用 | `running` | 直到其他活跃状态覆盖 |
| 正在工作 | `executing` | 有未完成工具调用 | `running` | 直到工具输出或任务状态变化 |
| 正在检查 | `reviewing` | `patch_apply_end` 或检查类工具调用 | `review` | 直到其他活跃状态覆盖 |
| 等待确认 | `waitingForUser` | `request_user_input`、提权确认等等待型调用 | `waiting` | 直到用户确认或任务完成 |
| 刚刚完成 | `completed` | `task_complete` | `waving` | 20 秒后回到待命 |
| 任务已中止 | `interrupted` | `turn_aborted` | `failed` | 20 秒后回到待命 |
| 状态不可用 | `unavailable` | 无法读取本地 Codex 数据 | `idle` | 显示“状态暂不可用”，不伪造任务状态 |

优先级保持为：等待确认 > 工作中 > 检查中 > 思考中 > 中止 > 完成 > 待命。多个 Codex 任务并行时，窗口展示最高优先级状态，同时显示活跃任务数。

## “多使用 Codex”如何可行地表达

不做无法证明的“亲密度”或“心情值”。改用可解释、可复算的本地指标：

- **今天一起工作**：当状态属于 `thinking`、`executing`、`reviewing`、`waitingForUser` 时开始累计；离开这些状态、应用退出或跨天时结算。
- **连续使用天数（可选）**：当天累计活跃时长达到 5 分钟，即记为一个陪伴日；只保存在 Codexling 本地。
- **近期完成（可选）**：当天收到的 `task_complete` 次数。仅展示数量，不读取提示词、推理或工具参数。

这些指标由 Codexling 自己存储在 Application Support 的轻量 JSON / UserDefaults 中即可。按分钟落盘，并在状态变更、应用终止时立即结算，可防止崩溃或重启丢失时长。

## 可行性验证

| 能力 | 当前代码 / 数据来源 | 结论 | 所需补充 |
|---|---|---|---|
| 读取当前选中的 Pet | `AppSettingsStore.selectedPetID` 与 `selectedPet` | 已具备 | 主窗口复用该对象，不新增选择字段 |
| 选择切换时重载图集 | `PetAnimationPlayer.setPet(_:)` | 已具备 | 主窗口接入同一个播放器或共享帧流 |
| 读取任务活动 | `CodexActivity.swift` 解析本地线程 JSONL 与 SQLite 索引 | 已具备 | 无 |
| 八类任务状态 | `CodexActivityState` 已定义全部状态与优先级归并 | 已具备 | 无 |
| 精灵动画切换 | `petAnimationState` 已映射到 `idle/running/review/waiting/waving/failed` | 已具备 | 无 |
| 任务标题与安全摘要 | `CodexActivitySnapshot` 已提供标题和经清理的可见摘要 | 已具备 | 无 |
| 额度、刷新时间 | `CodexUsageSnapshot` 有 5 小时 / 周额度、`fetchedAt`、刷新状态 | 已具备 | 无 |
| 今天一起工作 | 活跃状态已经可观察 | 可二次开发 | 新增本地 `CompanionStatsStore`，只累计活跃状态时间 |
| 连续使用天数 / 完成数 | 可从活跃时长与 `completed` 状态导出 | 可二次开发 | 与 `CompanionStatsStore` 一并持久化 |

## 不做的内容

- 不读取或展示 reasoning、原始工具参数、完整提示词、环境变量。
- 不宣称“用户在努力”“精灵感到孤独”等不可验证结论。
- 不要求 Codex 提供尚不存在的在线 Pet 或活动 API；本方案保留现有本地只读 Provider 的 `unavailable` 降级。
