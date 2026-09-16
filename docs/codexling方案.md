# Codexling 当前实现方案

> 本文是当前架构摘要。逐文件、逐设置项的完整说明以 [`docs/manual/`](manual/00-总览.md) 为准;
> 本仓库的现行行为以源码和测试为最终事实来源。

## 1. 产品形态

Codexling 是一个 macOS 菜单栏应用(accessory 模式),围绕本地 AI 工作流提供五类能力:

1. **多供应商账号额度**——统一接入 Codex (OpenAI) OAuth、Google Gemini OAuth、
   DeepSeek、OpenCode (Go/Zen) API Key,统一刷新并按账号轮播。
2. **多 Agent 活动监测**——被动只读感知 Codex、DSH (DeepSeek Harness)、Hermes、
   Antigravity、Pi 五家本地 Agent 的任务状态。
3. **本地 LLM 网关**——Rust 子进程,把上述账号统一暴露为三种协议的模型端点,
   供各 Agent 接入,并提供健康巡检、路由调度与用量遥测。
4. **桌面宠物 / 伙伴系统**——10 只内置宠物 + 自定义宠物,随 Agent 状态切换动画,
   与 Codex 双向同步,可独立置顶显示。
5. **刘海(Notch)胶囊面板**——在刘海区承载供应商卡片轮播与实时任务面板。

状态栏胶囊由三部分组成:前置圆灯(任务状态,可切换为额度色)、任务/额度文字、
活动波浪流光。点击胶囊打开独立主窗口;悬停约 120ms 显示不抢焦点的 Pet + 任务卡片。
刘海面板启用的屏幕上,菜单栏图标自动隐藏。

## 2. 运行架构

```text
AppDelegate
├── GatewaySupervisor.shared          ← 启动即拉起 Rust 网关子进程
│   └── codexling-gateway (crates/gateway-server)
│       ├── 三协议代理 /v1/chat/completions /v1/responses /v1/messages
│       ├── 供应商路由(smooth / pinned+自动切换)
│       ├── 模型健康巡检 /v1/models 严格过滤
│       └── 遥测 /telemetry/*
├── MultiAgentSettingsStore           ← 连接注册中心 connections-v1.json
│   ├── CodexUsageService(OAuth PKCE + wham/subscriptions)
│   ├── GeminiOAuthService / DeepSeek / OpenCode 连接服务
│   └── UsageSnapshotStore(latest_snapshot.json)
├── CodexActivityStore + AgentEventSocketService
│   └── 五家 Agent 只读活动发现 + agent-events.sock 事件桥
├── PetFrameStore / CompanionStatsStore(宠物帧动画与陪伴统计)
├── StatusBarController / NotchCapsulePanel(状态栏与刘海)
└── DetachedWindowController(主窗口 / 设置 / Gateway 窗口)
```

主可执行产物两个:`Codexling`(主应用)与 `CodexlingAgentBridge`(agent 事件桥 CLI);
网关二进制 `CodexlingGateway` 随 app 打包在 `Contents/Helpers/`。

## 3. 账号与凭据

| 供应商 | 认证 | 凭证位置(`~/Library/Application Support/Codexling/`) |
|---|---|---|
| Codex (OpenAI) | OAuth 2.0 PKCE,回调 `http://localhost:1455/auth/callback` | `Runtimes/Codex/<UUID>/oauth_token.json`(0600,按账号隔离 CODEX_HOME) |
| Google Gemini | Google OAuth 2.0 PKCE | `gemini_oauth/<handle>.json`(0600) |
| DeepSeek | API Key | `deepseek_credentials/<handle>.json`(0600) |
| OpenCode (Go/Zen) | API Key + 计划类型 | `opencode_credentials/<handle>.json`(0600) |

连接元数据(列表、启用、排序)持久化于 `connections-v1.json`(Schema V4)。
旧版单账号 Keychain token 仅用于一次性迁移,迁移后删除;Keychain 现仅用于网关侧
密钥托管(`GatewaySecretBroker`)。本应用不读取浏览器 Cookie,不保存密码或 MFA code。

## 4. 用量与订阅数据

| 端点 | 用途 | 失败行为 |
|---|---|---|
| `GET /backend-api/wham/usage` | 主/次级额度、套餐、工作区 | 本次刷新失败,保留上次成功快照 |
| `GET /backend-api/wham/rate-limit-reset-credits` | 可用重置券 | 可选;失败不阻断额度 |
| `GET /backend-api/subscriptions?account_id=…` | `active_until`、`will_renew` | best-effort;失败时不展示订阅周期 |

这些 ChatGPT Web 端点不是公开稳定 API,所有请求和解析集中在 `CodexUsageService`
与 `CodexlingParser`,UI 只消费 `CodexUsageSnapshot`。额度窗口按 `limit_window_seconds`
生成实际标签,不假定固定"5 小时 / 7 天";`total == 0` 的窗口不展示。

## 5. Agent 活动监测

五家 Agent 全部通过读取本地会话/状态文件被动感知,不安装 hook:

| Agent | 数据来源 |
|---|---|
| Codex | `~/.codex` state SQLite + rollout JSONL 尾部 |
| DSH | `~/.dsh/sessions` zstd 压缩会话(帧解压读首尾) |
| Hermes | `~/.hermes/state.db` |
| Antigravity | `~/.gemini/antigravity/` transcript |
| Pi | `~/.pi/agent/sessions/*.jsonl` |

事件归并为统一状态机:

```text
unavailable / idle / thinking / executing
reviewing / waitingForUser / completed / interrupted
```

解析只使用生命周期事件、工具元数据和清理截断后的用户可见 commentary;不持久化、
不上传、不展示 reasoning 内容、完整提示词、工具原始参数、Token 或环境变量。

## 6. 本地网关

- **监听**:`http://127.0.0.1:58349`,本地 Bearer token;局域网访问开启后绑定
  `0.0.0.0`,非回环来源访问对话/模型端点强制鉴权,管理端点对所有来源强制鉴权。
- **守护**:`GatewaySupervisor` 启动即拉起;健康检查失败计数驱动自愈,可接管已有
  健康实例;`codexling.gateway.autostart` 控制随 App 启动。
- **协议**:OpenAI Chat Completions、OpenAI Responses、Anthropic Messages 三协议
  互转(`crates/protocol-*`),多模态附件按上游格式转换转发。
- **路由**:每供应商 smooth(多账号轮询)或 pinned(固定账号,429/额度耗尽自动切换
  并回写 `gateway-settings.json`)。
- **健康巡检**:启动 15 秒后首轮全量巡检,每小时循环;串行探测 + 重试,`tab_*`
  补全模型跳过;`/v1/models` 只导出 available/error 模型,`/v1/models/all` 提供诊断。
- **一键接入**:Hermes、Pi、DSH 三家幂等配置(窄域跨度替换、指纹驱动同步、
  容量/模态/思考档位显式声明);token 轮换平滑同步。

## 7. Pet 与陪伴统计

- 发现 Codex 安装包内置 spritesheet 与 `~/.codex/pets` 自定义 Pet;App 自带 10 只
  宠物随包分发。图集契约:8 列 × 192px = 1536px 宽,208px 行高,至少 9 行;≥11 行
  视为 v2。
- 在 Codexling 选择 Pet 会写回 Codex `config.toml`;Codex 侧变化由文件监控实时
  同步回来;App Support 与 `~/.codex/pets` 之间做文件级双向补齐。
- `CompanionStatsStore` 每 30 秒结算一次有效活动时长,单次最多计 90 秒,避免系统
  休眠夸大统计。

## 8. UI 承载面与主题

- 菜单栏胶囊:AppKit `NSStatusItem` + 自绘(圆灯/文字/波浪/波纹同一坐标系)。
- 刘海面板:非激活式 `NSPanel`,展开约 700pt,供应商卡轮播 + 任务区;外接屏可
  拖拽,按显示器记忆偏移;无物理刘海的屏幕回退为菜单栏区同款胶囊。
- 主窗口:SwiftUI Companion 仪表盘,横向(约 579pt 宽)/竖向(330pt)双布局,
  可置顶;设置窗按内容测量尺寸。
- 独立宠物窗:置顶小窗,边缘贴靠、缩放与自由位置可调。
- 主题支持跟随系统/浅色/暗色;macOS 26 hover 卡片用系统 `glassEffect`,
  macOS 14–15 回退 material;根窗口保持不透明 `windowBackgroundColor`。

## 9. 刷新与缓存

自动刷新可选 30 秒、1/2/5/10 分钟或关闭,默认 1 分钟;账号轮播可独立设置
5 秒–1 分钟。启动时已有凭证会立即静默刷新。刷新失败不覆盖上次成功快照;
token 无效时清除本地凭证并要求重新授权。

```text
~/Library/Application Support/Codexling/
├── connections-v1.json        # 连接注册中心
├── gateway-settings.json      # 网关设置
├── latest_snapshot.json       # 最近额度快照
├── companion_stats.json        # 陪伴统计
├── agent-events.sock           # agent 事件桥
├── Runtimes/Codex/<UUID>/      # Codex OAuth(0600)
├── gemini_oauth/ deepseek_credentials/ opencode_credentials/
└── api-probes/                 # 仅显式 debug 探测时生成
```

## 10. 打包发布

`package_app.sh` 构建 Swift 主程序与事件桥,再以 Cargo 构建 Rust 网关,产出:

```text
dist/Codexling.app
dist/Codexling-<version>.zip
dist/Codexling-<version>.dmg
```

产物使用 ad-hoc codesign,并由脚本校验签名和 DMG 内容。当前没有 Apple notarization。
交互式 GitHub Release 流程见 [`app/Codexling/RELEASE.zh-CN.md`](../app/Codexling/RELEASE.zh-CN.md)。

## 11. 验收基线

- 各供应商登录、刷新、断开和旧 token 迁移可用;额度、重置券与订阅周期正确降级。
- 五家 Agent 活动状态归并正确;任务状态不影响额度刷新。
- 网关三协议代理、路由切换、健康巡检与一键接入可用;非回环访问强制鉴权。
- Pet 发现、安装、选择、Codex 双向同步和资源丢失回退可用。
- 陪伴统计跨日清零,休眠间隔封顶。
- 菜单栏、刘海、主窗口、设置与 Gateway 窗口行为符合当前窗口约束。
- Swift 测试、Rust 测试、Release 构建、ZIP/DMG 和 codesign 验证通过。
