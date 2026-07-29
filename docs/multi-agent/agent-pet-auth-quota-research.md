# Codexling 多 Agent、Pet、登录与额度能力调研

> 最后核实：2026-07-29（Asia/Shanghai）  
> 调研对象：国内外主流 Coding Agent、Agent 订阅、模型 API Provider、第三方 API Key（BYOK）  
> 本文是此前各轮 Pet、Agent 接入、第三方登录、订阅额度、API Key 额度调研的合并版。

## 1. 结论摘要

### 1.1 产品结论

1. **Codex 是本次调研中唯一有官方一方 Pet 资源与动画协议的 Agent。** 其他产品截至核实日均未发现公开的官方 Pet 系统，但多数产品有 hooks、ACP、SDK、JSON stream 或 telemetry，足以让 Codexling 为它们提供自己的宠物表现层。
2. **Agent 接入、用户登录、额度查询、Pet 状态必须拆成四套能力。** 它们经常来自不同系统，不能把“支持某 Agent”理解成四项能力都支持。
3. **第三方登录不能靠复制现有 OAuth token。** 应优先让官方 CLI/SDK完成登录并复用其会话；没有公开授权 SDK 的产品，只能提供启动器或引导用户在官方客户端登录。
4. **订阅额度与 API Key 余额是两种账本。** 例如 Kimi Code 的会员 `/usage` 与 Moonshot OpenPlatform 的 `/v1/users/me/balance` 互不等价。
5. **第三方 API Key 额度查询目前并不普遍完善。**
   - 普通推理 Key 可直接查余额：DeepSeek、Moonshot/Kimi API、SiliconFlow。
   - 特定套餐可查剩余量：MiniMax Token Plan。
   - 可查得很完整但需独立管理凭证：OpenAI、Anthropic、Mistral、xAI，以及阿里云等云厂商的账单 API。
   - 主要依赖控制台：Google Gemini API、Together AI、Groq、阿里云百炼普通模型 Key、腾讯云、火山方舟、百度千帆等。
   - OpenRouter 的普通 Key 可查 Key 自身用量/限额，是海外 BYOK 体验最完整的对象之一；组织总 credits 则需 Management Key。
6. **首期最值得落地：**
   - Agent：Kimi Code、Qoder、CodeBuddy、Qwen Code、iFlow、Claude Code、GitHub Copilot CLI。
   - 余额 Provider：DeepSeek、Moonshot、SiliconFlow、OpenRouter。
   - Pet：继续复用 Codex v2 精灵协议，把其他 Agent 的生命周期事件映射到统一动画状态。

### 1.2 “支持”在本文中的定义

| 能力 | 含义 | 不等价项 |
|---|---|---|
| Agent 接入 | Codexling 能启动、观察或控制 Agent 任务 | 仅能打开官方 App 不等于可观察任务 |
| 第三方登录 | 有官方 CLI/SDK/OAuth/PAT/API Key 流程可委托 | 读取浏览器 Cookie 或复制 OAuth 文件不算 |
| 订阅额度 | Agent 产品自身的消息、请求、周/月额度 | 单次会话 token 统计不等于账户剩余额度 |
| API Key 额度 | 模型 Provider 的余额、消费或限流 | response `usage` 只代表当前请求 |
| Pet | 产品本身有 Pet，或 Codexling 能用可靠事件驱动外部 Pet | 仅显示“正在运行”不等于完整状态 |

## 2. 证据与评级标准

### 2.1 证据等级

| 等级 | 证据 |
|---|---|
| A | 官方公开 API、SDK、协议或结构化 CLI 输出 |
| B | 官方 CLI 交互命令、插件、hooks、控制台导出 |
| C | 官方控制台可见，但未发现公开机器接口 |
| D | 只能通过本地私有文件、日志文本或未公开接口推断 |
| — | 在本轮官方公开资料中未发现 |

“未发现”只表示截至 2026-07-29 的公开文档范围内没有找到稳定能力，不表示厂商内部绝对不存在。

### 2.2 API Key 额度的三个维度

| 维度 | 典型字段 | 用途 |
|---|---|---|
| 余额/Grant | cash、granted、credits、balance、plan remains | 判断还能否继续付费调用 |
| 历史用量/成本 | tokens、requests、cost、按模型/API Key 聚合 | 做账单分析和异常检测 |
| 速率额度 | RPM、RPD、TPM、remaining、reset | 判断短期能否继续请求 |

三者必须分别建模。余额充足不代表没有触发 TPM；当前请求返回 token 数也无法推出账户现金余额。

### 2.3 已确认的历史变化

| 时间 | 变化 | 对 Codexling 的影响 |
|---|---|---|
| 2026-04-15 | Qwen Code 旧 Qwen OAuth 免费层停止 | 新接入必须使用 ModelStudio Coding Plan、Token Plan、API Key 或自定义 endpoint |
| 2026-06-18 起 | Gemini CLI 官方开始把个人账户工作流迁往 Antigravity CLI | 需要按安装版本探测；企业和 API Key 模式仍独立支持 |
| 截至 2026-07-29 | xAI 已公开 Management API，Mistral 已公开 Admin usage/limit API | 应从“控制台型 Provider”升级成“独立管理凭证型 Provider” |
| 截至 2026-07-29 | Codex 仍是调研范围内唯一公开一方 Pet 协议和素材结构的 Agent | 保留 Codex sprite v2 为 Codexling 通用 Pet Contract 的起点 |

## 3. Pet 与 Agent 活动状态

### 3.1 国内外总览

| 地区 | Agent | 官方 Pet | 可驱动 Codexling Pet 的公开信号 | 结论 |
|---|---|---:|---|---|
| 国外 | OpenAI Codex | **有** | 本地任务记录、官方 Pet 资源；当前部分状态接口为非公开实现 | 唯一原生 Pet；保留为基准协议 |
| 国外 | Claude Code | 未发现 | Hooks、Agent SDK、JSON/stream-json | 高可行 |
| 国外 | Gemini CLI / Antigravity | 未发现 | CLI、telemetry、hooks、结构化事件 | 高可行，但注意 2026 产品迁移 |
| 国外 | GitHub Copilot CLI | 未发现 | 官方 hooks JSON、CLI 会话 | 高可行 |
| 国外 | Cursor | 未发现 | 公开宿主集成信号有限 | 中低；先做启动器/弱状态 |
| 国外 | OpenCode | 未发现 | 开源运行时、事件/插件能力取决于版本 | 可做适配器，不承担 Provider 额度 |
| 国外 | Hermes Agent | 未发现 | 开源运行时，状态依实现版本 | 可做适配器，不承担 Provider 额度 |
| 国内 | Kimi Code | 未发现 | ACP、Web REST/WebSocket、CLI | 高可行 |
| 国内 | Qoder | 未发现 | ACP、SDK hooks | 高可行 |
| 国内 | CodeBuddy | 未发现 | SDK、hooks、headless、stream-json、ACP | 高可行 |
| 国内 | Qwen Code | 未发现 | Hooks、SDK、headless | 高可行 |
| 国内 | iFlow CLI | 未发现 | 9 类 hooks、CLI | 高可行 |
| 国内 | 百度 Comate | 未发现 | 公开宿主级状态接口有限 | 中低 |
| 国内 | TRAE | 未发现 | 未找到稳定公开 hooks/SDK | 中低 |
| 国内 | 通义灵码 | 未发现 | 公开宿主级状态接口有限 | 中低；不要与 Qwen Code 混为一谈 |

### 3.2 Codex 原生 Pet 基线

Codexling 当前已经实现 Codex Pet。详细协议见[状态栏与 Pet](../status-bar-pets.md)，当前整体实现见[Codexling 方案](../codexling方案.md)。

核心事实：

- 自定义 Pet 目录：`~/.codex/pets/<pet-id>/`
- 清单：`pet.json`
- 图集：`spritesheet.webp`
- sprite v2：1536 × 2288
- 8 列 × 11 行
- 单帧：192 × 208
- 11 行覆盖标准动画状态
- 当前对 ChatGPT App 内置资源仅做读取，不修改 App 包

建议把这一协议升级为 **Codexling Pet Contract**，而不是继续让它只属于 Codex。其他 Agent 只需要提供统一状态：

```text
offline
idle
thinking
reading
writing
toolRunning
waitingForUser
succeeded
failed
rateLimited
```

适配层将各 Agent 的事件映射到这些状态，Pet 渲染层不需要知道 Claude、Kimi 或 Qoder 的专有字段。

### 3.3 各 Agent 的最佳状态来源

优先级从高到低：

1. 官方 SDK/ACP 的结构化事件。
2. 官方 hooks 的 JSON 输入。
3. 官方 JSON/stream-json CLI 输出。
4. 官方 telemetry。
5. CLI 文本和本地任务文件。
6. 进程存在性、窗口存在性等弱信号。

禁止为了 Pet 去读取或上传用户 prompt、response 正文。状态适配器默认只保留：

- session/task ID 的不可逆或本地标识
- 状态枚举
- 工具类别，不保存工具参数
- token/cost 聚合数
- 错误类别
- 时间戳

## 4. 第三方登录与认证

### 4.1 国外 Agent

| Agent | 官方认证方式 | Codexling 可采用方式 | 评级与限制 |
|---|---|---|---|
| Codex | ChatGPT/Codex 登录；当前 App 使用 OAuth PKCE | 继续隔离现有实现；长期等待稳定公开授权面 | D：当前 `/backend-api/wham/*` 等并非公开稳定 API |
| Claude Code | Anthropic Console OAuth、Claude Pro/Max、Bedrock、Vertex | 优先官方 Agent SDK/API Key；本机模式可委托 `claude` 登录 | A/B；不要复制消费者 OAuth token |
| Gemini CLI | Google 登录、Gemini API Key、Vertex | 第三方宿主必须用 AI Studio/Vertex Key；不要搭便车 CLI OAuth | A；官方明确限制第三方收割 CLI OAuth |
| GitHub Copilot CLI | device OAuth、环境 token、`gh` 会话、PAT、GitHub App token | 委托 CLI/device flow，或用户提供最小权限 PAT | A；OAuth 凭证由 CLI 存 OS Keychain |
| Cursor | Cursor 账号登录 | 启动/深链官方客户端 | C；未发现面向第三方宿主的个人登录 SDK |
| OpenCode | Provider API Key、部分 Provider OAuth | 让 OpenCode 自己管理 Provider；Codexling 只看运行时 | A/B；认证归实际 Provider |
| Hermes Agent | Provider API Key/运行时配置 | 同上 | B；随具体版本与 Provider 变化 |

来源：

- [Claude Code 快速开始与认证](https://docs.anthropic.com/en/docs/claude-code/getting-started)
- [Claude Code CLI 用法](https://docs.anthropic.com/en/docs/claude-code/cli-usage)
- [Gemini CLI FAQ：第三方工具不得复用其 OAuth](https://github.com/google-gemini/gemini-cli/blob/main/docs/resources/faq.md)
- [GitHub Copilot CLI 认证](https://docs.github.com/en/enterprise-cloud@latest/copilot/how-tos/copilot-cli/set-up-copilot-cli/authenticate-copilot-cli)

### 4.2 国内 Agent

| Agent | 官方认证方式 | Codexling 可采用方式 | 评级与限制 |
|---|---|---|---|
| Kimi Code | `kimi login`，RFC 8628 device-code OAuth | 启动官方登录命令并等待 CLI 完成；不碰 token 文件 | A |
| Qoder | PAT、环境变量、direct access token、复用 `qodercli` 登录 | SDK 的 `qodercliAuth()` 或 PAT | A |
| CodeBuddy | 复用 CLI 登录、API Key；企业 OAuth2 Client Credentials | 个人端委托 CLI；企业服务端使用 client credentials | A；企业 OAuth 不是消费者登录 |
| Qwen Code | ModelStudio Coding Plan、Token Plan、API Key、自定义 endpoint | 委托官方 CLI或明确配置 API Key | A；旧 Qwen OAuth 免费层已于 2026-04-15 停止 |
| iFlow CLI | 浏览器登录、iFlow API Key、OpenAI-compatible | 委托 CLI；或保存用户提供的 Key | A/B；文档中的 iFlow Key 有有效期提示 |
| 百度 Comate | 百度账号/企业账号 | 打开官方登录；企业由管理员配置 | C；未发现第三方宿主授权 SDK |
| TRAE | TRAE 账号体系 | 打开官方登录 | C；未发现稳定公开第三方授权协议 |
| 通义灵码 | 阿里云/企业账号体系 | 打开官方登录 | C；未发现个人宿主授权 SDK |

来源：

- [Kimi CLI 命令与 `kimi login`](https://www.kimi.com/code/docs/en/kimi-code-cli/reference/kimi-command.html)
- [Kimi 数据目录](https://www.kimi.com/code/docs/en/kimi-code-cli/configuration/data-locations.html)
- [Qoder SDK 认证](https://docs.qoder.com/en/cli/sdk/authentication)
- [CodeBuddy SDK 与认证](https://www.codebuddy.ai/docs/cli/sdk)
- [Qwen Code 认证](https://qwenlm.github.io/qwen-code-docs/zh/users/configuration/auth/)
- [iFlow CLI 快速开始](https://platform.iflow.cn/cli/quickstart)

### 4.3 登录实现安全要求

1. **OAuth 登录委托给官方 CLI/SDK。** Codexling 只观察登录完成状态，不读取 `~/.kimi-code`、Claude、Copilot 等产品的 token 文件。
2. **显式 API Key/PAT 放 macOS Keychain。** 不进入日志、偏好 plist、崩溃报告、分析事件或 UI 截图。
3. **管理 Key 与推理 Key 分槽。** UI 要明确标记 `Inference Key`、`Admin Key`、`Cloud IAM Credential`。
4. **最小权限。** 支持 scope/ACL/IP allowlist 的 Provider 应提示用户创建只读 billing/usage 凭证。
5. **不自动回退到 Cookie 抓取。** 如果厂商没有公开登录能力，就显示“在官方客户端中登录”，不要模拟浏览器账号接管。

## 5. Agent 订阅额度查询

这一节讨论 Agent 产品的个人/团队订阅，不讨论模型 API 账户。

### 5.1 国外 Agent

| Agent | 可见内容 | 机器查询能力 | 结论 |
|---|---|---|---|
| Codex | ChatGPT/Codex 计划限额 | 当前实现依赖非公开 ChatGPT 接口 | D：能做但应标实验性、可降级 |
| Claude Code | 会话成本、SDK `total_cost_usd`；计划额度通常在产品 UI | 未发现稳定的个人订阅剩余额度 API | 会话统计 A，订阅剩余 C |
| Gemini CLI / Antigravity | `/stats model` 可显示用量/额度信息 | CLI 输出可观察；个人产品正处于迁移期 | B；不能给第三方复用 OAuth |
| GitHub Copilot CLI | 个人 premium requests 在设置/账单页面；组织有 metrics API | 组织/企业 metrics API 完整，个人剩余额度接口不明确 | 组织 A，个人 C |
| Cursor | Dashboard 可看用量 | 未发现公开个人 quota API | C |
| OpenCode/Hermes | 自身通常不售卖模型额度 | 查询实际 Provider | 不应建立“OpenCode 额度” |

补充：

- GitHub 的组织/企业 Copilot usage metrics 可包含 CLI sessions、requests、token usage，但需要相应管理员或 billing 权限。
- Gemini CLI 官方在 2026 年公布个人账户向 Antigravity CLI 迁移，企业和 API Key 模式不受同样影响。适配器要按产品版本探测，不能硬编码旧登录入口。

来源：

- [Gemini CLI 使用与 `/stats`](https://github.com/google-gemini/gemini-cli/blob/main/docs/get-started/index.md)
- [Gemini CLI 至 Antigravity CLI 迁移讨论](https://github.com/google-gemini/gemini-cli/discussions/28017)
- [GitHub Copilot usage metrics 概念](https://docs.github.com/en/copilot/concepts/copilot-usage-metrics/copilot-metrics)
- [GitHub Copilot usage metrics 参考](https://docs.github.com/en/copilot/reference/copilot-usage-metrics/copilot-usage-metrics)

### 5.2 国内 Agent

| Agent | 可见内容 | 机器查询能力 | 结论 |
|---|---|---|---|
| Kimi Code | `/usage`：周、滚动 5 小时、月/共享会员、Extra Usage | 未发现 `/usage --json` 或公开额度 REST API | B：PTY 文本可做实验适配 |
| Qoder | IDE/网站 Settings → Usage：Credits、套餐、加油包、到期和日志 | 未发现公开 Credits API | C |
| CodeBuddy | `/cost` 会话成本、`/stats` 本地统计；网站 Usage 看账户 Credits | 会话统计可解析，账户余额未发现公开 API | B/C |
| Qwen Code | `/stats` 与本地 usage；Coding Plan 页面看整体额度 | 未发现稳定账户余额 API | B/C |
| iFlow CLI | `/stats` 会话统计 | 未发现公开账户额度 API | B/C |
| 百度 Comate | 企业后台可看 License 与智能体券总量、已用、剩余；可设成员限额 | 未发现公开 quota API | C |
| TRAE | 产品 UI 内额度规则 | 未发现稳定公开查询 API | C/— |
| 通义灵码 | 产品/企业控制台内额度 | 未发现稳定公开查询 API | C/— |

来源：

- [Kimi Code 会员与 `/usage`](https://www.kimi.com/code/docs/en/kimi-code/membership.html)
- [Qoder Credits](https://docs.qoder.com/Credits)
- [CodeBuddy slash commands](https://www.codebuddy.ai/docs/cli/slash-commands)
- [CodeBuddy Usage](https://www.codebuddy.ai/docs/ide/Account/usage)
- [iFlow slash commands](https://platform.iflow.cn/en/cli/examples/slash-commands)
- [百度 Comate 企业统计](https://cloud.baidu.com/doc/COMATE/s/Tmjznlabr)
- [百度 Comate 用量限制](https://cloud.baidu.com/doc/COMATE/s/Cmk2eigr4)

## 6. 第三方 API Key 额度查询

### 6.1 国内 Provider

| Provider | 普通推理 Key 查余额 | 历史用量/成本 | 速率额度 | 综合 |
|---|---|---|---|---|
| DeepSeek | **A**：`GET /user/balance` | C：未发现公开历史账单 API；可本地累计 response usage | C：主要靠错误/规则 | 首期 |
| Moonshot/Kimi API | **A**：`GET /v1/users/me/balance` | C：未发现公开历史账单 API | C | 首期 |
| SiliconFlow | **A**：`GET /v1/user/info` | C：账单主要在控制台 | B/C：规则与控制台 | 首期 |
| MiniMax | **A（Token Plan）**：`GET /v1/token_plan/remains` | C | C | 套餐型首期/二期 |
| 智谱 GLM | B：Coding Plan 官方 usage-query 插件 | C：控制台 | C：余额不足以 429 等体现 | 二期 |
| 阿里云百炼 / DashScope | 普通模型 Key 不可直接查；Coding Plan 页面显示 | B：控制台可按 Key 过滤；云 BSS API 可查账单 | C/B | 云 IAM 另做 |
| 腾讯云 TokenHub | C：控制台 | C：按计划/Key 看用量 | C | 控制台跳转 |
| 火山方舟 Ark | C：控制台 | C：控制台 token/计划剩余 | C | 控制台跳转 |
| 百度千帆 | 普通模型 Key 未发现通用余额 API | C；部分服务配额有 BCE 签名 API | C/B | 云 IAM 另做 |

#### 6.1.1 DeepSeek

```http
GET https://api.deepseek.com/user/balance
Authorization: Bearer <DEEPSEEK_API_KEY>
```

响应包含：

- `is_available`
- `total_balance`
- `granted_balance`
- `topped_up_balance`
- 币种（CNY/USD）

这是本次国内调研里最适合直接接入的标准余额接口。[官方文档](https://api-docs.deepseek.com/zh-cn/api/get-user-balance/)

#### 6.1.2 Moonshot / Kimi OpenPlatform

```http
GET https://api.moonshot.ai/v1/users/me/balance
Authorization: Bearer <MOONSHOT_API_KEY>
```

响应可区分可用余额、现金与代金券。必须在 UI 中写成“Kimi API 余额”，不能与 Kimi Code 会员 `/usage` 合并。[官方文档](https://platform.kimi.ai/docs/api/balance)

#### 6.1.3 SiliconFlow

```http
GET https://api.siliconflow.cn/v1/user/info
Authorization: Bearer <SILICONFLOW_API_KEY>
```

可返回 `balance`、`chargeBalance`、`totalBalance`、账户状态。账单明细与更完整限流仍以控制台为主。

- [User Info API](https://siliconflow.readme.io/reference/user-info)
- [官方 OpenAPI 描述](https://github.com/siliconflow/siliconcloud/blob/main/openapi.yaml)
- [Rate Limits](https://docs.siliconflow.cn/en/userguide/rate-limits/rate-limit-and-upgradation)

#### 6.1.4 MiniMax

```http
GET https://www.minimaxi.com/v1/token_plan/remains
Authorization: Bearer <MINIMAX_API_KEY>
```

该接口查询 Token Plan 剩余量，不应被解释为所有 PAYG 账户的现金余额。[Token Plan FAQ](https://platform.minimaxi.com/docs/token-plan/faq)

#### 6.1.5 智谱 GLM

Coding Plan 提供官方 `/glm-plan-usage:usage-query` 插件，可查询套餐用量，但未发现一个适用于普通模型 Key 的通用现金余额 REST API。

- [Usage Query 插件](https://docs.bigmodel.cn/cn/coding-plan/extension/usage-query-plugin)
- [Coding Plan FAQ](https://docs.bigmodel.cn/cn/coding-plan/faq)
- [API 错误码](https://docs.bigmodel.cn/cn/faq/api-code)

#### 6.1.6 阿里云百炼 / DashScope

必须区分：

1. **模型 API Key**：调用 DashScope/百炼推理，不等于云账单凭证。
2. **Coding Plan**：文档说明只展示整体套餐用量，未提供逐模型 token 消费。
3. **阿里云 BSS OpenAPI**：`QueryAccountBalance`、账单查询等，需要独立 RAM AccessKey/Secret。

因此 Codexling 不应要求用户粘贴阿里云主账号 AccessKey。若未来接入，只接受最小权限 RAM 子账号凭证，并将其标为“云账单管理凭证”。

- [Coding Plan](https://help.aliyun.com/zh/model-studio/coding-plan)
- [Coding Plan FAQ](https://help.aliyun.com/zh/model-studio/coding-plan-faq)
- [模型用量统计](https://help.aliyun.com/zh/model-studio/model-usage-statistics)
- [QueryAccountBalance](https://help.aliyun.com/en/user-center/developer-reference/api-queryaccountbalance)
- [BSS OpenAPI](https://help.aliyun.com/en/user-center/developer-reference/api-bssopenapi-2017-12-14-overview)

#### 6.1.7 腾讯云、火山方舟、百度千帆

- 腾讯云 TokenHub 控制台支持按套餐/API Key 看用量并配置 Key 限额，但本轮未找到普通 bearer Key 的余额 API：
  [TokenHub 文档](https://cloud.tencent.com/document/product/1823/130661)、
  [API Key 管理](https://intl.cloud.tencent.com/document/product/1300/78949)。
- 火山方舟在控制台提供 token 用量统计和 Coding Plan 剩余量，未找到 Ark 推理 Key 可直接调用的余额接口：
  [用量统计](https://www.volcengine.com/docs/82379/1159199?lang=zh)。
- 百度千帆部分服务存在 BCE 签名的配额 API，但这不等于普通模型 Key 的通用余额接口：
  [配额 API 示例](https://cloud.baidu.com/doc/qianfan-api/s/qm9lc22zh)。

### 6.2 国外 Provider

| Provider | 普通推理 Key 查余额 | 管理 API | 用量/限流 | 综合 |
|---|---|---|---|---|
| OpenRouter | **A**：当前 Key 的 usage、limit、remaining | A：Management Key 查 credits | A：response cost + Key usage | 首期，最完整 |
| OpenAI API | 未发现普通项目 Key 的预付余额接口 | **A**：Admin Key 查 organization usage/costs | A：单请求 usage；Dashboard | 二期管理模式 |
| Anthropic API | 未发现普通推理 Key 的 credit balance API | **A**：Admin Key 查 usage/cost | A：单请求 usage | 二期管理模式 |
| Mistral API | 未发现普通推理 Key 的余额 API | **A**：Admin Key 查 usage、spend/rate limits | A | 二期管理模式 |
| xAI | 普通推理 Key 不查账单 | **A**：Management Key 查余额、历史用量、spend limits | A；控制台 rate limits | 二期管理模式 |
| Google Gemini API | C：AI Studio Billing 页面 | B：Cloud Service Usage/Monitoring，需 OAuth/IAM | A：单请求 usage；rate limit 以项目计 | 控制台/云 IAM |
| Groq | C：Console Usage/Billing | 未发现公开 billing API | **A**：每次响应含 remaining/reset headers | 限流可首期，余额不行 |
| Together AI | C：Billing 页面看 credits/cost | 未发现公开 credits API | **A**：推理响应含动态限流 headers | 限流可首期，余额不行 |

#### 6.2.1 OpenRouter

当前 Key：

```http
GET https://openrouter.ai/api/v1/key
Authorization: Bearer <OPENROUTER_API_KEY>
```

可返回：

- daily/weekly/monthly usage
- `limit`
- `limit_remaining`
- reset/expiry
- BYOK usage

组织 credits：

```http
GET https://openrouter.ai/api/v1/credits
Authorization: Bearer <OPENROUTER_MANAGEMENT_KEY>
```

普通响应还提供 token 和 cost 记账信息。

- [Get current key](https://openrouter.ai/docs/api/api-reference/api-keys/get-current-key)
- [Get credits](https://openrouter.ai/docs/api/api-reference/credits/get-credits)
- [Usage accounting](https://openrouter.ai/docs/cookbook/administration/usage-accounting)

#### 6.2.2 OpenAI API

OpenAI 公共 Administration API 提供 organization usage 与 costs，例如：

```text
GET /organization/usage/completions
GET /organization/costs
```

可以按 API Key、project、model、user 等聚合，但应使用具备权限的 Admin API Key。普通 project inference key 不应被假定可用。公开文档没有给出普通项目 Key 的“剩余预付余额”接口。

- [Organization Usage API](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage)
- [API Usage Dashboard](https://help.openai.com/en/articles/10478918-api-usage-dashboard)
- [单请求 token usage](https://help.openai.com/en/articles/6614209-how-do-i-check-my-token-usage)

另需强调：OpenAI API 账单与 ChatGPT/Codex 订阅不是同一账本。

#### 6.2.3 Anthropic

Anthropic Admin API 可查询 Messages Usage Report，需要独立 `ANTHROPIC_ADMIN_KEY`，可按 API key、workspace、model 等聚合；credit balance 主要仍在 Console Billing 中。

- [Messages Usage Report](https://docs.anthropic.com/zh-CN/api/admin-api/usage-cost/get-messages-usage-report)
- [API Billing](https://support.anthropic.com/en/articles/8977456-how-do-i-pay-for-my-api-usage)
- [Cost and usage reporting](https://support.anthropic.com/en/articles/9534590-cost-and-usage-reporting-in-console)

#### 6.2.4 Mistral

Mistral Admin API 是较完善的管理面：

```http
GET https://api.mistral.ai/v1/admin/usage
GET https://api.mistral.ai/v1/admin/spend-limit
GET https://api.mistral.ai/v1/admin/rate-limit
x-api-key: <MISTRAL_ADMIN_KEY>
```

它能查组织账期消费、月度 spend limit、每模型限流，但要求 Backoffice 创建的 Admin API Key，不是普通推理 Key。[官方文档](https://docs.mistral.ai/admin/admin-api/usage-metrics)

#### 6.2.5 xAI

xAI 有独立 `https://management-api.x.ai`：

```text
GET  /v1/billing/teams/{team_id}/prepaid/balance
POST /v1/billing/teams/{team_id}/usage
GET  /v1/billing/teams/{team_id}/postpaid/spending-limits
```

它需要带 billing/management 权限的 **Management Key**。普通 `api.x.ai` 推理 Key 不可替代。控制台也能查看 prepaid credits、Usage Explorer 和当前模型速率层级。

- [Management API 概览](https://docs.x.ai/developers/rest-api-reference/management)
- [Billing Management API](https://docs.x.ai/developers/rest-api-reference/management/billing)
- [Billing 控制台](https://docs.x.ai/console/billing)
- [Usage Explorer](https://docs.x.ai/console/usage)
- [Rate Limits](https://docs.x.ai/developers/rate-limits)

#### 6.2.6 Google Gemini API / Vertex AI

- Gemini API Key 的账务按 Google Cloud project/account 管理，Key 本身没有独立余额。
- AI Studio Billing 页管理预付余额和交易。
- 配额按 project 而不是单个 Key 计算。
- Cloud Service Usage 与 Monitoring API 能程序化读取部分 quota/metric，但需要 Google OAuth/IAM，不接受普通 Gemini API Key。

- [Gemini API Billing](https://ai.google.dev/gemini-api/docs/billing)
- [Gemini API Rate Limits](https://ai.google.dev/gemini-api/docs/rate-limits)
- [Service Usage quota metrics API](https://docs.cloud.google.com/service-usage/docs/reference/rest/v1beta1/services.consumerQuotaMetrics/list)
- [Cloud Monitoring metrics](https://docs.cloud.google.com/monitoring/api/metrics_gcp_d_h)

#### 6.2.7 Groq

- 用量与账单主要在 Groq Console。
- 每次 API 响应都会返回 rate-limit headers，包括 request/token limit、remaining 与 reset。
- spend limit 是组织级，控制台数据约有 10–15 分钟延迟。
- 本轮未发现公开的余额/账单 REST API。

- [Billing FAQ](https://console.groq.com/docs/billing-faqs)
- [Spend Limits](https://console.groq.com/docs/spend-limits)
- [Rate-limit headers](https://console.groq.com/docs/rate-limits)

#### 6.2.8 Together AI

- credits、余额、历史成本在 Billing 控制台。
- 每次 serverless inference 响应返回当前模型动态 rate limit、usage 与 reset headers。
- 成本分析可按 product、project、API key 分组，但本轮未发现公开 credits API。

- [Credits](https://docs.together.ai/docs/billing-credits)
- [Usage limits & analytics](https://docs.together.ai/docs/billing-usage-limits)

### 6.3 第三方 API Key 额度能力成熟度

### 第一档：普通推理 Key 即可提供有用额度

- DeepSeek
- Moonshot/Kimi API
- SiliconFlow
- OpenRouter（当前 Key 范围）
- MiniMax Token Plan（仅套餐剩余量）

这些可以在 Codexling 中做“添加 Key → 立即验证 → 展示余额/限额”，不要求额外管理凭证。

### 第二档：需要独立 Admin/Management Key

- OpenAI
- Anthropic
- Mistral
- xAI
- OpenRouter 组织 credits

这类适合新增一个明确的“组织管理连接”流程。不能偷偷把推理 Key 当管理 Key，也不能默认请求写权限。

### 第三档：需要云 IAM

- 阿里云 BSS / 百炼
- Google Cloud / Vertex
- 腾讯云账单体系
- 火山引擎账单体系
- 百度智能云账单/配额体系

这是完整的云账号接入，不是简单 BYOK。安全、权限、签名 SDK、企业合规成本都更高，建议后置。

### 第四档：控制台为主

- Groq 余额/消费
- Together AI credits/消费
- Gemini AI Studio 余额
- Cursor、Qoder 等个人订阅额度
- 多数国内 IDE Agent 订阅

Codexling 可以提供“打开官方 Usage 页面”和本地请求记账，不应把网页抓取包装成稳定 API。

## 7. 建议架构

### 7.1 四个独立适配协议

```swift
protocol AgentAdapter {
    func discoverInstallations() async -> [AgentInstallation]
    func observeSessions() -> AsyncStream<AgentSessionEvent>
    func launch(_ request: AgentLaunchRequest) async throws
}

protocol AgentIdentityAdapter {
    func connectionState() async -> ConnectionState
    func beginOfficialLogin() async throws
    func logout() async throws
}

protocol QuotaAdapter {
    func snapshot() async throws -> QuotaSnapshot
}

protocol PetStateAdapter {
    func map(_ event: AgentSessionEvent) -> PetActivity
}
```

`QuotaAdapter` 必须带来源与可信度：

```swift
struct QuotaSnapshot {
    let balance: Money?
    let grantedBalance: Money?
    let usedCost: Money?
    let tokenUsage: TokenUsage?
    let rateLimits: [RateLimitWindow]
    let period: DateInterval?
    let fetchedAt: Date
    let source: QuotaSource
    let reliability: Reliability
    let scope: QuotaScope
}
```

其中：

- `source`：officialAPI、officialCLI、dashboard、localEstimate
- `scope`：session、apiKey、project、organization、subscription
- `reliability`：A/B/C/D

这样 UI 不会把“本地估算 $12”显示成“官方余额 $12”。

### 7.2 Provider 与 Agent 解耦

示例：

```text
Qwen Code
  ├─ AgentAdapter: QwenCodeAdapter
  ├─ Identity: Qwen Code / ModelStudio
  └─ Provider: DeepSeek API Key
        └─ QuotaAdapter: DeepSeekBalanceAdapter
```

用户在 Qwen Code 中使用 DeepSeek Key 时：

- Pet 状态来自 Qwen Code hooks/SDK。
- 登录状态来自 Qwen Code。
- 余额来自 DeepSeek `/user/balance`。
- 不能显示为“Qwen 剩余余额”。

### 7.3 UI 分区

建议把菜单分为：

1. **Agents**
   - 是否安装
   - 登录状态
   - 当前任务状态
   - Pet
2. **Subscriptions**
   - Codex、Kimi Code、Qoder、Copilot 等订阅用量
   - 数据来源标签
3. **API Providers**
   - Key 有效性
   - 余额/套餐
   - 本期消费
   - RPM/TPM
4. **Connections**
   - Inference Key
   - Admin/Management Key
   - Cloud IAM
   - 权限与最后使用时间

每个数值旁显示来源：

```text
¥42.80 available · Official API · updated 2m ago
$18.20 used · Local estimate · since Jul 1
TPM 17,997 / 18,000 · Response header · resets in 8s
```

### 7.4 刷新和降级

- 余额 API：用户打开菜单时刷新；后台 5–15 分钟一次。
- Admin usage：15–60 分钟，尊重 Provider 延迟和请求成本。
- rate-limit headers：随推理请求被动更新，不额外制造探测请求。
- 429/余额不足：立即更新健康状态，但不把错误当精确余额。
- API 不可用：保留上次成功值并显示时间，不回退到抓网页。
- 文本 CLI 解析：必须带版本探测和 feature flag。

## 8. 落地优先级

### Phase 1：高价值、低风险

### Agent

- Kimi Code：ACP/Web
- Qoder：ACP/SDK
- CodeBuddy：hooks/stream-json
- Qwen Code：hooks/headless
- iFlow：hooks

### Provider

- DeepSeek balance
- Moonshot balance
- SiliconFlow user info
- OpenRouter current key
- Groq/Together rate-limit headers

### Pet

- 把 Codex Pet 状态机抽成通用协议
- 使用 hooks/ACP 事件，不读取对话正文

### Phase 2：官方管理面

- Claude Code Agent SDK/hooks
- GitHub Copilot CLI hooks 与组织 metrics
- OpenAI Admin Usage/Costs
- Anthropic Admin Usage
- Mistral Admin Usage/Limits
- xAI Management Billing
- MiniMax Token Plan
- GLM Usage Query

### Phase 3：云 IAM 与封闭产品

- Google Cloud/Vertex quota
- 阿里云 BSS、腾讯云、火山、百度云管理 API
- Cursor、TRAE、通义灵码、Comate 的弱集成
- 控制台深链和本地估算

## 9. 风险与边界

1. **非公开接口风险**：Codexling 当前使用的部分 ChatGPT/Codex endpoint 随时可能改变，应隔离在单独 adapter，失败不能影响菜单主进程。
2. **OAuth 合规风险**：Gemini CLI 已明确不允许第三方工具搭便车其 OAuth；其他产品即使技术上能读 token，也不代表被授权。
3. **管理凭证风险**：Admin/Management/Cloud IAM key 通常能看全组织账单，风险远高于推理 Key。
4. **口径风险**：余额、grant、月 spend limit、订阅消息数、TPM 是五种不同指标。
5. **延迟风险**：控制台和账单 API 常有分钟到小时级延迟，本地 response usage 反而更实时但不是权威账单。
6. **共享范围风险**：很多 Provider 按 organization/project 计费或限流，不按单 Key。UI 必须显示 scope。
7. **版本风险**：CLI slash command 和文本输出不是协议；每个适配器应记录已验证版本并可远程/本地关闭。
8. **隐私风险**：Pet 只需要状态，不需要 prompt、文件名、命令参数或模型输出。

## 10. 最终产品建议

Codexling 不应演变成“把每家 Agent 私有接口都抓一遍”的聚合器，而应定位成：

> 一个在 macOS 菜单栏统一呈现 Agent 活动、身份连接、订阅与 API 预算，并用 Pet 将机器状态可视化的本地控制面。

产品上应坚持：

- **Pet 是统一表现层**：只有 Codex 提供原生素材协议，但所有 Agent 都可驱动。
- **登录是官方委托层**：CLI/SDK 能做就委托，不能做就深链。
- **额度是独立 Provider 层**：Agent 订阅和 BYOK 余额分开。
- **数据带来源和 scope**：不制造“精确但错误”的剩余额度。
- **安全默认值保守**：普通 Key 优先；管理 Key 显式 opt-in；云主账号凭证默认拒绝。

## 11. 参考资料索引

### 国外

- OpenAI：[Organization Usage](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage)、[Usage Dashboard](https://help.openai.com/en/articles/10478918-api-usage-dashboard)
- Anthropic：[Claude Code](https://docs.anthropic.com/en/docs/claude-code/getting-started)、[Admin Usage](https://docs.anthropic.com/zh-CN/api/admin-api/usage-cost/get-messages-usage-report)
- Google：[Gemini Billing](https://ai.google.dev/gemini-api/docs/billing)、[Gemini Rate Limits](https://ai.google.dev/gemini-api/docs/rate-limits)、[Gemini CLI](https://github.com/google-gemini/gemini-cli)
- GitHub：[Copilot CLI Auth](https://docs.github.com/en/enterprise-cloud@latest/copilot/how-tos/copilot-cli/set-up-copilot-cli/authenticate-copilot-cli)、[Hooks](https://docs.github.com/en/copilot/reference/hooks-reference)、[Metrics](https://docs.github.com/en/copilot/reference/copilot-usage-metrics/copilot-usage-metrics)
- OpenRouter：[Current Key](https://openrouter.ai/docs/api/api-reference/api-keys/get-current-key)、[Credits](https://openrouter.ai/docs/api/api-reference/credits/get-credits)
- Mistral：[Admin Usage](https://docs.mistral.ai/admin/admin-api/usage-metrics)
- xAI：[Management API](https://docs.x.ai/developers/rest-api-reference/management)、[Billing API](https://docs.x.ai/developers/rest-api-reference/management/billing)
- Groq：[Billing](https://console.groq.com/docs/billing-faqs)、[Rate Limits](https://console.groq.com/docs/rate-limits)
- Together AI：[Credits](https://docs.together.ai/docs/billing-credits)、[Usage](https://docs.together.ai/docs/billing-usage-limits)

### 国内

- Kimi Code：[CLI](https://www.kimi.com/code/docs/en/kimi-code-cli/reference/kimi-command.html)、[会员](https://www.kimi.com/code/docs/en/kimi-code/membership.html)
- Moonshot API：[余额](https://platform.kimi.ai/docs/api/balance)
- Qoder：[认证](https://docs.qoder.com/en/cli/sdk/authentication)、[ACP](https://docs.qoder.com/en/cli/acp)、[Credits](https://docs.qoder.com/Credits)
- CodeBuddy：[SDK](https://www.codebuddy.ai/docs/cli/sdk)、[CLI](https://www.codebuddy.ai/docs/cli/cli-reference)、[Hooks](https://www.codebuddy.ai/docs/cli/hooks)
- Qwen Code：[认证](https://qwenlm.github.io/qwen-code-docs/zh/users/configuration/auth/)、[Hooks](https://qwenlm.github.io/qwen-code-docs/en/users/features/hooks/)、[SDK](https://qwenlm.github.io/qwen-code-docs/en/developers/sdk-typescript/)
- iFlow：[快速开始](https://platform.iflow.cn/cli/quickstart)、[Hooks](https://platform.iflow.cn/cli/examples/hooks)
- DeepSeek：[余额](https://api-docs.deepseek.com/zh-cn/api/get-user-balance/)
- SiliconFlow：[User Info](https://siliconflow.readme.io/reference/user-info)、[Rate Limits](https://docs.siliconflow.cn/en/userguide/rate-limits/rate-limit-and-upgradation)
- MiniMax：[Token Plan](https://platform.minimaxi.com/docs/token-plan/faq)
- 智谱 GLM：[Usage Query](https://docs.bigmodel.cn/cn/coding-plan/extension/usage-query-plugin)
- 阿里云百炼：[Coding Plan](https://help.aliyun.com/zh/model-studio/coding-plan)、[用量统计](https://help.aliyun.com/zh/model-studio/model-usage-statistics)
- 腾讯云：[TokenHub](https://cloud.tencent.com/document/product/1823/130661)
- 火山方舟：[用量统计](https://www.volcengine.com/docs/82379/1159199?lang=zh)
- 百度：[Comate](https://cloud.baidu.com/doc/COMATE/s/Tmjznlabr)、[千帆配额 API 示例](https://cloud.baidu.com/doc/qianfan-api/s/qm9lc22zh)
