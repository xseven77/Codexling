# Codexling 主题与窗口材质

## 当前产品决策

Codexling 当前只有两类承载面：

1. 独立 dashboard / 设置窗口。
2. 状态栏 Pet hover 卡片。

点击状态栏胶囊直接打开独立窗口，不再打开用量 `NSPopover`。

## 独立窗口

独立窗口使用传统不透明的 `NSWindow`：

- `window.isOpaque = true`
- `window.backgroundColor = .windowBackgroundColor`
- SwiftUI 根视图使用 `Color.codexBackground`
- 支持浅色、暗色和跟随系统

窗口不会透出后方内容。macOS 26 上，局部按钮或卡片可以使用系统 glass interaction，但根窗口仍是不透明背景。

dashboard 使用固定内容尺寸：

- 已登录：约 `579×510pt`
- 未登录：约 `579×440pt`
- 屏幕高度不足时，上限为 `visibleFrame.height - 32pt`

设置窗口按实际内容高度测量：

- 宽度范围 `579–680pt`
- 高度最小 `400pt`
- 高度上限 `visibleFrame.height - 32pt`
- 内容超过当前窗口时启用滚动
- 调整尺寸时锚定窗口顶边，避免路由切换时上下跳动

## Hover 卡片

状态栏 hover 卡片使用透明、非激活式 `NSPanel`：

- macOS 26 及以上使用系统 `.glassEffect(in:)`
- macOS 14–15 回退到 `ultraThinMaterial`
- Pet 与任务摘要共享一块玻璃，不叠加不透明根卡片
- 面板不抢键盘焦点；状态栏与卡片之间使用安全三角区保持交互

## 主题同步

- `AppThemePreference` 支持跟随系统、浅色和暗色。
- SwiftUI 使用解析后的 `preferredColorScheme`。
- AppKit 窗口使用对应 `NSAppearance`。
- 跟随系统时，`applicationDidUpdate` 检测有效外观变化并刷新已有窗口。

## 验证要求

- 独立窗口在浅色与暗色下均保持不透明和可读。
- hover 卡片在 macOS 26 使用原生玻璃，在旧系统正确回退。
- 切换主题后无需重启。
- dashboard 不允许手动拉伸；设置窗口可在约束范围内缩放并正确滚动。
- 小屏幕上所有窗口都不超过当前屏幕可视区域。
