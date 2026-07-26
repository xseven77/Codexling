# Codexling 精灵状态与陪伴统计方案

## 产品边界

精灵不模拟或推断用户情绪。界面只表达两类可验证数据：

1. **Codex 任务状态**：从本地 Codex 线程事件得出，决定精灵当下动作和状态文案。
2. **陪伴时间**：由 Codexling 将有效的 Codex 活跃时段累计到本地，展示“今天一起工作 X 分钟”。

“今天一起工作”表示 Codex 有活跃任务的累计时长，不等同于用户的屏幕时间或生产力。

## 当前 Pet 的来源与主窗口展示

主窗口左侧的 Pet **必须是设置页“状态与 Pets”当前选中的 Pet**，而不是固定展示 Codexling 吉祥物。它可以是 Codex 内置 Pet，也可以是用户放在 `~/.codex/pets` 的自定义 Pet。

主窗口只负责复用设置，不提供第二套选择状态；Codexling 与 Codex 共享同一个选择：

```text
AppSettingsStore.selectedPetID
        ↕ CodexPetSelectionSync / CodexPetSelectionMonitor
~/.codex/config.toml
        ↓
AppSettingsStore.selectedPet
        ↓
PetAnimationPlayer.setPet(selectedPet)
        ↓
主窗口 / 悬停卡片渲染同一帧
```

概念稿中暂以 `Codexling` 展示，这是当前设置选择它时的样例；实际界面应展示 `selectedPet.displayName`，例如 `Dewey · 正在工作`。

### 现有 App 中的实现位置

这条逻辑已经由共享 `PetFrameStore` 实际运行：AppDelegate 读取 `settings.selectedPet` 与活动状态，统一驱动 `PetAnimationPlayer`，并把输出帧送给主窗口和 hover 卡片。状态栏左侧固定为任务状态圆灯。

分离窗口已经由 `DetachedUsageWindowView → CompanionDashboardView` 接收额度、活动、共享 Pet 帧与陪伴统计 Store。主窗口和 hover 复用同一个播放器，不复制图集裁剪或计时逻辑。

当前接入链路：

```text
AppDelegate 持有 activityStore
  → DetachedWindowController 注入 activityStore
  → DetachedUsageWindowView 观察 activityStore 与 settings
  → CompanionStatusView 接收 selectedPet、当前动画帧、活动快照
```

为避免窗口与 hover 各自计时造成不同步，当前实现由 `PetFrameStore` 作为共享帧源；窗口关闭时仅取消窗口订阅，不能停止仍服务于 hover 的播放器。

### 资源与降级规则

1. Codexling 中变更 `selectedPetID` 后，会更新共享 `PetFrameStore`，并写入 Codex 配置；Codex 重启后使用同一选择。
2. `CodexPetSelectionMonitor` 监听 `~/.codex/config.toml`，包括原子替换场景；Codex 中的选择变化会重新扫描资源并同步回 Codexling。
3. 任务状态变更时只切换动画状态，保留当前选择的 Pet，不会切回默认形象。
4. 当选中的资源丢失或重扫后不兼容时，`AppSettingsStore.reloadPets()` 会将选择回退到第一个有效 Pet；若没有有效 Pet，主窗口显示资源缺失降级。
5. 旧 `petsEnabled` 偏好不再控制当前 UI；主窗口和 hover 都使用共享播放器，状态栏固定使用任务圆灯。
6. 开启“减少动态效果”时，播放器只显示对应状态的首帧，状态文字和数据继续更新。

## 状态设计与切换

| 精灵展示 | 任务状态 | 触发事件 / 条件 | Pet 动画 | 停留规则 |
|---|---|---|---|---|
| 安静待命 | `idle` | 无活跃任务 | `idle` | 持续 |
| 正在思考 | `thinking` | `task_started`、推理中且没有工具调用 | `running` | 直到其他活跃状态覆盖 |
| 正在工作 | `executing` | 有未完成工具调用 | `running` | 直到工具输出或任务状态变化 |
| 正在检查 | `reviewing` | `patch_apply_end` 或检查类工具调用 | `review` | 直到其他活跃状态覆盖 |
| 等待确认 | `waitingForUser` | `request_user_input`、提权确认等等待型调用 | `waiting` | 直到用户确认或任务完成 |
| 刚刚完成 | `completed` | `task_complete` | `waving` | 20 秒后回到待命 |
| 任务已中止 | `interrupted` | `turn_aborted` | `failed` | 保留到该线程出现新的可识别事件 |
| 状态不可用 | `unavailable` | 无法读取本地 Codex 数据 | `idle` | 显示“状态暂不可用”，不伪造任务状态 |

优先级保持为：等待确认 > 工作中 > 检查中 > 思考中 > 中止 > 完成 > 待命。多个 Codex 任务并行时，窗口展示最高优先级状态，同时显示活跃任务数。

## “多使用 Codex”如何可行地表达

不做无法证明的“亲密度”或“心情值”。改用可解释、可复算的本地指标：

- **今天一起工作**：当状态属于 `thinking`、`executing`、`reviewing`、`waitingForUser` 时开始累计；离开这些状态、应用退出或跨天时结算。
- **连续使用天数（可选）**：当天累计活跃时长达到 5 分钟，即记为一个陪伴日；只保存在 Codexling 本地。
- **近期完成（可选）**：当天收到的 `task_complete` 次数。仅展示数量，不把提示词、推理或工具参数提取为界面数据。

“今天一起工作”已由 `CompanionStatsStore` 存储在 Application Support 的 `companion_stats.json`。每 30 秒、状态变更和应用终止时结算；单次增量封顶 90 秒，避免休眠时间被计入。连续使用天数和完成数仍未实现。

## 可行性验证

| 能力 | 当前代码 / 数据来源 | 结论 | 所需补充 |
|---|---|---|---|
| 读取当前选中的 Pet | `AppSettingsStore.selectedPetID` 与 `selectedPet` | 已实现 | 与 Codex 配置双向同步 |
| 选择切换时重载图集 | `PetFrameStore.update` → `PetAnimationPlayer.setPet(_:)` | 已实现 | 主窗口与 hover 共享帧流 |
| 读取任务活动 | `CodexActivity.swift` 解析本地线程 JSONL 与 SQLite 索引 | 已具备 | 无 |
| 八类任务状态 | `CodexActivityState` 已定义全部状态与优先级归并 | 已具备 | 无 |
| 精灵动画切换 | `petAnimationState` 已映射到 `idle/running/review/waiting/waving/failed` | 已具备 | 无 |
| 任务标题与状态摘要 | `CodexActivitySnapshot` 已提供标题，以及清理并截断后的可见 commentary / 通用工具状态 | 已具备 | 无 |
| 额度、刷新时间 | `CodexUsageSnapshot` 有 5 小时 / 周额度、`fetchedAt`、刷新状态 | 已具备 | 无 |
| 今天一起工作 | `CompanionStatsStore` | 已实现 | 30 秒心跳、90 秒封顶、跨日与退出结算 |
| 连续使用天数 / 完成数 | 可从活跃时长与 `completed` 状态导出 | 未实现 | 当前没有对应持久化字段或 UI |

## 不做的内容

- 不把 reasoning 内容、原始工具参数、完整提示词或环境变量提取为 UI 数据，也不展示、持久化或上传这些内容。
- 不宣称“用户在努力”“精灵感到孤独”等不可验证结论。
- 不要求 Codex 提供尚不存在的在线 Pet 或活动 API；本方案保留现有本地只读 Provider 的 `unavailable` 降级。
