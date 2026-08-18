# OpenCode 供应商登录与额度适配方案

> 调研日期：2026-08-18（Asia/Shanghai）  
> 范围：仅把 OpenCode 作为 AI 供应商；不接入 OpenCode Agent、Session、SSE 或本地任务活动。

## 1. 结论

OpenCode 供应商应拆成两个独立的连接类型：

- **OpenCode Go**：订阅制供应商，使用 5 小时、周、月三类额度窗口。
- **OpenCode Zen**：按余额/消费计费的供应商，重点展示账户余额。

两者都通过 API Key 接入，但账本不同，不能合并成一个“OpenCode 额度”字段。

登录和连接管理可直接复用当前 API Key 连接模型；额度查询不能依赖 OpenCode 通用 Provider API，必须为 Go 和 Zen 分别设计适配器。

## 2. 官方登录模型

OpenCode 官方文档将 Go 和 Zen 都定义为普通 Provider：用户在 OpenCode 控制台登录、创建或复制 API Key，再通过 `/connect` 保存到 OpenCode。Go 的官方流程是订阅 Go 后复制 API Key；Zen 的流程是登录、配置账单并创建 API Key。

官方参考：

- [OpenCode Providers](https://opencode.ai/docs/providers)
- [OpenCode Go](https://dev.opencode.ai/docs/go/)

OpenCode 本地凭证默认保存于：

```text
~/.local/share/opencode/auth.json
```

本机现有文件已验证出以下结构特征（不读取或输出密钥值）：

```text
provider: opencode-go
type: api
```

这说明 Codexling 可以支持两种入口：

1. 用户在 Codexling 中输入 API Key，由 Codexling 保存为自己的供应商连接（独立目录、权限 `0600`）。
2. 可选地读取 OpenCode 的 `auth.json`，导入已存在的 `opencode-go` 或 `opencode-zen` API Key。

第二种入口必须提供明确的导入确认，不能静默复制凭证。

## 3. 连接模型

建议不要将 OpenCode 当作一个单一连接，而是按产品计划拆分 Provider：

```swift
extension ProviderID {
    static let openCodeGo = Self(rawValue: "provider.opencode-go")
    static let openCodeZen = Self(rawValue: "provider.opencode-zen")
}
```

连接记录可以复用现有 `DeepSeekAPIConnection` 的结构，但应抽象为更通用的 API Key 连接：

```swift
struct APIKeyProviderConnection {
    let id: ConnectionID
    let providerID: ProviderID
    var label: String
    let credentialHandle: String
    let keySuffix: String
    var authenticationState: ConnectionAuthenticationState
    var quota: ProviderQuotaSnapshot?
    let createdAt: Date
}
```

重要约束：

- Go 与 Zen 的连接记录平等，不存在主账号。
- 同一计划可以保存多个 API Key 连接，但是否属于同一 OpenCode workspace 由服务端决定。
- OpenCode Go 官方说明每个 workspace 当前只能有一个成员订阅 Go；Codexling 不应据此限制本地连接数量，只需把服务端错误正常展示。

## 4. OpenCode Go 适配

### 4.1 账本模型

OpenCode Go 官方公开的额度窗口为：

| 窗口 | 官方额度 | 展示字段建议 |
|---|---:|---|
| Rolling / 5h | 12 美元使用价值 | `primaryWindow` |
| Weekly | 30 美元使用价值 | `secondaryWindow` |
| Monthly | 60 美元使用价值 | `monthlyWindow` |

额度按美元价值计算，实际请求次数取决于所用模型，不应把它转换成固定请求次数。官方页面给出的请求数只是估算值。

参考：[OpenCode Go Usage limits](https://dev.opencode.ai/docs/go/)

### 4.2 官方 API 现状

OpenCode Server 的 `/provider`、`/provider/auth` 和 `/auth/:id` 只解决 Provider 列表和凭证管理，不提供 Go 账户的 rolling、weekly、monthly 使用量接口。

当前已落地的 Key 验证使用官方模型目录端点，而非推理请求：

- Go：`GET https://opencode.ai/zen/go/v1/models`
- Zen：`GET https://opencode.ai/zen/v1/models`

请求携带 `Authorization: Bearer <API_KEY>`。响应只用于确认 Key / 计划可用性并记录可用模型数；绝不由此推算余额或用量。

OpenCode 官方 issue 明确记录：Go 额度目前只能从 Web Dashboard 查看，尚无公开的程序化额度 API。该 issue 中提出的 `/api/v1/usage/plan` 是功能建议，不是已确认可用的接口。

参考：[Go plan usage/balance API feature request](https://github.com/anomalyco/opencode/issues/16017)

### 4.3 第一阶段策略

Go 第一阶段支持：

- API Key 添加、保存、删除。
- API Key 有效性验证。
- Provider 名称、模型可用性、连接状态。
- “额度查询暂不可用”状态。

Go 第一阶段不做：

- 猜测 5h/周/月剩余量。
- 根据响应中的 token usage 反推出账户额度。
- 把 OpenCode 官方 Web Dashboard 抓取当作稳定 API。

后续如果要支持额度，单独增加 `OpenCodeGoQuotaAdapter`，凭证可能需要 API Key 之外的 workspace/cookie 信息；这类能力应明确标注为实验性，并与官方公开 API 分开。

## 5. OpenCode Zen 适配

### 5.1 账本模型

Zen 是 OpenCode 团队提供的模型服务，官方接入方式同样是创建 API Key。它更接近余额/消费模型，而不是 Go 的固定时间窗口：

```text
current balance
top-up / credits
usage or spend
```

因此不应复用 Go 的 5h/周/月窗口 UI。

### 5.2 官方 API 现状

目前 OpenCode 官方 Provider API 没有公开稳定的 Zen 余额查询接口。OpenCode Console 的 Usage API 是组织级 CSV 导出，需要 service account key，不能作为单个 Zen API Key 的余额接口。

参考：[OpenCode Console Usage API](https://console.opencode.ai/guides/usage)

### 5.3 第一阶段策略

Zen 第一阶段支持：

- API Key 添加、保存、删除。
- API Key 有效性验证。
- 连接状态。
- Provider 名称和模型可用性。

Zen 第一阶段不做：

- 从 OpenCode Console Usage API 推断个人余额。
- 把组织用量 CSV 当成账号余额。
- 依赖未公开或网页结构推断的余额接口。

后续可单独增加 `OpenCodeZenBalanceAdapter`，但必须以官方公开接口为准；网页 Dashboard 抓取只能作为明确的实验功能，不能混入默认刷新流程。

## 6. 与当前 Codexling 的映射

| Codexling 能力 | OpenCode Go | OpenCode Zen |
|---|---:|---:|
| 供应商连接记录 | 直接支持 | 直接支持 |
| API Key 安全存储 | 直接支持 | 直接支持 |
| 多连接平等管理 | 直接支持 | 直接支持 |
| 添加 / 删除 / 重新验证 | 直接支持 | 直接支持 |
| Provider 可用性验证 | 直接支持 | 直接支持 |
| 额度窗口 | 暂无官方 API | 不适用 |
| 账户余额 | 不作为主展示 | 暂无官方 API |
| 统一轮播 | 支持 | 支持 |
| 状态栏健康色 | 基于连接状态 | 基于连接状态 |

当前实现将 Go / Zen 落为独立的 `OpenCodeAPIConnection`，与 Codex OAuth 和 DeepSeek Key 平等参与选择、删除、轮播及统一刷新；它保留计划字段，避免把两种账本混成单一 API Key 卡片。后续可再将 DeepSeek 与 OpenCode 提炼到通用 `APIKeyProviderConnection`，但不得牺牲 Go / Zen 的独立额度语义。

## 7. 推荐落地顺序

### Phase 1：统一连接模型

1. 新增 `provider.opencode-go` 和 `provider.opencode-zen`。
2. 抽象通用 API Key 连接存储。
3. UI 中新增“OpenCode Go”和“OpenCode Zen”两个供应商入口。
4. 连接列表、选择、退出、删除和轮播复用现有平等连接逻辑。

### Phase 2：登录验证

1. 输入 API Key。
2. 通过轻量模型列表/Provider 请求验证。
3. 保存连接状态和脱敏 key suffix。
4. 对 401、403、429、服务端余额不足分别展示状态。

### Phase 3：额度适配

1. 先等待官方 Go usage API 或稳定公开接口。
2. 单独实现 `OpenCodeGoQuotaAdapter`。
3. 单独实现 `OpenCodeZenBalanceAdapter`。
4. 额度适配失败不能影响登录状态和其他供应商刷新。

## 8. 最终判断

OpenCode 作为两个普通 AI 供应商连接接入是可行的：

- Go：登录可行，额度模型明确，但官方额度查询 API 缺失。
- Zen：登录可行，余额模型明确，但官方余额查询 API 缺失。
- 两者必须拆开适配，不能共用同一种额度卡片。
- 第一版可以先交付“登录 + 连接管理 + 状态验证”，额度查询作为 Provider-specific 后续能力。
