# Codexling 多 Agent 与多账号优先开发方案

> 版本：v1
> 日期：2026-08-10（Asia/Shanghai）
> 状态：已确认优先级，并完成本机协议级可行性验证
> 本文覆盖并替代旧方案中的“首版范围、分阶段交付、首批研发任务拆分”；旧方案的隐私、安全、Pet 和 UI 原则继续有效。

## 1. 已确认的优先级

### 1.1 Agent

严格按以下顺序交付：

1. Codex
2. Hermes
3. Claude Code CLI
4. Claude Code Desktop
5. Reasonix

Claude Code CLI 与 Claude Code Desktop 是同一 Agent family 的两个 surface，共用身份与订阅语义，但采用不同的状态接入方式，不能在底层建成两个独立账号域。

### 1.2 多账号

1. 多 Codex 账号
2. 多 DeepSeek 官方 API Key

多账号必须先于外部 Agent UI 扩张进入领域模型。所有 session、quota、错误、刷新状态都必须带 `connectionID`，不得再假设一个 Agent 或 Provider 在本机只有一个连接。

## 2. 核心技术决策

### 2.1 统一主键

```text
AgentSessionID = agentID + connectionID + vendorSessionID
QuotaSnapshot  = providerID + connectionID + scope + fetchedAt
```

理由：不同 Codex 账号可能产生相同形态的 thread ID；同一个 DeepSeek 用户下的多个 Key 也可能返回完全相同的账户余额。UI 显示名不能作为主键。

### 2.2 Agent 与 surface 分离

```text
agent.claude-code
├── surface.claude-code-cli
└── surface.claude-code-desktop
```

同理，Codex CLI/Desktop 和 Reasonix CLI/Desktop 也使用 surface 区分。身份、额度属于 connection；安装、启动、事件来源属于 surface。

### 2.3 多 Codex 不复制 token

每个 Codex connection 使用独立目录：

```text
~/Library/Application Support/Codexling/Runtimes/Codex/<connection-id>/
├── config.toml
├── auth.json                 # 仅当官方 CLI 配置为 file store 时由 Codex 自己写入
├── sessions/
└── log/
```

Codexling 只设置该子进程的 `CODEX_HOME`，并为多账号 connection 固定 `cli_auth_credentials_store = "file"`，然后启动官方 `codex login`、`codex app-server` 或 `codex logout`。文件由官方 Codex 写入并保持 `0600`；Codexling 不读取、不复制、不解析 `auth.json`。在官方文档明确确认 Keychain item 会按 `CODEX_HOME` 隔离前，不用 keyring 承载多账号，以免不同 connection 命中同一个系统凭证项。

每个账号独立运行一个 App Server，并维护独立的 socket、健康状态和退避器。Codexling 通过 App Server 的 account/thread/turn/rate-limit 协议读取结构化状态；当前 SQLite/rollout 解析器降级为 legacy fallback，不再作为新架构主路径。

限制：这一方案首先保证 Codexling 托管的 CLI/App Server 账号隔离。Codex 官方 Desktop App 是否能同时绑定多个 `CODEX_HOME` 不作为首期承诺；默认 Desktop 仍代表官方 App 当前登录账号。

### 2.4 多 DeepSeek Key 不冒充“每 Key 余额”

每个 Key 独立保存为 Keychain item：

```text
service: com.qiizo.Codexling.credentials
account: <connection-id>
```

连接元数据只保存 label、Key 后四位、验证时间和状态。每个连接独立调用官方 `GET /user/balance`。

该接口返回的是 user/account balance，不是 Key 独享余额或 Key 历史消费。因此：

- snapshot 的 `scope` 必须是 `account`，不能标成 `apiKey`。
- 同一 DeepSeek 账号创建的多个 Key 很可能显示相同余额，这是正确结果。
- 首期不展示“某 Key 已花费多少”，除非后续有官方 Key 级 usage API。
- 401/403 仅使当前 connection invalid，不影响其他 Key。

## 3. Agent 接入方案

| 优先级 | 对象 | 首选接入 | Attached/回退 | 首期能力 | 可行性 |
|---:|---|---|---|---|---|
| 1 | Codex | 每账号独立 `codex app-server` | 现有 SQLite/rollout 只读解析 | 多账号、thread/turn、等待、额度、Pet | 高；App Server 当前仍标 experimental，需版本门禁 |
| 2 | Hermes | TUI Gateway JSON-RPC；managed 可用 ACP | 官方 shell hooks | session list/status/usage、审批、Pet | 高 |
| 3 | Claude Code CLI | `claude agents --json` 聚合后台/活动 session | 官方 hooks；managed 可用 stream-json/SDK | 活动发现、等待/完成、启动/打开 | 高；命令需按版本探测 |
| 4 | Claude Code Desktop | 官方 `claude://code/...` 深链 | 仅复用已确认来自 Claude Code hooks 的事件 | 安装发现、打开/新建 Code session | 启动高，完整被动观测中等 |
| 5 | Reasonix | ACP v1 stdio managed session | 官方 lifecycle hooks / event log | tool、plan、permission、状态、Pet | 高 |

### 3.1 Codex

开发顺序：

1. App Server client + schema/version capability probe。
2. 用单账号 adapter 包装现有 UI，确保无回归。
3. 引入 `CodexConnectionRuntime`，每 connection 一个 `CODEX_HOME`、socket 和进程。
4. 登录、退出、启动任务都必须显式选择 connection。
5. 聚合多个账号的 thread/turn/rate-limit，Pet 仍按等待优先、最近活跃次之。

### 3.2 Hermes

Hermes 的 TUI Gateway 已提供 `session.list`、`session.active_list`、`session.status`、`session.usage`、approval/clarify 等方法，比仅安装 hooks 信息更完整。建议：

- managed/attached-to-gateway：优先 Gateway JSON-RPC。
- Codexling 自己创建的编辑器式会话：ACP。
- 用户在普通 CLI/gateway 中启动的会话：用户显式安装 shell hook，bridge 只保留脱敏状态。

### 3.3 Claude Code CLI

- discovery：`claude auth status` 只读取官方 JSON 状态并严格白名单字段。
- active sessions：优先 `claude agents --json`，轮询间隔 2–5 秒，失焦后降频。
- fine-grained lifecycle：SessionStart、PreToolUse/PostToolUse、PermissionRequest、Stop 等官方 hooks 映射到 bridge。
- managed automation：仅在用户从 Codexling 启动任务时使用 `--output-format stream-json` 或 Agent SDK。
- 不读取 Claude token 文件，不解析完整 transcript。

### 3.4 Claude Code Desktop

首期仅承诺：

- 检测 `/Applications/Claude.app`。
- 使用 `claude://code/new?folder=...` 打开新会话；folder 必须由 Claude Desktop 再次确认。
- 若官方后续提供 Code session 定位 deep link，再按 capability 增加“打开已有会话”；首期不自行拼接未文档化 URL。

不得通过 Accessibility、窗口标题或私有数据库推断完整任务状态。若 Desktop Code session 触发与 CLI 相同的官方 hooks，则可复用 Claude adapter 事件，但必须先做版本矩阵验证后再标“实时状态”。

### 3.5 Reasonix

Reasonix 当前官方 ACP v1 能推送 message、tool、plan、permission 和配置更新，适合 managed adapter；CLI/desktop 的 lifecycle hooks 适合 attached adapter。首期实现 ACP，hooks 次之，不读取 transcript 正文。

### 3.6 Pet Hook 与统一状态桥接

#### 3.6.1 能力结论

“Pet 能力”拆成两层：

1. **Pet 素材与渲染**：spritesheet、动画播放和 Pet 选择。
2. **活动事件来源**：Agent lifecycle hook、ACP/RPC/App Server 事件，用于决定当前播放哪个状态。

Codex 和 Hermes 已有一方 Pet；Claude Code 与 Reasonix 没有公开的一方 Pet，但其生命周期事件足以驱动 Codexling Pet。DeepSeek API Key 是 Provider connection，不产生 Agent lifecycle，只影响余额、限流和 `rateLimited` 健康状态。

| 对象 | 一方 Pet | 首选 Pet 状态源 | Hook/回退 | Pet 可行性 |
|---|---:|---|---|---|
| Codex | 有；Desktop/CLI 均有官方状态 | App Server thread/turn events | 官方 Codex Hooks | 很高 |
| Hermes | 有；Petdex 可跟随 CLI/TUI/Desktop | Gateway JSON-RPC / ACP | plugin 或 shell hooks | 很高 |
| Claude Code CLI | 未发现 | `claude agents --json` + hooks | stream-json / Agent SDK | 很高 |
| Claude Code Desktop | 未发现 | 经版本验证后复用 Claude Code hooks | launcher + 弱状态 | 中等，实验性 |
| Reasonix | 未发现 | Managed 使用 ACP | Attached 使用 lifecycle hooks | 高 |

Codex 官方 Pet 使用 `Running`、`Needs input`、`Ready`、`Blocked` 四种活动语义，并在多 chat 时按 `Needs input → Blocked → Ready → Running` 仲裁。Codexling 保留更细的内部状态，但 Pet 多会话仲裁与其对齐：

```text
waitingForUser
→ failed / rateLimited
→ completed
→ reviewing / executing / thinking
→ idle / offline
```

#### 3.6.2 通用 Pet Bridge

所有 attached hooks 统一调用随 App 打包的无状态 helper：

```text
Vendor Hook / ACP / App Server
        │
        ▼
codexling-agent-bridge
        │  Unix domain socket
        ▼
NormalizedAgentEvent
        │
        ▼
AgentActivityState → PetStateMapper → PetFrameStore
```

统一事件只允许以下字段：

```json
{
  "schemaVersion": 1,
  "agentID": "agent.claude-code",
  "surfaceID": "surface.claude-code-cli",
  "connectionID": "local-connection-id",
  "sessionID": "vendor-session-id",
  "turnID": "optional-turn-id",
  "event": "permission.requested",
  "toolCategory": "shell",
  "outcome": null,
  "timestamp": "2026-08-10T12:00:00Z"
}
```

helper 的产品约束：

- 只做白名单提取、状态归一化和本地 socket 投递，不做账号、审批或 Agent 控制。
- App/socket 不可用时在 100 ms 内成功退出，绝不能阻塞 Agent。
- observer hook 始终 fail-open；Codexling 不通过 Pet hook 自动允许、拒绝或修改工具调用。
- 单事件上限 8 KB；超限直接丢弃并仅记录错误类别。
- hook 安装前显示配置 diff，用户显式确认；卸载只删除 Codexling 自己的配置块。

#### 3.6.3 Agent 事件映射

**Codex**

| 官方事件 | Codexling 状态 |
|---|---|
| `SessionStart` | `idle` |
| `UserPromptSubmit` | `thinking` |
| `PreToolUse` | `executing`；按 tool name 映射 reading/writing/shell |
| `PermissionRequest` | `waitingForUser` |
| `PostToolUse` | `thinking` 或 `reviewing` |
| `Stop` | debounce 后 `completed`；若立即出现新事件则不闪完成动画 |
| `SessionEnd` | `idle` / `offline` |
| App Server turn error | `failed` |

Codex 的 App Server 是状态主源，Hook 用于用户自行启动的 CLI attached session 和版本回退。Custom Pet 只提供视觉素材，动画状态仍由运行时决定，Codexling 不尝试给 `pet.json` 注入执行逻辑。

**Hermes**

| 官方事件 | Codexling 状态 |
|---|---|
| `on_session_start` / `pre_llm_call` | `thinking` |
| `pre_tool_call` | `executing` |
| `pre_approval_request` | `waitingForUser` |
| `post_approval_response` | `thinking` / `executing`；deny/timeout 可显示短暂失败 |
| `on_session_end(completed=true)` | `completed` |
| `on_session_end(interrupted=true)` | `interrupted` |
| `on_session_finalize` | `idle` / `offline` |

Hermes 自带 Petdex，Codexling 只观察状态，不改写 Hermes 当前 Pet 选择；用户可以同时关闭 Hermes Pet、只保留 Codexling 菜单栏 Pet。

**Claude Code CLI**

| 官方事件 | Codexling 状态 |
|---|---|
| `SessionStart` / `UserPromptSubmit` | `thinking` |
| `PreToolUse` | `executing` |
| `PermissionRequest` | `waitingForUser` |
| `PostToolUse` | `thinking` / `reviewing` |
| `PostToolUseFailure` / `StopFailure` | `failed` |
| `Stop` / `TaskCompleted` | `completed` |
| `SessionEnd` | `idle` / `offline` |

Claude Code Desktop 不单独创建第二套 Pet adapter。先安装一个只上报事件名的诊断 hook，在目标版本逐项验证 SessionStart、tool、permission、Stop；全部通过后，该版本的 Desktop surface 才声明 `realtimePet=true`。未通过时只显示“已打开/可能运行”，不显示虚假的等待或完成状态。

**Reasonix**

| 模式 | 事件来源与映射 |
|---|---|
| Managed | ACP message → `thinking`；tool → `executing`；permission request → `waitingForUser`；session result → `completed/failed` |
| Attached CLI/Desktop | `UserPromptSubmit` → `thinking`；`PreToolUse` → `executing`；`PostToolUse` → `thinking/reviewing`；`Stop` → `completed` |

Reasonix Attached 模式只有在对应版本能稳定提供审批通知事件时才启用 `waitingForUser`；否则该状态只由 ACP managed session 提供。

#### 3.6.4 Hook 隐私边界

各厂商 hook payload 可能包含 `transcript_path`、`tool_input`、`tool_response`、shell command、args、prompt、最后一条 assistant message 或环境信息。以下字段不得进入 bridge payload、cache、diagnostics、崩溃信息或 UI：

- prompt、response、assistant message 正文
- transcript 路径与内容
- tool arguments、command、tool response
- 环境变量、API Key、token
- 完整本地路径；workspace 只保存用户可见名称或不可逆本地标识

Pet 只需要知道“谁、哪次 session、处于什么状态、何时更新”，不需要知道 Agent 正在处理的内容。

## 4. 分阶段交付

### M0：账号感知内核

- `AgentID`、`AgentSurfaceID`、`ConnectionID`、`ProviderID`。
- `NormalizedAgentEvent`、`AgentActivityState`、`PetStateMapper` 与跨 session Pet 仲裁器。
- 所有 session/quota 主键纳入 connection。
- registry 支持同一 adapter 的多个 runtime instance。
- UI 在只有一个 connection 时保持现状。

验收：两个账号的同名 session 不冲突；删除一个 connection 不影响另一个；等待/失败/完成/活动仲裁顺序稳定；旧缓存可安全迁移或丢弃后重建。

### M1：Codex App Server + 多账号

- App Server Swift client、schema capability probe、版本门禁。
- 独立 `CODEX_HOME` 生命周期与每账号进程 supervisor。
- Add/Login/Logout/Rename/Disable Codex connection。
- account/thread/turn/rate-limit 聚合。
- App Server Pet mapping；Codex Hook 作为 attached/fallback adapter。

验收：至少两个测试 home 可独立登录状态检查；一个进程崩溃不影响另一账号；`PermissionRequest` 能驱动等待动画；现有单账号 UI 和 Pet 无回归。

### M2：DeepSeek 多 Key

- Keychain CRUD、connection metadata、secret redaction。
- `/user/balance` adapter 与 fixture parser。
- 多 Key 设置页、逐连接刷新/删除/失败隔离。

验收：相同账户的两个 Key 可显示相同 account balance 且不会误标为 Key 余额；日志、缓存、诊断中无完整 Key。

### M3：Hermes

- Gateway JSON-RPC adapter。
- ACP managed adapter。
- shell hook bridge 与隐私过滤。

验收：session status/approval/usage 可结构化映射；`pre_approval_request` 能驱动等待动画；不修改 Hermes Pet 选择；Hermes 未运行时零影响；hook 可预览和卸载。

### M4：Claude Code CLI

- `claude agents --json` discovery adapter。
- hooks bridge。
- CLI launcher/deep link handoff。

验收：前台和后台 session 至少各一种可观测；等待批准置顶；tool failure 和 Stop 能正确驱动 Pet；不保存 prompt、tool input 或 transcript。

### M5：Claude Code Desktop

- 安装发现和 `claude://code/new`。
- 验证 Desktop Code session 是否稳定触发官方 hooks。
- 仅在验证通过的版本上启用实时状态 feature flag。

验收：版本矩阵明确记录每个 lifecycle event 是否触发；不满足实时状态门槛时自动降级 launcher，Pet 不显示推断状态。

### M6：Reasonix

- ACP v1 client。
- lifecycle hook bridge。
- CLI/Desktop launcher。

验收：managed session 的 tool/plan/permission 全链路可映射并驱动 Pet；Attached 模式不伪造等待确认；ACP 异常退出可回收。

## 5. 可行性验证结果

验证机器日期：2026-08-10。

| 项目 | 本机版本/证据 | 结果 |
|---|---|---|
| Codex | `codex-cli 0.139.0` | 已安装 |
| Codex App Server | 可生成 316 个 schema 文件；含 `thread/list`、`thread/started`、`turn/started`、`account/read`、`account/rateLimits/read` | 通过 |
| Codex 多 home | 两个临时 `CODEX_HOME` 分别固定 file credential store 并执行 `codex login status`，均只看到各自未登录状态 | 隔离机制通过；真实双登录需人工验收 |
| Hermes | `v0.20.0`；CLI 暴露 ACP、hooks、sessions、status、usage 等能力 | 通过 |
| Hermes Pet | 官方 Petdex 可响应 CLI/TUI/Desktop 活动；hooks 含 approval 与完成/中断结果 | 通过 |
| Claude Code | `2.1.226`；`claude agents --json` 为官方脚本接口 | 通过 |
| Claude Code Pet hooks | 官方 hooks 覆盖 session、tool、permission、failure、stop/task completed | CLI 通过 |
| Claude Desktop | `/Applications/Claude.app` 存在；官方提供 `claude://code/new` | launcher 通过；完整观测待版本矩阵 |
| Reasonix | `v1.21.5`；`reasonix acp --help` 暴露 workspace/profile/model 等参数 | 通过 |
| Reasonix Pet events | ACP 可提供 tool/plan/permission；Attached hooks 覆盖 prompt/tool/stop | Managed 通过；Attached approval 待验证 |
| Reasonix Desktop | `/Applications/Reasonix.app` 存在 | 发现通过 |
| DeepSeek | 官方 `GET /user/balance` schema 返回 CNY/USD、total/granted/topped-up | 协议通过；未使用真实 Key 发请求 |
| Swift 领域模型 | 多账号复合主键、surface 分离、DeepSeek account scope 单测 | 通过（见测试结果） |

可重复运行：

```bash
cd app/Codexling
sh scripts/probe_multi_agent_capabilities.sh
swift test
```

## 6. Go / No-Go

结论：**Go**，可按 M0 → M1 → M2 开始开发。

进入 M1 前唯一需要保留的技术约束是：Codex App Server 仍标 experimental，所以必须生成/检查协议能力，不能只按 Codex 版本号硬编码。进入 M5 前必须完成 Claude Code Desktop hooks 的真实版本矩阵验证；在此之前它只作为 launcher，不影响整体首版成立。

## 7. 参考依据

- [OpenAI Codex Authentication](https://developers.openai.com/codex/auth)：`CODEX_HOME` 下的凭证存储与官方 login/logout 流程。
- [OpenAI Codex Configuration Reference](https://developers.openai.com/codex/config-reference)：profile 与 `CODEX_HOME` 配置边界。
- [OpenAI Codex Hooks](https://learn.chatgpt.com/docs/hooks)：session、tool、permission、stop 等 lifecycle events。
- [OpenAI Codex Pets](https://learn.chatgpt.com/docs/pets)：官方 Pet 状态、仲裁顺序和 custom Pet 边界。
- [Anthropic Claude Code CLI Reference](https://code.claude.com/docs/en/cli-usage)：`claude agents --json`、auth status、stream-json。
- [Anthropic Claude Code Hooks](https://code.claude.com/docs/en/hooks)：session、tool、permission、failure 和 task lifecycle。
- [Anthropic Claude Desktop deep links](https://support.claude.com/en/articles/14729294-open-claude-desktop-with-a-link)：`claude://code/new`。
- [NousResearch Hermes programmatic integration](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/developer-guide/programmatic-integration.md) 与 [Hermes Hooks](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/hooks.md)。
- [Hermes Petdex CLI](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/reference/cli-commands.md)：跨 CLI/TUI/Desktop 的一方 Pet。
- [Reasonix 官方 ACP 文档](https://reasonix.io/docs/)与 [Reasonix hooks](https://github.com/esengine/DeepSeek-Reasonix)。
- [DeepSeek Get User Balance API](https://api-docs.deepseek.com/api/get-user-balance/)。
