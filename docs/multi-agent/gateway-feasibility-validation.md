# Codexling Gateway 可行性验证

> 验证日期：2026-08-29  
> 验证环境：macOS 26.6.2 / arm64 / Swift 6.3.3 / Rust 1.98.0  
> 目标：验证独立 Gateway 窗口背后的进程、传输和安全边界是否能在当前 Codexling 工程中落地。

## 1. 结论

**独立 Gateway 窗口与本地 Rust Gateway 的基础闭环可实现，并已通过运行验证。**

已经实际验证的链路：

```text
Codexling / Swift Process
        │ launch + stdout ready handshake
        ▼
Bundled-style Rust executable
        │ random 127.0.0.1 port + local bearer token
        ▼
health / status / models / SSE events / graceful shutdown
```

本次验证不等于完整 Gateway 已实现。Canonical IR、真实 OpenAI Responses / Anthropic Messages 协议转换、Provider 推理出口、工具调用 ID ledger、reasoning/provider state 和 Agent smoke test 仍需单独实现与验证。

## 2. 运行验证结果

### 2.1 Rust Release 构建

- Rust crate 可在当前仓库独立构建。
- Release 产物为 arm64 Mach-O。
- Release 大小：458,176 bytes。
- 动态依赖只有系统 `libSystem.B.dylib`，没有额外运行时依赖。

### 2.2 Swift → Rust 端到端闭环

Swift 验证器通过 `Process` 启动 Rust 二进制，并验证：

- stdout ready handshake；
- 随机 loopback 端口；
- 无 token 的 control plane 请求返回 401；
- 带 local token 的 `/status` 可用；
- `/v1/models` 返回稳定模型别名；
- `text/event-stream` 返回有序语义事件；
- `POST /shutdown` 后 Rust 进程以状态 0 退出。

实际结果：

```text
PASS process_launch ready_handshake loopback_binding public_health
     local_token models_endpoint sse_events graceful_shutdown
gateway_exit=0
```

验证代码位于 `spikes/gateway-feasibility/`。

### 2.3 现有工程回归证据

运行了与 Gateway 集成边界直接相关的 6 个现有测试，全部通过：

- 独立窗口关闭和重建；
- 主窗口与设置窗口事件隔离；
- OAuth callback 随机 loopback 端口；
- Gemini 凭据文件权限 round-trip；
- Codex app-server capability gate；
- 多 Codex runtime credential home 隔离。

## 3. 功能可行性矩阵

| UI / 产品功能 | 结论 | 验证依据 | 仍需完成 |
|---|---|---|---|
| 设置页按钮打开独立 Gateway 窗口 | 可直接实现 | 已有 `DetachedWindowController`、`SettingsWindowController` 和独立窗口测试 | 新增 `GatewayWindowController` 与 AppDelegate 生命周期 |
| 关闭窗口但 Gateway 继续运行 | 可直接实现 | 现有窗口 controller 与进程 runtime 生命周期已经分离 | `GatewaySupervisor` 由 AppDelegate 持有，不由窗口持有 |
| App 启动/停止 Rust Gateway | 已验证 | Swift verifier 成功启动并关闭 Rust Release 二进制 | 崩溃重启、退避、drain timeout |
| 随机 localhost endpoint | 已验证 | Rust 实际绑定 `127.0.0.1:0` 并回传真实端口 | 端口持久展示、Agent 配置更新 |
| Local token 保护 control plane | 已验证 | 无 token 401，正确 token 200 | token 轮换、权限和日志脱敏 |
| `/health`、`/status`、`/v1/models` | 接口骨架已验证 | Swift 对 Rust 端点完成真实 HTTP 请求 | 正式 schema、版本控制、错误模型 |
| 实时请求列表 | 传输可行 | SSE content type 与事件顺序已验证 | 长连接重连、backpressure、事件缓存、Swift Store |
| 今日 Agent 工作（时间 vs Token） | 架构已理顺 | 工作时间与状态来自本地 SQLite/Socket Hook；Token 来自 Gateway 流量 | 双通道数据合流，未走网关时标记为不可见，不阻断任务看板 |
| 模型别名 UI | 接口可行 | `/v1/models` 别名读取已验证 | alias CRUD、capability filter、持久化和 Router |
| Gateway Doctor | 部分可行 | 进程、loopback、token、SSE 可形成自动检查 | 真实 Agent / Provider smoke test |
| Provider Keychain 隔离 | **当前不满足** | 当前 API Key store 是 `0600` 文件，不是真正 Keychain | 实现 Security.framework secret broker 与迁移 |
| OpenAI Chat ingress | 未验证 | 仅有研究设计 | schema、SSE、tool fixture 与 conformance tests |
| OpenAI Responses ingress | 未验证 | 仅有研究设计 | item lifecycle、semantic events、reasoning state |
| Anthropic Messages ingress | 未验证 | 仅有研究设计 | headers、content blocks、count_tokens、thinking signature |
| Gemini / OpenAI-compatible inference | 未验证 | 当前 Provider 服务只处理账号、额度或模型探测 | 真正 Provider Adapter 与推理请求 |
| Canonical IR / TranslationLoss | 未验证 | 文档中有类型草案 | Rust crate、round-trip 和 golden tests |
| Tool call ID ledger | 未验证 | 文档中有设计 | 并行调用、重试与跨协议 fixture |
| App bundle / DMG 集成 | 高可行，尚未打包验证 | 当前已把 `CodexlingAgentBridge` 放进 `Contents/Helpers` 并 deep-sign | 把 Rust binary 加入 Helpers、签名、DMG 和升级测试 |
| Intel / Universal Binary | 未验证 | 本次只构建 arm64 | 增加 x86_64 target 或明确 Apple Silicon 要求 |

## 4. 与当前代码的适配点

### 4.1 可以复用

- `NSWindow + NSHostingController` 的独立窗口模式；
- AppDelegate 持有窗口 controller 的生命周期模式；
- `Process + Pipe` 的长期子进程管理模式；
- `NWListener` 随机 loopback 端口模式；
- 本地 Unix socket 的权限和事件分发模式；
- SwiftUI observable store、toast、主题与独立窗口交互；
- `Contents/Helpers` 中携带辅助二进制的打包方式。

### 4.2 建议新增模块

```text
Swift
├── GatewayWindowController       独立窗口
├── GatewayView                  概览 / 路由 / 请求 / Doctor
├── GatewayStore                 UI observable state
├── GatewaySupervisor            launch / ready / restart / drain / stop
├── GatewayControlClient         status / config / diagnostics
└── GatewaySecretBroker          Security.framework / Keychain

Rust
├── gateway-bin
├── gateway-server
├── gateway-control
├── gateway-ir
├── gateway-stream
├── gateway-routing
├── gateway-state
├── protocol-*
└── provider-*
```

窗口关闭只销毁 `GatewayWindowController`；`GatewaySupervisor` 继续由 AppDelegate 持有，因此后台 Gateway 不会被错误停止。

## 5. 验证中发现的产品修正

当前界面多处写着“API Key 保存在 macOS Keychain”，但实际 `DeepSeekCredentialStore`、`OpenCodeCredentialStore` 和 `GeminiCredentialStore` 使用的是 Application Support 下权限为 `0600` 的文件。

`0600` 文件具备基础本地访问控制，但不等于 Keychain。Gateway 正式实现前应：

1. 新增真正的 Keychain store；
2. 启动时迁移旧 secret 文件；
3. 迁移成功后安全移除旧文件；
4. Agent 配置只写 localhost token 或 credential handle；
5. UI 只在迁移完成后显示“Keychain 已保护”。

## 6. 下一轮必须验证

基础设施通过后，下一轮应验证最小真实 coding loop，而不是继续扩展 UI：

1. OpenAI Chat fixture → Canonical IR → 同协议 round-trip；
2. OpenAI Responses SSE → Canonical stream events；
3. Anthropic Messages tool use/result 与 thinking signature；
4. Gemini 或 OpenAI-compatible Provider 的真实 streaming 请求；
5. 并行 tool calls 的 ID ledger；
6. Codex 完成“读取文件 → 修改文件 → 运行测试”的 smoke test；
7. Rust helper 进入 `.app/Contents/Helpers` 后完成签名与 DMG 验证。

只有第 1–6 项通过后，UI 中的 `Native / Compatible / Degraded` 才能来自真实 conformance 结果，而不是演示数据。
