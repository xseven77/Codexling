# Codexling 状态栏 Pets 方案与实现

## 1. 目标

Codexling 在原有额度摘要之外，直接在 macOS 状态栏展示与 Codex 相同格式的动画 Pet，并通过 Pet 动画、状态文字和悬停浮层表达当前 Codex 执行情况。

本功能包含：

- 兼容 Codex 内置 Pet 与 `~/.codex/pets` 自定义 Pet。
- 设置页发现、预览、选择、刷新和持久化 Pet。
- 设置页将自动刷新置于状态栏配置之前，并以横向分隔线区分两个配置区域。
- 按 Codex spritesheet 原始帧时长播放动画。
- 根据本地 Codex 任务事件显示空闲、思考、执行、检查、等待确认、完成和中止状态。
- 活动文件默认只读末尾 4 MB；若窗口内没有任务开始/完成/中止事件，则按需向前扩展，避免长任务把 `task_started` 挤出读取窗口后被误判为空闲。
- 鼠标悬停状态栏时显示当前执行情况文案和活跃任务数。
- 状态栏 hover 卡片使用 120ms 触发延迟，在过滤快速掠过的同时减少等待感。
- macOS 26 及以上的悬停卡片使用系统原生 `glassEffect`；旧系统回退到 `ultraThinMaterial`。透明承载面板不再叠加实色卡片。左侧 Pet 直接融入整块玻璃并同步播放动画，不使用独立灰色背景；右侧展示执行状态与活跃任务数。
- 活跃时右侧优先显示 Codex 线程标题与最新的用户可见执行摘要，效果对应 Codex 的“任务标题 · 当前步骤”；空闲或数据不可用时回退到通用状态文案。
- 状态栏不再设置系统 tooltip，避免它与自定义悬停卡片重复或互相遮挡。
- Pet 开关只控制胶囊左侧指示物：开启时显示动画 Pet，关闭或 Pet 不可用时显示原有额度健康圆灯；胶囊背景、任务状态与额度摘要不受开关影响。
- 状态栏按钮启用紧凑图文布局，Pet 与执行/额度文字之间使用一个受控细空格。
- Pet 模式使用轻量半透明圆角胶囊；Pet 已承担产品识别，因此状态文字省略重复的 `Codex` 前缀：执行时显示“思考中 · 周 8%”一类摘要，空闲时只显示额度。
- 胶囊背景提供 `automatic`、`neutral`、`blue`、`purple`、`cyan`、`amber`、`green`、`red` 枚举。自动模式映射为空闲中性、思考紫、执行蓝、检查青、等待橙、完成绿、中止红；设置页也可以选择固定颜色覆盖自动映射。
- 胶囊背景的默认值为 `neutral`，并在设置菜单中排在第一项；`automatic` 排在第二项。已有持久化选择保持不变。
- 状态栏背景使用约 88–90% 不透明度的高饱和状态色、细白描边和极轻投影；鲜明底色与白色 Pet 瓷片形成稳定对比。不在 `NSStatusBarButton` 内嵌视觉材质视图，避免 AppKit 合成层遮住按钮内容。
- 动画 Pet 在状态栏中合成到 20pt、7pt 连续圆角的半透明白色小瓷片上，并保留极轻阴影；整体背景同步使用 7pt 连续圆角，不再使用大胶囊轮廓。Pet 画布收窄到 23pt，并移除额外的标题前导空格，让左右 padding 更均衡。悬停弹窗仍使用无独立背景的原始 Pet 帧。
- 状态项采用自绘内容布局，绕开 `NSStatusBarButton` 强制的左右内容边距：Pet 左侧与 Pet 顶部保持 0.5pt 的紧凑起点，文字右侧单独保留 5pt 呼吸空间，Pet 与文字固定间隔 3pt，并按当前状态文案宽度动态计算状态项长度。
- 禁用 `NSStatusBarButton` 默认的大胶囊按压高亮；点击态由自绘视图以同样的 R7 轮廓叠加 16% 白色高光，避免点击前后圆角跳变。
- 自绘视图使用 `NSClickGestureRecognizer` 触发原有 popover action，按下/释放事件只维护视觉状态；同时实现 accessibility press，避免覆盖系统按钮后点击事件丢失。
- 状态与额度之间使用细空格包围中点，减少等宽字体造成的松散占位。

## 2. 已确认的 Codex Pet 来源

### 2.1 内置 Pet

当前 macOS 版本的 Codex 已合入 ChatGPT 应用：

```text
/Applications/ChatGPT.app
CFBundleIdentifier = com.openai.codex
```

动画资产位于：

```text
/Applications/ChatGPT.app/Contents/Resources/app.asar
└── /webview/assets/*-spritesheet-*.webp
```

当前版本确认包含 9 个内置 Pet：

| ID | 显示名 |
|---|---|
| `codex` | Codex |
| `dewey` | Dewey |
| `fireball` | Fireball |
| `hoots` | Hoots |
| `null-signal` | Null Signal |
| `rocky` | Rocky |
| `seedy` | Seedy |
| `stacky` | Stacky |
| `bsod` | BSOD |

Codexling 不修改 Codex/ChatGPT 安装包。启动时只读取 ASAR 目录索引，将命中的 WebP 条目原样提取到：

```text
~/Library/Application Support/Codexling/Pets/<Codex 版本>/
```

缓存按 Codex 版本隔离。Codex 升级后会读取新版本目录，不复用旧图集。

为兼容旧安装方式，发现器也检查：

```text
/Applications/Codex.app
~/Applications/ChatGPT.app
~/Applications/Codex.app
NSWorkspace 中 bundle id 为 com.openai.codex 的应用
```

### 2.2 自定义 Pet

自定义 Pet 读取 Codex 官方使用的本地结构：

```text
~/.codex/pets/<pet-id>/
├── pet.json
└── spritesheet.webp
```

manifest 示例：

```json
{
  "id": "my-pet",
  "displayName": "My Pet",
  "description": "A custom Codex pet.",
  "spriteVersionNumber": 2,
  "spritesheetPath": "spritesheet.webp"
}
```

发现器会校验 manifest、文件存在性、图集宽度、单元格高度和行数。损坏或不兼容的目录不会进入设置页。

## 3. 动画契约

Codex v2 Pet 使用固定规格：

```text
图集：1536 × 2288
布局：8 列 × 11 行
单元格：192 × 208
spriteVersionNumber：2
```

标准状态行：

| 行 | 状态 | 使用列 | 帧时长 |
|---:|---|---:|---|
| 0 | `idle` | 0–5 | 280、110、110、140、140、320 ms |
| 1 | `running-right` | 0–7 | 120 ms，末帧 220 ms |
| 2 | `running-left` | 0–7 | 120 ms，末帧 220 ms |
| 3 | `waving` | 0–3 | 140 ms，末帧 280 ms |
| 4 | `jumping` | 0–4 | 140 ms，末帧 280 ms |
| 5 | `failed` | 0–7 | 140 ms，末帧 240 ms |
| 6 | `waiting` | 0–5 | 150 ms，末帧 260 ms |
| 7 | `running` | 0–5 | 120 ms，末帧 220 ms |
| 8 | `review` | 0–5 | 150 ms，末帧 280 ms |
| 9–10 | 16 个注视方向 | 0–7 | 22.5° 步进 |

Codexling 的播放器与 Codex 当前播放器保持一致：

- 非空闲状态动画连续播放三遍，然后进入慢速 idle 循环。
- idle 每帧时长放大 6 倍，减少菜单栏视觉干扰。
- macOS 开启“减少动态效果”后只显示当前状态首帧。
- v1 9 行图集仍可播放标准状态；v2 额外保留方向帧兼容空间。

## 4. Codex 活动状态来源

当前没有公开稳定的 Codex Pets/任务状态 API。本实现使用独立 Provider 只读观察 Codex 本地数据，并与 UI、动画解耦。

线程索引读取：

```text
~/.codex/state_5.sqlite
~/.codex/sqlite/state_5.sqlite
```

从 `threads.rollout_path` 获取最近未归档线程的 JSONL。只解析以下事件元数据：

- `task_started`
- `task_complete`
- `turn_aborted`
- 用户可见的 `agent_message`，且 `phase = commentary`
- 工具调用名称、调用 ID 与结束事件

不会读取或展示模型内部 reasoning，也不会展示工具原始参数、完整命令、用户提示词、Token 或环境变量。

### 4.1 状态归并

| 本地事件 | Codexling 状态 | Pet 动画 |
|---|---|---|
| 无活动 | 空闲 | `idle` |
| `task_started` / reasoning | 思考中 | `running` |
| 工具调用未结束 | 工作中 | `running` |
| 图像/结果检查 | 检查中 | `review` |
| `request_user_input` / 提权确认 | 等待确认 | `waiting` |
| `task_complete` | 已完成，保留 20 秒 | `waving` |
| `turn_aborted` | 已中止 | `failed` |

多任务优先级：

```text
等待用户 > 正在执行 > 正在检查 > 正在思考 > 中止 > 完成 > 空闲
```

本地格式将来发生变化时，Provider 返回 `unavailable`，Pet 回退 idle，额度功能不受影响。

## 5. 状态栏与悬停交互

状态栏格式：

```text
[Pet] Codex · 周 19%
[Pet] Codex 工作中 · 周 19%
[Pet] Codex 等待确认 · 周 19%
[Pet] Codex 已完成 · 周 19%
```

Pet 关闭或加载失败时回退：

```text
● Codex 周 19%
```

状态栏按钮保留原有点击行为，点击仍打开用量弹窗。

鼠标悬停 220 ms 后显示非激活式 `NSPanel`：

```text
Codex 正在工作
正在运行本地命令
1 个活跃任务
```

悬停面板：

- 不抢键盘焦点。
- 不阻断状态栏点击。
- 点击状态栏前自动关闭。
- 同步提供系统 tooltip 作为无障碍和降级路径。
- 文案优先使用用户已可见的 commentary；否则显示经过映射的通用工具状态。

## 6. 设置页

设置页新增“状态与 Pets”区域，其中“胶囊背景色”位于 Pet 开关之前：

- 显示/关闭动画 Pet；该开关只切换动画 Pet 与额度健康圆灯。
- 无论动画是否开启，都显示任务状态、额度摘要和配置的胶囊背景。
- 展示当前 Pet 首帧、名称、来源、版本和动画行数。
- 按“Codex 内置 / 自定义”分组选择。
- 显示两类 Pet 的发现数量。
- “重新扫描”用于 Codex 更新或新增自定义 Pet 后刷新。

持久化键：

```text
codexling.petsEnabled
codexling.selectedPetID
```

## 7. 代码结构

```text
Sources/Codexling/
├── PetModels.swift
│   ├── CodexPetCatalog
│   ├── AsarArchive
│   ├── PetSpriteSheet
│   ├── PetAnimationContract
│   └── PetAnimationPlayer
├── CodexActivity.swift
│   ├── CodexActivityEventParser
│   ├── CodexActivityService
│   └── CodexActivityStore
├── StatusBarController.swift
│   ├── 状态栏 Pet 帧渲染
│   ├── StatusHoverTrackingView
│   └── PetHoverPanelController
├── AppSettings.swift
└── SettingsViews.swift
```

## 8. 风险和边界

### ASAR 属于安装包内部格式

内置 Pet 文件名和打包位置可能随 Codex 更新变化。发现器不依赖哈希文件名，只按标准 spritesheet 前缀搜索，并校验最终图集尺寸。读取失败时不影响自定义 Pet 和额度功能。

### 本地活动数据库不是公开 API

SQLite 表名和 rollout 事件可能变化，因此所有读取都集中在 `CodexActivityService`。解析异常只会使状态变成不可用，不会修改 Codex 数据。

### 版权与分发

Codexling 不把 Codex 内置 Pet 放入自身安装包，也不上传或重新发布这些资产。只有用户本机已经安装 Codex/ChatGPT 时，才从本机安装包只读提取到个人缓存供本机显示。

## 9. 验证要求

自动验证覆盖：

- Codex v2 动画行、帧数和帧时长。
- 等待用户和任务完成状态解析。
- ASAR 索引和文件提取。
- 从当前安装的 ChatGPT/Codex 中发现全部 9 个内置 Pet。
- Debug/Release 构建。
- `.app`、`.zip`、`.dmg` 打包与 codesign 校验。
- 启动打包后的 `.app`，检查设置页选择、状态栏动画和悬停状态。
