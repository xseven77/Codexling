# 文档漂移审计

本轮只把“存在代码演进历史证据”的不一致计作文档漂移。单纯措辞陈旧、但无法由提交历史证明的内容不计入。

## 已确认的演进证据

| 代码演进提交 | 已发生的变化 | 受影响文档与修复 |
|---|---|---|
| `39b0864` | 额度解析改为主/次级窗口，并按实际时长生成标签 | 当前方案与 landing 不再把所有账号硬编码成固定 5 小时/周额度 |
| `e67ce58` | 多任务 companion dashboard、`PetFrameStore`、`CompanionStatsStore` 落地；多线程读取中仅最近线程按生命周期事件向前扩展；状态栏移除 Pet 图片与用量 popover，点击统一打开独立窗口；胶囊背景从任务状态色切换为额度状态色，默认跟随额度 | 更新 Pet/陪伴、活动读取边界、状态栏和 UI 实现记录；移除“可二次开发”“下一步创建 UI”、Pet 状态栏和 popover 选择等规划态文案 |
| `35913da`、`bcc5500` | dashboard 尺寸先调整为约 579pt 宽，随后已登录高度收紧为 510pt | 修正主题与 UI 文档中的 475/760/860pt 旧尺寸 |
| `cdcb5fe`、`a37b449` | 设置页改为内容测量、400pt 最小高度、屏幕上限和受约束缩放 | 重写窗口材质/尺寸说明 |
| `bcc5500` | 状态栏按压反馈从手势/静态高光改为直接鼠标事件、本地事件监听与 Material ripple；可访问性 press 在主队列异步完成 | 修正状态栏交互说明并同步异步点击测试 |
| `ca29220` | subscriptions 产品化；胶囊背景默认值从自动跟随额度改为 `neutral`，`blue`、`purple`、`cyan`、`amber` 等已失效旧原始值按未知值回退为中性背景 | 更新订阅调研；修正默认值和旧任务色回退语义 |
| `6104b1c` | Pet 选择写回 Codex、窗口置顶、任务元数据和随机 Pet 动作 | 更新功能、设置、Pet 和 landing 文案 |
| `1a74b62` | 监听 Codex `config.toml`，原子替换后重新挂载并实时同步 Pet | 更新 Pet 双向同步链路与测试范围 |
| `bad61c9` | DMG 挂载验证增加清理与重试 | 发布文档继续以当前脚本为准；未发现互相矛盾的旧步骤 |

## 初始不一致（不计作文档漂移）

`e397f1c` 的首个仓库快照中，`PROJECT.md` / 方案文档已写着 `MenuBarExtra`、Keychain
和“可 notarize”，但同一提交的源码实际已经使用 `NSStatusItem`、Application Support 的
`0600` token 文件与 ad-hoc codesign。`9bdf1d8` 主要完成 Codex Light → Codexling
重命名及旧路径兼容，并不是这些实现的引入提交。

按本轮“必须由后续代码演进造成”的口径，这组内容不计入漂移数量；当前架构文档仍改为
陈述真实实现，避免继续传播错误的安全与发布边界。

`c36c589` 同一快照中的陪伴方案还把 `completed` 和 `interrupted` 都写成 20 秒后回落，
而源码从引入时起只让 `completed` 在 20 秒后回到 `idle`。这同样不是后续演进造成的
漂移，但当前状态表已按实际行为修正。

审计还发现两条回归测试仍保留旧假设：设置页被限制为 dashboard 的 960pt 上限，以及
可访问性 press 同步完成。它们分别与 `cdcb5fe`、`bcc5500` 的现行实现冲突，已按对应提交
更新断言；产品代码未为迁就旧测试而回退。

## 历史设计稿

以下 HTML 在代码继续演进后不再具备当前规范效力：

- `ui-concepts.html`：冻结于 2026-07-23。
- `settings-concepts.html`：冻结于 2026-07-22。
- `ui-concepts-companion-backup.html`：早期陪伴概念备份。

前两份保留视觉探索并增加显式历史标记；早期备份改为归档说明，完整旧内容仍可从 Git 历史读取。

## 当前事实来源

1. 运行行为：`app/Codexling/Sources/Codexling/`
2. 自动验证：`app/Codexling/Tests/CodexlingTests/`
3. 打包发布：`app/Codexling/package_app.sh`、`release_app.sh`
4. Landing：`app/landing/src/`
5. 当前架构摘要：`PROJECT.md`、`docs/codexling方案.md`
