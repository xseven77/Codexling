# 05 - Gateway 本地网关

本章介绍 Codexling 的本地 LLM 网关（Gateway）：进程守护、供应商账号路由、密钥托管、遥测分析与自动化巡检。

---

## 1. 架构定位与生命周期

Gateway 是一个绑定本机回环地址的本地 LLM 代理服务，由仓库根部的 Rust workspace 构建（`crates/gateway-server` 产出二进制 `codexling-gateway`，成员含 `gateway-ir`/`gateway-stream`/`gateway-state`/`gateway-routing`/`protocol-openai-chat`/`protocol-openai-responses`/`protocol-anthropic-messages`/`provider-openai-compatible` 等），将 Codex / Gemini / DeepSeek / OpenCode 等多家账号统一暴露为模型端点，供 Hermes、Pi 等 Agent 接入。**同时代理 OpenAI Chat Completions、OpenAI Responses 与 Anthropic Messages 三种协议**（`crates/gateway-server/src/server.rs` 路由表）：

```text
端点（server.rs）：
  对话：  POST /v1/chat/completions  /v1/responses  /v1/messages（及无前缀变体）
  模型：  GET  /v1/models  /v1/models/all
  遥测：  /telemetry/summary  /telemetry/timeseries  /telemetry/breakdown  /telemetry/requests
  健康：  /health  /status
  内部：  /internal/model-check(/cancel|/status)  /internal/models/health  /shutdown
```

```
 Hermes / Pi 等 Agent
        │  http://127.0.0.1:58349  (Bearer localToken)
        ▼
 Codexling Gateway helper（Rust 子进程）
   ├─ 供应商路由（ProviderRoutingMode 每供应商策略）
   ├─ 密钥注入（GatewaySecretBroker / 各凭证目录）
   └─ 遥测记录（GatewayTelemetry）
        ▼
 OpenAI (Codex OAuth) / Gemini OAuth / DeepSeek Key / OpenCode Key
```

- **监听**：`http://127.0.0.1:58349`，携带本地 token 鉴权（`GatewaySupervisor.swift:13-15`）。
- **守护**：`GatewaySupervisor.shared` 在 App 启动时立即拉起（`AppDelegate.swift:32`），与 Gateway 窗口无关。helper 二进制查找顺序：`Contents/Helpers/CodexlingGateway` → bundle auxiliary → 开发目录 `target/(release|debug)/codexling-gateway`（`GatewaySupervisor.swift:45-91`）；找不到时进入 mock loopback 模式（`:101-102`）。
- **启动握手**：以 `--port 58349 --token <token> --auto-check` 启动子进程，读取 stdout 首行 JSON（host/port/token）确认就绪；握手失败则尝试接管已有的健康 Gateway 而不是误报运行（`:142-161`）。
- **自愈**：子进程意外退出触发 `handleUnexpectedGatewayExit`，连续健康检查失败计数 `consecutiveHealthFailures` 驱动恢复调度（`:173-180`）。
- **自动启动开关**：`codexling.gateway.autostart`（UserDefaults，默认 true，`:23-27`），在 Gateway 窗口内可切换。
- **Gemini 联动**：启动 helper 时只注入公开的 OAuth client ID 环境变量，不泄露 refresh token（`:115-121`）。

---

## 2. Gateway 窗口结构

菜单栏/主窗口动作「打开 Gateway 窗口」（`AppDelegate.swift:132-134`）唤起 `GatewayWindowController.shared`。左侧导航共 7 个标签（`GatewayStore.swift:6-39`）：

| Tab | 副标题 | 视图文件 |
|---|---|---|
| 接入与模型 | 管理本地网关服务、已连接供应商账号与全量模型接入 | GatewayConnectView |
| 自动化任务 | 编排并管理本地模型定时巡检与自动化计划 | GatewayAutomationView |
| 一键接入 Agent | 一键配置并同步 Hermes、Pi 等第三方 Agent 客户端 | GatewayAgentsView |
| 监控概览 | 外部 Agent 伴侣工作时长、流量指标与协议中枢拓扑 | GatewayOverviewView |
| 用量分析 | Token 年度用量热力分布、模型消耗趋势与工具调用统计 | GatewayAnalyticsView |
| 实时请求 | 经本地网关反代的实时请求与流式明细 | GatewayRequestsView |
| Gateway Doctor | 环回端口、鉴权与上游桥接诊断 | GatewayDoctorView |

---

## 3. 接入与模型（Connect）

- 按供应商分组展示账号卡（`GatewayProviderSection` / `GatewayAccountModelGroup` / `GatewayExportedModel`，`GatewayStore.swift:75-195`）：每个 Codex/Gemini 账号导出哪些模型一目了然。
- **每供应商路由策略**（`ProviderRoutingMode`，`GatewaySettings.swift:3-33`）：
  - **平滑过渡 (smooth)**：多账号轮询均衡负载，各账号额度平滑消耗、防并发限频。
  - **固定特定账号 (pinnedAccount)**：流量优先直通所选账号（记录 `pinnedAccountId`）。当该固定账号遭遇 429 限频、额度耗尽或凭证异常时，网关将自动无缝切换到同渠道池的另一健康可用账号，并持久化回写 `gateway-settings.json`（等效于用户在 UI 设置中主动切换）。
  - 设置入口 `GatewayStore.setProviderRoutingMode`（`GatewayStore.swift:365`），持久化于 `~/Library/Application Support/Codexling/gateway-settings.json`（`GatewaySettings.swift:303-322`）。
- **供应商合并展示**：`isProviderConsolidated` / `setProviderConsolidated` 将同供应商多账号折叠为一组（`GatewayStore.swift:349-357`）。聚合模式下点击查看模型抽屉，直接呈现可访问的可用模型清单，并动态展示调度流向（固定直通或多账号均衡调度）。

---

## 4. 自动化任务（Automation）

任务类型目前为「模型健康巡检」（`AutomationTaskType.modelHealthCheck`，`GatewaySettings.swift:59-81`）：按计划自动探测并验证指定供应商与账号下模型的可用性与时延。

- **任务字段**（`GatewayAutomationTask`，`GatewaySettings.swift:83-105`）：名称、启用开关、目标供应商列表 `providers`、`allAccounts` 或指定 `accountIds`、运行小时表 `hours: [Int]`（0-23 任意小时，空=未设置，24 个=全天候）。
- **全局巡检节奏**（`HealthCheckInterval`，`GatewaySettings.swift:35-57`）：每 1 小时 / 每 6 小时 / 每天 0 点。
- CRUD 与手动触发：`addAutomationTask` / `updateAutomationTask` / `deleteAutomationTask` / `toggleAutomationTask` / `runAutomationTaskNow`（`GatewayStore.swift:384-404`，立即执行走 `triggerModelCheck`）。
- 编辑器：`AutomationTaskEditorSheet`（`GatewayAutomationView.swift:627`），小时选择使用自定义 `FlowLayout` 圆片网格。
- 任务回写 `lastRunAt` / `lastRunStatus` / `lastRunSummary` 供列表展示。

---

## 5. 模型健康检查（Model Health）

- 数据模型：`GatewayModelHealthSummary` / `GatewayModelHealthItem` / `GatewayAccountHealth` / `GatewayModelCheckJobStatus`（`GatewayModelHealthModels.swift`）。
- Gateway 启动就绪后立即 `GatewayStore.shared.refreshModelHealth()`（`GatewaySupervisor.swift:169-171`）；随后按上述自动化计划巡检。
- 巡检结果驱动「接入与模型」页的健康角标与过滤。

---

## 6. 一键接入 Agent（Agents）

为 Hermes 与 Pi 提供非手动改配置的接入器（幂等地写入/还原）：

- **Hermes**（`HermesGatewayConfigurator.configure(baseURL:apiKey:models:defaultModel:)`，`HermesGatewayConfigurator.swift:156`）：通过 `hermes` CLI 子命令完成模型提供方注册；`unconfigure()` 撤销（`:119`）。
- **Pi**（`PiGatewayConfigurator.configure(...)`，`PiGatewayConfigurator.swift:159`）：以 agent 目录为上下文调用 `pi` CLI 注册网关模型；`unconfigure()` 撤销（`:121`）。
- Agent 目录模型白名单随账号刷新动态同步：账号刷新成功后仅在官方模型目录真正变化时调用 `GatewayStore.shared.syncConfiguredAgentCatalogsIfNeeded()`（`AppDelegate.swift:272-274`）。

---

## 7. 监控概览 / 用量分析 / 实时请求

- **监控概览 (Overview)**：`GatewayAgentWorkRow` 展示各外部 Agent 的工作时长与流量指标、协议拓扑（`GatewayStore.swift:43`，`GatewayOverviewView.swift`）。
- **用量分析 (Analytics)**（`GatewayTelemetryModels.swift`）：
  - 日期范围 `GatewayDateRange`（含自定义起止日期，`GatewayCommon.swift:56-103` 提供选择器）。
  - 年度/区间 **Token 热力图**（`GatewayHeatmapCell/Summary`），模型时序（`GatewayModelTimeseriesPoint`），Token 构成（`GatewayTokenComposition`），模型排行 / 延迟排行 / 客户端排行（`GatewayModelRankingItem` / `GatewayLatencyRankingItem` / `GatewayClientRankingItem`），可按维度分组（`GatewayBreakdownDimension`）。
- **实时请求 (Requests)**：
  - `GatewayRequestRow` 逐条展示经网关反代的请求（含流式明细）；服务端数据来自遥测接口（`GatewayRequestsResponse`）。
  - 分页：`goToPage/nextPage/prevPage/setPageSize`（`GatewayStore.swift:558-579`）。
  - **列设置**：`GatewayRequestColumn` 枚举全部可显示列，按 `GatewayColumnCategory` 分类；`GatewayColumnSettingsSheet`（`GatewayColumnSettingsView.swift:3`）中勾选，`isColumnVisible/toggleColumn`（`GatewayStore.swift:608-612`）持久化。

---

## 8. Gateway Doctor（诊断）

`GatewayDoctorCheck`（`GatewayStore.swift:256`）驱动的诊断页（`GatewayDoctorView.swift`）：环回端口占用/连通、local token 鉴权、上游供应商桥接逐项体检。

---

## 9. 密钥托管（SecretBroker）

`GatewaySecretBroker` 用 macOS Keychain 保存网关侧账号密钥（`saveSecret/retrieveSecret/deleteSecret`，`GatewaySecretBroker.swift:33-86`），并提供 `migrateLegacyFile` 将旧版明文文件凭证迁移进 Keychain（`:100`）。Agent 侧只需拿到指向 127.0.0.1:58349 的配置与 local token，真实上游密钥不出网关进程。
