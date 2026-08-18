import AppKit
import Foundation

// MARK: - 刘海屏检测与屏幕度量

extension NSScreen {
    /// 是否为 MacBook 内建显示器。
    var isBuiltin: Bool {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(number.uint32Value) != 0
    }

    /// 是否为物理刘海屏（仅内建屏可能有刘海；外接屏即使上报 safeArea 也按非刘海处理）。
    var isNotched: Bool {
        isBuiltin && (safeAreaInsets.top > 0 || auxiliaryTopLeftArea != nil)
    }

    /// 刘海高度（安全获取）：内建刘海屏用 safeAreaInsets.top，其余屏幕用系统菜单栏高度。
    var notchHeight: CGFloat {
        if isBuiltin {
            let top = safeAreaInsets.top
            return top > 0 ? top : Self.systemMenuBarHeight
        }
        return Self.systemMenuBarHeight
    }

    /// 系统状态栏（菜单栏）高度：从「有菜单栏的屏幕」的 frame 与 visibleFrame 顶部差获取。
    /// 这比 NSStatusBar.system.thickness 更贴近真实菜单栏高度。
    private static var systemMenuBarHeight: CGFloat {
        for screen in NSScreen.screens {
            let top = screen.frame.maxY - screen.visibleFrame.maxY
            if top > 0 { return top }
        }
        return 24
    }

    /// 物理刘海宽度：内建刘海屏用屏幕宽减去两侧辅助区（+ 少量补偿），其余用基础值 104pt。
    var notchWidth: CGFloat {
        guard isBuiltin,
              let left = auxiliaryTopLeftArea,
              let right = auxiliaryTopRightArea else {
            return 104
        }
        return max(104, frame.width - left.width - right.width + 4)
    }

    /// 显示器名称（系统 API），用于设置列表展示。
    var displayName: String {
        localizedName.isEmpty ? "显示器" : localizedName
    }

    /// 显示器唯一编号（CGDirectDisplayID）。
    var screenNumber: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// 监听屏幕参数变化（外接/断开、分辨率、缩放、菜单栏归属），变化后触发重算。
@MainActor
final class MenuBarNotchDetector: NSObject {
    var onChange: (() -> Void)?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        onChange?()
    }
}

// MARK: - 状态栏双维度数据模型

/// 左区 tick：本机某个 Agent 的运行状态（Codex 可登录多个账号，各自独立）。
struct StatusBarAgentTick: Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    let state: CodexActivityState
    let taskCount: Int
    let asset: BrandAssetID
    var taskTitle: String
    var taskDetail: String
    var workspaceName: String?
    var gitBranch: String?
    var model: String?
    var updatedAt: Date?
    /// 对应的底层任务 id（用于深链打开该 Agent 的会话）。为空时退回打开 Agent 应用。
    var taskID: String?

    var statusText: String {
        state.statusBarText ?? (state == .unavailable ? "不可用" : "空闲")
    }

    /// 与主页面任务卡片一致的元信息（工作区 / 分支 / 模型）。
    var metadataItems: [(icon: String, value: String)] {
        [
            workspaceName.map { ("folder", $0) },
            gitBranch.map { ("arrow.triangle.branch", $0) },
            model.map { ("cpu", $0) }
        ].compactMap { $0 }
    }
}

/// 右区 tick：某个账号 / API Key 的额度（与 Agent 独立，API Key 型无对应 Agent）。
struct StatusBarProviderTick: Identifiable, Equatable, Sendable {
    let id: String
    let providerName: String
    let accountName: String
    let asset: BrandAssetID
    /// 胶囊短文本，如 "5h 82% · 周76%" 或 "¥42.80"
    let quotaText: String
    /// 展开面板副值，如 "周 76%" 或 "API Key"
    let detailText: String
    /// 与主界面额度状态共用的红 / 黄 / 绿颜色等级。
    let quotaHealth: QuotaHealthLevel
}

/// 双维度独立轮播索引：左区 Agent 与右区 Provider 各自独立计时切换。
struct StatusBarTicker: Equatable {
    var agentIndex = 0
    var providerIndex = 0

    mutating func advanceAgent(count: Int) {
        guard count > 0 else { agentIndex = 0; return }
        agentIndex = (agentIndex + 1) % count
    }

    mutating func advanceProvider(count: Int) {
        guard count > 0 else { providerIndex = 0; return }
        providerIndex = (providerIndex + 1) % count
    }

    mutating func clampAgent(to count: Int) {
        agentIndex = count > 0 ? min(agentIndex, count - 1) : 0
    }

    mutating func clampProvider(to count: Int) {
        providerIndex = count > 0 ? min(providerIndex, count - 1) : 0
    }
}

// MARK: - 品牌资产映射

extension BrandAssetID {
    /// 把 Agent 显示名映射到品牌图标；未收录的 Agent 回退到 Codex。
    static func forAgentDisplayName(_ name: String) -> BrandAssetID {
        for descriptor in BuiltInAgentCatalog.prioritized where descriptor.displayName == name {
            return agent(descriptor.id)
        }
        return .codex
    }
}

// MARK: - 额度 tick 提取

enum StatusBarProviderTickFactory {
    /// Codex 连接额度：主值优先周额度（语义清晰稳定），5h 作为副值。
    static func codexTick(
        id: String,
        label: String,
        accountName: String,
        usage: CodexUsageSnapshot?,
        isConnected: Bool = true
    ) -> StatusBarProviderTick? {
        guard let usage, usage.hasShortWindow || usage.hasWeeklyWindow else { return nil }
        var quotaText: String
        var detailText = ""
        if usage.hasWeeklyWindow {
            quotaText = "\(statusBarWindowLabel(usage.weekly.label)) \(usage.weekly.percentText)"
            if usage.hasShortWindow, let short = usage.shortWindow {
                detailText = "\(statusBarWindowLabel(short.label)) \(short.percentText)"
            }
        } else if let short = usage.shortWindow {
            quotaText = "\(statusBarWindowLabel(short.label)) \(short.percentText)"
        } else {
            quotaText = "无额度"
        }
        return StatusBarProviderTick(
            id: id,
            providerName: "Codex",
            accountName: accountName.isEmpty ? "Codex" : accountName,
            asset: .codex,
            quotaText: quotaText,
            detailText: detailText,
            quotaHealth: QuotaHealthLevel.from(window: usage.primaryWindow, isLoggedIn: isConnected)
        )
    }

    /// DeepSeek API Key 余额。
    static func deepSeekTick(_ connection: DeepSeekAPIConnection) -> StatusBarProviderTick? {
        guard let balance = connection.balance else { return nil }
        let value = NSDecimalNumber(decimal: balance.total).stringValue
        let text = balance.currency == "CNY" ? "¥\(value)" : "\(balance.currency) \(value)"
        let quotaHealth: QuotaHealthLevel = switch ProviderBalanceIndicator.resolve(
            total: balance.total,
            authenticationState: connection.authenticationState
        ) {
        case .healthy: .green
        case .low: .yellow
        case .depleted: .red
        }
        return StatusBarProviderTick(
            id: "deepseek.\(connection.id.rawValue.uuidString.lowercased())",
            providerName: "DeepSeek",
            accountName: connection.label,
            asset: .deepSeek,
            quotaText: text,
            detailText: "API Key",
            quotaHealth: quotaHealth
        )
    }

    /// OpenCode 提供独立的 Go / Zen 模型目录端点，可用于验证 Key；但目前
    /// 没有稳定的公开账户额度接口，因此明确展示为不可查询而非虚构数值。
    static func openCodeTick(_ connection: OpenCodeAPIConnection) -> StatusBarProviderTick {
        let connected = connection.authenticationState == .connected
        let quotaText = connection.plan == .go ? "额度暂不可查" : "余额暂不可查"
        let detailText: String
        switch connection.plan {
        case .go: detailText = "5h / 周 / 月额度"
        case .zen:
            detailText = connection.availableModelCount.map { "已验证 \($0) 个模型" } ?? "API Key"
        }
        return StatusBarProviderTick(
            id: connection.plan == .go
                ? "opencode-go.\(connection.id.rawValue.uuidString.lowercased())"
                : "opencode-zen.\(connection.id.rawValue.uuidString.lowercased())",
            providerName: connection.plan.displayName,
            accountName: connection.label,
            asset: .openCode,
            quotaText: quotaText,
            detailText: detailText,
            quotaHealth: connected ? .green : .yellow
        )
    }
}
