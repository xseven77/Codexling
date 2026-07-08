# Codex Light 方案

## 1. 背景

目标是在 macOS 状态栏中直接看到 Codex 额度概况，并支持点击后打开详情弹窗。

需要展示的信息包括：

- 5 小时内额度
- 一周额度
- credits 余额
- 重置券数量
- 重置券过期时间
- 当前账号、工作区、套餐、最近刷新时间

这个方案必须通用，并且通过 Codex / ChatGPT 官方登录方式查看，不保存用户密码，不绕过官方认证流程。

## 2. 官方边界

当前实现参考 Codex usage：通过 OpenAI 官方 OAuth 授权获取访问令牌，再访问 ChatGPT 的 Codex `wham` 用量端点读取 5 小时 / 7 天额度与重置券。

需要特别注意：

- `wham` 端点并非公开承诺的长期稳定 API，需要隔离在 provider/parser 中。
- 不应要求用户输入 OpenAI 账号密码给本应用。
- 不应绕过 MFA、SSO、Cloudflare、企业策略或官方登录流程。

因此，当前方案采用“官方 OAuth PKCE 授权 + Codex usage 同源 `wham` 用量读取”的方式落地。未来如果 OpenAI 发布正式 Usage API，再增加官方 API provider，并让其优先于当前 provider。

## 3. 产品形态

### 3.1 状态栏展示

状态栏常驻一个简短文本或图标：

```text
Codex 5h 72% · 周 41%
```

异常或特殊状态：

```text
Codex 登录
Codex 刷新失败
Codex 无数据
Codex 受限
```

### 3.2 点击弹窗

点击状态栏后显示详情弹窗：

```text
Codex Light

账号：name@example.com
工作区：Personal
套餐：Plus / Pro / Business / Enterprise

5小时额度
剩余：72 / 100
重置：今天 18:30

周额度
剩余：410 / 1000
重置：2026-08-01

Credits
余额：123 credits
过期：2027-07-01

重置券
数量：1
过期：2026-08-05

最近更新：2026-07-07 15:42

[刷新] [打开官方 Usage 页] [重新登录]
```

## 4. 技术架构

推荐使用原生 macOS 应用：

- Swift + SwiftUI
- `MenuBarExtra` 实现状态栏入口
- `Popover` 或 `NSPanel` 实现详情弹窗
- 系统浏览器承载官方 OpenAI OAuth 登录页
- 本地 `localhost:1455/auth/callback` 接收授权回调
- `Keychain` 保存 OAuth token，不保存密码
- `UserDefaults` 或本地 JSON 缓存最后一次成功快照
- `LaunchAgent` 或 Login Item 支持开机自启

整体结构：

```text
CodexLightApp
  -> AuthController
     -> 生成 OAuth PKCE state / verifier / challenge
     -> 打开官方 OpenAI 授权页
     -> 本地 callback server 接收 code
     -> 交换 access token / refresh token
  -> CodexUsageService
     -> 调用 /backend-api/wham/usage
     -> 调用 /backend-api/wham/rate-limit-reset-credits
  -> CodexLightParser
     -> 解析 usage.limits 和 rate_limit primary/secondary window
  -> UsageStore
     -> 缓存最后一次成功结果
  -> MenubarRenderer
     -> 渲染状态栏摘要和详情弹窗
```

## 5. 登录方案

登录必须走官方授权页：

1. 首次启动 App。
2. App 生成 OAuth PKCE 参数，并打开官方 OpenAI authorization URL。
3. 用户在系统浏览器完成官方登录、MFA 或组织 SSO。
4. OpenAI 回调到 `http://localhost:1455/auth/callback`。
5. App 用授权 code 交换 token，并将 token 存入 Keychain。
6. App 使用 token 调用 Codex `wham` 用量端点获取数据。

本应用不做：

- 不保存账号密码。
- 不拦截 MFA code。
- 不保存账号密码。
- 不绕过 SSO 或组织策略。
- 不要求用户提供 OpenAI session token。

## 6. 数据模型

建议统一成一个快照模型：

```ts
type CodexUsageSnapshot = {
  accountEmail?: string
  workspaceName?: string
  planName?: string

  shortWindow?: {
    label: "5小时额度"
    used?: number
    remaining?: number
    total?: number
    resetsAt?: string
  }

  weekly?: {
    label: "周额度"
    used?: number
    remaining?: number
    total?: number
    resetsAt?: string
  }

  credits?: {
    balance?: number
    currencyEquivalent?: string
    expiresAt?: string
  }

  resetCoupons?: Array<{
    id?: string
    name: string
    count: number
    expiresAt?: string
    source?: "referral" | "promotion" | "student" | "unknown"
  }>

  fetchedAt: string
  sourceUrl: string
}
```

Swift 实现时可拆成：

- `CodexUsageSnapshot`
- `UsageWindow`
- `CreditBalance`
- `ResetCoupon`
- `UsageFetchState`

## 7. Codex usage 数据适配器设计

因为 `wham` payload 结构可能变化，解析逻辑必须独立封装：

```text
UsageAdapter
  -> OfficialUsageApiAdapter       # 未来可加，若官方 API 发布
  -> Codex usageWhamAdapter         # 当前主方案
  -> Sample/Unavailable Adapter    # 无 token 或接口不可用时的兜底状态
```

解析器建议按领域拆分：

- `OAuthTokenStore`
- `WhamUsageProvider`
- `QuotaWindowParser`
- `ResetCreditParser`
- `ResetCouponParser`
- `RefreshTimeParser`

适配器输出统一的 `CodexUsageSnapshot`，UI 层不关心数据来自 API 还是页面。

## 8. 刷新策略

默认刷新策略：

- App 启动后立即刷新一次。
- 正常每 5 分钟刷新一次。
- 用户点击“刷新”时立即刷新。
- 登录失效时停止后台刷新，并显示“需要登录”。
- 解析失败时保留最后一次成功数据，并提示“接口响应可能变化”。

退避策略：

```text
成功：5分钟后刷新
网络失败：1分钟、2分钟、5分钟、10分钟退避
登录失效：等待用户重新登录
解析失败：30分钟后重试，并提示需要更新适配器
```

## 9. 本地缓存

本地只缓存展示所需的最近一次快照：

```text
~/Library/Application Support/CodexLight/latest_snapshot.json
```

缓存内容：

- 最近一次成功的 `CodexUsageSnapshot`
- 刷新状态
- 用户 UI 偏好，例如状态栏显示格式

不缓存：

- 用户密码
- MFA code
- 手动复制的 session token
- 原始网页 HTML，除非用户开启 debug 模式

## 10. 安全和隐私

必须遵守：

- 用户只在官方页面登录。
- App 不读取系统浏览器 Cookie。
- App 不上传额度信息到第三方服务。
- 默认不记录原始页面内容。
- debug 日志需要手动开启，并提示可能包含账号或额度信息。

建议提供隐私设置：

- 隐藏状态栏数字，仅显示颜色或百分比。
- 弹窗中隐藏邮箱。
- 一键清除本地缓存。
- 一键退出登录，清除 WebView 数据。

## 11. UI 细节

状态栏可配置三种展示模式：

```text
简洁：Codex 72%
双额度：5h 72% · 周 41%
图标：仅显示图标，颜色表示健康度
```

颜色建议：

- 绿色：额度充足，大于 50%
- 黄色：额度偏低，20% 到 50%
- 红色：额度紧张，低于 20%
- 灰色：未登录或无数据

详情弹窗操作：

- 刷新
- 打开官方 Usage 页
- 重新登录
- 偏好设置
- 退出

## 12. 项目目录建议

```text
codex-light/
  README.md
  PROJECT.md
  docs/
    codex-light方案.md
  app/
    CodexLight/
      CodexLightApp.swift
      MenuBar/
      DetailPopover/
      Auth/
      Usage/
      Storage/
  adapters/
    usage-page-adapter-notes.md
    fixtures/
```

## 13. 实现里程碑

### Milestone 1: App Shell

- 创建 SwiftUI macOS App。
- 使用 `MenuBarExtra` 显示状态栏入口。
- 点击后打开详情弹窗。
- 支持手动刷新按钮和占位数据。

### Milestone 2: 官方 OAuth 登录

- 生成 OAuth PKCE 参数。
- 打开官方 OpenAI authorization URL。
- 本地 callback server 接收授权 code。
- token 写入 Keychain。
- 能判断“已登录 / 未登录 / token 过期”。

### Milestone 3: Wham Usage 读取

- 调用 `/backend-api/wham/usage`。
- 解析 5 小时额度。
- 解析周额度。
- 解析重置时间。
- 输出统一快照。

### Milestone 4: Credits 和重置券

- 解析 credits 余额。
- 解析 reset coupon 数量。
- 解析 reset coupon 过期时间。
- 展示 promotion / referral / unknown 来源。

### Milestone 5: 稳定性

- 增加本地缓存。
- 增加刷新退避。
- 增加页面结构变化提示。
- 增加 parser fixture 测试。

### Milestone 6: 打包发布

- 支持开机启动。
- 支持清除本地数据。
- 支持导出 debug 信息。
- 完成签名、公证和安装包。

## 14. 风险

### Wham 响应结构变化

风险：ChatGPT `wham` payload 字段变化，导致解析失败。

应对：

- 适配器独立封装。
- 保留最后一次成功快照。
- 提示用户打开官方 Usage 页面确认。
- 增加可更新 parser。

### 端点不是公开稳定 API

风险：无法使用稳定接口获取额度。

应对：

- 当前版本参考 Codex usage 的 `wham` 端点。
- 未来新增 `OfficialUsageApiAdapter`。
- UI 层只依赖统一快照模型。

### 多账号和多工作区

风险：用户有多个 workspace，Usage 数据与当前选中 workspace 相关。

应对：

- 在详情中明确展示当前账号和 workspace。
- 支持打开官方页面切换 workspace。
- 后续版本支持 workspace 选择。

### 登录失效

风险：OAuth token 过期或 refresh 失败。

应对：

- 状态栏显示“Codex 登录”。
- 点击后重新打开官方 OAuth 授权页。
- 不尝试绕过官方认证。

## 15. 验收标准

MVP 验收：

- App 能在 macOS 状态栏显示。
- 点击状态栏能打开详情弹窗。
- 能通过官方 OAuth 登录流程获取 token。
- 能调用 `wham` 用量端点获取数据。
- 能显示 5 小时额度和周额度。
- 能显示最近更新时间。
- 登录失效时能提示重新登录。

完整版本验收：

- 能显示 credits 余额。
- 能显示重置券数量和过期时间。
- 能缓存最后一次成功数据。
- 接口解析失败时不崩溃。
- 支持打开官方 Usage 页。
- 支持清除本地数据。

## 16. 推荐下一步

下一步可以直接创建 SwiftUI macOS 项目，并优先实现：

1. `MenuBarExtra` 状态栏壳子。
2. `UsageSnapshot` 数据模型。
3. 假数据详情弹窗。
4. OAuth PKCE 登录。
5. Codex usage `wham` 用量 provider。
