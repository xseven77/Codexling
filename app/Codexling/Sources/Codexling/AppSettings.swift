import AppKit
import Observation
import SwiftUI

enum AppThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var symbolName: String {
        switch self {
        case .system: "desktopcomputer"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }

    /// Drives SwiftUI `colorScheme` inside popovers/windows where AppKit appearance alone is not enough.
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    func resolvedColorScheme(system: ColorScheme) -> ColorScheme {
        preferredColorScheme ?? system
    }
}

enum AutoRefreshInterval: Int, CaseIterable, Identifiable {
    case seconds30 = 30
    case minutes1 = 60
    case minutes2 = 120
    case minutes5 = 300
    case minutes10 = 600
    case off = 0

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .seconds30: "30 秒"
        case .minutes1: "1 分钟"
        case .minutes2: "2 分钟"
        case .minutes5: "5 分钟"
        case .minutes10: "10 分钟"
        case .off: "关闭"
        }
    }

    var timeInterval: TimeInterval? {
        rawValue > 0 ? TimeInterval(rawValue) : nil
    }
}

enum StatusBarPetBackgroundColor: String, CaseIterable, Identifiable {
    case neutral
    case automatic
    case green
    case yellow
    case red
    case gray

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "跟随额度"
        case .neutral: "中性"
        case .green: "绿色"
        case .yellow: "黄色"
        case .red: "红色"
        case .gray: "灰色"
        }
    }

    var symbolName: String {
        switch self {
        case .automatic: "wand.and.stars"
        case .neutral: "circle.lefthalf.filled"
        case .green, .yellow, .red, .gray: "circle.fill"
        }
    }

    func resolved(for health: QuotaHealthLevel) -> Self {
        guard self == .automatic else { return self }
        return switch health {
        case .gray: .gray
        case .green: .green
        case .yellow: .yellow
        case .red: .red
        }
    }

    func foregroundColor(for colorScheme: ColorScheme) -> NSColor {
        switch self {
        case .automatic, .neutral:
            .labelColor
        case .green:
            QuotaHealthLevel.green.nsColor
        case .yellow:
            QuotaHealthLevel.yellow.nsColor
        case .red:
            QuotaHealthLevel.red.nsColor
        case .gray:
            colorScheme == .dark
                ? NSColor(red: 0.620, green: 0.645, blue: 0.680, alpha: 1)
                : NSColor(red: 0.357, green: 0.397, blue: 0.447, alpha: 1)
        }
    }

    var foregroundColor: NSColor { foregroundColor(for: .light) }
}

/// 主界面的排布方向。竖向把宠物移到顶部，窗口收窄到 330pt。
enum DashboardOrientation: String, CaseIterable, Identifiable {
    case horizontal
    case vertical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .horizontal: "横向"
        case .vertical: "竖向"
        }
    }

    var symbolName: String {
        switch self {
        case .horizontal: "rectangle.split.2x1"
        case .vertical: "rectangle.split.1x2"
        }
    }
}

enum TaskHoverDisplayMode: String, CaseIterable, Identifiable {
    case primary
    case current

    var id: String { rawValue }

    var title: String {
        switch self {
        case .primary: "主显示器"
        case .current: "当前高亮显示器"
        }
    }
}

/// 刘海面板出现的目标显示器。
/// 选项由系统 `NSScreen.screens` 动态提供（具体显示器 + 所有显示器 + 关闭）。
enum NotchDisplayTarget: Hashable, Sendable {
    case off
    case allDisplays
    case specificScreen(UInt32)

    var storageString: String {
        switch self {
        case .off: "off"
        case .allDisplays: "all"
        case .specificScreen(let number): "\(number)"
        }
    }

    static func fromStorage(_ string: String) -> NotchDisplayTarget {
        switch string {
        case "off": return .off
        case "all": return .allDisplays
        default: return .specificScreen(UInt32(string) ?? 0)
        }
    }

    var title: String {
        switch self {
        case .off: "所有显示器都不开刘海"
        case .allDisplays: "所有显示器"
        case .specificScreen: "指定显示器"
        }
    }
}

extension NotchDisplayTarget: Identifiable {
    public var id: String { storageString }
}

enum StatusCapsuleColorMode: String, CaseIterable, Identifiable {
    case activityState
    case quotaHealth
    case purple
    case blue
    case cyan
    case orange
    case green
    case red

    var id: String { rawValue }

    static var activityFlowCases: [Self] {
        allCases.filter { $0 != .quotaHealth }
    }

    var title: String {
        switch self {
        case .activityState: "跟随任务状态"
        case .quotaHealth: "跟随额度状态"
        case .purple: "紫色"
        case .blue: "蓝色"
        case .cyan: "青色"
        case .orange: "橙色"
        case .green: "绿色"
        case .red: "红色"
        }
    }

    var swatchColor: Color {
        Color(nsColor: previewNSColor)
    }

    private var previewNSColor: NSColor {
        switch self {
        case .activityState, .purple:
            NSColor(red: 0.478, green: 0.259, blue: 0.961, alpha: 1)
        case .quotaHealth, .green:
            NSColor(red: 0.122, green: 0.647, blue: 0.353, alpha: 1)
        case .blue:
            NSColor(red: 0.180, green: 0.420, blue: 1.000, alpha: 1)
        case .cyan:
            NSColor(red: 0.020, green: 0.631, blue: 0.800, alpha: 1)
        case .orange:
            NSColor(red: 0.949, green: 0.451, blue: 0.078, alpha: 1)
        case .red:
            NSColor(red: 0.929, green: 0.220, blue: 0.302, alpha: 1)
        }
    }

    func resolvedNSColor(
        activityState: CodexActivityState,
        quotaHealth: QuotaHealthLevel
    ) -> NSColor? {
        switch self {
        case .activityState:
            activityState.statusNSColor
        case .quotaHealth:
            quotaHealth.nsColor
        case .purple, .blue, .cyan, .orange, .green, .red:
            previewNSColor
        }
    }
}

@MainActor
@Observable
final class AppSettingsStore {
    private enum Legacy {
        static let domain = "com.qiizo.codex-light"
        static let keyPrefix = "codexLight."
    }

    private enum Keys {
        static let theme = "codexling.theme"
        static let autoRefreshInterval = "codexling.autoRefreshInterval"
        static let petsEnabled = "codexling.petsEnabled"
        static let selectedPetID = "codexling.selectedPetID"
        static let petBackgroundColor = "codexling.petBackgroundColor"
        static let statusBarIndicatorColorMode = "codexling.statusBarIndicatorColorMode"
        static let statusBarWaveEnabled = "codexling.statusBarWaveEnabled"
        static let statusBarWaveColorMode = "codexling.statusBarWaveColorMode"
        static let autoOpenTaskHoverEnabled = "codexling.autoOpenTaskHoverEnabled"
        static let taskHoverDisplayMode = "codexling.taskHoverDisplayMode"
        static let statusBarOpacityPercent = "codexling.statusBarOpacityPercent"
        static let statusBarCornerPercent = "codexling.statusBarCornerPercent"
        static let windowAlwaysOnTop = "codexling.windowAlwaysOnTop"
        static let dashboardOrientation = "codexling.dashboardOrientation"
        static let notchDisplayTarget = "codexling.notchDisplayTarget"
    }

    private let defaults: UserDefaults
    private let codexPetSelectionSync: CodexPetSelectionSync?
    private var suppressCodexPetSelectionWrite = true
    private(set) var systemColorScheme: ColorScheme

    var theme: AppThemePreference {
        didSet {
            guard theme != oldValue else { return }
            defaults.set(theme.rawValue, forKey: Keys.theme)
            applyAppearance()
            onThemeChanged?(theme)
        }
    }

    var autoRefreshInterval: AutoRefreshInterval {
        didSet {
            guard autoRefreshInterval != oldValue else { return }
            defaults.set(autoRefreshInterval.rawValue, forKey: Keys.autoRefreshInterval)
            onAutoRefreshIntervalChanged?(autoRefreshInterval)
        }
    }

    var petsEnabled: Bool {
        didSet {
            guard petsEnabled != oldValue else { return }
            defaults.set(petsEnabled, forKey: Keys.petsEnabled)
            onPetSettingsChanged?()
        }
    }

    var selectedPetID: String {
        didSet {
            guard selectedPetID != oldValue else { return }
            defaults.set(selectedPetID, forKey: Keys.selectedPetID)
            if !suppressCodexPetSelectionWrite {
                syncSelectedPetToCodex()
            }
            onPetSettingsChanged?()
        }
    }

    // 保留 UserDefaults 键值以兼容旧版本设置，但当前胶囊不再使用此颜色
    // （状态栏文字现按实际背景自动取黑/白，圆灯由单独的颜色模式控制）。
    var petBackgroundColor: StatusBarPetBackgroundColor {
        didSet {
            guard petBackgroundColor != oldValue else { return }
            defaults.set(petBackgroundColor.rawValue, forKey: Keys.petBackgroundColor)
            onPetSettingsChanged?()
        }
    }

    var statusBarWaveEnabled: Bool {
        didSet {
            guard statusBarWaveEnabled != oldValue else { return }
            defaults.set(statusBarWaveEnabled, forKey: Keys.statusBarWaveEnabled)
            onPetSettingsChanged?()
        }
    }

    var statusBarIndicatorColorMode: StatusCapsuleColorMode {
        didSet {
            guard statusBarIndicatorColorMode != oldValue else { return }
            defaults.set(
                statusBarIndicatorColorMode.rawValue,
                forKey: Keys.statusBarIndicatorColorMode
            )
            onPetSettingsChanged?()
        }
    }

    var statusBarWaveColorMode: StatusCapsuleColorMode {
        didSet {
            guard statusBarWaveColorMode != oldValue else { return }
            defaults.set(statusBarWaveColorMode.rawValue, forKey: Keys.statusBarWaveColorMode)
            onPetSettingsChanged?()
        }
    }

    var autoOpenTaskHoverEnabled: Bool {
        didSet {
            guard autoOpenTaskHoverEnabled != oldValue else { return }
            defaults.set(autoOpenTaskHoverEnabled, forKey: Keys.autoOpenTaskHoverEnabled)
            onPetSettingsChanged?()
        }
    }

    var taskHoverDisplayMode: TaskHoverDisplayMode {
        didSet {
            guard taskHoverDisplayMode != oldValue else { return }
            defaults.set(taskHoverDisplayMode.rawValue, forKey: Keys.taskHoverDisplayMode)
            onPetSettingsChanged?()
        }
    }

    var statusBarOpacityPercent: Double {
        didSet {
            guard statusBarOpacityPercent != oldValue else { return }
            defaults.set(statusBarOpacityPercent, forKey: Keys.statusBarOpacityPercent)
            onPetSettingsChanged?()
        }
    }

    var statusBarCornerPercent: Double {
        didSet {
            guard statusBarCornerPercent != oldValue else { return }
            defaults.set(statusBarCornerPercent, forKey: Keys.statusBarCornerPercent)
            onPetSettingsChanged?()
        }
    }

    var windowAlwaysOnTop: Bool {
        didSet {
            guard windowAlwaysOnTop != oldValue else { return }
            defaults.set(windowAlwaysOnTop, forKey: Keys.windowAlwaysOnTop)
            onWindowAlwaysOnTopChanged?(windowAlwaysOnTop)
        }
    }

    var dashboardOrientation: DashboardOrientation {
        didSet {
            guard dashboardOrientation != oldValue else { return }
            defaults.set(dashboardOrientation.rawValue, forKey: Keys.dashboardOrientation)
            onDashboardOrientationChanged?(dashboardOrientation)
        }
    }

    var notchDisplayTarget: NotchDisplayTarget {
        didSet {
            guard notchDisplayTarget != oldValue else { return }
            defaults.set(notchDisplayTarget.storageString, forKey: Keys.notchDisplayTarget)
            onNotchDisplayTargetChanged?(notchDisplayTarget)
        }
    }

    private(set) var availablePets: [CodexPet] = []
    private(set) var isCodexlingPetInstalled = false
    private(set) var codexlingPetInstallationError: String?
    private(set) var codexPetSyncError: String?
    private(set) var codexPetRestartRequired = false

    var selectedPet: CodexPet? {
        availablePets.first { $0.id == selectedPetID } ?? availablePets.first
    }

    var resolvedColorScheme: ColorScheme {
        theme.resolvedColorScheme(system: systemColorScheme)
    }

    var onAutoRefreshIntervalChanged: ((AutoRefreshInterval) -> Void)?
    var onThemeChanged: ((AppThemePreference) -> Void)?
    var onPetSettingsChanged: (() -> Void)?
    var onDashboardOrientationChanged: ((DashboardOrientation) -> Void)?
    var onWindowAlwaysOnTopChanged: ((Bool) -> Void)?
    var onNotchDisplayTargetChanged: ((NotchDisplayTarget) -> Void)?

    init(
        defaults: UserDefaults = .standard,
        codexPetSelectionSync: CodexPetSelectionSync? = nil
    ) {
        if defaults === UserDefaults.standard {
            Self.migrateLegacyDefaultsIfNeeded(into: defaults)
        }
        self.defaults = defaults
        self.codexPetSelectionSync = codexPetSelectionSync
            ?? (defaults === UserDefaults.standard ? CodexPetSelectionSync() : nil)
        systemColorScheme = Self.currentSystemColorScheme()

        if let raw = defaults.string(forKey: Keys.theme),
           let saved = AppThemePreference(rawValue: raw) {
            theme = saved
        } else {
            theme = .system
        }

        let intervalRaw = defaults.object(forKey: Keys.autoRefreshInterval) as? Int
        if let intervalRaw, let saved = AutoRefreshInterval(rawValue: intervalRaw) {
            autoRefreshInterval = saved
        } else {
            autoRefreshInterval = .minutes1
        }

        petsEnabled = defaults.object(forKey: Keys.petsEnabled) as? Bool ?? true
        selectedPetID = defaults.string(forKey: Keys.selectedPetID) ?? "builtin:codex"
        let backgroundRaw = defaults.string(forKey: Keys.petBackgroundColor)
        petBackgroundColor = backgroundRaw.flatMap(StatusBarPetBackgroundColor.init(rawValue:)) ?? .neutral
        statusBarIndicatorColorMode = defaults.string(forKey: Keys.statusBarIndicatorColorMode)
            .flatMap(StatusCapsuleColorMode.init(rawValue:)) ?? .activityState
        statusBarWaveEnabled = defaults.object(forKey: Keys.statusBarWaveEnabled) as? Bool ?? true
        let savedWaveColorMode = defaults.string(forKey: Keys.statusBarWaveColorMode)
        statusBarWaveColorMode = savedWaveColorMode.flatMap { rawValue in
            ["statusColor", "neutral", StatusCapsuleColorMode.quotaHealth.rawValue].contains(rawValue)
                ? .activityState
                : StatusCapsuleColorMode(rawValue: rawValue)
        } ?? .activityState
        autoOpenTaskHoverEnabled =
            defaults.object(forKey: Keys.autoOpenTaskHoverEnabled) as? Bool ?? true
        taskHoverDisplayMode = defaults.string(forKey: Keys.taskHoverDisplayMode)
            .flatMap(TaskHoverDisplayMode.init(rawValue:)) ?? .primary
        let savedOpacityPercent =
            defaults.object(forKey: Keys.statusBarOpacityPercent) as? Double ?? 20
        statusBarOpacityPercent = min(max(savedOpacityPercent, 0), 50)
        let savedCornerPercent = defaults.object(forKey: Keys.statusBarCornerPercent) as? Double ?? 50
        statusBarCornerPercent = min(max(savedCornerPercent, 20), 50)
        windowAlwaysOnTop = defaults.object(forKey: Keys.windowAlwaysOnTop) as? Bool ?? false
        dashboardOrientation = defaults.string(forKey: Keys.dashboardOrientation)
            .flatMap(DashboardOrientation.init(rawValue:)) ?? .horizontal
        if let stored = defaults.string(forKey: Keys.notchDisplayTarget) {
            notchDisplayTarget = NotchDisplayTarget.fromStorage(stored)
        } else {
            // 首次启动：内建显示器是刘海屏则默认选中内建屏，否则默认所有显示器。
            if let builtin = NSScreen.screens.first(where: \.isBuiltin), builtin.isNotched {
                notchDisplayTarget = .specificScreen(builtin.screenNumber)
            } else {
                notchDisplayTarget = .allDisplays
            }
            // 首次启动的默认值也要持久化，后续启动直接读取，不再重复判定。
            defaults.set(notchDisplayTarget.storageString, forKey: Keys.notchDisplayTarget)
        }
        // The status capsule now has one behavior: open the detached window.
        // Remove the retired popover preference so older installations cannot
        // retain an unreachable mode.
        defaults.removeObject(forKey: "codexling.statusBarClickBehavior")
        reloadPets(notify: false)
        syncPetSelectionFromCodex()
        suppressCodexPetSelectionWrite = false
    }

    private static func migrateLegacyDefaultsIfNeeded(into defaults: UserDefaults) {
        guard let legacyDefaults = UserDefaults(suiteName: Legacy.domain) else { return }

        let keys = [
            Keys.theme,
            Keys.autoRefreshInterval,
            Keys.petsEnabled,
            Keys.selectedPetID,
            Keys.petBackgroundColor,
            Keys.statusBarIndicatorColorMode,
            Keys.statusBarWaveEnabled,
            Keys.statusBarWaveColorMode,
            Keys.autoOpenTaskHoverEnabled,
            Keys.taskHoverDisplayMode,
            Keys.statusBarOpacityPercent,
            Keys.statusBarCornerPercent,
            Keys.windowAlwaysOnTop,
            Keys.dashboardOrientation
        ]
        for key in keys where defaults.object(forKey: key) == nil {
            let suffix = key.replacingOccurrences(of: "codexling.", with: "")
            guard let value = legacyDefaults.object(forKey: Legacy.keyPrefix + suffix) else { continue }
            defaults.set(value, forKey: key)
        }
    }

    func applyAppearance() {
        let appearance = theme.nsAppearance
        // Do not override NSApplication.appearance: a status item lives in the
        // system menu bar, whose text contrast must continue to follow macOS.
        for window in NSApplication.shared.windows {
            window.appearance = appearance
            window.contentView?.needsDisplay = true
        }
    }

    func refreshSystemAppearanceIfNeeded(_ colorScheme: ColorScheme? = nil) {
        let next = colorScheme ?? Self.currentSystemColorScheme()
        guard next != systemColorScheme else { return }
        systemColorScheme = next
        guard theme == .system else { return }
        applyAppearance()
        onThemeChanged?(theme)
    }

    private static func currentSystemColorScheme() -> ColorScheme {
        let match = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua ? .dark : .light
    }

    func reloadPets(notify: Bool = true) {
        isCodexlingPetInstalled = CodexlingPetInstaller.isInstalled()
        availablePets = CodexPetCatalog().discover()
        if !availablePets.contains(where: { $0.id == selectedPetID }),
           let fallback = availablePets.first {
            selectedPetID = fallback.id
        } else if notify {
            onPetSettingsChanged?()
        }
    }

    func syncPetSelectionFromCodex() {
        guard let codexPetID = codexPetSelectionSync?.readSelectedPetID(),
              availablePets.contains(where: { $0.id == codexPetID }),
              selectedPetID != codexPetID else {
            return
        }
        let wasSuppressingWrite = suppressCodexPetSelectionWrite
        suppressCodexPetSelectionWrite = true
        selectedPetID = codexPetID
        suppressCodexPetSelectionWrite = wasSuppressingWrite
        codexPetRestartRequired = false
        codexPetSyncError = nil
    }

    func refreshPetsAndSyncSelectionFromCodex() {
        let wasSuppressingWrite = suppressCodexPetSelectionWrite
        suppressCodexPetSelectionWrite = true
        reloadPets(notify: false)
        syncPetSelectionFromCodex()
        suppressCodexPetSelectionWrite = wasSuppressingWrite
        onPetSettingsChanged?()
    }

    private func syncSelectedPetToCodex() {
        guard let codexPetSelectionSync else { return }
        do {
            if try codexPetSelectionSync.writeSelectedPetID(selectedPetID) {
                codexPetRestartRequired = true
            }
            codexPetSyncError = nil
        } catch {
            codexPetSyncError = error.localizedDescription
        }
    }

    func markCodexPetRestartCompleted() {
        codexPetRestartRequired = false
    }

    func installCodexlingPet() {
        do {
            try CodexlingPetInstaller.install()
            codexlingPetInstallationError = nil
            reloadPets()
            selectedPetID = "custom:\(CodexlingPetInstaller.petID)"
        } catch {
            codexlingPetInstallationError = error.localizedDescription
        }
    }
}
