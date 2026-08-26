# Codexling 独立 Pet 体系与双向同步架构方案

## 1. 概述与背景

### 1.1 现状与问题分析
在现有设计中，Codexling 的 Pet 发现与加载机制高度耦合于 OpenAI Codex 桌面应用：
1. **强依赖 Codex 宿主**：内置 Pet 依赖动态解析 `/Applications/ChatGPT.app/Contents/Resources/app.asar` 并解压 webp 文件至缓存；自定义 Pet 依赖 `~/.codex/pets/`。
2. **非 Codex 用户体验割裂**：当用户仅使用 DeepSeek、Hermes 或 Antigravity 等 Agent 且未安装 Codex 时，Codexling 的 Pet 列表为空，桌面 Pet 悬浮窗与状态栏流光无法正常展现对应形象。
3. **架构扩展性受限**：Codexling 作为一个支持多 Agent 的独立 macOS 桌面伴侣，核心视觉与伴随体验（Pet）应具备完整的自主性，而非作为单一 Agent 的附属功能。

### 1.2 目标定位
- **完全自主的 Pet 资产与选择权**：Codexling 自身内置全套标准 Pet，并拥有独立的 Pet 存储目录；系统所用 Pet 的选择与渲染 100% 取决于 Codexling 自身。
- **与 Codex 保持生态兼容与双向互通**：在检测到本地安装 Codex 时，自动建立与 `~/.codex/pets` 的增量双向同步，保持与 Codex 社区 Pet 资产的一致性。

---

## 2. 总体架构设计

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ 1. Codexling App Bundle（内置官方标准 Pet 资产，只读）                       │
│    Codexling.app/Contents/Resources/Pets/                                   │
│    ├── Codexling/     (pet.json + spritesheet.webp)                         │
│    ├── Codex/         (pet.json + spritesheet.webp)                         │
│    ├── Dewey/         (pet.json + spritesheet.webp)                         │
│    ├── Fireball/      (pet.json + spritesheet.webp)                         │
│    ├── Hoots/         (pet.json + spritesheet.webp)                         │
│    ├── Null Signal/   (pet.json + spritesheet.webp)                         │
│    ├── Rocky/         (pet.json + spritesheet.webp)                         │
│    ├── Seedy/         (pet.json + spritesheet.webp)                         │
│    ├── Stacky/        (pet.json + spritesheet.webp)                         │
│    └── BSOD/          (pet.json + spritesheet.webp)                         │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │ 1. 扫描加载内置 Pet
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 2. Codexling 本地数据目录（用户自定义 / 导入 / 同步存储，读写）                │
│    ~/Library/Application Support/Codexling/Pets/                            │
│    ├── custom-pet-a/  (用户在 Codexling 中添加的自定义 Pet)                  │
│    └── synced-pet-b/  (从 Codex 反向同步导入的 Pet)                          │
└───────────────────────▲──────────────────────────────▲──────────────────────┘
                        │                              │
         【正向同步】将 Codexling 自定义 Pet            │ 【反向同步】将 Codex 自定义 Pet
         同步写入 ~/.codex/pets/                        │ 同步导入至 Codexling
                        ▼                              │
┌──────────────────────────────────────────────────────┴──────────────────────┐
│ 3. Codex 宿主环境（仅在检测到本地存在 Codex 时参与同步）                       │
│    ~/.codex/pets/                                                           │
│    ~/.codex/config.toml  ([desktop] selected-avatar-id = "...")             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. 核心机制设计

### 3.1 Pet 资产发现与优先级（Discovery & Hierarchy）

Codexling 采用单一、确定的事实来源（Single Source of Truth），所有 UI（菜单栏胶囊、独立桌面 Pet 悬浮窗、主界面 Dashboard、设置面板预览）只从 Codexling 自身 Catalog 获取资产：

1. **第 1 优先级：App 内置标准 Pet（`Bundle.main/Contents/Resources/Pets/`）**
   - 包含 Codexling 专属 Pet 以及 9 款经典 Pet（Codex、Dewey、Fireball、Hoots、Null Signal、Rocky、Seedy、Stacky、BSOD）。
   - 采用标准 `pet.json` + `spritesheet.webp` 规范打包，随 App 发布，开箱即用，免除网络下载与外部应用依赖。
   - 唯一标识为 `builtin:<id>`（如 `builtin:codexling`、`builtin:codex`）。
2. **第 2 优先级：用户自定义与同步 Pet（`Application Support/Codexling/Pets/`）**
   - 存放用户直接导入的 Pet，以及从 `~/.codex/pets/` 反向同步过来的第三方 Pet。
   - 唯一标识为 `custom:<id>`。
3. **选择与持久化**：
   - 选中的 Pet ID 直接保存在 Codexling 的 `UserDefaults`（`codexling.selectedPetID`）。
   - 不再依赖 `~/.codex/config.toml` 作为前置判断依据。

---

### 3.2 双向同步机制（Bidirectional Synchronization）

当且仅当系统检测到本地安装了 Codex（或存在 `~/.codex/` 目录）时，激活后台轻量同步管理服务 `PetBidirectionalSyncManager`：

#### ① 正向同步（Codexling ➔ Codex）
- **触发时机**：
  - Codexling 启动且检测到 Codex 已安装；
  - 用户在 Codexling 中导入或更新自定义 Pet；
  - 用户在 Codexling 中切换选中的 Pet。
- **动作**：
  - 将 Codexling 中的自定义 Pet 增量复制/更新到 `~/.codex/pets/<id>/`。
  - 将当前选中的 Pet 标识同步更新至 `~/.codex/config.toml` 的 `[desktop] selected-avatar-id` 字段（保持两边形象统一）。

#### ② 反向同步（Codex ➔ Codexling）
- **触发时机**：
  - Codexling 启动时初次比对；
  - 本地文件监听器捕获到 `~/.codex/pets/` 目录变动（新增/修改子目录）；
  - 本地文件监听器捕获到 `~/.codex/config.toml` 的选定 Avatar 发生变化。
- **动作**：
  - 扫描 `~/.codex/pets/` 下每个子目录，校验其 `pet.json` 与 `spritesheet.webp` 的有效性。
  - 若该 Pet 不属于 Codexling 内置，且在 `Application Support/Codexling/Pets/` 中不存在或版本更新，自动复制导入至 Codexling 数据目录。
  - 触发 Codexling `availablePets` 列表的静默刷新。

---

### 3.3 防循环与冲突处理策略（Loop Prevention & Conflict Resolution）

为了避免两边文件监听产生“A 同步到 B，B 变动又同步到 A”的死循环：

1. **元数据与内容指纹比对**：
   - 同步复制前先校验目标文件是否存在、文件大小（`fileSize`）以及修改时间（`modificationDate`）。若内容一致则跳过复制，不产生额外 I/O 事件。
2. **内置 Pet 保护**：
   - 内置 Pet（`builtin:*`）具备最高权威，外部同名目录无法覆盖内置资源，防止核心资产被污染。
3. **防抖与静默更新标志**：
   - 使用 `DispatchWorkItem` 施加 300ms 防抖。
   - 在程序主动执行同步写操作时设置 `isInternalSyncInProgress` 信号锁，忽略由自身写入触发的文件变更通知。

---

## 4. 方案可行性对比评估

| 评估指标 | 现有实现（Asar 动态提取 + 依赖 Codex） | 独立 Pet + 双向同步新方案 | 结论 |
| :--- | :--- | :--- | :--- |
| **独立运行能力** | ❌ 强依赖 Codex 桌面端安装 | ✅ 100% 独立运行，零依赖 | **极大提升** |
| **资产加载稳定性** | ⚠️ 解析 Electron asar，结构升级易崩 | ✅ 直接读取标准 Bundle/FS 资源 | **显著增强** |
| **非 Codex Agent 支持** | ❌ DeepSeek / Hermes / Antigravity 用户无 Pet | ✅ 所有 Agent 用户均可享受完整动画与伴侣体验 | **全面覆盖** |
| **Codex 生态互通** | ⚠️ 单向读写 `~/.codex` | ✅ 智能双向对齐，互不影响 | **双向兼容** |
| **包体积影响** | ~0 MB（运行时解压） | + 约 10~15 MB（内置 10 款精灵图 WebP） | **在合理范围** |

---

## 5. 模块改动计划

### 5.1 资源与目录调整
- 在 `app/Codexling/Resources/Pets/` 下建立标准内置 Pet 目录结构：
  - `Codexling/`、`Codex/`、`Dewey/`、`Fireball/`、`Hoots/`、`NullSignal/`、`Rocky/`、`Seedy/`、`Stacky/`、`BSOD/`。
- 每个目录包含标准的 `pet.json` 与 `spritesheet.webp`。

### 5.2 核心代码重构
- **`PetModels.swift`**：
  - 重写 `CodexPetCatalog`：扫描 `Bundle.main` 内置资源与 `Application Support/Codexling/Pets` 用户目录。
  - 新增 `PetBidirectionalSyncManager`：封装正向与反向同步、文件监听及防抖比对逻辑。
  - 清理废弃的 `AsarArchive` 与 `AsarEntry` 相关解包代码。
- **`AppSettings.swift`**：
  - `selectedPetID` 默认以自身持久化配置为主。
  - 在 `reloadPets` 时调度后台双向同步逻辑。
- **`SettingsViews.swift`**：
  - Pet 管理区域展示来源标签（「Codexling 内置」/「自定义 & 已同步」）。
  - 支持直接在设置中添加/导入外部 Pet 文件夹。

### 5.3 自动化测试验证
- 编写 `PetBidirectionalSyncTests.swift`：
  - 独立运行测试：无 Codex 目录时能正确列出并加载所有内置 Pet。
  - 正向同步测试：新建自定义 Pet 能同步至虚拟 Codex 目录。
  - 反向同步测试：虚拟 Codex 目录新增 Pet 能同步回 Codexling 数据目录。
  - 防死循环测试：重复同步不产生多余文件写入与事件风暴。
