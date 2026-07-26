# Codexling 陪伴式 UI 实现记录

## 1. 当前结论

`ui-concepts.html` 在 2026-07-23 前后用于定义陪伴式主窗口的信息架构。当前 Swift 实现已经继续演进，HTML 仅作为历史设计稿，不再是尺寸、控件或安全文案的事实来源。

现行实现：

1. 主窗口以任务陪伴为主，额度是次级信息。
2. `CodexActivitySnapshot` 保留稳定 ID 的多任务数组，并带项目、分支和模型元数据。
3. `CompanionStatsStore` 本地累计“今天一起工作”。
4. `PetFrameStore` 为主窗口和 hover 卡片提供共享帧；状态栏固定显示任务圆灯。
5. 状态栏圆灯表达任务状态，胶囊背景表达额度健康度或固定颜色。
6. dashboard 使用固定尺寸；设置页按内容测量，并可在约束内缩放。
7. Pet 选择与 Codex 双向同步，并实时监控 `config.toml` 的变化。
8. 独立窗口支持持久化置顶；设置页 Pet 选择器使用可滚动网格。

## 2. 当前界面结构

```text
AppDelegate
├── UsageSnapshotStore ───────────────┐
├── CodexActivityStore ── tasks[] ────┤
├── CompanionStatsStore ─ today ──────┤
├── AppSettingsStore ─ selectedPet ───┤
└── PetFrameStore ─ currentFrame ─────┤
                                      ↓
                         CompanionDashboardView
                         ├── Pet / account sidebar
                         ├── Activity summary
                         ├── Task stack
                         ├── Quota cards
                         └── Sync footer
```

主窗口场景：

| 场景 | 当前行为 |
|---|---|
| 空闲 | 保留 Pet、陪伴统计和额度，不伪造任务 |
| 执行中 | 展示活跃任务数、任务标题、项目/分支/模型及清理、截断后的状态摘要 |
| 多任务 | 按稳定 task ID 切换，列表变化后回退到有效任务 |
| 等待确认 | 最高提醒优先级，只引导回 Codex，不代替审批 |
| 未登录 | 不展示缓存账号与额度，打开官方 OAuth |
| 设置 | 账号、应用、状态栏、Pet、更多 Pet 资源与退出登录 |
| 条件额度 | 没有有效主/次级窗口时不渲染对应额度 |

## 3. 状态栏最终规则

任务圆灯：

- `unavailable/idle`：灰
- `thinking`：紫
- `executing`：蓝
- `reviewing`：青
- `waitingForUser`：橙
- `completed`：绿
- `interrupted`：红

额度背景：

- ≥ 50%：绿
- 20%–49%：黄
- < 20%：红
- 未登录/无有效额度：灰
- `neutral`：半透明白色

当前几何和交互：

- 胶囊高 `24pt`，圆灯 `8pt`，圆灯到文字 `8pt`。
- 字体为 12pt 等宽 medium。
- 宽度随当前状态和额度文案计算。
- 点击只打开独立窗口；旧的 popover 选择偏好已移除。
- hover 延迟 120ms，不设置系统 tooltip。
- 活跃状态可显示 Material wave。
- 胶囊背景默认 `neutral`；`automatic` 是用户可选的跟随额度模式。

## 4. Dashboard 与设置尺寸

`DetachedWindowMetrics` 的当前基线：

```text
dashboard width = 188 + 22×2 + 169×2 + 9 = 579pt
logged-in dashboard height = 510pt
login dashboard height = 440pt
settings width = 579–680pt
settings minimum height = 400pt
settings maximum height = visibleFrame.height - 32pt
```

dashboard 尺寸固定，不允许用户拉伸。设置页首次以屏幕允许高度布局，测得实际内容后收敛；用户可在内容和屏幕约束内调整，较小窗口通过滚动展示内容。路由切换和测量调整以窗口顶边为锚点。

独立窗口根背景不透明，支持浅色、暗色和跟随系统。窗口标题栏提供置顶按钮，置顶状态保存在 `codexling.windowAlwaysOnTop`。

## 5. Pet 选择与动画

- `AppSettingsStore.selectedPetID` 是 Codexling 内部选择状态。
- `CodexPetSelectionSync` 将选择映射到 Codex `config.toml`。
- `CodexPetSelectionMonitor` 监听写入、删除、重命名和原子替换，并重新挂载监控。
- Codexling 中选择 Pet 后会提示重启 Codex；重启可能中断任务，因此先确认。
- 主窗口点击 Pet 可播放随机 one-shot 动作，并避免连续重复。
- 主窗口和 hover 使用同一个 `PetFrameStore`；状态栏不渲染 Pet。

## 6. 陪伴统计

只有 `thinking`、`executing`、`reviewing`、`waitingForUser` 计入“今天一起工作”。

持久化路径：

```text
~/Library/Application Support/Codexling/companion_stats.json
```

Store 每 30 秒结算，状态变化和 App 退出也会结算。跨日清零，单次增量最多 90 秒，避免系统休眠夸大数据。

## 7. 文件落点

当前实现没有按最初计划拆成 `Sources/Codexling/UI/` 目录，而是保持较粗粒度文件：

| 文件 | 当前职责 |
|---|---|
| `AppDelegate.swift` | Store 生命周期、刷新、窗口和 Pet 监控 |
| `CodexActivity.swift` | 本地活动解析、任务聚合与状态色 |
| `CompanionDashboardViews.swift` | dashboard、任务、Pet、额度和重置券 UI |
| `CompanionStores.swift` | `PetFrameStore`、`CompanionStatsStore` |
| `DetachedWindowController.swift` | dashboard/设置尺寸、置顶与窗口生命周期 |
| `StatusBarController.swift` | 胶囊、点击、wave、hover 与安全三角区 |
| `SettingsViews.swift` | 账号、更新、主题、额度提醒色、Pet 网格和外部资源 |
| `AppSettings.swift` | 偏好、迁移和 Codex Pet 选择同步 |

## 8. 已验证范围

当前测试文件包含 46 个 XCTest case，覆盖：

- 主题与跟随系统。
- Pet v2 动画契约、ASAR 与内置 Pet 发现。
- 状态栏额度背景、胶囊点击、hover 安全三角区和偏好迁移。
- dashboard 屏幕高度约束。
- 主/次级额度、订阅周期、重置券与刷新状态。
- 活动状态、多任务、稳定 ID、最近线程的 4 MB 向前扩展和线程元数据。
- 陪伴统计、休眠封顶与跨日清零。
- Pet 选择读写、配置实时监控、置顶偏好和随机交互。

验证命令：

```bash
cd app/Codexling
swift test
```

## 9. 历史设计稿边界

- `ui-concepts.html`：2026-07-23 的设计探索，保留历史场景和交互原型。
- `settings-concepts.html`：2026-07-22 的设置页草案。
- `ui-concepts-companion-backup.html`：更早的陪伴概念备份。

这些 HTML 已明确标记为历史文档。当前尺寸、控件、token 存储和状态栏规则以 Swift 源码及本记录为准。
