# ChatGPT Plus / Pro 会员到期时间调研方案

> 文档版本：2026-07-27
> 状态：探测、实机验证和产品化均已完成；§5 保留为可选复现步骤。

---

## 1. 目标与结论摘要

| 问题 | 结论 |
|------|------|
| 能否从现有 `wham/usage` 读出 **Plus/Pro 会员到期日**？ | **通常不能**。该端点面向 Codex **用量/额度**，公开样本与社区文档仅稳定出现 `plan_type`、`rate_limit`、`credits` 等，**不含** `active_until` 类订阅周期字段。 |
| 能否用 **同一 OAuth Bearer** 读取会员到期？ | **有较可行路径**：社区与第三方实现指向 ChatGPT Web **`GET /backend-api/subscriptions?account_id=…`**，响应含 `plan_type`、`active_until`（RFC3339）、`will_renew` 等（**非公开文档 API，存在变更/403 风险**）。 |
| 备选 | **`GET /backend-api/accounts/check/v4-2023-04-27`** 在多账号/Team 场景下，`accounts.*.entitlement.expires_at` 可能描述 **entitlement**（与当前选中 workspace 相关，不等于个人 Plus 账单日时需甄别）。 |

**当前产品边界：**

1. **不要**把 `wham` 额度窗口的 `reset_at` / 重置券 `expires_at` 当作会员到期展示。  
2. Codexling 已在 OAuth 同源、用户已授权前提下 best-effort 请求 **subscriptions** 并解析 `active_until`；失败时静默降级，仅保留额度和 `plan_type`。
3. **长期**关注 OpenAI 是否提供正式 Consumer Subscription API；在此之前 treat 为 **best-effort 非保证字段**。

---

## 2. 第一步：验证 `wham/usage` 是否已有订阅字段

### 2.1 Codexling 当前已使用的数据

| 端点 | 用途 | Codexling 已解析字段 |
|------|------|----------------------|
| `GET https://chatgpt.com/backend-api/wham/usage` | Codex 额度 | `plan_type`、`rate_limit.*`、`limits`、`credits`（间接） |
| `GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits` | 重置券 | `credits[].expires_at` 等 |

实现位置：`CodexUsageService.swift` → `CodexlingParser.parse`。

### 2.2 公开资料对 wham payload 的描述

参考 [Token Use – Codex Subscription Quota](https://tokenuse.app/docs/development/tools/codex-subscription/) 等整理，`usage` 内典型结构为：

- `plan_type`（如 `plus`）
- `rate_limit.primary_window` / `secondary_window`（`used_percent`、`limit_window_seconds`、`reset_after_seconds`）
- `credits` / `spend_control`

**未列出** ChatGPT 订阅账单周期字段（如 `active_until`）。

### 2.3 本仓库已落地的「实机验证」能力

为避免凭猜测改 Parser，已增加 **API 探测落盘**（**不写入 access token**）：

| 组件 | 说明 |
|------|------|
| `CodexAPIProbe.swift` | 保存 JSON、扫描 `subscription*` / `active_until` / `entitlement` 等键路径 |
| `CodexUsageService.runChatGPTAPIProbe()` | 用 Application Support 中的本地 OAuth token 拉 wham，并探测 subscriptions / accounts-check |
| CLI | `Codexling --probe-chatgpt-apis` |
| 脚本 | `app/Codexling/scripts/run_chatgpt_api_probe.sh` |

**落盘目录：**

```text
~/Library/Application Support/Codexling/api-probes/
  latest/          # 最近一次（覆盖）
  <ISO-timestamp>/ # 历史一次
    wham-usage.json
    wham-rate-limit-reset-credits.json   # 若有
    subscriptions-<status>.json
    accounts-check-v4-<status>.json
    manifest.json                        # 字段命中 + recommendation
```

**扫描规则：** 递归 JSON，匹配键名包含 `subscription`、`active_until`、`expires_at`、`entitlement`、`will_renew`、`plan_type` 等（见 `CodexAPIProbe.scanSubscriptionRelatedFields`）。

**如何解读 manifest：**

- `endpoints[].subscriptionFieldHits`：在**该响应**里命中的路径。  
- 若 **仅** `wham-usage-cached` 有 `plan_type`，**无** `active_until` → 符合「wham 不提供会员到期」假设。  
- 若 `subscriptions-200.json` 含 `active_until` → 进入 §3 产品化路径。

**可选：刷新时自动落盘**

```bash
export CODEXLING_API_PROBE=1
# 或
defaults write com.qiizo.codexling codexling.debug.apiProbeEnabled -bool true
```

之后在 App 内触发一次用量刷新即可（无需 CLI）。

---

## 3. 第二步：ChatGPT 订阅相关 OAuth 可访问接口调研

> 以下端点为 **ChatGPT Web 内部 API**，OpenAI **未**作为公开产品文档发布。仅适合在 **用户显式登录 OAuth**、与现有 Codexling 授权范围一致的前提下做 **只读** 展示；需做好 **403/404/字段更名** 降级。

### 3.1 推荐：`GET /backend-api/subscriptions`

| 项 | 内容 |
|----|------|
| URL | `https://chatgpt.com/backend-api/subscriptions?account_id={chatgpt_account_id}` |
| 鉴权 | `Authorization: Bearer {access_token}`（与 wham 相同 OAuth） |
| 账号 | JWT `https://api.openai.com/auth` → `chatgpt_account_id`；请求头 `ChatGPT-Account-Id`（Codexling 已在 wham 使用） |
| 参考实现 | 开源项目 [sub2api `openai_privacy_service.go`](https://github.com/Wei-Shaw/sub2api/blob/5a8d6c4e/backend/internal/service/openai_privacy_service.go) / [`openai_subscription_test.go`](https://github.com/Wei-Shaw/sub2api/blob/5a8d6c4e/backend/internal/service/openai_subscription_test.go) |
| 典型 JSON 字段（测试样例） | `plan_type`, `active_until` (RFC3339), `will_renew`, `id` |

**与 Plus/Pro 的关系：** `plan_type` 与 wham 一致；**`active_until` 为当前探测目标字段**（个人订阅周期结束/当前周期结束，以实际 JSON 为准）。

**风险：**

- 非 Plus/Pro（如 free）可能 **200 但无 `active_until`** 或非 200。  
- `account_id` 缺失或 workspace 切换导致读到 **错误账号** 的订阅。  
- 接口随时变更；需 Parser 隔离 + 功能开关。

### 3.2 备选：`GET /backend-api/accounts/check/v4-2023-04-27`

| 项 | 内容 |
|----|------|
| URL | `https://chatgpt.com/backend-api/accounts/check/v4-2023-04-27` |
| 用途 | 多账号列表、默认 workspace、`plan_type`、**entitlement.expires_at** |
| 注意 | Team / 过期 workspace 场景下，`expires_at` 可能描述 **entitlement** 而非个人 Plus 续费日；需选 **当前默认个人账号** 或 UI 上标明来源 |

sub2api 测试表明：过期 org workspace 会 fallback 到 personal 账号的 `plan_type`，并 **清空** 误导性的 `SubscriptionExpiresAt`。

### 3.3 浏览器 Network 对照（人工一步）

在 **已登录** chatgpt.com 打开 **Settings → Subscription / 计划**，在 DevTools Network 中筛选：

- `subscriptions`
- `accounts/check`
- `billing` / `checkout`（通常 **不应** 在 Codexling 中调用）

记录：**Method、URL、Query、Request Headers（勿外泄 Cookie/Token）、Response 关键字段**。  
与 `api-probes/latest/*.json`  diff，确认与 App 探测一致。

### 3.4 明确不应使用的来源

| 来源 | 原因 |
|------|------|
| `platform.openai.com` Billing / Usage | **API 平台**预付费，与 **ChatGPT 订阅**分离 |
| 浏览器 Cookie / session-token 抓取 | 违反 Codexling 安全原则（见 `docs/codexling方案.md` §10） |
| wham 额度 `reset_at` | 速率限制窗口重置，非会员到期 |

---

## 4. 已落地的产品化实现

> **2026-07-24 更新：** 已在 Codexling 落地：`fetchQuotaSnapshot` 在额度成功后 best-effort 拉取 `subscriptions`，写入 `CodexUsageSnapshot.subscriptionActiveUntilISO` / `subscriptionWillRenew`；设置页账号区展示；首页 7 天内琥珀色提醒条。

### 4.1 当前数据模型

```swift
struct CodexUsageSnapshot: Codable, Equatable, Sendable {
    // 其他额度与账号字段……
    var subscriptionActiveUntilISO: String?
    var subscriptionWillRenew: Bool?
}
```

字段已直接挂载到 `CodexUsageSnapshot`。UI 使用「当前周期至 …」/「自动续费」；仅在 `will_renew == false` 时使用「会员到期」。

### 4.2 拉取策略

```text
刷新用量
  → GET wham/usage
  → 可选 GET wham/rate-limit-reset-credits
  → GET subscriptions?account_id=
       200 + active_until → 写入当前快照
       失败或字段缺失 → 不展示订阅周期，额度仍正常返回
```

- 缓存：订阅字段与用量快照同生命周期；一次完整刷新成功后写入最新快照。
- 隐私：原始 JSON 仅在 debug probe 显式开启时落盘（默认关）；不上传服务器。

### 4.3 当前降级与体验

- 解析到周期时，设置页展示「当前周期至 …」或「会员到期：…」，并展示续费状态。
- 周期在 7 天内或已经结束时，首页显示琥珀色提醒。
- subscriptions 请求失败或字段缺失时不单独报错；设置页保留「订阅与账单请在 ChatGPT 官网管理」和官方 Billing 链接。
- 不在日志中打印 Bearer token；只有显式开启 debug probe 才会把响应 JSON 写入 Application Support。

---

## 5. 可选：本地复现探测

在 **已用 Codexling 登录** 的本机执行：

```bash
cd app/Codexling
chmod +x scripts/run_chatgpt_api_probe.sh
./scripts/run_chatgpt_api_probe.sh
```

或：

```bash
cd app/Codexling && swift run Codexling --probe-chatgpt-apis
```

打开 `~/Library/Application Support/Codexling/api-probes/latest/manifest.json`：

1. 看 `recommendation` 字段。  
2. 看 `wham-usage-cached.subscriptionFieldHits` 是否出现 `active_until`。  
3. 打开 `subscriptions-200.json`（若存在）确认 `active_until` 格式。

如需报告接口变化，可将**脱敏后**的 `manifest.json`（删除 email/account_id）提供给开发。

### 5.1 本机实探测结果（2026-07-24，Plus 账号样本）

已在开发环境执行 `./scripts/run_chatgpt_api_probe.sh`，结论与 §1 一致，并**确认 subscriptions 可用**：

| 端点 | HTTP | 会员到期相关字段 |
|------|------|------------------|
| `wham/usage` | 200 | 仅 `plan_type`（如 `plus`），**无** `active_until` |
| `wham/rate-limit-reset-credits` | 200 | `credits[].expires_at`（**重置券**，非会员） |
| `subscriptions?account_id=…` | 200 | **`active_until`**（如 `2026-08-21T06:22:29Z`）、`will_renew`、`plan_type` |
| `accounts/check/v4-2023-04-27` | 200 | `accounts.*.entitlement.expires_at`（与 subscriptions 同周期，作校验/兜底） |

`manifest.recommendation` 自动生成：

> wham 不含会员到期；建议在 OAuth 同源下增加 GET /backend-api/subscriptions（account_id）解析 active_until。

**注意：** 落盘 JSON 可能含 `email`、`account_id`，请勿提交到 Git；仅本地 `~/Library/Application Support/Codexling/api-probes/`。

---

## 6. 当前架构落点

| 层级 | 变更 |
|------|------|
| Provider | `CodexUsageService.fetchQuotaSnapshot` best-effort 请求 subscriptions |
| Parser | `CodexlingParser.parseSubscription` 解析 `active_until` / `will_renew` |
| UI | 设置页账号卡和首页 7 天内提醒；链接到官方 Billing |
| 测试 | subscriptions 解析与 7 天提醒单测 |
| 文档 | 本文件 + README 链接 |

---

## 7. 参考链接

- [Token Use – Codex Subscription Quota](https://tokenuse.app/docs/development/tools/codex-subscription/) — wham 字段说明  
- [sub2api – subscription fetch 测试](https://github.com/Wei-Shaw/sub2api/blob/5a8d6c4e/backend/internal/service/openai_subscription_test.go) — `active_until` 样例  
- 仓库内：`docs/codexling方案.md` §3–4（授权边界与 wham/subscriptions 适配）
- 实现：`app/Codexling/Sources/Codexling/CodexAPIProbe.swift`

---

## 8. 变更记录

| 日期 | 说明 |
|------|------|
| 2026-07-24 | 初版：wham 验证方案落地、subscriptions/accounts-check 调研、产品化路径 |
| 2026-07-24 | 本机探测：`subscriptions.active_until` 可用；wham 无会员到期字段 |
| 2026-07-26 | 按当前代码修正 token 存储、已落地模型、拉取策略和复现状态 |
| 2026-07-27 | 按 `ca29220` 的实际串行 best-effort 路径修正拉取、失败降级和 UI 说明 |
