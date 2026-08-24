# Codexling Antigravity CLI 接入实施方案

> 版本：v1
> 日期：2026-08-25（Asia/Shanghai）
> 状态：方案已确认，待实施
> 适用范围：Codexling macOS Native Multi-Agent Companion
> 关联文档：[Gemini 供应商额度查询与 Antigravity 桌面端状态检测方案](gemini-and-antigravity-integration-research.md)、[多 Agent 产品与技术方案](multi-agent-product-technical-plan.md)

## 1. 方案结论

Codexling 将 **Antigravity CLI** 建模为 Antigravity Agent Family 下的独立 Surface，而不是新增 Agent、Provider 或账号类型：

```text
agent.antigravity
├── surface.antigravity-desktop
├── surface.antigravity-ide
└── surface.antigravity-cli
```

首期目标是让用户直接在 Terminal 中运行官方 `agy` 时，Codexling 能够无侵入地发现 CLI 会话并把活动状态同步到：

- 主窗口 Agent 任务卡；
- 状态栏与刘海面板；
- 主窗口 Pet；
- 独立 Pet；
- 多任务聚合与等待确认优先级仲裁。

首期不由 Codexling 托管或代理用户的 `agy` 进程，不复制 Google OAuth Token，不修改 Antigravity 权限策略，也不读取或持久化完整 Prompt、回复、命令参数和文件内容。

## 2. 本机验证结论

### 2.1 官方 CLI 与版本

本机真正的 Antigravity CLI 可执行文件为：

```text
~/.local/bin/agy
```

实测版本：

```text
agy 1.1.19
```

Antigravity Desktop 附带的：

```text
~/.gemini/antigravity/bin/agentapi
```

是调用 Desktop `language_server agentapi` 的辅助入口，不等同于 Antigravity CLI。两者必须分别探测，不能继续用 `agentapi` 代表“CLI 已安装”。

### 2.2 CLI 本地数据目录

Antigravity CLI 使用独立于 Desktop 的数据目录：

```text
~/.gemini/antigravity-cli/
├── conversations/
│   └── <conversation-id>.db
├── brain/
│   └── <conversation-id>/.system_generated/logs/
│       ├── transcript.jsonl
│       └── transcript_full.jsonl
├── presence/
│   └── <conversation-id>.lock
├── history.jsonl
├── cache/
├── log/
└── settings.json
```

现有 `AntigravityActivityService` 只读取：

```text
~/.gemini/antigravity/
```

因此当前实现只能覆盖 Desktop 会话，无法发现 `agy` CLI 会话。

### 2.3 官方结构化接口

`agy` 支持 Headless 结构化输出：

```bash
agy --input-format stream-json --output-format stream-json
```

事件流为 NDJSON，主要事件包括：

- `init`：会话 ID、工作目录、工具列表、权限模式、模型与 Agent；
- `step_update`：用户输入、模型回复、工具执行、Checkpoint 与 Subagent；
- `result`：最终状态、回复、耗时、轮次与 Token 用量。

官方文档：<https://antigravity.google/docs/cli/headless/>

该协议适用于未来由 Codexling 启动的 Managed Session。用户自行在 Terminal 启动的普通 TUI 会话，其 stdout 不属于 Codexling，首期仍采用本地只读 Attached Session 方案。

## 3. 当前代码缺口

### 3.1 安装状态存在误判

`AgentHookManager.locateExecutable(for:)` 当前优先检查 Desktop 的 `agentapi`，导致以下情况可能被错误标记为“CLI 已安装”：

```text
Antigravity Desktop 已安装
agy CLI 未安装
agentapi 存在
→ 当前结果：cliInstalled = true
```

应把安装能力拆成明确的 Surface 状态：

```swift
struct AgentSurfaceIntegrationStatus {
    let agentID: AgentID
    let surfaceID: AgentSurfaceID
    let installed: Bool
    let executableURL: URL?
    let version: String?
    let activitySource: ActivitySource
}
```

### 3.2 Activity Service 固定为 Desktop

现有 `AntigravityActivityService` 存在以下硬编码：

- 根目录固定为 `~/.gemini/antigravity`；
- 任务 ID 固定为 `antigravity:<id>`；
- 模型/Agent 名固定为 `Antigravity`；
- 快照未携带 Surface；
- Desktop 与 CLI 同时运行时无法区分来源。

### 3.3 任务模型缺少可路由身份

当前任务打开逻辑依赖 `agentDisplayName == "Antigravity"`，然后一律打开 Antigravity Desktop。CLI 会话加入后，这会产生错误路由。

任务应显式保存：

```swift
agentID: AgentID?
surfaceID: AgentSurfaceID?
vendorSessionID: String?
workspacePath: String?
modelName: String?
```

兼容现有已持久化数据时，这些字段保持可选并提供默认值，不对旧任务做破坏性迁移。

## 4. 总体架构

```text
Antigravity Desktop                  Antigravity CLI
~/.gemini/antigravity                ~/.gemini/antigravity-cli
          │                                      │
          └─────────── Read-only Adapter ────────┘
                              │
                    AntigravitySessionReader
                              │
                ┌─────────────┴─────────────┐
                │                           │
      surface.antigravity-desktop  surface.antigravity-cli
                │                           │
                └──── CodexActivitySnapshot ┘
                              │
                 CodexActivitySnapshot.merged
                              │
             Main Window / Notch / Status Bar / Pet
```

推荐将现有服务拆成两层：

```swift
struct AntigravitySurfaceConfiguration {
    let rootURL: URL
    let surfaceID: AgentSurfaceID
    let displayName: String
    let taskIDPrefix: String
}

struct AntigravitySessionReader {
    let configuration: AntigravitySurfaceConfiguration

    func loadSnapshot(now: Date) -> CodexActivitySnapshot
}
```

默认注册两个 Reader：

```text
Desktop → ~/.gemini/antigravity
CLI     → ~/.gemini/antigravity-cli
```

IDE 后续可按相同结构接入 `~/.gemini/antigravity-ide`，不再复制第三套解析代码。

## 5. 会话发现与活跃判定

### 5.1 会话发现

CLI Reader 扫描：

```text
~/.gemini/antigravity-cli/conversations/*.db
```

以文件名作为 `vendorSessionID`，定位：

```text
~/.gemini/antigravity-cli/brain/<id>/.system_generated/logs/transcript.jsonl
```

任务主键必须带 Surface，避免 Desktop 与 CLI ID 冲突：

```text
antigravity:desktop:<conversation-id>
antigravity:cli:<conversation-id>
```

### 5.2 标题与工作区

元数据按以下顺序读取：

1. `history.jsonl` 中同 `conversationId` 的最近一条普通用户输入；
2. transcript 首批 `USER_INPUT` 中的 `<USER_REQUEST>`；
3. transcript Checkpoint 中的 `# USER Objective:`；
4. 默认标题 `Antigravity CLI 任务`。

工作区按以下顺序读取：

1. `history.jsonl.workspace`；
2. Hook 的 `workspacePaths`；
3. Headless `init.cwd`；
4. 无法确定时保持为空，不猜测用户路径。

展示层只使用工作区目录名；绝对路径仅在本地内存中用于打开目标，不上传、不写入诊断日志。

### 5.3 活跃判定

不能单独依赖 `presence/*.lock` 是否存在，因为 CLI 异常退出后可能留下空锁文件。首期使用组合信号：

1. transcript 或 conversation DB 最近更新时间；
2. 最后一条 Step 的时间与状态；
3. `presence/<id>.lock` 作为加权信号；
4. 已完成/失败状态使用较短展示保留时间；
5. 超出活跃窗口后回落为空闲，不永久展示僵尸任务。

建议保留当前 180 秒活跃窗口作为兼容默认值，并把“刚完成”展示窗口单独设为 15 秒。

性能要求：

- 不在每次刷新时读取完整 transcript；
- 首次读取头部少量事件解析标题；
- 后续仅读取文件尾部或缓存上次偏移；
- 文件未变化时直接复用解析结果；
- 外部文件格式异常时 fail-open，不影响 Codex、Gemini 和 UI 主线程。

## 6. 状态机映射

| Antigravity CLI 信号 | Codexling 状态 | UI 文案建议 |
|---|---|---|
| 新 `USER_INPUT` | `.thinking` | 正在思考与规划 |
| `PLANNER_RESPONSE` 正在形成回复 | `.thinking` | 正在分析任务 |
| 只读工具：`view_file`、`grep_search`、`find_by_name`、`search_web` | `.reviewing` | 正在分析任务 |
| 写入/命令工具：`write_to_file`、`replace_file_content`、`run_command` | `.executing` | 正在执行工具 |
| 工具返回 `GENERIC` | `.reviewing` | 正在检查结果 |
| `ask_question` 或已确认的权限等待信号 | `.waitingForUser` | 等待你确认 |
| 最终纯文本回复且无挂起工具 | `.completed` | 本轮任务已完成 |
| Step `status == ERROR` | `.failed` | 执行失败 |
| Headless `result.status == CANCELED/INTERRUPTED` | `.interrupted` | 任务已中止 |
| Headless `result.status == WAITING` | `.waitingForUser` | 等待你操作 |
| 长时间无新事件 | `.idle` | Antigravity CLI 当前空闲 |

状态仲裁继续使用项目现有规则：

```text
waitingForUser
→ failed / rateLimited
→ completed
→ reviewing / executing / thinking
→ interrupted
→ idle / offline
```

## 7. 官方 Hook 接入策略

Antigravity Lifecycle Hook 支持：

- `PreToolUse`；
- `PostToolUse`；
- `PreInvocation`；
- `PostInvocation`；
- `Stop`。

Hook 会通过 stdin 提供 camelCase JSON，包括：

```text
conversationId
workspacePaths
transcriptPath
artifactDirectoryPath
modelName
```

### 7.1 首期原则

首期 Hook 为可选增强，不作为 CLI 发现的前置条件。未安装 Hook 时，transcript Reader 仍必须正常工作。

### 7.2 权限安全边界

`PreToolUse` 不只是通知事件，还要求 Hook 返回 `allow`、`deny`、`ask` 或 `force_ask` 决策。因此不能把它当作纯观察 Hook 随意安装，否则可能改变 Antigravity 原有权限行为。

实施约束：

- 未验证官方无副作用的 no-op 契约前，不自动安装 `PreToolUse`；
- 不返回 `allow` 绕过用户确认；
- 不返回 `ask` 强制增加确认；
- 不修改 `permissionOverrides`；
- 不使用 `overwrite` 改写工具参数；
- Hook Bridge 必须输出符合事件契约的中性 JSON；
- Hook 失败不得阻止 Agent 正常执行。

### 7.3 可安全复用的事件桥

现有 `CodexlingAgentBridge` 与本地 `agent-events.sock` 可以继续复用。事件统一脱敏为：

```swift
NormalizedAgentEvent(
    agentID: .antigravity,
    surfaceID: .antigravityCLI,
    sessionID: conversationId,
    event: normalizedEvent,
    toolCategory: sanitizedCategory,
    outcome: sanitizedOutcome
)
```

Bridge 不传递：

- Prompt/回复正文；
- 工具参数；
- 命令内容；
- 文件完整路径；
- 模型 Reasoning；
- OAuth Token、Cookie 或环境变量。

## 8. Managed Headless Session（后续阶段）

当产品未来支持从 Codexling 发起 Antigravity 任务时，使用官方 stream-json 协议：

```text
Codexling
   │ stdin: {"event":"user","message":{"content":"..."}}
   ▼
agy --input-format stream-json --output-format stream-json
   │ stdout: init / step_update / result
   ▼
AntigravityCLIStreamAdapter
   ▼
NormalizedAgentEvent
```

推荐映射：

| stream-json | Normalized Agent Event |
|---|---|
| `init` | `session.started` |
| `step_update.step_type == user_input` | `prompt.submitted` |
| `agent_response + ACTIVE` | `prompt.submitted` / thinking |
| `tool + ACTIVE` | `tool.started` |
| `tool + DONE` | `tool.finished` |
| `result.status == SUCCESS` | `turn.completed` |
| `ERROR` | `failed` |
| `CANCELED/INTERRUPTED` | `session.ended` + interrupted outcome |

Managed Session 不进入首期，避免把“监控现有 Agent”扩大为“由 Codexling 托管执行与权限”的新产品范围。

## 9. UI 与交互

### 9.1 Agent 设置

Antigravity 使用一个 Agent 分组，按 Surface 展示：

```text
Antigravity
├── Desktop   已安装 · Transcript 活动读取
└── CLI       已安装 · agy 1.1.19 · Transcript 活动读取
```

CLI 未安装时显示官方安装入口，但不把 Desktop 的 `agentapi` 当作 CLI。

### 9.2 任务卡

CLI 任务建议显示：

```text
Antigravity CLI · 正在执行
分析当前项目的 Agent 接入架构
Codexling · Gemini 3.7 Flash
```

主窗口、独立 Pet 和刘海面板必须使用同一个 `CodexTaskActivity`，避免三处状态与点击逻辑不一致。

### 9.3 打开 CLI 任务

CLI 会话不能继续沿用“打开 Antigravity Desktop”的逻辑。

首期安全交互：

1. 有可靠的原 Terminal 窗口归属时，激活该终端；
2. 无法定位时提供“复制恢复命令”：

   ```bash
   agy --conversation <conversation-id>
   ```

3. 不在后台自动执行恢复命令；
4. 不把 CLI 会话错误路由到 Desktop App；
5. 不通过解析显示文案判断 Surface。

如果首期不实现终端窗口定位，任务卡仍可点击弹出操作菜单，至少提供“复制恢复命令”和“打开工作目录”。

## 10. 代码改造清单

### 10.1 领域模型

- `MultiAgentModels.swift`
  - 保留现有 `.antigravityCLI`；
  - 将开发优先级从仅 Desktop 扩展到 CLI；
  - 为任务增加可选 Agent/Surface/Session 路由字段。

### 10.2 安装发现

- `AgentHookManager.swift`
  - 分离 `agentapi` 与 `agy`；
  - 探测 `~/.local/bin/agy`、Homebrew 和 PATH；
  - 读取 `agy --version`，设置短超时并缓存；
  - 失败时只显示未知版本，不阻塞设置页。

### 10.3 活动读取

- `AntigravityActivityService.swift`
  - 抽取 Surface Configuration；
  - 注册 Desktop 与 CLI 两个 Reader；
  - 增加 history/workspace 读取；
  - 增加增量尾读与缓存；
  - 为任务 ID 添加 Surface 前缀。

### 10.4 聚合与路由

- `CodexActivity.swift`
  - 同时合并 Desktop 与 CLI 快照；
  - 同会话同 Surface 去重；
  - 不让空闲 CLI 覆盖活跃 Codex/Desktop。
- `AgentTaskOpener.swift`
  - 改为基于 `agentID + surfaceID` 路由；
  - CLI 不再打开 Desktop；
  - 提供恢复命令与工作目录动作。

### 10.5 UI

- `SettingsViews.swift`
  - 按 Surface 显示安装与活动来源；
  - 展示 `agy` 版本和诊断信息。
- `CompanionDashboardViews.swift`
  - 显示 `Antigravity CLI` 来源；
  - 复用统一任务点击路由。
- `StatusBarNotch.swift` / `NotchCapsulePanel.swift`
  - 使用统一任务模型，不增加 CLI 专用状态分支。

## 11. 测试矩阵

### 11.1 安装发现

- 仅 Desktop/`agentapi` 存在时：Desktop 已安装，CLI 未安装；
- 仅 `agy` 存在时：CLI 已安装，Desktop 未安装；
- 两者都存在时：两个 Surface 分别已安装；
- `agy --version` 超时或异常时：CLI 仍可标记安装，版本为未知。

### 11.2 会话读取

- CLI `USER_INPUT` 映射为思考中；
- 只读工具映射为检查中；
- 写入/命令工具映射为执行中；
- 最终回复映射为已完成；
- ERROR 映射为失败；
- 过期会话不进入活跃任务；
- 损坏 JSONL 行被忽略且不影响其他会话；
- 大 transcript 只读取必要片段，不整文件反复加载。

### 11.3 多 Surface

- Desktop 与 CLI 同时活跃时显示两个任务；
- 两个 Surface 使用相同 conversation ID 时不冲突；
- CLI 等待确认时按优先级置顶；
- CLI 空闲不覆盖 Desktop/Codex 活跃任务；
- Pet 能从 Desktop 平滑切换到优先级更高的 CLI 任务。

### 11.4 交互

- CLI 任务不打开 Antigravity Desktop；
- 恢复命令使用原始 vendor conversation ID；
- 无 workspace 时不显示无效“打开目录”；
- 主窗口、独立 Pet、刘海面板点击结果一致。

## 12. 验收标准

### 12.1 MVP 验收

1. 安装 `agy` 后，设置页准确显示 Antigravity CLI 已安装及版本；
2. 在任意 Terminal 启动普通 `agy` TUI 并提交任务，Codexling 在一个刷新周期内出现 `Antigravity CLI` 任务；
3. 思考、读取、执行、检查、完成等状态能够驱动 Pet；
4. Desktop 与 CLI 同时工作时任务不冲突；
5. CLI 任务不会错误打开 Antigravity Desktop；
6. 退出 CLI 后，任务在合理保留窗口后回落为空闲；
7. 不修改 `~/.gemini/antigravity-cli/settings.json` 和权限配置；
8. 不读取或复制 OAuth Token；
9. 全量 Swift 测试通过，Release 构建成功；
10. 真机验证主窗口、刘海、状态栏、主 Pet 与独立 Pet。

### 12.2 增强阶段验收

1. 用户显式启用 Hook 后，事件通过本地 Socket 实时进入统一 Reducer；
2. Hook 不改变 Antigravity 权限行为；
3. Hook 删除或失效时自动退回 transcript Reader；
4. Managed Headless Session 可以精确获得工具开始/结束、最终状态与 Token 用量。

## 13. 风险与回退

| 风险 | 影响 | 应对 |
|---|---|---|
| Antigravity 本地目录或 transcript 格式升级 | CLI 状态无法解析 | 宽松 Decodable、版本探测、未知字段忽略、Reader fail-open |
| 仅用文件 mtime 误判活跃 | 僵尸任务或过早消失 | 组合 transcript、DB、Step 时间与 presence 信号 |
| Hook 参与权限决策 | 改变用户安全策略 | 首期不自动安装 `PreToolUse`，Hook 必须显式启用 |
| transcript 过大 | 轮询引起 CPU/IO 增长 | 增量尾读、offset 缓存、文件未变直接复用 |
| Desktop/CLI ID 相同 | 任务被错误去重 | 主键加入 Surface |
| 无法定位原 Terminal 窗口 | 点击体验不完整 | 提供复制恢复命令与打开工作区作为可靠回退 |
| `agy` 更新导致 CLI 参数变化 | 版本检测或启动失败 | capability probe、超时、版本缓存；不把 Managed Session 作为 MVP 前置条件 |

## 14. 分阶段实施顺序

### 阶段 A：基础 Attached CLI（MVP）

1. 修正 `agy`/`agentapi` 安装探测；
2. 抽象 Antigravity Surface Reader；
3. 接入 `~/.gemini/antigravity-cli`；
4. 任务模型补充 Surface 与 vendor session；
5. Desktop/CLI 双源聚合；
6. CLI 任务安全打开策略；
7. 单元测试、Release 构建与真机验收。

### 阶段 B：可选官方 Hook

1. 验证各 Hook 的中性输出契约；
2. 扩展 `CodexlingAgentBridge` 的 camelCase 输入；
3. 提供显式安装、诊断和卸载；
4. 与 transcript Reader 去重；
5. 验证权限行为无变化。

### 阶段 C：Managed Headless Session

1. 新增 `AntigravityCLIProcessController`；
2. 解析 `init/step_update/result`；
3. stdin 多轮会话与优雅退出；
4. 模型、Agent、Effort 与 Sandbox 选择；
5. Token 用量展示；
6. 进程崩溃、超时和恢复处理。

## 15. 最终产品边界

Antigravity CLI 首期接入的准确表述是：

> Codexling 以本地只读方式观察用户正在运行的 Antigravity CLI 会话，将脱敏后的生命周期状态统一展示在主窗口、状态栏、刘海与 Pet 中。

首期不承诺：

- 代替 Antigravity CLI 登录；
- 管理或复用 Google OAuth Token；
- 自动批准工具权限；
- 从 Codexling 启动完整 Antigravity 对话；
- 在 Desktop、IDE 与 CLI 之间实时迁移同一运行中会话；
- 展示完整 Prompt、回复、命令或代码内容。

该边界可以先稳定交付 Attached CLI 体验，同时为官方 Hook 与 Headless Managed Session 留出清晰的后续演进路径。
