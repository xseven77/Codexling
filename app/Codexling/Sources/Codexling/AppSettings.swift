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

enum StatusBarClickBehavior: String, CaseIterable, Identifiable {
    case detachedWindow
    case popover

    var id: String { rawValue }

    var title: String {
        switch self {
        case .detachedWindow: "打开分离窗口"
        case .popover: "打开下拉窗口"
        }
    }

    var symbolName: String {
        switch self {
        case .detachedWindow: "rectangle.on.rectangle.angled"
        case .popover: "menubar.arrow.down.rectangle"
        }
    }
}

enum StatusBarPetBackgroundColor: String, CaseIterable, Identifiable {
    case neutral
    case automatic
    case blue
    case purple
    case cyan
    case amber
    case green
    case red

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "跟随状态"
        case .neutral: "中性"
        case .blue: "蓝色"
        case .purple: "紫色"
        case .cyan: "青色"
        case .amber: "橙色"
        case .green: "绿色"
        case .red: "红色"
        }
    }

    var symbolName: String {
        switch self {
        case .automatic: "wand.and.stars"
        case .neutral: "circle.lefthalf.filled"
        case .blue: "circle.fill"
        case .purple: "circle.fill"
        case .cyan: "circle.fill"
        case .amber: "circle.fill"
        case .green: "circle.fill"
        case .red: "circle.fill"
        }
    }

    func resolved(for state: CodexActivityState) -> Self {
        guard self == .automatic else { return self }
        return switch state {
        case .unavailable, .idle: .neutral
        case .thinking: .purple
        case .executing: .blue
        case .reviewing: .cyan
        case .waitingForUser: .amber
        case .completed: .green
        case .interrupted: .red
        }
    }

    var nsColor: NSColor {
        switch self {
        case .automatic, .neutral:
            NSColor.white.withAlphaComponent(0.18)
        case .blue:
            NSColor(red: 0.18, green: 0.42, blue: 1.00, alpha: 0.88)
        case .purple:
            NSColor(red: 0.48, green: 0.26, blue: 0.96, alpha: 0.88)
        case .cyan:
            NSColor(red: 0.02, green: 0.63, blue: 0.80, alpha: 0.88)
        case .amber:
            NSColor(red: 0.95, green: 0.46, blue: 0.08, alpha: 0.90)
        case .green:
            NSColor(red: 0.05, green: 0.65, blue: 0.31, alpha: 0.88)
        case .red:
            NSColor(red: 0.93, green: 0.22, blue: 0.30, alpha: 0.88)
        }
    }

    var foregroundColor: NSColor {
        switch self {
        case .automatic, .neutral:
            .labelColor
        case .blue, .purple, .cyan, .amber, .green, .red:
            .white
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
        static let statusBarWaveEnabled = "codexling.statusBarWaveEnabled"
        static let statusBarCornerPercent = "codexling.statusBarCornerPercent"
        static let statusBarClickBehavior = "codexling.statusBarClickBehavior"
    }

    private let defaults: UserDefaults
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
            onPetSettingsChanged?()
        }
    }

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

    var statusBarCornerPercent: Double {
        didSet {
            guard statusBarCornerPercent != oldValue else { return }
            defaults.set(statusBarCornerPercent, forKey: Keys.statusBarCornerPercent)
            onPetSettingsChanged?()
        }
    }

    var statusBarClickBehavior: StatusBarClickBehavior {
        didSet {
            guard statusBarClickBehavior != oldValue else { return }
            defaults.set(statusBarClickBehavior.rawValue, forKey: Keys.statusBarClickBehavior)
            onPetSettingsChanged?()
        }
    }

    private(set) var availablePets: [CodexPet] = []

    var selectedPet: CodexPet? {
        availablePets.first { $0.id == selectedPetID } ?? availablePets.first
    }

    var resolvedColorScheme: ColorScheme {
        theme.resolvedColorScheme(system: systemColorScheme)
    }

    var onAutoRefreshIntervalChanged: ((AutoRefreshInterval) -> Void)?
    var onThemeChanged: ((AppThemePreference) -> Void)?
    var onPetSettingsChanged: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        if defaults === UserDefaults.standard {
            Self.migrateLegacyDefaultsIfNeeded(into: defaults)
        }
        self.defaults = defaults
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
        petBackgroundColor = defaults.string(forKey: Keys.petBackgroundColor)
            .flatMap(StatusBarPetBackgroundColor.init(rawValue:)) ?? .neutral
        statusBarWaveEnabled = defaults.object(forKey: Keys.statusBarWaveEnabled) as? Bool ?? true
        let savedCornerPercent = defaults.object(forKey: Keys.statusBarCornerPercent) as? Double ?? 50
        statusBarCornerPercent = min(max(savedCornerPercent, 20), 50)
        statusBarClickBehavior = defaults.string(forKey: Keys.statusBarClickBehavior)
            .flatMap(StatusBarClickBehavior.init(rawValue:)) ?? .detachedWindow
        reloadPets(notify: false)
    }

    private static func migrateLegacyDefaultsIfNeeded(into defaults: UserDefaults) {
        guard let legacyDefaults = UserDefaults(suiteName: Legacy.domain) else { return }

        let keys = [
            Keys.theme,
            Keys.autoRefreshInterval,
            Keys.petsEnabled,
            Keys.selectedPetID,
            Keys.petBackgroundColor,
            Keys.statusBarWaveEnabled,
            Keys.statusBarCornerPercent,
            Keys.statusBarClickBehavior
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
        availablePets = CodexPetCatalog().discover()
        if !availablePets.contains(where: { $0.id == selectedPetID }),
           let fallback = availablePets.first {
            selectedPetID = fallback.id
        } else if notify {
            onPetSettingsChanged?()
        }
    }
}
