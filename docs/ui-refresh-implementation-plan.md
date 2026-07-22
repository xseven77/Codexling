# Codexling 最新 UI 全量升级实施方案

## 1. 结论

`ui-concepts.html` 不是单纯的视觉换肤，而是一次主界面信息架构调整：Codexling 从“额度查看器”变为“任务陪伴主窗口”，额度退居次要信息，同时继续保留未登录、设置、Pet 安装和状态栏入口。

本轮升级已经实现。代码复用了额度、账号、任务活动解析、八类状态、Pet 发现与动画、主题、刷新、更新检查和 Pet 安装等底层能力，并完成了：

1. 给主窗口注入任务活动和 Pet 动画数据，重写 `UsagePanel` 的已登录布局。
2. 让活动快照保留多条活跃任务，而不只保留最高优先级的一条。
3. 新增“今天一起工作”的本地累计 Store。
4. 将状态栏改成“圆灯表示任务状态、胶囊背景表示额度健康度”。
5. 让分离窗口在约 377pt 的主界面和约 838pt 的设置界面之间按内容调整高度。

实现按本文的 P0 → P3 顺序完成，并通过原生 App 视觉验收。

### 实施状态（2026-07-23）

- 已实现稳定 ID 的多任务活动数组和任务卡切换。
- 已实现本地按日陪伴统计、休眠增量封顶和跨日清零。
- 已实现共享 `PetFrameStore`，主窗口与 hover 使用同一动画帧源。
- 已实现约 580×475pt 原生主窗口、双栏布局、环形额度卡和独立登录页；HTML 只作为布局参考，不照搬 CSS 像素。
- 已实现设置页账号卡、新状态栏语义和 475/860pt 动态窗口高度。
- 已实现 20pt 状态栏胶囊、任务圆灯和额度健康背景。
- `swift test` 共 38 项全部通过；Release App、ZIP 和 DMG 已重新打包并验证签名。

## 2. 设计稿的最终含义

### 2.1 信息优先级

主窗口由左、右两区组成：

- 左侧陪伴区：账号摘要、当前选中 Pet、Pet 当前状态、“今天一起工作”。
- 右侧任务区：总状态标题、当前任务或任务堆叠、双额度卡、同步信息和刷新操作。

信息优先级为：等待用户处理 > 正在执行的任务 > Pet 状态 > 额度 > 同步元信息。

### 2.2 七个设计场景

| 场景 | 最终产品含义 | 数据来源 |
|---|---|---|
| 01 空闲 | 保留 Pet、陪伴统计和额度，不伪造任务 | `CodexActivitySnapshot` + `CodexUsageSnapshot` |
| 02 执行中 | 展示活跃任务数和可切换的任务卡片 | 扩展后的活动快照 |
| 03 等待确认 | 最高提醒优先级，但不在 Codexling 内替代原确认流程 | `waitingForUser` |
| 04 未登录 | 不展示缓存中的过期账号和额度，清楚说明官方 OAuth 和 Keychain 边界 | `UsageSnapshotStore.isLoggedIn` |
| 05 设置 | 将账号、应用、状态栏、Pet 能力收进统一卡片式设置页 | 现有 Settings/Updater/SettingsStore |
| 06 条件分支 | 5 小时额度缺失时隐藏对应卡；Pet 安装卡只在未安装时出现 | 现有条件属性 |
| 07 状态栏 | 任务状态和额度健康度使用两个独立视觉通道 | Activity + Quota health |

### 2.3 实际渲染确认

通过本地 HTTP 服务在 Codex 自带浏览器中加载后，确认：

- 共渲染 7 个概念场景。
- HTML 概念稿主窗口约 460×377px、设置窗口约 460×838px；这些是布局比例参考，不是原生窗口尺寸约束。
- 原生实现采用约 580×475pt 主窗口与 580×860pt 设置窗口，以获得更适合 macOS 的字号和留白。
- 状态栏胶囊最终计算高度为 20px、圆角 10px，文字使用等宽中等字重。
- 状态栏规范实际生成 8 种任务状态 × 5 种额度背景，共 40 种组合。
- 多任务堆叠是一个带 `role=button`、`tabindex=0` 和动态 `aria-label` 的可操作控件；点击、Enter 和 Space 都会切换任务。
- 额度以环形双卡展示，不再使用当前 App 的“大百分比 + 横向进度条”主视觉。

## 3. 必须以最终覆盖规则为准的设计冲突

HTML 经过多轮 CSS 和 JavaScript 后置覆盖，源码前部和部分标题仍保留旧规则。实现时使用以下最终口径：

| 冲突 | 旧内容 | 最终口径 |
|---|---|---|
| 状态栏颜色职责 | 胶囊跟随任务、圆灯跟随额度 | 圆灯跟随任务、胶囊背景跟随额度 |
| 设置项文案 | “胶囊背景色 / 跟随状态” | “胶囊提醒色 / 跟随额度” |
| 状态栏高度 | 中间样式曾写 22pt | 最终渲染和标注均为 20pt |
| 场景 07 旁注 | 仍描述旧颜色职责 | 场景正文、矩阵和页面顶部说明才是最终规则 |
| 动画 Pet 开关 | 文案暗示关闭后才显示圆灯 | 新规范中的圆灯是任务状态的固定信息通道；Pet 是否继续进入状态栏需按下方决策落地 |

建议本轮同步清理 `ui-concepts.html` 的旧说明，避免它继续产生两套解释。

## 4. 当前 App 与目标设计的映射

### 4.1 已具备，可直接复用

| 能力 | 当前实现 | 结论 |
|---|---|---|
| 官方 OAuth、Keychain、账号与套餐 | `CodexUsageService.swift`、`UsageSnapshotStore` | 直接复用 |
| 5 小时和周额度回退 | `CodexUsageSnapshot.hasShortWindow/primaryWindow` | 直接复用 |
| 额度健康阈值 | `QuotaHealthLevel` | 直接复用，颜色值需对齐设计 |
| 八类任务状态 | `CodexActivityState` | 直接复用 |
| 本地 Codex 活动读取 | `CodexActivityService` 只读 SQLite 与 JSONL | 直接复用 |
| Pet 状态动画映射 | `petAnimationState`、`PetAnimationPlayer` | 直接复用并共享帧源 |
| Pet 发现、选择和安装 | `AppSettingsStore`、`CodexPetCatalog`、`CodexlingPetInstaller` | 已符合条件展示规则 |
| 主题、自动刷新、更新检查、点击行为 | `SettingsViews.swift`、`AppUpdateService.swift` | 直接复用 |
| 分离窗口和 Popover | `DetachedWindowController`、`StatusBarController` | 保留壳层，替换内容和尺寸策略 |

### 4.2 实施前存在但未接入目标 UI 的能力

- `AppDelegate` 当时持有 `CodexActivityStore`，但只传给 `StatusBarController`，主窗口看不到任务活动。
- `PetAnimationPlayer` 当时只服务状态栏和 hover 卡片，SwiftUI 主窗口没有共享 Pet 帧源。
- `CodexActivityService` 当时会读取最近 12 条线程并计算活跃任务数，但快照只保留一个选中任务，无法实现任务 1/2 切换。
- 额度条件逻辑虽已存在，`UsageViews.swift` 当时仍采用旧的主百分比、进度条和重置券列表布局。
- 设置页已有 Pet 安装卡和成功 Toast，但当时视觉分组、账号卡和新状态栏语义尚未对齐。

### 4.3 本轮新增项

- `CompanionStatsStore`：按日累计活动状态时长。
- 可枚举的 `CodexTaskActivity` 列表，以及稳定的 thread ID。
- SwiftUI 可观察的共享 `PetFrameStore`。
- 新主窗口组件和任务堆叠控件。
- 路由感知的窗口尺寸策略。

## 5. 新增功能可行性验证

| 新增/变化 | 可行性 | 验证结果与限制 |
|---|---|---|
| 主窗口显示任务状态 | 高 | 数据和状态枚举已经存在，只缺 Store 注入和 View 重构 |
| 多任务卡片切换 | 高 | Service 已扫描多线程；需保留活动数组和 thread ID。概念稿交互已验证可用 |
| 等待确认提醒 | 高 | Parser 已识别 `request_user_input` 和提权确认；只做提醒，不代替 Codex 确认 |
| 当前 Pet 驱动主窗口动画 | 中高 | 图集、动画协议和播放器已存在；需要共享帧源并处理窗口订阅生命周期 |
| 今天一起工作 | 中高 | 活跃状态可观察；需新增本地按日累计、跨天结算和异常退出保护 |
| 额度环形双卡 | 高 | 只需替换展示组件；`hasShortWindow` 条件已覆盖 nil 与 0/0 |
| 胶囊背景跟随额度 | 高 | `QuotaHealthLevel` 已有完整阈值；需要重构背景枚举和绘制输入 |
| 圆灯跟随任务状态 | 高 | 颜色枚举已有；需要独立的 `CodexActivityState.statusColor` |
| 登录窗口 | 高 | 当前登录逻辑完整；重排为独立居中引导页即可 |
| Pet 一键安装 | 已完成 | 条件隐藏、安装、重扫、自动选中和错误提示都已落地 |
| 从 Codexling 跳转到具体等待任务 | 暂不承诺 | 当前没有稳定 thread deep link；P0 只提示“回到 Codex” |

## 6. 推荐架构

```text
AppDelegate
├── UsageSnapshotStore ───────────────┐
├── CodexActivityStore ── tasks[] ────┤
├── CompanionStatsStore ─ today ──────┤
├── AppSettingsStore ─ selectedPet ───┤
└── PetFrameStore ─ currentFrame ─────┤
                                      ↓
                         CompanionDashboardView
                         ├── CompanionSidebar
                         ├── ActivitySummary
                         ├── TaskStackView
                         ├── QuotaCardsView
                         └── SyncFooter
```

### 6.1 活动模型调整

建议把聚合模型改为：

```swift
struct CodexTaskActivity: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let state: CodexActivityState
    let detail: String
    let updatedAt: Date
}

struct CodexActivitySnapshot: Equatable, Sendable {
    var primary: CodexTaskActivity?
    var activeTasks: [CodexTaskActivity]
    var displayState: CodexActivityState
    var updatedAt: Date
}
```

Service 查询 `threads.id, rollout_path, title`，以 thread ID 作为稳定标识。`activeTasks` 先按状态优先级，再按更新时间排序；`primary` 为第一项。为了兼容状态栏，可在 Snapshot 上保留当前 `state/detail/threadTitle/activeTaskCount` 的计算属性，分阶段迁移调用方。

### 6.2 陪伴统计定义

沿用 `docs/pet-companion-state-plan.md` 的产品边界：只有 `thinking/executing/reviewing/waitingForUser` 计入“今天一起工作”。

建议持久化到 Application Support：

```text
Codexling/companion_stats.json
```

至少保存 `localDay`, `accumulatedSeconds`, `activeSince`, `lastPersistedAt`。每分钟、状态变化、跨日和 App 退出时结算。系统休眠后的超长空档不能整段计入，可对单次心跳增量设置上限。

### 6.3 Pet 帧共享

不要在 SwiftUI 主窗口中复制一个独立计时器。把现有 `PetAnimationPlayer` 包装成 `@Observable @MainActor PetFrameStore`，由 AppDelegate 持有：

- 状态栏、hover 和主窗口观察同一个 `currentFrame`。
- `selectedPetID` 变化时统一 `setPet`。
- 活动状态变化时统一 `setState`。
- 主窗口关闭不停止播放器；App 退出才停止。
- Reduce Motion 时保留状态首帧。

## 7. 状态栏最终规则

### 7.1 两条独立映射

任务圆灯：

- `unavailable/idle`：`#AEB5B3`
- `thinking`：`#7A42F5`
- `executing`：`#2E6BFF`
- `reviewing`：`#05A1CC`
- `waitingForUser`：`#F27314`
- `completed`：`#1FA55A`
- `interrupted`：`#ED384D`

额度背景：

- ≥ 50%：`#04A05C`
- 20%–49%：`#D99B00`
- < 20%：`#DD4557`
- 未登录/无有效总量：`#79827F`
- 固定中性：白色 50% 透明度

### 7.2 代码改造

- 将 `StatusBarPetBackgroundColor.automatic.resolved(for: activityState)` 改为基于 `QuotaHealthLevel` 解析。
- 新增 `CodexActivityState.statusNSColor`，作为圆灯颜色。
- `StatusCapsuleView.update` 分别接收 `backgroundColor` 与 `activityColor`，取消 `healthColor` 这个会混淆语义的名字。
- 保留现有 12pt 等宽字体、分隔点 kerning 和 20%–50% 圆角设置。
- 将 View 实际高度固定为 20pt，并增加不同菜单栏缩放和深浅壁纸下的截图测试。

### 7.3 Pet 开关的推荐决策

最新状态栏规范以固定任务圆灯为首要信息通道，因此推荐：

- 状态栏总是显示任务圆灯，不再让 Pet 图片替换圆灯。
- 主窗口陪伴区始终播放共享 Pet 帧；“悬停动画 Pet”只控制 hover 卡片，关闭时不影响主窗口或状态圆灯。
- 如果仍必须在状态栏显示 Pet，应把它作为单独的“状态栏显示 Pet”选项，并明确这会隐藏任务圆灯；不应继续复用当前模糊开关。

这是本方案唯一需要产品确认的视觉分支。默认实现采用“固定任务圆灯”，因为它与页面顶部最终说明、40 组合矩阵和状态栏解剖图一致。

## 8. UI 组件拆分与文件落点

建议避免继续扩大 `UsageViews.swift`，新增目录：

```text
Sources/Codexling/UI/
├── DesignTokens.swift
├── CompanionDashboardView.swift
├── CompanionSidebar.swift
├── ActivitySummaryView.swift
├── TaskStackView.swift
├── QuotaCardsView.swift
├── LoginView.swift
├── SyncFooterView.swift
└── SettingsView.swift
```

现有文件改动范围：

| 文件 | 改动 |
|---|---|
| `AppDelegate.swift` | 创建并注入 Stats/Frame Store，统一订阅活动和 Pet 变化 |
| `CodexActivity.swift` | 输出任务数组、稳定 ID 和兼容计算属性 |
| `UsageModels.swift` | 保留额度模型；增加可展示窗口数组等纯计算属性即可 |
| `UsageViews.swift` | 缩减为入口容器或逐步迁移到 `UI/` |
| `SettingsViews.swift` | 新账号卡、新分组、新状态栏语义，复用现有控件与安装逻辑 |
| `DetachedWindowController.swift` | 支持主界面/设置界面不同目标高度和动画 resize |
| `StatusBarController.swift` | 交换任务/额度颜色职责，接入共享 Pet 帧 |
| `AppSettings.swift` | 迁移胶囊背景偏好，兼容旧 UserDefaults 值 |
| `PetModels.swift` | 只在抽取共享播放器接口时调整，不改 Pet 资源契约 |

## 9. 分阶段实施计划

### P0：模型与状态栏语义，先锁定正确性

1. 增加 `CodexTaskActivity` 和 `activeTasks`，保持旧计算属性兼容。
2. 增加 `CompanionStatsStore` 及持久化测试。
3. 增加 `PetFrameStore`，让状态栏先迁移到共享帧。
4. 交换状态栏圆灯/背景颜色职责，完成 8×5 映射单元测试。
5. 增加旧 `petBackgroundColor` 默认值迁移，避免升级后外观随机变化。

完成标准：不改主窗口也能通过现有功能回归；状态栏语义与最新规范一致。

### P1：主窗口和未登录页

1. 新建 `CompanionDashboardView` 并注入四个 Store。
2. 实现 150pt 左栏、任务摘要、单任务/多任务卡、额度环卡和固定 Footer。
3. 实现任务卡点击、Enter、Space 切换及选中任务在列表更新后的边界处理。
4. 以新 `LoginView` 替换旧登录 Feature 列表；未登录时不渲染缓存账号和额度。
5. 对 `idle/running/waiting/unavailable/completed/interrupted` 建 Preview/fixture。

完成标准：460pt 宽下与概念稿一致，无短窗口和多任务时都不跳版。

### P2：设置页与窗口尺寸

1. 设置页加入账号卡，把应用、状态栏与 Pet、当前 Pet 分组对齐概念稿。
2. 复用现有更新下载、主题、刷新、安装、重扫和错误提示逻辑。
3. 将安装卡严格放在“当前 Pet”，只在 `!isCodexlingPetInstalled` 时出现。
4. 重构 `DetachedWindowMetrics`：主界面默认约 580×475pt；设置页约 580×860pt 并在小屏滚动。
5. 路由切换时平滑调整窗口，但不改变用户设置的合法宽度。

完成标准：主窗口不再被当前 760pt 最小高度强制拉长；设置内容在小屏不溢出。

### P3：视觉收口、可访问性与清理

1. 抽取颜色、圆角、字体、间距为 Design Tokens。
2. 深色模式和 macOS 26 Liquid Glass 使用相同语义层级，不逐像素复制 HTML 的浅色背景。
3. 完成 Reduce Motion、VoiceOver、键盘焦点、高对比度和 Dynamic Type/中文截断检查。
4. 清理旧的 quota/coupon 主布局；重置券若仍需保留，移入可展开详情而不是挤回主界面。
5. 更新 `ui-concepts.html` 的冲突文案和 README 文档索引。

完成标准：所有状态截图、键盘路径和回归测试通过，无两套颜色定义残留。

## 10. 测试与验收矩阵

### 10.1 单元测试

- 活动 Parser：八类状态、多个 outstanding calls、任务结束后的 20 秒回落。
- 活动聚合：多任务排序、稳定 ID、任务完成/消失后的选中项回退。
- 陪伴统计：开始、暂停、跨日、休眠大间隔、退出结算、损坏缓存恢复。
- 额度卡：短窗口存在、nil、0/0、周窗口 0/0、未登录。
- 状态栏：8 个任务色、4 个额度健康色、中性固定色、全部组合的文字前景对比。
- 偏好迁移：旧 `automatic/neutral/固定色` 值迁移后结果确定。
- Pet：选择切换、资源消失回退、Reduce Motion、无 Pet 降级。

### 10.2 UI/视觉验收

至少保存以下快照：

- 已登录：idle、thinking、executing、reviewing、waiting、completed、interrupted、unavailable。
- 单任务与 2+ 任务；切换前后。
- 5 小时 + 周额度、仅周额度、无有效额度。
- 未登录、授权中、刷新失败、缓存数据但 token 已失效。
- Pet 已安装、未安装、安装失败、没有可用 Pet。
- 浅色、深色、Reduce Motion、小屏幕高度。
- 状态栏 40 种组合中的全部颜色组合，至少在浅色和深色菜单栏各检查一次。

### 10.3 行为验收

- 刷新、登录、退出、打开官方 Usage、打开设置、关闭设置、切换 Pet、重扫和安装仍可用。
- 等待确认只引导用户回到 Codex，不触发或伪造审批。
- 本地活动读取失败不会影响额度刷新；额度接口失败也不会停止本地活动展示。
- 窗口关闭后状态栏和 hover 的 Pet 动画继续运行。

## 11. 风险与处理

| 风险 | 处理 |
|---|---|
| HTML 有后置覆盖和旧文案 | 以实际渲染、本方案第 3 节和最终状态矩阵为唯一口径 |
| 本地 Codex SQLite/JSONL 是实现细节 | 保持只读 Provider、错误降级和 Parser 隔离，不让 UI 直接读取文件 |
| 多任务频繁变化导致卡片索引越界 | UI 按 task ID 选择，列表变化后回退到 primary，而不是只存数组 index |
| 共享 Pet 播放器引起生命周期问题 | AppDelegate 持有 Frame Store；窗口仅订阅，不拥有播放器 |
| 陪伴时间被休眠放大 | 心跳增量封顶，状态变化和退出时结算 |
| 旧用户偏好语义改变 | 做显式版本迁移，不把旧“跟随任务”静默解释成随机固定色 |
| 460pt 宽中文文案拥挤 | 标题一行、摘要两行、任务卡固定最小高度并允许截断；设置页使用滚动 |
| 当前重置券功能从新主界面消失 | 放入次级详情/展开区，数据与功能不删除 |

## 12. 本次验证记录

- 已完整检查 `ui-concepts.html` 的最终 DOM、CSS 覆盖和 JavaScript 交互。
- 已在 Codex 自带浏览器通过 `http://127.0.0.1:8765/ui-concepts.html` 实际渲染。
- 已验证多任务卡点击后从任务 1 切到任务 2，同时更新 class、辅助功能文案和操作提示。
- 已检查 `app/Codexling` 的 UI、状态栏、活动、额度、设置、窗口、Pet 和 App 生命周期代码。
- 已在正常系统权限下运行最终 `swift test`：38 项测试全部通过，0 failure；覆盖活动、多任务、子代理过滤、额度、陪伴统计、Pet、状态栏、主题、偏好迁移和窗口尺寸。

## 13. 后续维护建议

后续改动应继续保持当前的数据边界：UI 只观察 Store，不直接读取 Codex SQLite/JSONL；新增状态必须同时补充状态栏颜色、Pet 动画映射、主窗口文案和测试 fixture。
