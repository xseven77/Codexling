# Codexling 当前实现方案

## 1. 产品形态

Codexling 是一个 macOS 状态栏应用，把 Codex 的任务活动、当前 Pet 和 ChatGPT Codex 额度集中到一个本地 companion dashboard。

状态栏使用两个独立信号：

- 前置圆灯：Codex 任务状态。
- 胶囊背景：额度健康度或用户选择的固定颜色。

点击胶囊只打开独立窗口。鼠标悬停会显示不抢焦点的 Pet 活动卡片；当前实现没有状态栏用量 popover。

独立窗口包含：

- 当前账号、工作区、套餐及订阅周期（可读取时）。
- 当前任务、并行任务数量和截断后的状态摘要。
- 当前 Pet 动画与“今天一起工作”累计时间。
- 主额度与次级额度、重置时间和重置券。
- 刷新、官方 Usage/Billing 链接、设置、退出登录与退出应用。

## 2. 运行架构

```text
AppDelegate
├── CodexUsageService
│   ├── OAuth PKCE + localhost callback
│   ├── /backend-api/wham/usage
│   ├── /backend-api/wham/rate-limit-reset-credits
│   └── /backend-api/subscriptions
├── UsageSnapshotStore
│   └── latest_snapshot.json
├── CodexActivityStore
│   └── state_5.sqlite → rollout JSONL（只读）
├── AppSettingsStore
│   ├── UserDefaults
│   └── Codex Pet 选择双向同步
├── PetFrameStore
├── CompanionStatsStore
│   └── companion_stats.json
├── StatusBarController
└── DetachedWindowController
```

状态栏由 AppKit `NSStatusItem` 和自绘 `StatusCapsuleView` 实现。主窗口与设置页使用 SwiftUI，并由 `DetachedWindowController` 管理固定 dashboard 尺寸、按内容测量的设置页尺寸和窗口置顶。

## 3. 登录与凭据

1. App 生成 OAuth PKCE `state`、`verifier` 和 `challenge`。
2. 系统浏览器打开 OpenAI 官方授权页。
3. 本地 listener 在 `http://localhost:1455/auth/callback` 校验回调。
4. App 交换并按需刷新 access/refresh token。
5. token 写入：

   ```text
   ~/Library/Application Support/Codexling/oauth_token.json
   ```

   文件权限设为 `0600`。旧版 Keychain token 只用于一次性迁移，迁移后会删除。

本应用不读取浏览器 Cookie，不保存密码或 MFA code，也不绕过 SSO、MFA、Cloudflare 或组织策略。

## 4. 用量与订阅数据

| 端点 | 用途 | 失败行为 |
|---|---|---|
| `GET /backend-api/wham/usage` | 主/次级额度、套餐、工作区 | 本次刷新失败，保留上次成功快照 |
| `GET /backend-api/wham/rate-limit-reset-credits` | 可用重置券 | 可选；失败不阻断额度 |
| `GET /backend-api/subscriptions?account_id=…` | `active_until`、`will_renew` | best-effort；失败时不展示订阅周期 |

这些 ChatGPT Web 端点不是公开稳定 API。所有请求和解析集中在 `CodexUsageService` 与 `CodexlingParser`，UI 只消费 `CodexUsageSnapshot`。

额度窗口不再假定一定是固定的“5 小时 / 7 天”：

- `rate_limit.primary_window` 是主额度；按 `limit_window_seconds` 生成实际标签。
- `rate_limit.secondary_window` 是次级额度。
- `limits` 仍作为旧 payload 回退。
- `total == 0` 的窗口视为不可展示；没有次级额度时不会伪造周额度。

## 5. 本地任务活动

`CodexActivityService` 只读检查：

```text
~/.codex/state_5.sqlite
~/.codex/sqlite/state_5.sqlite
```

它从最近未归档线程的 `rollout_path` 读取 JSONL，并将事件归并为：

```text
unavailable / idle / thinking / executing
reviewing / waitingForUser / completed / interrupted
```

Provider 会读取所选 rollout 的 JSONL 尾部，但只把生命周期/推理事件标记、工具名称与调用 ID，以及清理并截断后的用户可见 commentary 映射到 UI 状态。它不会持久化、上传或展示 reasoning 内容、完整提示词、工具原始参数、完整命令、Token 或环境变量。

## 6. Pet 与陪伴统计

- 发现 ChatGPT/Codex 安装包中的内置 spritesheet，以及 `~/.codex/pets` 自定义 Pet。
- Codexling 自带 Pet 资源随 App 打包，但只在用户点击安装后写入 `~/.codex/pets/codexling`。
- 在 Codexling 选择 Pet 会更新 Codex 的 `config.toml`；Codex 侧选择变化也会被文件监控实时同步回来。
- `PetFrameStore` 为主窗口与 hover 卡片提供同一动画帧源。
- `CompanionStatsStore` 每 30 秒结算一次有效活动时长，单次最多计 90 秒，避免系统休眠夸大统计。

## 7. 刷新与缓存

自动刷新可选 30 秒、1/2/5/10 分钟或关闭，默认 1 分钟。启动时如果已有 token 会立即刷新；手动刷新也会立即执行。

```text
~/Library/Application Support/Codexling/
├── oauth_token.json       # 0600
├── latest_snapshot.json
├── companion_stats.json
└── api-probes/            # 仅显式 debug 探测时生成
```

刷新失败不会覆盖上次成功的额度时间；token 无效时清除本地 token 并要求重新授权。当前实现没有指数退避调度。

## 8. 主题与窗口

- macOS 26 的 hover 卡片使用系统 `glassEffect`；macOS 14–15 回退到 material。
- 独立窗口是传统不透明 `windowBackgroundColor`，SwiftUI 根视图使用 `codexBackground`。
- 已登录 dashboard 固定约 `579×510pt`，未登录约 `579×440pt`。
- 设置窗口宽度可在 `579–680pt` 调整，高度按内容测量，最小 `400pt`，上限为当前屏幕 `visibleFrame.height - 32pt`。
- dashboard 可置顶；关闭独立窗口后应用回到仅状态栏模式。

## 9. 打包发布

`package_app.sh` 构建 Release binary，并生成：

```text
dist/Codexling.app
dist/Codexling-<version>.zip
dist/Codexling-<version>.dmg
```

产物使用 ad-hoc codesign，并由脚本校验签名和 DMG 内容。当前没有 Apple notarization。

交互式 GitHub Release 流程见 [`app/Codexling/RELEASE.zh-CN.md`](../app/Codexling/RELEASE.zh-CN.md)。

## 10. 验收基线

- OAuth 登录、refresh token、退出登录和旧 token 迁移可用。
- 主/次级额度、重置券与订阅周期能解析并正确降级。
- 状态栏任务圆灯与额度背景互不混用。
- 多任务、等待确认、完成自动回落、中止状态保留和不可用状态均不影响额度刷新。
- Pet 发现、安装、选择、Codex 双向同步和资源丢失回退可用。
- 陪伴统计跨日清零，休眠间隔封顶。
- dashboard、设置尺寸、主题切换和置顶行为符合当前窗口约束。
- Swift 测试、Release 构建、ZIP/DMG 和 codesign 验证通过。
