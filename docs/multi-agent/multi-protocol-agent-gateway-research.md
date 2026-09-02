# Multi-Protocol Agent Gateway 技术调研与架构设计基础

> 文档状态：Architecture Research / Draft for Review  
> 调研基线：2026-08-29  
> 目标平台：macOS（SwiftUI）+ 本地 Rust Gateway  
> 项目暂定定位：Local LLM Gateway + Agent Manager

## 0. 执行摘要

本项目不应被定义为“Gemini 反代”或“OpenAI-compatible Proxy”，而应被定义为：

> 一个面向 Coding Agent 的本地多协议模型网关，同时提供 Agent 检测、配置、启动、诊断、模型路由、密钥隔离、调用观测与兼容性管理。

核心判断如下：

1. Coding Agent、模型 API 协议和模型 Provider 是三个不同层次；混为一层会迅速形成 `输入协议数 × Provider 数` 的转换爆炸。
2. `/v1/chat/completions` 仍是覆盖面最广的最低公分母，但已经不足以代表完整的 “OpenAI compatibility”。Codex 当前自定义 Provider 以 Responses wire API 为核心；Claude Code 主要消费 Anthropic Messages；Gemini 正在从 `generateContent` 向 Interactions 的 step/event 模型演进。
3. 网关内部必须使用 Canonical IR，但不能追求“彻底抹平 Provider 差异”。标准字段与 `ProviderOpaque` / `ProviderState` 必须并存，以保留 reasoning state、thought signature、cache control、beta header、原始 finish metadata 等不可逆信息。
4. Streaming、Tool Calling、Capability Negotiation 和状态连续性不是附加功能，而是 Coding Agent 能否真正工作的基础。
5. Protocol Adapter 负责 HTTP/JSON/SSE 方言；Provider Adapter 负责供应商能力与鉴权；Agent Adapter 只负责 Agent 的发现、配置、恢复、启动和诊断。三者必须分层。
6. V1 应追求小而闭环：OpenAI Chat + OpenAI Responses + Anthropic Messages 三个入口，Gemini 与至少一个 OpenAI-compatible 出口，真实 SSE、工具调用、模型别名、Keychain 和三类 Agent 的一键配置。
7. ACP 与 MCP 都值得支持，但它们不替代模型推理协议：MCP 连接 Agent/Host 与工具、资源和提示；ACP 连接编辑器/客户端与完整 Agent；OpenAI/Anthropic/Gemini API 连接 Agent 与模型。

### 0.1 推荐的系统边界

```text
┌───────────────────────────────────────────────────────────────┐
│ Agent / Harness                                               │
│ Codex · Claude Code · OpenCode · Pi · Hermes · Cline · ...   │
└───────────────────────┬───────────────────────────────────────┘
                        │ LLM API protocol
                        ▼
┌───────────────────────────────────────────────────────────────┐
│ Local Multi-Protocol Gateway                                  │
│                                                               │
│ Ingress Protocol Adapters                                     │
│ OpenAI Chat · OpenAI Responses · Anthropic Messages · Gemini │
│                         │                                     │
│                    Canonical IR                               │
│                         │                                     │
│ Routing · Capability · Alias · Policy · Observability         │
│                         │                                     │
│ Provider Adapters                                             │
│ OpenAI · Gemini · Anthropic · DeepSeek · OpenRouter · Local  │
└───────────────────────┬───────────────────────────────────────┘
                        │ Provider API
                        ▼
┌───────────────────────────────────────────────────────────────┐
│ Model Providers                                               │
└───────────────────────────────────────────────────────────────┘

Parallel integration planes:

Editor / Client  ── ACP ── Agent
Agent / Host      ── MCP ── Tools · Resources · Prompts
Agent / Host      ── Hook ── Local Activity (SQLite / UNIX Socket)
Agent             ── LLM API ── Local Multi-Protocol Gateway
```

## 1. 项目定位、目标与非目标

### 1.1 产品定位

项目是一个运行在用户 Mac 上的本地 Agent Gateway：

- 对 Agent 暴露稳定的 localhost API；
- 对上游 Provider 隐藏真实 API Key；
- 将不同 Agent 使用的模型协议转换为统一 IR，再转换到目标 Provider；
- 通过模型别名和能力约束实现路由、fallback 与平滑迁移；
- 通过 SwiftUI 提供启动状态、Agent 配置、模型管理、调用日志、用量和诊断；
- 后续可通过 ACP 将完整 Agent 接入编辑器，通过 MCP 管理工具与上下文。

### 1.2 核心目标

- 覆盖主流 Coding Agent 的真实工具调用链路，而不只保证普通文本对话。
- 在转换时尽量无损地保留多轮推理状态、tool call identity 和 Provider 专属字段。
- 让 Agent 依赖稳定别名，而不是依赖随时间变化的 Provider model ID。
- 将兼容结果显式分为 Native、Compatible、Degraded，避免“能返回文本即兼容”的误导。
- 将本地安全作为默认值：仅监听 loopback、真实密钥进入 Keychain、配置变更可回滚。
- 通过协议 fixture、跨协议 golden test 和 Agent smoke test 建立持续兼容基线。

### 1.3 非目标

- 不把 Google AI Pro、ChatGPT Plus/Pro、Claude Pro/Max 等网页订阅的非公开会话接口包装成公共 API。
- 不抓取浏览器 Cookie，不依赖非公开 endpoint，不规避 Provider 的计费、权限或风控。
- 不承诺任意模型在任意 Agent 上都达到原生体验；能力不足时必须拒绝或明确降级。
- V1 不做云端多租户控制面、团队 RBAC、复杂账单结算或企业级合规平台。
- 不用 MCP 替代推理 API，也不用 ACP 替代模型 Provider Adapter。

## 2. Agent / Protocol / Provider 三层模型

### 2.1 Agent / Harness 层

Agent 负责上下文组装、工作循环、文件与终端工具、权限交互、补丁应用和会话管理。不同 Agent 可能使用同一家模型，但发送完全不同的 wire protocol。

示例：

- Codex：以 OpenAI Responses 风格作为自定义 Provider wire API；
- Claude Code：主要使用 Anthropic Messages，并对 gateway header、token count 和模型发现有额外要求；
- OpenCode、Pi、Crush：内部存在多个 provider package / API dialect；
- Aider、OpenHands：借助 LiteLLM 覆盖大量 Provider；
- Cline、Roo Code、Kilo、Continue：通常可配置 OpenAI-compatible base URL，也有原生 Provider。

### 2.2 Protocol 层

协议层定义请求、响应、流事件、工具调用和状态续接的 wire representation。必须至少区分：

| 协议族 | 典型入口 | 核心抽象 |
|---|---|---|
| OpenAI Chat Completions | `POST /v1/chat/completions` | messages / choices / deltas |
| OpenAI Responses | `POST /v1/responses` | input/output items / semantic events / response state |
| Anthropic Messages | `POST /v1/messages` | content blocks / tool_use / message SSE |
| Gemini Interactions | `POST /v1beta/interactions` | typed steps / interaction state / semantic events |
| Gemini generateContent | `generateContent`, `streamGenerateContent` | contents / parts / candidates |

“OpenAI-compatible”必须带限定词：Chat-compatible、Responses-compatible 或仅 SDK-compatible。一个只实现 Chat Completions 的服务不能被视为完整兼容 Codex 的 Responses wire protocol。

### 2.3 Provider 层

Provider Adapter 处理：

- Provider base URL、鉴权与请求头；
- 模型目录与模型 metadata；
- 原生协议选择；
- 参数映射和能力限制；
- 错误、限流与 usage 归一化；
- Provider 专属状态的保存和回传。

同一 Provider 也可能有多个出口，例如：

```text
Gemini Provider
├── Interactions API                  long-term primary
├── generateContent / streamGenerateContent
└── OpenAI Chat compatibility        bootstrap / lowest friction
```

## 3. 四类核心模型协议

### 3.1 OpenAI Chat Completions

`POST /v1/chat/completions` 仍是生态覆盖最广的入口。请求围绕 `messages`、`tools`、`tool_choice`、`stream` 展开；流式响应通常由 `choices[].delta` 逐块产生。OpenAI 当前 API 仍记录了 developer/user/tool 等消息类型、函数工具、tool choice 和流式输出。[OpenAI Chat Completions API Reference](https://developers.openai.com/api/reference/cli/resources/chat/subresources/completions)

网关至少需要处理：

- `system` 与 `developer` 的优先级和 Provider 降级；
- 多模态 content parts；
- 多个并行 `tool_calls`；
- tool arguments 的增量 JSON；
- `tool_call_id` 与 tool result 的对应；
- `finish_reason`、usage、错误结构；
- `[DONE]` 和客户端断开取消。

优势是生态广、实现简单、适合作为 V1 最低公分母。缺点是它的 message/choice 模型无法天然表达 Responses、Interactions 中更细粒度的 item/step 状态。

### 3.2 OpenAI Responses

Responses 不只是 Chat Completions 的另一个 URL。它以输入/输出 item、response lifecycle 和语义化流事件为中心，能够表达 message、reasoning、function call、function call output 以及 Provider 托管工具。官方接口将创建响应、会话、输入 item、streaming events 等作为独立资源。[OpenAI Responses API Reference](https://developers.openai.com/api/reference/typescript/resources/beta/subresources/responses/methods/create)

关键事件示例：

```text
response.created
response.output_item.added
response.content_part.added
response.output_text.delta
response.function_call_arguments.delta
response.output_item.done
response.completed
response.failed
```

当前 Codex 源码中 `WireApi` 只接受 `responses`；对 `wire_api = "chat"` 会返回已移除错误，因此 Codex 的长期兼容入口必须是真正的 Responses Adapter，而不是假设其仍可使用 Chat wire API。[Codex model-provider-info source](https://github.com/openai/codex/blob/main/codex-rs/model-provider-info/src/lib.rs)；自定义 Provider 的字段可参考 [Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)。

实现要求：

- 不丢失 item ID、call ID、status、sequence 与 response lifecycle；
- 区分 input message、output message、function call 和 function call output；
- 支持有状态续接与无状态全量 history 两种模式；
- 不能把 reasoning 简单混进普通 assistant text；
- 非原生 Provider 必须生成一致、稳定的 Responses SSE 事件序列。

### 3.3 Anthropic Messages

Claude Code 的主要 gateway 入口是 Anthropic Messages。Claude Code 官方 gateway 文档要求至少暴露 `/v1/messages` 与 `/v1/messages/count_tokens`，并正确处理 `anthropic-beta`、`anthropic-version`；还可通过 `/v1/models` 做模型发现。[Claude Code LLM gateway configuration](https://code.claude.com/docs/en/llm-gateway)

Messages 的重要结构包括：

- 顶层 `system` 与 `messages`；
- content blocks：text、image、document、thinking、redacted thinking、tool use、tool result；
- `tool_choice` 与 JSON Schema；
- `cache_control`；
- message/content block 级 SSE；
- thinking signature 和必须原样回传的 opaque data。

Anthropic 的 API 参考明确要求 thinking block 及其 signature 原样、有序回传；redacted thinking 数据也属于不可解释但必须保留的状态。[Anthropic Messages API Reference](https://platform.claude.com/docs/en/api/http/messages/create)

因此 Anthropic Adapter 不能只做字段重命名；它还要维护 header contract、content block 顺序、cache breakpoint、thinking state 和 token counting 行为。

### 3.4 Gemini Native：Interactions 与 generateContent

Gemini 需要同时考虑三条路径：

1. Interactions：面向新 agentic 能力的 typed-step API；
2. `generateContent` / `streamGenerateContent`：仍受支持的传统原生 API；
3. OpenAI Chat compatibility：低成本接入，但不是 1:1 原生能力映射。

Interactions 将 user input、thought、function call、tool result、model output 等表达为有序 step。Google 已将 Interactions 作为 AI Studio / Gemini API 文档的默认路径，同时表示 `generateContent` 在可预见时期仍会受支持；前沿的长运行模型和 Agent 能力会更多进入 Interactions。[Google Interactions API announcement](https://blog.google/innovation-and-ai/technology/developers-tools/interactions-api-general-availability/)

Gemini thought signature 是关键状态。Interactions 有状态模式可由服务端通过 `previous_interaction_id` 管理；无状态模式必须完整重发 thought blocks 和相关 signatures。[Gemini thinking and thought signatures](https://ai.google.dev/gemini-api/docs/thought-signatures)

Google 对 OpenAI SDK compatibility 的定位也很明确：它适合优先统一 schema、且不需要高级 Gemini 能力的接入；OpenAI schema 与 Gemini architecture 并非 1:1，File API、Google Search grounding 等能力可能需要额外适配。[Gemini partner and library integrations](https://ai.google.dev/gemini-api/docs/partner-integration)

推荐策略：

- V1 可使用 Gemini OpenAI-compatible 出口缩短启动时间，但 Canonical IR 与 Provider trait 不得因此绑定 Chat schema；
- V2 增加 generateContent 原生 Adapter；
- V2/V3 将 Interactions 作为 Gemini 的优先原生出口，保留 generateContent 回退；
- `thought` / `signature` / built-in tool state 必须进入 ProviderState，而不是文本化。

## 4. MCP 与 ACP 的边界

### 4.1 MCP：Agent/Host 与工具、资源、提示

MCP 是基于 JSON-RPC 的 host-client-server 协议，核心 primitives 包括 prompts、resources 和 tools，并通过初始化能力协商决定双方可用功能。[MCP architecture](https://modelcontextprotocol.io/specification/2025-06-18/architecture)；[MCP server primitives](https://modelcontextprotocol.io/specification/2025-06-18/server/index)

它解决的是：

```text
Agent / LLM Host ── MCP ── Tool / Data / Context Server
```

它不解决：

```text
Agent ── LLM inference API ── Model Provider
```

网关将来可以作为 MCP Client/Gateway，把 MCP tools 转为 Canonical ToolDefinition 并注入模型请求；但这是一条工具平面，不是模型协议转换平面。

### 4.2 ACP：编辑器/客户端与完整 Agent

Agent Client Protocol 用于连接编辑器或其他客户端与完整 Coding Agent。它基于 JSON-RPC，本地模式通常经 stdio 启动 Agent 子进程，使用通知流式更新 UI，并支持 Agent 向客户端请求工具权限；协议尽量复用 MCP 的 JSON 类型，同时增加 diff 等 Coding UX 表达。[ACP introduction](https://agentclientprotocol.com/get-started/introduction)；[ACP architecture](https://agentclientprotocol.com/get-started/architecture)

它解决的是：

```text
Editor / Client ── ACP ── Coding Agent
```

### 4.3 四种平面的关系

| 平面 | 左端 | 协议 / 机制 | 右端 | 本项目角色 |
|---|---|---|---|---|
| Agent UX | 编辑器/GUI | ACP (JSON-RPC) | 完整 Agent | V3 Agent runtime / editor bridge |
| Tool & Context | Agent/Host | MCP (JSON-RPC) | 工具、资源、提示服务 | V2/V3 tool registry / gateway |
| Agent Activity | Agent 进程 / 本地系统 | SQLite 轮询 / 本地 UNIX Socket Hook | Codexling 客户端底座 | 现有常驻感知底座（与 Gateway 启停完全解耦） |
| Model Inference | Agent | OpenAI/Anthropic/Gemini wire APIs | 本地多协议网关 ── Provider | V1 核心推理、路由与遥测平面 |

结论：MCP、ACP、本地活动感知与模型推理 API 是互补且正交的关系，不应耦合进同一个状态机或 Adapter trait。

### 4.4 双通道感知体系：本地活动感知与模型推理感知

Codexling 客户端在获取 Agent 任务状态与运行数据时，设计了两个**正交独立**的数据通道：

```text
┌──────────────────────────────────────────────────────────────────────────┐
│ 通道一：Agent 本地活动感知 (Activity Plane) - 强生命周期，不依赖网关开关 │
│                                                                          │
│ Codex CLI/Desktop  ── 本地 SQLite / Session Index / Rollout ──┐           │
│ 其他 Agent (Hermes/Claude) ── CLI Hook ── agent-events.sock ───┴─► 任务看板 │
│ (任务标题、Git 分支、思考中/工作中/等待确认、陪伴时长、小宠物动画)        (常驻可用) │
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│ 通道二：模型推理与遥测感知 (Telemetry Plane) - 流量代理，依赖网关 Base URL │
│                                                                          │
│ Agent LLM 请求 ── Base URL: 127.0.0.1:<port> ──► Local Gateway ──► Provider│
│ (输入/输出 Token、Reasoning、首 Token 延迟、吞吐 tok/s、Tool ID Ledger)  │
│                                                                          │
│ 状态：开启网关时精准捕获；未开启或直连时，UI 显式标记为「不可见」，不报红中断│
└──────────────────────────────────────────────────────────────────────────┘
```

#### 4.4.1 通道一：本地活动感知（Activity Plane）

- **Codex 链路**：Codexling 的 `CodexActivityService` 直接读取本地 `~/.codex/state_5.sqlite`、`session_index.jsonl` 与 rollout 增量日志，毫秒级还原任务 ID、任务标题、工作区名称与 Git 分支。
- **第三方 Agent 链路（Hermes、Claude Code、DeepSeek Harness 等）**：通过轻量脚本 `CodexlingAgentBridge` 挂载为 CLI 生命周期 Hook，向本地 UNIX Domain Socket（`Library/Application Support/Codexling/agent-events.sock`，模式 `0600`）以 Datagram 形式单向广播 `NormalizedAgentEvent`（如 `session.started`、`tool.started`、`turn.completed`）。
- **完全解耦保证**：本地活动感知**不经过任何 HTTP 代理或网关端口**。无论网关是未启动、正在重启，还是 Agent 直接走官方公网直连，任务感知、状态栏提示、刘海屏展开与小宠物陪伴均 100% 正常运行。

#### 4.4.2 通道二：模型推理与调用遥测（Inference & Telemetry Plane）

- **网关代理链路**：当 Agent 的 Base URL 配置为网关监听地址（如 `http://127.0.0.1:<port>`）时，LLM 推理请求与流式响应经由网关转发。
- **深度数据捕获**：网关在流转过程中无损统计输入/输出 Token 数、Reasoning 消耗、缓存命中率、首 Token 延迟（P50/P95）、生成吞吐速度（tok/s）、Tool Call 成功率，并记录跨协议转换保真度（Native / Compatible / Degraded）。

#### 4.4.3 开启代理 vs 关闭代理（直连官方）对比矩阵

| 数据与功能维度 | 开启网关代理 (`127.0.0.1`) | 关闭代理 / 官方直连 | 影响与设计行为 |
|---|:---:|:---:|---|
| **今日任务标题 / ID / Git 分支** | ✅ 正常显示 | ✅ 正常显示 | 来自本地 SQLite / Hook 文件，完全不受网关影响 |
| **实时工作状态（思考中/工作中/待确认）** | ✅ 正常响应 | ✅ 正常响应 | 来自本地 Socket 数据报，维持小宠物和状态栏动画 |
| **今日陪伴时间 / 活跃时长** | ✅ 正常统计 | ✅ 正常统计 | 基于本地任务生命周期计算时间并集（避免多任务虚高） |
| **单任务的精确 Token 与 Reasoning 消耗** | ✅ 精准采集 | ❌ 标记为不可见 | 直连流量未走网关；UI 显示为灰色不可见，标明网关覆盖率（如 87%） |
| **首 Token 延迟 (TTFT) 与生成吞吐 (tok/s)** | ✅ 实时度量 | ❌ 无数据 | 只有网关拦截 SSE 流事件才能采集端到端微观延迟 |
| **跨模型路由（如 Codex 驱动 Gemini 3 Pro）** | ✅ 支持 | ❌ 不支持 | 协议与供应商转接必须依赖网关 Canonical IR |
| **账户官方总余额与订阅额度** | ✅ 正常轮询 | ✅ 正常轮询 | 通过设置面板独立的官方 Quota API 轮询，不依赖网关数据面 |

#### 4.4.4 架构设计原则：渐进增强与不强绑用户

1. **不绑架用户核心工作流**：本地网关是提供能力扩充（跨模型路由、协议转换、统一度量）的“性能倍增器”，而不是 Codexling 客户端生存的前置阻断条件。用户任何时候选择关闭网关，Codexling 依然是一个出色的陪伴式 Agent 看板。
2. **度量数据透明可溯源**：UI（如 `gateway-ui-concept.html`）对每一项 AI 运行数据均标注来源标签（`Provider` 官方报告、`Gateway` 代理采集、`本机` 统计或 `估算`），并在未走网关时诚实提示“绕过 Gateway 的 Token 显示为不可见”，绝不在缺失数据时胡乱编造。

## 5. Agent 兼容矩阵

### 5.1 入口能力矩阵

下表表示 Agent 作为模型 API 消费者时的主要可配置路径。`Native` 表示 Agent 有相应原生 Provider/协议实现；`Compatible` 表示可通过自定义 base URL 或兼容 Provider 使用；`Indirect` 表示经其内部统一层（如 LiteLLM）接入；`—` 表示不作为首选或未建立稳定依据。

| Agent | OpenAI Chat | OpenAI Responses | Anthropic Messages | Gemini Native | Custom Base URL | 推荐 Gateway 入口 |
|---|---|---|---|---|---|---|
| Codex | — | Native | — | — | Yes | Responses |
| Claude Code | — | — | Native | Vertex path | Yes | Anthropic Messages |
| OpenCode | Compatible | Native/package | Native/package | Native/package | Yes | 按 package 保持原协议 |
| Pi | Native/package | Native/package | Native/package | Native/package | Yes | Chat 或原生 package |
| Hermes | Compatible | Provider-specific | Native provider | Native provider | Yes | Chat Compatible |
| Cline | Compatible | Provider-specific | Native provider | Native provider | Yes | Chat Compatible |
| Roo Code | Compatible | Provider-specific | Native provider | Native provider | Yes | Chat Compatible |
| Kilo | Compatible | Selectable | Selectable | Native provider | Yes | Responses / Messages / Chat 可选 |
| Aider | Indirect | Indirect | Indirect | Indirect | Yes | LiteLLM/Chat path |
| OpenHands | Indirect | Indirect | Indirect | Indirect | Yes | LiteLLM path |
| Crush | Compatible | OpenAI provider path | Compatible | Native provider | Yes | Chat 或 Messages |
| Continue | Compatible | Provider-specific | Native provider | Native provider | Yes | Chat Compatible |

依据与注意事项：

- Codex 当前 wire API 以 Responses 为准，见 [Codex source](https://github.com/openai/codex/blob/main/codex-rs/model-provider-info/src/lib.rs)。
- Claude Code 的 gateway contract 见 [官方 LLM gateway 文档](https://code.claude.com/docs/en/llm-gateway)。
- OpenCode 允许为自定义 Provider 选择 package 并覆盖 `baseURL`，包括 OpenAI-compatible Responses package，见 [OpenCode Providers](https://opencode.ai/v2/docs/providers)。
- Pi 允许在 `models.json` 中配置自定义 Provider 与 API dialect，见 [Pi custom models](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/models.md)。
- Hermes 自定义 endpoint 以 `/v1/chat/completions` 为基础，见 [Hermes providers](https://github.com/hermes-agent-org/hermes/blob/main/website/docs/integrations/providers.md)。
- Cline 可配置 OpenAI-compatible Base URL、Key 和 Model ID，见 [Cline provider configuration](https://github.com/cline/cline/blob/main/docs/provider-config/openai-compatible.mdx)。
- Roo Code 列出 OpenAI Compatible Provider，见 [Roo Code providers](https://roocodeinc.github.io/Roo-Code/providers/)。
- Kilo 自定义模型可选择 OpenAI Responses、Anthropic Messages 或 OpenAI Compatible，见 [Kilo custom models](https://kilo.ai/docs/code-with-ai/agents/custom-models)。
- Aider 的跨 Provider 支持以 LiteLLM 为基础，见 [Aider LLM configuration](https://aider.chat/docs/llms.html)。
- OpenHands 可连接 LiteLLM 支持的 Provider 并允许 Base URL，见 [OpenHands LLM overview](https://docs.openhands.dev/openhands/usage/llms/llms)。
- Crush 支持自定义 OpenAI-compatible 和 Anthropic-compatible Provider，见 [Crush repository](https://github.com/charmbracelet/crush)。
- Continue 支持 `apiBase` 和显式 `tool_use` / `image_input` capabilities，见 [Continue config reference](https://docs.continue.dev/reference)。

### 5.2 Agent Adapter 首批优先级

| 优先级 | Agent | 理由 |
|---|---|---|
| P0 | Codex | 验证 Responses 语义转换是否真实可用 |
| P0 | Claude Code | 验证 Anthropic Messages、headers、count_tokens 与工具链 |
| P0 | OpenCode | 验证多 package / 多协议选择 |
| P1 | Pi | 自定义 Provider 清晰，适合测试 capability flags |
| P1 | Cline / Roo / Kilo | GUI 用户群与 OpenAI-compatible 覆盖 |
| P1 | Hermes | Chat-compatible 与多 Provider 场景 |
| P2 | Aider / OpenHands / Crush / Continue | 扩大生态覆盖并验证间接兼容 |

矩阵应作为版本化资产保存，例如 `compat/agents/2026-08.json`，而不是只存在于文档中。

## 6. Canonical IR 设计

### 6.1 设计原则

1. **语义优先，不以任一 Provider schema 为中心。**
2. **可逆优先。** 能无损 round-trip 的字段不应因归一化而丢失。
3. **状态显式。** request/response、item、tool call、stream 都要有稳定 identity。
4. **Opaque escape hatch。** Provider 独有数据原样保留，但不能污染跨 Provider 的通用逻辑。
5. **Streaming first。** 完整响应是流事件 fold 后的产物，不是流的前置条件。
6. **可表达降级。** 每次转换产生 loss report，而不是静默丢字段。

### 6.2 请求与内容结构

```rust
pub struct CanonicalRequest {
    pub request_id: RequestId,
    pub model: ModelSelector,
    pub instructions: Vec<Instruction>,
    pub items: Vec<InputItem>,
    pub tools: Vec<ToolDefinition>,
    pub tool_choice: ToolChoice,
    pub generation: GenerationConfig,
    pub requested_capabilities: CapabilitySet,
    pub conversation: ConversationRef,
    pub metadata: BTreeMap<String, JsonValue>,
    pub provider_state: Vec<ProviderState>,
}

pub enum InputItem {
    Message(Message),
    ToolResult(ToolResult),
    ReasoningState(ReasoningState),
    ProviderOpaque(ProviderOpaque),
}

pub struct Message {
    pub id: Option<ItemId>,
    pub role: Role,
    pub content: Vec<ContentBlock>,
    pub provider_state: Vec<ProviderState>,
}

pub enum Role {
    System,
    Developer,
    User,
    Assistant,
    Tool,
}

pub enum ContentBlock {
    Text(TextBlock),
    Image(ImageBlock),
    Audio(AudioBlock),
    File(FileBlock),
    ToolCall(ToolCall),
    ToolResult(ToolResult),
    Reasoning(ReasoningBlock),
    Refusal(RefusalBlock),
    Citation(CitationBlock),
    ProviderOpaque(ProviderOpaque),
}
```

### 6.3 ProviderOpaque 与 ProviderState

`ProviderOpaque` 是某个 item/content block 内的不可标准化载荷；`ProviderState` 是需要跨轮次或跨请求保持的 Provider 状态。两者不能用任意字符串拼接到 prompt 中。

```rust
pub struct ProviderOpaque {
    pub provider: ProviderId,
    pub kind: String,
    pub encoding: OpaqueEncoding,
    pub data: Bytes,
    pub integrity: Option<String>,
}

pub struct ProviderState {
    pub provider: ProviderId,
    pub scope: StateScope,
    pub key: String,
    pub value: SecretOrJson,
    pub replay: ReplayPolicy,
}

pub enum StateScope {
    Request,
    Item(ItemId),
    ToolCall(ToolCallId),
    Conversation(ConversationId),
}
```

典型内容：

| Provider | 必须保留的状态示例 |
|---|---|
| OpenAI Responses | response/item ID、reasoning opaque/encrypted content、hosted tool state |
| Anthropic | thinking signature、redacted thinking、cache control、beta feature metadata |
| Gemini | thought step/signature、built-in tool signatures、interaction ID |

安全规则：

- opaque state 默认加密落盘；
- 日志默认只记录 kind、size、hash，不记录正文；
- 只允许原 Provider 或明确定义的跨 Provider translator 消费；
- unknown opaque data 在同 Provider round-trip 时原样返回，在跨 Provider 时写入 loss report。

### 6.4 转换结果与损失报告

```rust
pub struct TranslationResult<T> {
    pub value: T,
    pub fidelity: Fidelity,
    pub losses: Vec<TranslationLoss>,
    pub warnings: Vec<CompatibilityWarning>,
}

pub enum Fidelity {
    Native,
    Compatible,
    Degraded,
    Unsupported,
}
```

这使 Router 能基于 policy 决定：继续、降级、改路由或拒绝。

## 7. Streaming IR

### 7.1 一等流模型

网关不应先缓冲完整响应再模拟 stream。内部 Provider Adapter 应直接输出统一事件：

```rust
pub enum StreamEvent {
    ResponseStarted(ResponseStarted),
    ItemStarted(ItemStarted),
    TextDelta(TextDelta),
    ReasoningDelta(ReasoningDelta),
    ToolCallStarted(ToolCallStarted),
    ToolArgumentsDelta(ToolArgumentsDelta),
    ToolCallCompleted(ToolCallCompleted),
    ItemCompleted(ItemCompleted),
    UsageUpdated(Usage),
    ResponseCompleted(ResponseCompleted),
    ResponseFailed(CanonicalError),
    KeepAlive,
}
```

事件必须包含：

- response/item/tool call ID；
- monotonic sequence number；
- provider timestamp（若有）与 gateway timestamp；
- raw/provider state reference；
- 可选 cumulative usage；
- cancellation token。

### 7.2 流式不变量

- `Started` 必须先于同 identity 的 `Delta/Completed`；
- tool arguments delta 按字节顺序重组后必须得到原始 JSON 文本；
- 一个 tool call ID 不能跨多个逻辑调用复用；
- terminal event 只能出现一次；
- 客户端断开必须向上游传播 cancellation；
- adapter 不得因 heartbeat/comment event 破坏客户端 SSE parser；
- usage 缺失时标注 unknown，不伪造精确值。

### 7.3 Backpressure 与故障

每个请求使用有界 channel；慢客户端触发 backpressure，而不是无限缓存。Provider 中途失败时，应尽可能输出目标协议的合法 error/terminal event，并记录响应是否已有部分内容，避免 Router 在已经输出 token 后进行不安全 fallback。

## 8. Tool Calling

Tool Calling 是兼容性的主要风险面，而非普通文本转换。

```rust
pub struct ToolDefinition {
    pub name: String,
    pub description: Option<String>,
    pub input_schema: JsonSchema,
    pub strictness: SchemaStrictness,
    pub provider_options: Vec<ProviderState>,
}

pub struct ToolCall {
    pub id: ToolCallId,
    pub name: String,
    pub arguments: ToolArguments,
    pub provider_state: Vec<ProviderState>,
}

pub struct ToolResult {
    pub call_id: ToolCallId,
    pub content: Vec<ContentBlock>,
    pub is_error: bool,
    pub provider_state: Vec<ProviderState>,
}
```

### 8.1 必须解决的问题

- JSON Schema 方言、`strict` 支持与 unsupported keywords；
- tool choice 的 none/auto/required/named 映射；
- 并行 tool calls；
- streaming arguments；
- call ID 的生成、保留与反向映射；
- tool result 的 role/content placement；
- reasoning 与 tool call 的先后关系；
- Provider built-in tools 与 client-executed tools 的边界；
- MCP tool 注入后的名字冲突和权限策略。

### 8.2 ID Ledger

使用每会话 ID ledger 维护：

```text
canonical_call_id
↔ ingress_protocol_call_id
↔ provider_call_id
↔ optional MCP request id
```

不得依赖 tool name 或数组下标关联结果。ledger 需要支持并行调用、重试和同名多次调用。

### 8.3 Schema 降级

如果目标 Provider 不支持某些 JSON Schema 关键字：

1. 优先选择能力匹配的 Provider/model；
2. 若 policy 允许，对 schema 做可解释的简化并产生 `TranslationLoss`；
3. 对关键约束丢失默认拒绝；
4. 不应静默把 native tool calling 改为“请输出 XML/JSON 文本”，除非用户明确开启 Degraded 模式。

## 9. Capability Negotiation

### 9.1 能力模型

```rust
pub struct ModelCapabilities {
    pub input_modalities: BTreeSet<Modality>,
    pub output_modalities: BTreeSet<Modality>,
    pub native_tools: SupportLevel,
    pub parallel_tools: SupportLevel,
    pub structured_output: SupportLevel,
    pub reasoning: SupportLevel,
    pub reasoning_stream: SupportLevel,
    pub prompt_cache: SupportLevel,
    pub stateful_continuation: SupportLevel,
    pub max_context_tokens: Option<u64>,
    pub max_output_tokens: Option<u64>,
    pub provider_features: BTreeSet<String>,
}

pub enum SupportLevel {
    Native,
    Emulated,
    Unsupported,
    Unknown,
}
```

能力来源按可信度排序：

1. 实际探测和 conformance test；
2. Provider 官方 model metadata；
3. 网关内置版本化 registry；
4. 用户显式 override；
5. 模型名称启发式（仅作最后 fallback）。

### 9.2 路由决策

```text
request requirements
        │
        ▼
resolve alias candidates
        │
        ▼
capability filter ── no match ── reject / explicit degrade
        │
        ▼
policy filter (privacy, budget, region, allowlist)
        │
        ▼
health / rate-limit / latency scoring
        │
        ▼
selected provider + model + protocol
```

网关应通过响应 header 和日志暴露：

```text
X-Agent-Gateway-Fidelity: native|compatible|degraded
X-Agent-Gateway-Resolved-Model: provider/model
X-Agent-Gateway-Warnings: <compact codes>
```

对严格客户端，警告只放 header/日志，不污染协议 JSON。

## 10. Model Alias 与路由

Agent 应调用稳定别名：

```yaml
models:
  coding-fast:
    require: [native_tools]
    candidates:
      - provider: google
        model: <current-fast-model>
      - provider: openai-compatible
        model: <fallback-model>

  coding-smart:
    require: [native_tools, reasoning]
    prefer: [reasoning_stream]
    candidates:
      - provider: google
        model: <current-pro-model>
      - provider: anthropic
        model: <current-sonnet-model>
```

别名解析要区分：

- logical alias：`coding-smart`；
- resolved Provider/model；
- exposed alias per ingress protocol；
- Provider snapshot/model revision；
- sticky session policy。

含 reasoning/provider state 的活跃会话默认保持 Provider 粘性。跨 Provider fallback 仅在请求尚未输出内容、且状态可安全转换时进行。

## 11. Protocol Adapter、Provider Adapter 与 Agent Adapter

### 11.1 Protocol Adapter

```rust
#[async_trait]
pub trait IngressProtocolAdapter {
    async fn decode_request(&self, http: HttpRequest)
        -> Result<TranslationResult<CanonicalRequest>>;

    async fn encode_stream(
        &self,
        events: CanonicalEventStream,
        sink: HttpStreamSink,
    ) -> Result<()>;
}
```

职责仅限：路径、headers、schema、SSE/event 编解码和协议错误。

### 11.2 Provider Adapter

```rust
#[async_trait]
pub trait ProviderAdapter {
    fn id(&self) -> ProviderId;
    async fn list_models(&self) -> Result<Vec<ProviderModel>>;
    async fn capabilities(&self, model: &str) -> Result<ModelCapabilities>;
    async fn stream(&self, request: CanonicalRequest)
        -> Result<CanonicalEventStream>;
    async fn count_tokens(&self, request: &CanonicalRequest)
        -> Result<TokenEstimate>;
}
```

Provider Adapter 不应知道 Codex、Claude Code 等客户端名称。

### 11.3 Agent Adapter

```rust
pub trait AgentAdapter {
    fn id(&self) -> AgentId;
    fn detect(&self) -> DetectionReport;
    fn inspect(&self) -> Result<AgentConfiguration>;
    fn plan_configuration(&self, target: GatewayTarget)
        -> Result<ConfigPatchPlan>;
    fn apply_configuration(&self, plan: ConfigPatchPlan)
        -> Result<RestorePoint>;
    fn restore(&self, point: RestorePoint) -> Result<()>;
    fn doctor(&self) -> Result<DiagnosticReport>;
    fn launch_spec(&self) -> Result<LaunchSpec>;
}
```

Agent Adapter 的配置写入必须：

- 先读取并解析现有文件；
- 只修改自己拥有的命名空间；
- 保留格式和未知字段；
- 创建可恢复快照；
- 在 UI 中展示 diff；
- 不把真实 Provider Key 写进 Agent 配置。

## 12. macOS SwiftUI + Rust Gateway 架构

### 12.1 进程模型

```text
YourApp.app
├── SwiftUI App
│   ├── Menu bar / Dashboard
│   ├── Provider & Model settings
│   ├── Agent manager
│   ├── Logs / Usage / Doctor
│   └── Keychain broker
│
└── Bundled Rust gateway process
    ├── loopback HTTP server
    ├── protocol adapters
    ├── canonical core
    ├── provider adapters
    ├── routing / policy
    └── local metadata database
```

SwiftUI 用 `Process` 管理 gateway 生命周期，通过单独的本地 control channel 通信。推理 data plane 与管理 control plane 分离：

| 平面 | 建议接口 | 用途 |
|---|---|---|
| Data plane | `127.0.0.1:<port>` HTTP/SSE | Agent 推理请求 |
| Control plane | Unix domain socket 或受保护 localhost | 状态、配置、日志、健康检查 |
| Secret plane | Keychain broker / short-lived handoff | Provider credentials |

### 12.2 SwiftUI 页面

- Overview：运行状态、endpoint、当前连接、今日 usage；
- Providers：Keychain 状态、模型发现、连通性测试；
- Models & Aliases：能力、别名、候选、fallback policy；
- Agents：安装检测、协议、目标 alias、一键配置、恢复；
- Requests：实时请求、协议、解析模型、fidelity、latency、错误；
- Doctor：端口、权限、Agent config、Provider auth、stream/tool smoke test；
- Settings：启动项、日志保留、隐私、导入导出。

### 12.3 生命周期

1. App 启动并获取单实例锁；
2. 从 Keychain 读取/授权 Provider secret；
3. 生成最小运行配置并启动 gateway；
4. gateway 绑定 loopback、生成 local token、回报 health；
5. App 开放 Agent 配置操作；
6. App 退出时先停止接收请求、等待短暂 drain，再终止 gateway。

### 12.4 本地安全默认值

- 默认只监听 `127.0.0.1` / `::1`；
- 每次安装生成独立 local gateway token；
- Provider Key 仅存 Keychain；
- 日志默认 redact prompt、tool arguments、opaque state 和 Authorization；
- 公网监听必须是显式高级选项，并强制 TLS、鉴权和风险提示；
- 配置导出默认不含 secret；
- 子进程继承最小环境，不通过全量 env 暴露所有 Key。

## 13. 开源方案对比：LiteLLM、Bifrost、Portkey

| 维度 | LiteLLM | Bifrost | Portkey Gateway | 本项目启示 |
|---|---|---|---|---|
| 技术栈 | Python | Go | TypeScript/edge-oriented | Rust 适合本地低占用二进制 |
| Provider 广度 | 很高 | 高 | 高 | 不必在 V1 追求数量 |
| OpenAI Chat | 成熟 | 支持 | 支持 | 必须 |
| Responses | 支持，含多 Provider 管理模式 | 面向 Codex 的兼容入口 | Open Responses across providers | 必须做真实语义事件 |
| Anthropic 入口 | 支持/演进中 | 明确支持 Claude Code | Messages API | 必须 |
| Gemini 入口 | Provider 支持 | 宣称 OpenAI/Anthropic/Gemini compatible endpoints | Provider/adapter | V2 原生入口 |
| Agent guides | 有生态用法 | Codex/Claude Code/Gemini CLI 等明确指南 | 通用 SDK/gateway | Agent Adapter 是差异点 |
| Routing/observability | 强 | 强 | 强 | V2 逐步加入 |
| 本地 macOS 产品体验 | 非重点 | 非重点 | 非重点 | 本项目的主要产品空间 |
| Canonical loss visibility | 不是其主要产品承诺 | 未作为主要 UI 概念 | 统一 API 为主 | 显式 fidelity/loss 是机会 |

资料：

- LiteLLM 提供 Proxy 与 Responses 支持，包括 Gemini、Anthropic 等 Provider 的 managed Responses 流。[LiteLLM documentation](https://docs.litellm.ai/)；[LiteLLM Responses docs](https://github.com/BerriAI/litellm-docs/blob/main/docs/response_api.md)
- Bifrost 明确提供 OpenAI、Anthropic、Gemini 兼容入口，并为 Claude Code、Codex CLI、Gemini CLI 等提供接入文档。[Bifrost CLI agents overview](https://docs.getbifrost.ai/cli-agents/overview)
- Portkey 同时暴露 Chat Completions、Responses 和 Anthropic Messages，并通过 Open Responses 对非原生 Provider 做语义适配。[Portkey Universal API](https://portkey.ai/docs/product/ai-gateway/universal-api)；[Portkey Open Responses](https://portkey.ai/docs/product/ai-gateway/responses-api)

### 13.1 Build vs Embed 建议

- 不建议把 LiteLLM Python runtime 直接嵌入 Swift App 作为长期核心，打包、启动、环境和升级体验较重；
- 可在原型期把 LiteLLM/Bifrost 作为 oracle 和兼容性对照组；
- Bifrost 最接近“多入口 Agent Gateway”竞品，应重点研究其 conformance 行为而不是复刻 UI；
- Portkey 的 Open Responses 和统一 API 可作为 Responses event normalization 的参考；
- 自研价值必须集中在 macOS 原生体验、Agent Adapter、无损状态、显式兼容等级、可恢复配置和本地隐私，而不是“又一个 Provider 列表”。

## 14. 兼容等级

### 14.1 定义

#### Native

- ingress/egress 语义由目标 Provider 原生支持；
- streaming、tools、state、usage 和错误均无已知语义损失；
- 通过对应 Agent 的 conformance suite。

#### Compatible

- 主要 coding loop、streaming 和 native tool calling 可工作；
- 允许可观测、非关键的字段差异或 emulation；
- 不影响 tool call identity 和多轮状态正确性；
- response 标记具体 warning。

#### Degraded

- 文本主路径可用，但至少一个请求能力被删除、模拟或文本化；
- 例如 reasoning 不可流式、并行工具被串行化、structured output 约束被弱化；
- 必须由 policy 或用户显式允许。

#### Unsupported

- 无法保证 Agent loop 正确，或关键状态会丢失；
- 默认拒绝并给出可操作诊断。

### 14.2 兼容不是单一布尔值

每个组合应按维度评分：

```text
agent × ingress protocol × provider × model × feature × version
```

示例报告：

```yaml
agent: codex
ingress: openai-responses
target: gemini/interactions
overall: compatible
features:
  text_stream: native
  function_tools: compatible
  parallel_tools: native
  reasoning_state: compatible
  hosted_tools: degraded
  usage: compatible
warnings:
  - hosted_tool_search_requires_provider_mapping
```

## 15. 推荐目录与 Rust crate 架构

```text
agent-gateway/
├── README.md
├── ARCHITECTURE.md
├── Cargo.toml
├── apps/
│   └── macos/
│       ├── AgentGateway.xcodeproj
│       └── Sources/
│           ├── App/
│           ├── Views/
│           ├── GatewayControl/
│           ├── AgentManager/
│           └── Keychain/
├── crates/
│   ├── gateway-bin/                 # executable / lifecycle
│   ├── gateway-server/              # HTTP, SSE, middleware
│   ├── gateway-control/             # local management API
│   ├── gateway-core/                # orchestration use cases
│   ├── gateway-ir/                  # canonical types only
│   ├── gateway-stream/              # event state machine / fold
│   ├── gateway-routing/             # alias, policy, fallback
│   ├── gateway-capabilities/        # registry, probes, negotiation
│   ├── gateway-state/               # conversation, ID ledger, opaque state
│   ├── gateway-auth/                # local token / secret handles
│   ├── gateway-observability/       # logs, traces, usage, redaction
│   ├── protocol-openai-chat/
│   ├── protocol-openai-responses/
│   ├── protocol-anthropic-messages/
│   ├── protocol-gemini-interactions/
│   ├── protocol-gemini-generate-content/
│   ├── provider-openai/
│   ├── provider-anthropic/
│   ├── provider-gemini/
│   ├── provider-openai-compatible/
│   ├── agent-codex/
│   ├── agent-claude-code/
│   ├── agent-opencode/
│   ├── agent-common/
│   ├── mcp-bridge/                  # V2+
│   └── acp-bridge/                  # V3+
├── compat/
│   ├── agents/
│   ├── models/
│   └── known-losses/
├── fixtures/
│   ├── protocols/
│   ├── providers/
│   └── agents/
├── tests/
│   ├── golden/
│   ├── roundtrip/
│   ├── conformance/
│   └── agent-smoke/
└── docs/
    ├── protocols/
    ├── compatibility/
    ├── security/
    └── decisions/                   # ADRs
```

### 15.1 依赖方向

```text
protocol-* ─┐
provider-* ─┼──> gateway-ir
agent-* ────┘

gateway-server -> gateway-core -> routing/state/capabilities -> gateway-ir
gateway-bin    -> server/control/providers/agents
```

`gateway-ir` 不依赖 HTTP SDK、Provider SDK、数据库或 UI。Protocol crate 之间不能互相依赖；任何 OpenAI → Gemini 的直接转换都应被 code review 阻止，路径必须经过 IR。

## 16. Roadmap

### V1：可用的本地 Agent Gateway

目标：证明三个主流 Agent 可以通过同一 localhost gateway 完成真实 coding tool loop。

范围：

- Ingress：OpenAI Chat、OpenAI Responses、Anthropic Messages；
- Egress：Gemini（先 compatibility，随后原生）+ generic OpenAI-compatible；
- SSE 真流式；
- native function tools、并行调用、ID ledger；
- `/v1/models`、Anthropic `count_tokens` 的可用实现；
- Model Alias 和 capability filter；
- SwiftUI overview/providers/models/agents/logs；
- Keychain 与 local token；
- Codex、Claude Code、OpenCode Agent Adapter；
- 配置 diff、restore point、doctor；
- Native/Compatible/Degraded 标记。

V1 退出标准：

- 三个 P0 Agent 各完成“读取文件 → 修改文件 → 运行测试”的 smoke test；
- streaming 首 token 不依赖完整响应缓冲；
- tool call/result 在 1000 次 fixture round-trip 中无 ID 错配；
- 未经允许的关键能力降级为零；
- secret/redaction 测试通过；
- Agent 配置可完全恢复。

### V2：多 Provider、原生 Gemini 与可靠路由

- Gemini Interactions 与 generateContent 原生 Adapter；
- OpenAI、Anthropic、DeepSeek/OpenRouter、本地 Provider；
- reasoning/thought/provider state 完整持久化；
- health、retry、rate-limit aware routing；
- 安全 fallback 与 sticky sessions；
- usage/cost/latency dashboard；
- Pi、Hermes、Cline、Roo、Kilo Adapter；
- MCP client/tool registry 与权限策略；
- capability probes 和版本化 compatibility registry；
- request replay bundle（默认脱敏）。

V2 退出标准：

- 至少 5 个 Provider、8 个 Agent 有持续 smoke test；
- 跨协议工具调用、reasoning state 有 golden fixtures；
- Provider 故障在“未输出内容”条件下可安全 fallback；
- P95 gateway 自身增加的流式延迟达到预定本地预算。

### V3：Agent Runtime 与生态平台

- ACP bridge：将 Agent 暴露给支持 ACP 的编辑器；
- 远程 Agent / remote gateway 的明确安全模型；
- 多会话、工作区和可选同步；
- 团队 policy、RBAC、审计与受控共享；
- 插件化 Protocol/Provider/Agent Adapter SDK；
- MCP Gateway、tool catalog、per-agent permissions；
- conformance kit 和公开兼容矩阵；
- 企业部署与签名更新机制。

## 17. 测试与验证策略

### 17.1 四层测试

1. **Schema test**：官方 fixture、未知字段、错误输入、header contract。
2. **Round-trip test**：协议 → IR → 同协议，验证可逆字段和 opaque state。
3. **Cross-protocol golden test**：Chat/Responses/Messages/Gemini 之间的文本、工具、reasoning 和错误事件。
4. **Agent smoke test**：使用真实 Agent 版本执行确定性小仓库任务。

### 17.2 必测场景

- 单/多 tool call；
- arguments 跨任意 chunk 边界；
- tool result error；
- reasoning + tool + text 混合顺序；
- 客户端取消、Provider 超时、429/5xx；
- streaming 中途断开；
- context overflow；
- unknown Provider fields；
- 模型不支持工具或 schema；
- thought/thinking signature 多轮回传；
- Agent 升级导致 config schema 变化。

### 17.3 兼容性版本固定

每次测试记录：Agent version、gateway commit、Provider API revision、model snapshot/alias resolution、fixture version。只有这样“Compatible”才是可复现结论。

## 18. 主要风险与设计决策

| 风险 | 后果 | 缓解 |
|---|---|---|
| 把 IR 设计成简化 messages | reasoning/tool state 丢失 | item/block/state 分层 + opaque escape hatch |
| 先完整缓冲再伪流 | Agent 延迟高、取消失效 | provider stream 直接转 Canonical events |
| 静默 capability 降级 | 对话正常但 Agent 不工作 | negotiation + fidelity + loss report |
| call ID 映射不稳定 | tool result 无法关联 | session ID ledger |
| Provider state 跨模型误用 | API 错误或推理连续性损坏 | provider-scoped state + sticky session |
| Agent 配置覆盖用户内容 | 数据损失、信任下降 | AST/structured patch + diff + restore point |
| 日志泄露代码或 Key | 严重安全问题 | 默认 redact、Keychain、opaque 加密 |
| 只依赖模型名推断能力 | 新模型/代理误判 | probes + registry + explicit overrides |
| 上游协议快速变化 | 兼容回归 | fixture/conformance CI + adapter crates |

建议立即记录的 ADR：

- ADR-001：Canonical IR 而非 pairwise translators；
- ADR-002：ProviderOpaque/ProviderState 为一等类型；
- ADR-003：Streaming-first state machine；
- ADR-004：Protocol/Provider/Agent Adapter 分层；
- ADR-005：本地进程隔离与 Keychain secret broker；
- ADR-006：显式 fidelity/loss policy；
- ADR-007：Provider sticky sessions 与 fallback 安全边界；
- ADR-008：双通道感知解耦（本地生命周期 Hook 与模型推理 Gateway 正交分离，代理未开启时不阻断客户端任务感知）。

## 19. 推荐的 V1 API 表面

### Data plane

```text
GET  /health
GET  /v1/models
POST /v1/chat/completions
POST /v1/responses
POST /v1/messages
POST /v1/messages/count_tokens
```

Anthropic 路径是否带 `/v1` 应在 ingress router 中兼容 Agent 的实际 base URL 拼接方式；内部 handler 不复制业务逻辑。

### Control plane

```text
GET  /status
GET  /providers
POST /providers/{id}/probe
GET  /models/aliases
PUT  /models/aliases/{id}
GET  /agents
POST /agents/{id}/plan
POST /agents/{id}/apply
POST /agents/{id}/restore
GET  /requests
GET  /diagnostics
```

Control plane schema 独立版本化，不伪装成任何 Provider API。

## 20. 结论与建议

该项目具备明确的技术与产品空间，但成功标准不是“能把一句话转发给 Gemini”，而是：

> 在不同 Agent 的真实 coding loop 中，稳定地保留流式语义、工具调用 identity、模型能力和 Provider 状态，同时给用户一个安全、可诊断、可回滚的 macOS 原生管理体验。

推荐立即执行的顺序：

1. 先冻结 Canonical IR v0、Streaming IR 和 TranslationLoss 结构；
2. 用 Codex Responses、Claude Messages、OpenAI Chat 三组真实 fixture 驱动 Protocol Adapter；
3. 实现 Gemini 与 generic OpenAI-compatible Provider，跑通三类 P0 Agent；
4. 再做 SwiftUI 管理面和 Agent 配置注入；
5. 达到 V1 conformance 后，再扩展 Provider 数量、MCP 与 ACP。

如果过早追求 Provider 数量、复杂 UI 或“全兼容”宣传，项目会掩盖真正的协议损失。相反，以 IR、状态、流和工具为内核，后续新增协议和 Provider 的成本将从 N×M 对转换降为 N+M 个 Adapter。

## 21. 参考资料

### OpenAI / Codex

- [OpenAI Chat Completions API Reference](https://developers.openai.com/api/reference/cli/resources/chat/subresources/completions)
- [OpenAI Responses API Reference](https://developers.openai.com/api/reference/typescript/resources/beta/subresources/responses/methods/create)
- [Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)
- [Codex model provider source: Responses wire API](https://github.com/openai/codex/blob/main/codex-rs/model-provider-info/src/lib.rs)

### Anthropic / Claude Code

- [Claude Code LLM gateway configuration](https://code.claude.com/docs/en/llm-gateway)
- [Anthropic Messages API Reference](https://platform.claude.com/docs/en/api/http/messages/create)
- [Anthropic token counting API](https://platform.claude.com/docs/en/api/http/messages/count_tokens)
- [Anthropic prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)

### Google Gemini

- [Gemini Interactions API announcement](https://blog.google/innovation-and-ai/technology/developers-tools/interactions-api-general-availability/)
- [Gemini thought signatures](https://ai.google.dev/gemini-api/docs/thought-signatures)
- [Gemini API reference](https://ai.google.dev/api)
- [Gemini OpenAI SDK / partner integration guidance](https://ai.google.dev/gemini-api/docs/partner-integration)

### MCP / ACP

- [MCP architecture](https://modelcontextprotocol.io/specification/2025-06-18/architecture)
- [MCP server primitives](https://modelcontextprotocol.io/specification/2025-06-18/server/index)
- [ACP introduction](https://agentclientprotocol.com/get-started/introduction)
- [ACP architecture](https://agentclientprotocol.com/get-started/architecture)
- [Zed ACP project](https://zed.dev/acp)

### Agents

- [OpenCode Providers](https://opencode.ai/v2/docs/providers)
- [Pi custom models](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/models.md)
- [Hermes providers](https://github.com/hermes-agent-org/hermes/blob/main/website/docs/integrations/providers.md)
- [Cline OpenAI-compatible provider](https://github.com/cline/cline/blob/main/docs/provider-config/openai-compatible.mdx)
- [Roo Code providers](https://roocodeinc.github.io/Roo-Code/providers/)
- [Kilo custom models](https://kilo.ai/docs/code-with-ai/agents/custom-models)
- [Aider LLM configuration](https://aider.chat/docs/llms.html)
- [OpenHands LLM overview](https://docs.openhands.dev/openhands/usage/llms/llms)
- [Crush repository and custom providers](https://github.com/charmbracelet/crush)
- [Continue configuration reference](https://docs.continue.dev/reference)

### Gateways

- [LiteLLM documentation](https://docs.litellm.ai/)
- [LiteLLM Responses documentation](https://github.com/BerriAI/litellm-docs/blob/main/docs/response_api.md)
- [Bifrost overview](https://docs.getbifrost.ai/overview)
- [Bifrost CLI agents](https://docs.getbifrost.ai/cli-agents/overview)
- [Portkey open-source gateway](https://github.com/Portkey-ai/gateway)
- [Portkey Universal API](https://portkey.ai/docs/product/ai-gateway/universal-api)
- [Portkey Open Responses](https://portkey.ai/docs/product/ai-gateway/responses-api)

---

### 附录 A：术语

| 术语 | 含义 |
|---|---|
| Agent / Harness | 组织模型、工具、工作区和循环的应用 |
| Protocol Adapter | 模型 wire protocol 与 Canonical IR 的转换层 |
| Provider Adapter | Canonical IR 与某个模型供应商 API 的转换层 |
| Agent Adapter | Agent 安装检测、配置、恢复、启动和诊断层 |
| Canonical IR | 网关内部统一且尽量无损的语义表示 |
| ProviderOpaque | 无法通用化但需要在 item/block 内保留的数据 |
| ProviderState | 需要跨 item、请求或会话续接的供应商状态 |
| Fidelity | Native / Compatible / Degraded / Unsupported |
| MCP | Agent/Host 与工具、资源、提示之间的协议 |
| ACP | 编辑器/客户端与完整 Agent 之间的协议 |

### 附录 B：V1 架构验收清单

- [ ] Chat、Responses、Messages 三种 ingress 均有 schema 和 streaming fixture
- [ ] Gemini / OpenAI-compatible 两种 egress 可用
- [ ] ProviderOpaque 与 ProviderState round-trip 测试通过
- [ ] tool call ID ledger 支持并行与重试
- [ ] capability 不匹配会拒绝或显式降级
- [ ] Codex、Claude Code、OpenCode smoke test 通过
- [ ] Agent 配置修改前可预览，修改后可恢复
- [ ] Provider Key 不进入 Agent 配置或普通日志
- [ ] gateway 仅监听 loopback
- [ ] 客户端取消能传播到 Provider
- [ ] partial stream 后禁止不安全 fallback
- [ ] compatibility report 可导出并带版本信息
