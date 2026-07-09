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

@MainActor
@Observable
final class AppSettingsStore {
    private enum Keys {
        static let theme = "codexLight.theme"
        static let autoRefreshInterval = "codexLight.autoRefreshInterval"
    }

    private let defaults: UserDefaults

    var theme: AppThemePreference {
        didSet {
            guard theme != oldValue else { return }
            defaults.set(theme.rawValue, forKey: Keys.theme)
            applyAppearance()
        }
    }

    var autoRefreshInterval: AutoRefreshInterval {
        didSet {
            guard autoRefreshInterval != oldValue else { return }
            defaults.set(autoRefreshInterval.rawValue, forKey: Keys.autoRefreshInterval)
            onAutoRefreshIntervalChanged?(autoRefreshInterval)
        }
    }

    var onAutoRefreshIntervalChanged: ((AutoRefreshInterval) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

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
    }

    func applyAppearance() {
        NSApplication.shared.appearance = theme.nsAppearance
    }
}
