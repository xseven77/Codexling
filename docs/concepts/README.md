# UI 概念稿与预览 HTML 索引

本目录集中存放 Codexling 开发过程中用于视觉探索与方案预览的独立 HTML 文件。
它们**不是**当前界面的规范来源;现行行为以
[`app/Codexling/Sources/Codexling/`](../../app/Codexling/Sources/Codexling/) 源码、
[`app/Codexling/Tests/CodexlingTests/`](../../app/Codexling/Tests/CodexlingTests/) 测试与
[`docs/manual/`](../manual/) 操作手册为准(见[文档漂移审计](../documentation-drift-audit.md))。
文件按主题与演进顺序整理如下,时间取自 Git 历史。

## 陪伴式主窗口与设置页(0.3.x 时代,已冻结)

| 文件 | 主题 | 最后更新 | 状态 |
|---|---|---|---|
| [ui-concepts.html](ui-concepts.html) | 主窗口信息架构拆解 | 2026-07-23 | 冻结的历史设计稿,Swift 实现已继续演进 |
| [ui-concepts-companion-backup.html](ui-concepts-companion-backup.html) | 早期陪伴概念备份 | 2026-07-27 | 归档备份 |
| [ui-vertical.html](ui-vertical.html) | 竖向布局完整设计方案(330pt) | 2026-07-28 | 历史设计稿;现行横向/竖向布局见 [dashboard-orientation](../dashboard-orientation.md) 与手册[07-菜单栏与窗口](../manual/07-菜单栏与窗口.md) |
| [settings-concepts.html](settings-concepts.html) | 设置页草案 | 2026-07-27 | 冻结于 2026-07-22;现行设置见手册[08-设置与更新](../manual/08-设置与更新.md) |

## 重置券 UI(已定稿落地)

| 文件 | 主题 | 最后更新 | 状态 |
|---|---|---|---|
| [reset-coupon-concepts.html](reset-coupon-concepts.html) | 重置券 UI 概念方案 | 2026-07-28 | 概念探索 |
| [reset-coupon-concepts-v2.html](reset-coupon-concepts-v2.html) | 重置券 v2(数据驱动概念) | 2026-07-28 | 概念探索 |
| [reset-coupon-timeline-concepts.html](reset-coupon-timeline-concepts.html) | 重置券 F2×F3 时间线融合概念 | 2026-07-28 | 概念探索 |
| [reset-coupon-m1-final.html](reset-coupon-m1-final.html) | 重置券 M1 定稿 | 2026-07-28 | 定稿;对应实现 `ResetCouponFusionViews.swift` |
| [reset-coupon-empty-state-variants.html](reset-coupon-empty-state-variants.html) | 重置券空态样式方案对比 | 2026-08-14 | 空态方案对比 |

## Gateway 网关(0.6.x–0.7.x 时代)

| 文件 | 主题 | 最后更新 | 状态 |
|---|---|---|---|
| [gateway-ui-concept.html](gateway-ui-concept.html) | Gateway 窗口 UI 概念(数据标注与可观测性) | 2026-09-02 | 概念稿;现行 Gateway 窗口七标签见手册[05-Gateway网关](../manual/05-Gateway网关.md) |
| [gateway_account_structure_optimization.html](gateway_account_structure_optimization.html) | 供应商多账号/巡检诊断结构优化方案 | 2026-09-16 | 对应提交 `fa656e7` 的单账号 Tab 驱动重构 |

## 约定

- 新增预览 HTML 时同步更新本索引,注明主题、时间与落点(定稿实现或冻结原因)。
- 设计稿一旦与实现分叉,以源码与测试为准;不要从这些文件反推现行行为。
