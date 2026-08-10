# Codexling 多 Agent 产品与技术方案

> 方案版本：v1  
> 日期：2026-07-29  
> 依据：[多 Agent、Pet、登录与额度能力调研](agent-pet-auth-quota-research.md)  
> 目标：将当前仅支持 Codex 的菜单栏 companion，演进为同时支持国内外 Agent、订阅额度和第三方 API Key 预算的本地控制面。

> **优先级更新（2026-08-10）：** 后续首批开发顺序已调整为 Codex、Hermes、Claude Code CLI、Claude Code Desktop、Reasonix；多账号优先支持多 Codex 与多个 DeepSeek 官方 API Key。新的范围、里程碑和验证结论以[优先开发方案](prioritized-agent-account-development-plan.md)为准。本文其余通用架构、隐私和安全原则继续有效。

## 1. 方案摘要

Codexling 下一阶段不做“另一个聊天客户端”，而做四件事：

1. 统一显示多个 Coding Agent 的运行状态。
2. 用同一套 Pet 动画表达不同 Agent 的工作生命周期。
3. 委托官方 CLI/SDK 完成登录，并显示连接状态。
4. 将 Agent 订阅额度与 BYOK Provider 余额、消费、限流统一呈现。

整体采用四层适配架构：

```text
Agent Runtime     身份连接             额度/账单              Pet
────────────────────────────────────────────────────────────────────
AgentAdapter      IdentityAdapter      QuotaAdapter          PetStateMapper
     │                   │                   │                     │
     └─────────────── Unified Local Model / Stores ────────────────┘
                                      │
                       Status Bar / Dashboard / Settings
```

首版保留现有 Codex 功能，并新增：

- Agent：Kimi Code、Qoder、CodeBuddy、Qwen Code、iFlow、Claude Code、GitHub Copilot CLI。
- API Provider：DeepSeek、Moonshot/Kimi API、SiliconFlow、OpenRouter。
- 管理型额度接口先预留结构，不在首版要求用户提供 OpenAI/Anthropic/Mistral/xAI Admin Key。

首版最重要的产品约束：

- 不复制第三方 OAuth token。
- 不读取浏览器 Cookie。
- 不将会话 token 数冒充账户余额。
- 不通过网页抓取实现“稳定额度”。
- 不为了 Pet 读取或上传 prompt、response、命令参数。
- 外部 Agent 适配失败不能影响 Codex 和菜单栏主进程。

## 2. 产品定位

### 2.1 一句话定位

> Codexling 是 macOS 菜单栏里的多 Agent 本地控制面：知道谁在工作、谁在等你、预算还剩多少，并让一个 Pet 陪你完成整个开发过程。

### 2.2 目标用户

- 同时使用 Codex、Claude Code、Kimi、Qoder、Qwen 等多个 Agent 的开发者。
- 在不同 Agent 中复用 DeepSeek、Moonshot、OpenRouter 等 API Key 的用户。
- 希望快速看到任务状态、等待确认和额度健康度，而不想频繁切换窗口的用户。
- 重视本地隐私、不接受账号密码或对话内容上传的用户。

### 2.3 非目标

首版不提供：

- 通用聊天窗口或代码编辑器。
- 跨设备同步 Agent 会话。
- 代替 Agent 官方账号系统。
- 云端托管用户 API Key。
- 自动充值、购买套餐、修改组织限额。
- 抓取厂商网页或模拟浏览器操作。
- 统一结算不同 Provider 的财务账单。

## 3. 产品信息架构

### 3.1 四类对象

| 对象 | 示例 | 由谁提供 |
|---|---|---|
| Agent | Codex、Kimi Code、Qoder | Agent runtime adapter |
| 身份连接 | Codex ChatGPT 登录、Qoder CLI 会话 | Identity adapter |
| 订阅 | Codex 周额度、Kimi Code 5 小时额度 | Subscription quota adapter |
| API Provider | DeepSeek、OpenRouter | Provider quota adapter |

一个 Agent 可以关联多个 Provider，一个 Provider 也可被多个 Agent 使用：

```text
Qwen Code ─┬─ DeepSeek API
           └─ OpenRouter

OpenCode ──── DeepSeek API

Kimi Code ─── Kimi Code 会员
              ≠
Moonshot API Key ─ Moonshot API 余额
```

### 3.2 主窗口

主窗口从当前的单 Codex dashboard 演进为三块：

```text
┌──────────────────────────────────────────────────────┐
│ Codexling                           全部正常   设置 ⚙ │
├──────────────────────────────────────────────────────┤
│ Agents                                                │
│ ● Codex       工作中    修复登录流程          2 tasks │
│ ● Kimi Code   待确认    是否执行测试？                │
│ ○ Qoder       空闲                              已连接 │
├──────────────────────────────────────────────────────┤
│ Pet                           当前跟随：Kimi Code      │
│ [动画]                        等待你确认               │
├──────────────────────────────────────────────────────┤
│ Budget                                                │
│ Codex       周额度 77%       5h 42%                   │
│ DeepSeek    ¥42.80 可用      Official API             │
│ OpenRouter  $8.20 remaining  本月已用 $11.80          │
└──────────────────────────────────────────────────────┘
```

交互规则：

- 点击 Agent 行打开详情；有官方客户端或会话 URL 时提供“打开”。
- `waitingForUser` 始终置顶并高亮。
- Pet 默认跟随当前优先级最高的活跃 Agent。
- 用户可以固定 Pet 跟随某个 Agent。
- 额度卡明确显示 scope 和数据来源。
- 没有机器接口时只显示“打开官方 Usage”，不显示伪造的剩余额度。

### 3.3 状态栏

状态栏继续保持紧凑，不直接罗列所有 Agent。

聚合策略：

1. 等待用户
2. 执行中
3. 检查中
4. 思考中
5. 失败/中止
6. 刚完成
7. 空闲

示例：

```text
● Kimi 待确认 · Codex 2 个任务
● 3 个 Agent 工作中 · 周 77%
○ DeepSeek ¥42.80
```

规则：

- 有活跃任务时优先展示 Agent 活动。
- 无活跃任务时展示用户固定的主额度。
- 主额度可以是 Agent 订阅或 API Provider 余额。
- 多个 Agent 同优先级时，最近更新者作为 Pet 和状态栏主对象。
- hover 卡片展示最多 3 个活跃 Agent，不把状态栏胶囊无限拉长。

### 3.4 设置页

设置页调整为：

```text
General
Agents
Subscriptions
API Providers
Pet
Privacy & Data
Advanced
```

其中：

- `Agents`：发现、启用、连接方式、状态来源、打开官方客户端。
- `Subscriptions`：各 Agent 订阅额度及来源。
- `API Providers`：添加 Key、验证、余额、限流、移除。
- `Pet`：Pet 选择、跟随策略、Codex 同步。
- `Privacy & Data`：每个 adapter 读取什么、缓存什么、清除数据。
- `Advanced`：hooks 安装、bridge 状态、诊断导出。

## 4. 会话接入模式

不同协议能观察的会话范围不同，产品必须明确区分。

### 4.1 Managed Session

由 Codexling 启动的会话。

技术来源：

- ACP
- Agent SDK
- headless JSON/stream-json
- 本地 REST/WebSocket server

能力：

- 完整生命周期
- 当前工具类型
- 等待确认
- 完成/失败
- session ID
- 可能包含 token/cost

适合：

- Kimi Code ACP/Web
- Qoder ACP
- CodeBuddy ACP/headless
- Claude Agent SDK

限制：Codexling 只能完整观察自己启动的这次会话，不能自动接管用户在其他终端已启动的 ACP 进程。

### 4.2 Attached Session

用户在终端或 IDE 自己启动，Codexling 通过官方 hooks/telemetry 观察。

能力取决于厂商：

- session start/end
- tool start/end
- stop
- waiting
- error

适合：

- Qoder hooks
- CodeBuddy hooks
- Qwen Code hooks
- iFlow hooks
- Claude Code hooks
- GitHub Copilot hooks
- Gemini CLI telemetry/hooks

需要用户在设置页明确点击“安装集成”。Codexling 只修改对应的 hooks 配置，不改模型、账号、权限或 prompt 设置。

### 4.3 Observed Local Session

通过只读本地状态文件观察。

当前实例：

- Codex `state_5.sqlite`
- Codex rollout JSONL

该方式只用于有明确隐私边界、格式可探测、失败可降级的产品。不得把未知本地数据库作为默认接入方式。

### 4.4 Launcher Only

没有公开状态接口的产品：

- Cursor
- TRAE
- 通义灵码
- 百度 Comate

首版只提供：

- 是否安装
- 打开 App
- 打开官方 Usage/账号页
- 用户手工绑定 Provider

UI 标记为“仅启动”，不显示虚假的实时任务状态。

## 5. 首版范围

### 5.1 Agent 能力矩阵

| Agent | 首版模式 | 登录 | 活动 | 订阅额度 | Pet |
|---|---|---|---|---|---|
| Codex | Observed Local | 保留当前 PKCE | 完整保留 | 保留当前能力 | 原生协议 |
| Kimi Code | Managed + 可选 CLI 探测 | 委托 `kimi login` | ACP/Web | `/usage` 仅实验解析 | 统一映射 |
| Qoder | Managed + Attached | `qodercliAuth()`/PAT | ACP + hooks | 官方 Usage 深链 | 统一映射 |
| CodeBuddy | Attached，Managed 实验 | 复用 CLI/API Key | hooks/stream-json | `/cost`、`/stats`；账号额度深链 | 统一映射 |
| Qwen Code | Attached | 委托 CLI/API Key | hooks | 本地 stats；计划页面深链 | 统一映射 |
| iFlow | Attached | 委托 CLI/API Key | hooks | `/stats`；官方页面深链 | 统一映射 |
| Claude Code | Attached | 委托 CLI；SDK 模式用 API Key | hooks | session cost；订阅深链 | 统一映射 |
| GitHub Copilot CLI | Attached | 委托 device flow/`gh` | hooks | 个人深链；组织 metrics 后置 | 统一映射 |

说明：

- “委托 CLI”意味着 Codexling 启动官方命令并展示进度，不读取 CLI 保存的 token。
- 交互式额度文本解析均置于 `experimental` feature flag 下。
- 用户没有安装相应 CLI 时，显示安装说明，不自动下载执行文件。

### 5.2 API Provider 能力矩阵

| Provider | 首版接口 | 展示内容 | 凭证类型 |
|---|---|---|---|
| DeepSeek | `GET /user/balance` | 总余额、赠送、充值、币种、可用状态 | 普通推理 Key |
| Moonshot | `GET /v1/users/me/balance` | available、cash、voucher | 普通推理 Key |
| SiliconFlow | `GET /v1/user/info` | balance、charge、total、状态 | 普通推理 Key |
| OpenRouter | `GET /api/v1/key` | daily/weekly/monthly usage、limit、remaining、reset | 普通推理 Key |

首版不做：

- OpenRouter 组织 credits Management Key。
- OpenAI、Anthropic、Mistral、xAI 管理 Key。
- 阿里云、Google Cloud、腾讯云、火山、百度云 IAM。
- 自动充值或修改 spend limit。

这些接口的数据模型在首版预留，第二阶段再开放连接 UI。

## 6. 统一领域模型

### 6.1 标识

```swift
struct AgentID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String
}

struct ProviderID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String
}

struct ConnectionID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: UUID
}
```

内置 ID 使用稳定值：

```text
agent.codex
agent.kimi-code
agent.qoder
agent.codebuddy
agent.qwen-code
agent.iflow
agent.claude-code
agent.github-copilot

provider.deepseek
provider.moonshot
provider.siliconflow
provider.openrouter
```

### 6.2 Agent 能力描述

```swift
struct AgentCapabilities: OptionSet, Sendable {
    let rawValue: Int

    static let discovery       = Self(rawValue: 1 << 0)
    static let launch          = Self(rawValue: 1 << 1)
    static let managedSessions = Self(rawValue: 1 << 2)
    static let attachedEvents  = Self(rawValue: 1 << 3)
    static let login           = Self(rawValue: 1 << 4)
    static let subscription    = Self(rawValue: 1 << 5)
    static let openOfficialUI  = Self(rawValue: 1 << 6)
}
```

### 6.3 统一活动状态

现有 `CodexActivityState` 演进为：

```swift
enum AgentActivityState: String, Codable, Sendable {
    case unavailable
    case offline
    case idle
    case thinking
    case reading
    case executing
    case reviewing
    case waitingForUser
    case rateLimited
    case completed
    case failed
    case interrupted
}
```

Pet 映射：

| Agent 状态 | Pet v2 动画 |
|---|---|
| unavailable / offline / idle | idle |
| thinking / reading / executing | running |
| reviewing | review |
| waitingForUser / rateLimited | waiting |
| completed | waving |
| failed / interrupted | failed |

新增状态不会要求修改 spritesheet 协议。

### 6.4 Session 快照

```swift
struct AgentSessionSnapshot: Identifiable, Codable, Sendable {
    let id: String
    let agentID: AgentID
    let mode: SessionObservationMode
    var state: AgentActivityState
    var title: String?
    var safeDetail: String?
    var workspaceName: String?
    var gitBranch: String?
    var model: String?
    var startedAt: Date?
    var updatedAt: Date
}
```

`safeDetail` 只能来自：

- 厂商提供的状态说明。
- 用户已经可见的 commentary/status。
- Codexling 自己生成的通用文案。

不得存原始 prompt、tool input 或 command。

### 6.5 额度快照

```swift
struct QuotaSnapshot: Identifiable, Codable, Sendable {
    let id: String
    let owner: QuotaOwner
    let scope: QuotaScope
    var balances: [BalanceComponent]
    var usage: UsageAggregate?
    var rateLimits: [RateLimitWindow]
    var billingPeriod: DateInterval?
    var fetchedAt: Date
    var freshness: SnapshotFreshness
    var source: QuotaSource
    var reliability: Reliability
}
```

```swift
enum QuotaScope: String, Codable, Sendable {
    case session
    case apiKey
    case project
    case organization
    case subscription
}

enum QuotaSource: String, Codable, Sendable {
    case officialAPI
    case officialSDK
    case officialCLI
    case responseHeader
    case dashboard
    case localEstimate
}

enum Reliability: String, Codable, Sendable {
    case officialStructured = "A"
    case officialInteractive = "B"
    case dashboardOnly = "C"
    case privateOrInferred = "D"
}
```

## 7. 适配器协议

### 7.1 AgentAdapter

```swift
protocol AgentAdapter: Sendable {
    var descriptor: AgentDescriptor { get }

    func discover() async -> AgentInstallation?
    func currentConnectionState() async -> AgentConnectionState
    func sessions() -> AsyncStream<AgentSessionEvent>
    func launch(_ request: AgentLaunchRequest) async throws -> ManagedSessionHandle
    func openOfficialApp() async
}
```

不支持的方法由 capability 决定，调用方不得靠捕获 `notImplemented` 判断能力。

### 7.2 IdentityAdapter

```swift
protocol IdentityAdapter: Sendable {
    var agentID: AgentID { get }
    func connectionState() async -> AgentConnectionState
    func beginOfficialLogin() async throws
    func disconnectLocalConnection() async throws
}
```

`disconnectLocalConnection()` 默认只断开 Codexling 自己保存的连接。对于复用官方 CLI 会话的 Agent，不应擅自让官方 CLI 全局 logout。

### 7.3 QuotaAdapter

```swift
protocol QuotaAdapter: Sendable {
    var descriptor: QuotaProviderDescriptor { get }
    func validateCredential(_ credential: CredentialHandle) async throws
    func fetchSnapshot(using credential: CredentialHandle) async throws -> QuotaSnapshot
    func officialUsageURL() -> URL?
}
```

Provider adapter 只能取得 `CredentialHandle`，不能从 UI model 取得明文 Key。

### 7.4 PetStateMapper

```swift
protocol PetStateMapper: Sendable {
    func map(_ event: AgentSessionEvent) -> AgentActivityState?
}
```

默认 mapper 处理标准事件；厂商专有事件在各自 adapter 内转换。

## 8. 本地事件 Bridge

### 8.1 目的

Qoder、CodeBuddy、Qwen、iFlow、Claude、Copilot 等产品的 hooks 需要把事件安全送入 Codexling。

新增随 App 打包的 helper：

```text
Codexling.app/Contents/Helpers/codexling-agent-bridge
```

用户点击“安装集成”后，Codexling 将该 helper 的绝对路径写入厂商官方 hooks 配置。

### 8.2 传输

首选 Unix domain socket：

```text
~/Library/Application Support/Codexling/bridge/events.sock
```

要求：

- 目录权限 `0700`
- socket 仅当前用户可访问
- 单事件大小上限 64 KB
- 只接受已注册 Agent ID
- JSON schema 版本化
- App 不运行时 helper 快速退出，不阻塞 Agent
- 事件处理超时不超过 100 ms

事件示例：

```json
{
  "schemaVersion": 1,
  "agentID": "agent.qwen-code",
  "sessionID": "local-session-id",
  "event": "tool.started",
  "toolCategory": "shell",
  "timestamp": "2026-07-29T12:00:00Z"
}
```

helper 在发送前丢弃：

- prompt
- response
- tool arguments
- command text
- environment
- file contents
- secrets

### 8.3 Hooks 配置管理

- 安装前生成 diff 并说明将修改的文件。
- 只添加带 `codexling` ID 的配置块。
- 保存原配置备份。
- 卸载只删除 Codexling 自己的配置块。
- 如果用户随后修改过同一块，停止自动删除并提示人工处理。
- 每个 Agent 的 hooks schema 与已验证版本写进 adapter descriptor。

## 9. 凭证与安全

### 9.1 凭证分级

| 类型 | 示例 | 风险 |
|---|---|---|
| Inference Key | DeepSeek、Moonshot API Key | 可调用模型和消耗余额 |
| PAT | Qoder PAT、GitHub PAT | 取决于 scope |
| Admin Key | OpenAI、Anthropic、Mistral Admin | 可见组织用量 |
| Management Key | OpenRouter、xAI Management | 可见账单/组织资源 |
| Cloud IAM | RAM AK/SK、Google OAuth | 高权限云账户 |

首版 UI 只开放 Inference Key 和必要 PAT。其他类型数据模型预留但隐藏。

### 9.2 Keychain

新增凭证必须使用 macOS Keychain：

```text
service: com.qiizo.Codexling.credentials
account: <connection-id>
label: Codexling · DeepSeek · Personal
```

Keychain item 只允许当前用户、当前 App 访问。普通配置文件仅保存：

- connection ID
- provider ID
- 显示名称
- Key 后四位
- 创建/验证时间
- capability

当前 Codex OAuth token 暂时保留现有 `0600` 文件实现，避免在多 Agent 重构中同时改变已验证登录流程。后续单独迁移 Keychain，并提供回滚测试。

### 9.3 网络安全

- Provider base URL 使用内置 HTTPS allowlist。
- 首版不允许用户为内置 Provider 修改 host。
- OpenAI-compatible 自定义 endpoint 后置，并明确 SSRF/本地网络风险。
- 重定向默认禁止；如官方 endpoint 必须重定向，只允许同厂商 allowlist。
- 错误日志不输出 Authorization header、query secret 或 response 原文。
- 支持 Key 撤销和“清除所有本地连接”。

## 10. Store 与运行时

### 10.1 新 Store

```text
AppDelegate
├── AgentRegistry
│   ├── AgentConnectionStore
│   ├── AgentSessionStore
│   └── AgentBridgeService
├── QuotaRegistry
│   ├── ProviderConnectionStore
│   ├── QuotaSnapshotStore
│   └── QuotaRefreshScheduler
├── PetFrameStore
├── CompanionStatsStore
├── AppSettingsStore
├── StatusBarController
└── DetachedWindowController
```

### 10.2 AgentRegistry

职责：

- 注册内置 adapters。
- 并行探测安装情况。
- 启停各 adapter。
- 聚合 session events。
- 计算当前最高优先级活动。
- adapter 崩溃/超时隔离。

单个 adapter 连续失败三次后进入 degraded 状态，并使用指数退避：

```text
30s → 1m → 2m → 5m → 15m
```

用户手动刷新可绕过一次退避。

### 10.3 QuotaRefreshScheduler

刷新策略：

| 来源 | 默认 |
|---|---|
| 普通余额 API | 打开窗口时 + 每 10 分钟 |
| Agent 订阅结构化 API | 每 5 分钟 |
| Admin usage | 每 30 分钟 |
| response headers | 随实际请求更新 |
| CLI 文本 | 仅手动或每 15 分钟 |
| dashboard only | 不刷新 |

限制：

- 同一 Provider 只允许一个 in-flight refresh。
- HTTP 429 尊重 `Retry-After`。
- 401/403 标记 credential invalid，不无限重试。
- 网络失败保留上次成功快照。
- 快照显示 `fresh/stale/expired`。
- App 唤醒后加入 0–10 秒随机抖动，避免所有 Provider 同时请求。

### 10.4 缓存

```text
~/Library/Application Support/Codexling/
├── connections.json                 # 无明文凭证
├── agent-snapshots.json
├── quota-snapshots/
│   ├── provider.deepseek.json
│   └── provider.openrouter.json
├── bridge/
│   └── events.sock
└── adapter-diagnostics/
```

快照使用原子写入。诊断默认只保存最近 7 天，且不包含内容字段。

## 11. 当前代码迁移

### 11.1 保留

以下组件直接复用：

- `PetFrameStore`
- `PetAnimationPlayer`
- `CodexPetCatalog`
- `CompanionStatsStore`
- `StatusBarController` 的自绘、hover、wave、ripple
- `DetachedWindowController`
- 当前 Codex parser 与 OAuth service
- `UsageSnapshotCache` 的保留上次成功语义

### 11.2 演进

| 当前类型 | 目标 |
|---|---|
| `CodexActivityState` | `AgentActivityState` |
| `CodexTaskActivity` | `AgentSessionSnapshot` |
| `CodexActivityStore` | 先实现 `CodexAgentAdapter`，再由 `AgentSessionStore` 聚合 |
| `CodexUsageSnapshot` | 保留为 Codex adapter 内部 DTO，转换成通用 `QuotaSnapshot` |
| `UsageSnapshotStore` | 演进为多来源 `QuotaSnapshotStore` |
| `UsageActions` | 拆成 Agent、Connection、Quota、App actions |
| `CodexUsageService` | 继续隔离非公开接口，实现 Codex identity/quota adapter |

### 11.3 兼容迁移顺序

1. 增加通用 model，不改 UI。
2. 用 `CodexAgentAdapter` 包装现有活动实现。
3. 用 `CodexQuotaAdapter` 将当前 snapshot 转为通用 snapshot。
4. UI 切换到 registry/store，但只注册 Codex。
5. 确认视觉和行为与当前版本一致。
6. 再逐个添加 Provider。
7. 最后添加外部 Agent hooks/ACP。

这样任何阶段都能发布，不需要一次性大重写。

## 12. 文件布局建议

```text
Sources/Codexling/
├── Core/
│   ├── AgentModels.swift
│   ├── QuotaModels.swift
│   ├── ConnectionModels.swift
│   └── Reliability.swift
├── Agents/
│   ├── AgentAdapter.swift
│   ├── AgentRegistry.swift
│   ├── Codex/
│   ├── Kimi/
│   ├── Qoder/
│   ├── CodeBuddy/
│   ├── Qwen/
│   ├── IFlow/
│   ├── Claude/
│   └── Copilot/
├── Providers/
│   ├── QuotaAdapter.swift
│   ├── QuotaRegistry.swift
│   ├── DeepSeek/
│   ├── Moonshot/
│   ├── SiliconFlow/
│   └── OpenRouter/
├── Connections/
│   ├── CredentialStore.swift
│   └── ConnectionStore.swift
├── Bridge/
│   ├── AgentBridgeService.swift
│   └── HookConfigurationManager.swift
├── Pets/
├── Stores/
└── Views/
```

首个重构 PR 不强制移动所有现有文件。先添加协议和 adapter wrapper，确认稳定后再机械整理目录。

## 13. 分阶段交付

### Milestone A：通用内核，Codex 行为不变

交付：

- 通用 Agent/Quota/Connection models。
- AgentRegistry、QuotaRegistry。
- Codex adapter wrapper。
- 多来源 snapshot cache。
- 当前 UI 使用通用 store。

验收：

- Codex 登录、额度、Pet、状态栏、hover、dashboard 无回归。
- adapter 失败不会崩溃 App。
- cache 可从旧格式迁移或安全回退。

### Milestone B：BYOK Provider

交付：

- Keychain credential store。
- DeepSeek、Moonshot、SiliconFlow、OpenRouter adapters。
- API Providers 设置页。
- 余额、用量、限流卡。
- 主额度固定选择。

验收：

- Key 添加后能验证、查询、刷新、删除。
- 401、403、429、超时、离线、畸形 JSON 均正确降级。
- 日志和缓存中搜不到完整 Key。
- Moonshot API 余额不会显示成 Kimi Code 会员额度。

### Milestone C：Hooks Bridge

交付：

- `codexling-agent-bridge` helper。
- Unix socket event service。
- hooks 安装、预览、卸载。
- Qwen Code、iFlow、CodeBuddy adapters。
- 多 Agent 聚合 Pet 和状态栏。

验收：

- 外部终端启动的受支持 Agent 能更新 Pet。
- App 不运行时不影响 Agent。
- 原配置可恢复。
- 事件负载中不保留 prompt/tool args。

### Milestone D：ACP 与更多 Agent

交付：

- Kimi Code、Qoder managed sessions。
- Claude Code、Copilot hooks。
- Agent 详情与 launcher。
- 实验性 CLI 订阅统计。

验收：

- Managed 与 Attached 会话在 UI 明确区分。
- ACP 子进程退出、hang、协议错误可回收。
- 登录委托不读取厂商 token 文件。

### Milestone E：组织管理额度

候选：

- OpenAI Admin Usage/Costs
- Anthropic Admin Usage
- Mistral Admin Usage/Limits
- xAI Management Billing
- OpenRouter Management Credits

需要独立安全评审后再开放。

## 14. 测试方案

### 14.1 单元测试

- 每个 adapter 的成功、缺字段、错误 payload fixture。
- 货币精度与多币种。
- rate-limit window 与 reset 解析。
- Agent event → activity state → Pet state 映射。
- 多 Agent 优先级与最近更新时间。
- stale/expired 判定。
- connection scope 和 source 标签。
- 旧 Codex snapshot 转换。

### 14.2 集成测试

- 使用本地 mock HTTP server，不调用真实付费 API。
- helper → socket → store 全链路。
- hooks 配置安装/卸载/冲突。
- ACP 子进程启动、stderr、取消、异常退出。
- Keychain 增删改查和授权失败。
- App sleep/wake 后刷新抖动与退避。

### 14.3 隐私测试

测试 fixture 主动包含：

- 假 API Key
- prompt
- shell command
- env token
- 文件内容

验证这些内容不会进入：

- snapshot
- cache
- diagnostics
- UI
- crash metadata

### 14.4 UI 验收

- 0、1、3、8 个 Agent。
- 无额度、单额度、多 Provider。
- 中英文长名称。
- 离线、stale、无权限、等待确认、429。
- 横向/纵向 dashboard。
- VoiceOver 和减少动态效果。

## 15. 发布与灰度

每个 adapter 均有本地 feature flag：

```text
codexling.adapters.<id>.enabled
codexling.adapters.<id>.experimental
```

发布策略：

1. 通用内核只注册 Codex。
2. Provider adapters 标 beta。
3. hooks 安装默认关闭，由用户显式开启。
4. CLI 文本解析标 experimental。
5. Admin/Management Key UI 默认不出现。

诊断页显示：

- adapter 版本
- capability
- 安装路径
- 最近成功时间
- 最近错误类别
- 已验证 CLI 版本范围
- 数据来源与 scope

不显示 secret 或原始事件。

## 16. 成功指标

不依赖云端埋点也可在本地判断：

- 已连接 Agent 数。
- 已连接 Provider 数。
- 每周被 Pet 呈现的有效工作时长。
- 等待确认事件从出现到用户打开 Agent 的本地耗时。
- adapter 刷新成功率。
- stale snapshot 比例。
- hooks 安装后有效事件比例。

如果未来加入匿名遥测，必须单独 opt-in，并只发送聚合计数。

## 17. 关键决策

| 决策 | 选择 |
|---|---|
| 是否把所有产品叫 Agent | UI 可以；底层分 Agent 与 Provider |
| 是否复用第三方 OAuth | 不复制 token，只委托官方流程 |
| 是否把 API Key 当登录 | UI 称“连接 Provider”，不称账号登录 |
| 是否抓网页额度 | 不抓；只深链 |
| 是否统一 Pet 素材格式 | 继续使用 Codex sprite v2 |
| 是否为每个 Agent做独立 Pet | 不做；Pet 与 Agent 解耦 |
| 多 Agent 状态栏显示谁 | 等待优先，其次活动优先级与最近更新 |
| 首期是否支持云 IAM | 不支持 |
| 新凭证存哪里 | macOS Keychain |
| 当前 Codex 私有 API 怎么办 | 保留并隔离，标为 D 级来源 |
| 首个研发目标 | 先抽象而不改变 Codex 行为，再接 BYOK |

## 18. 首批研发任务拆分

### PR 1：Domain Models

- AgentID、ProviderID、ConnectionID。
- AgentActivityState。
- QuotaSnapshot、QuotaScope、QuotaSource、Reliability。
- 现有 Codex model 转换测试。

### PR 2：Registries

- AgentAdapter、QuotaAdapter。
- AgentRegistry、QuotaRegistry。
- Codex wrapper。
- 保持现有 UI 行为。

### PR 3：Credential Store

- Keychain CRUD。
- Connection metadata。
- secret redaction。
- 测试与清除流程。

### PR 4：Provider MVP

- DeepSeek。
- Moonshot。
- SiliconFlow。
- OpenRouter。
- mock fixtures。

### PR 5：Provider UI

- Connections/API Providers 设置。
- Budget cards。
- 主额度选择。
- freshness/source/scope 标签。

### PR 6：Bridge

- helper target。
- Unix socket。
- schema。
- privacy filter。

### PR 7：首批 Attached Agents

- Qwen Code。
- iFlow。
- CodeBuddy。
- hooks 配置管理。

### PR 8：Managed Agents

- Kimi Code ACP/Web。
- Qoder ACP。
- 子进程和会话生命周期。

## 19. 首版完成定义

满足以下条件才算多 Agent 首版完成：

- 现有 Codex 全部能力无回归。
- 至少 3 个外部 Agent 可通过官方 hooks/ACP 提供实时状态。
- 至少 4 个 Provider 可通过普通 Key 查询官方余额或用量。
- Pet 能在多个 Agent 之间按统一优先级切换。
- 状态栏能正确聚合等待、执行和额度健康度。
- 所有新增明文凭证只存在于 Keychain 和请求内存。
- 每个额度都显示 source、scope、更新时间。
- 无公开 API 的产品只提供深链，不伪造额度。
- 可一键卸载 Codexling 写入的 hooks。
- 断网、凭证失效、CLI 升级和 adapter 故障不会影响 App 主功能。
