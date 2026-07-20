import Foundation
import Observation
import SwiftUI

struct UsageWindow: Codable, Equatable, Sendable {
    let label: String
    var remaining: Int
    var total: Int
    var resetsAt: String

    var percent: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(remaining) / Double(total), 0), 1)
    }

    var percentText: String {
        "\(Int((percent * 100).rounded()))%"
    }

    var amountText: String {
        "\(remaining)/\(total)"
    }
}

struct CreditBalance: Codable, Equatable, Sendable {
    var balance: Int
    var expiresAt: String
}

struct ResetCoupon: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var count: Int
    var expiresAt: String
    var source: String
}

struct CodexUsageSnapshot: Codable, Equatable, Sendable {
    var accountName: String?
    var accountEmail: String
    var workspaceName: String
    var planName: String
    /// `nil` when Codex temporarily does not expose the five-hour limit.
    var shortWindow: UsageWindow?
    var weekly: UsageWindow
    var credits: CreditBalance
    var resetCoupons: [ResetCoupon]
    var fetchedAt: Date
    var refreshState: String
    var sourceURL: String
}

extension CodexUsageSnapshot {
    /// The five-hour limit is normally the primary signal. When it is unavailable,
    /// all quota presentation and health indicators fall back to the weekly limit.
    var primaryWindow: UsageWindow {
        guard let shortWindow, shortWindow.total > 0 else { return weekly }
        return shortWindow
    }

    var hasShortWindow: Bool {
        // Older cached snapshots and a temporarily disabled API window can both
        // contain a 0/0 five-hour quota. Treat either as unavailable.
        (shortWindow?.total ?? 0) > 0
    }
}

@Observable
@MainActor
final class UsageSnapshotStore {
    private let cache = UsageSnapshotCache()
    private let tokenStore = CodexOAuthTokenStore()
    var snapshot: CodexUsageSnapshot
    var isLoggedIn: Bool

    init() {
        snapshot = cache.load() ?? CodexUsageSnapshot.preview
        isLoggedIn = tokenStore.hasStoredToken()
    }

    func markRefreshing(allowsAuthorization: Bool) {
        snapshot.refreshState = allowsAuthorization ? "授权中" : "刷新中"
        snapshot.fetchedAt = Date()
    }

    func apply(_ snapshot: CodexUsageSnapshot) {
        self.snapshot = snapshot
        isLoggedIn = true
        cache.save(snapshot)
    }

    func markDisconnected() {
        isLoggedIn = false
        tokenStore.clear()
        snapshot.fetchedAt = Date()
        snapshot.refreshState = "已退出登录"
    }

    func markFailed(_ message: String) {
        snapshot.fetchedAt = Date()
        snapshot.refreshState = message
    }
}

struct UsageSnapshotCache {
    private var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private var fileURL: URL {
        return supportDirectory
            .appendingPathComponent("Codexling", isDirectory: true)
            .appendingPathComponent("latest_snapshot.json")
    }

    private var legacyFileURL: URL {
        supportDirectory
            .appendingPathComponent("CodexLight", isDirectory: true)
            .appendingPathComponent("latest_snapshot.json")
    }

    func load() -> CodexUsageSnapshot? {
        if let snapshot = load(from: fileURL) {
            return snapshot
        }
        if let snapshot = load(from: legacyFileURL) {
            save(snapshot)
            return snapshot
        }
        return nil
    }

    private func load(from url: URL) -> CodexUsageSnapshot? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CodexUsageSnapshot.self, from: data)
    }

    func save(_ snapshot: CodexUsageSnapshot) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Cache failures should never block showing fresh usage data.
        }
    }
}

struct UsageActions {
    var refresh: () -> Void
    var openUsagePage: () -> Void
    var loginAndFetch: () -> Void
    var disconnect: () -> Void
    var openDetachedWindow: () -> Void
    var quit: () -> Void
}

enum UsageDateFormat {
    static func display(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    static func timeOnly(_ value: String) -> String {
        let parts = value.split(separator: " ")
        guard let time = parts.last else { return value }
        return String(time)
    }
}

enum QuotaHealthLevel: Equatable {
    case gray
    case green
    case yellow
    case red

    static func from(window: UsageWindow, isLoggedIn: Bool) -> QuotaHealthLevel {
        guard isLoggedIn, window.total > 0 else { return .gray }

        switch window.percent {
        case 0.5...:
            return .green
        case 0.2..<0.5:
            return .yellow
        default:
            return .red
        }
    }
}

extension QuotaHealthLevel {
    var color: Color {
        switch self {
        case .gray:
            .codexMuted
        case .green:
            .codexGreen
        case .yellow:
            .codexAmber
        case .red:
            .codexRed
        }
    }

    var nsColor: NSColor {
        switch self {
        case .gray:
            NSColor.systemGray
        case .green:
            NSColor(red: 0.157, green: 0.753, blue: 0.306, alpha: 1)
        case .yellow:
            NSColor(red: 1.000, green: 0.745, blue: 0.000, alpha: 1)
        case .red:
            NSColor(red: 1.000, green: 0.373, blue: 0.373, alpha: 1)
        }
    }

    var surfaceColors: [Color] {
        switch self {
        case .gray:
            [.codexSurface, .codexMist, .codexSurface]
        case .green:
            [.codexSurface, .codexGreen.opacity(0.10), .codexSurface]
        case .yellow:
            [.codexSurface, .codexAmber.opacity(0.12), .codexSurface]
        case .red:
            [.codexSurface, .codexRed.opacity(0.10), .codexSurface]
        }
    }
}

extension CodexUsageSnapshot {
    static let preview = CodexUsageSnapshot(
        accountName: "name",
        accountEmail: "name@example.com",
        workspaceName: "Personal",
        planName: "Plus",
        shortWindow: UsageWindow(label: "5 小时", remaining: 72, total: 100, resetsAt: "2026-07-07 18:30:00"),
        weekly: UsageWindow(label: "周额度", remaining: 410, total: 1000, resetsAt: "2026-07-14 23:59:00"),
        credits: CreditBalance(balance: 123, expiresAt: "2027-07-01 00:00:00"),
        resetCoupons: [
            ResetCoupon(name: "推荐重置券", count: 1, expiresAt: "2026-07-20 00:00:00", source: "推荐奖励"),
            ResetCoupon(name: "活动重置券", count: 2, expiresAt: "2026-08-05 00:00:00", source: "活动奖励"),
            ResetCoupon(name: "学生重置券", count: 1, expiresAt: "2026-09-01 00:00:00", source: "学生奖励")
        ],
        fetchedAt: Date(),
        refreshState: "预览数据",
        sourceURL: "preview"
    )
}
