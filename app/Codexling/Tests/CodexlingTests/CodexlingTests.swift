import Foundation
import SQLite3
import SwiftUI
import XCTest
@testable import Codexling

final class CodexlingTests: XCTestCase {
    @MainActor
    func testThemePreferencesMapToLightDarkAndSystemColorSchemes() {
        XCTAssertNil(AppThemePreference.system.preferredColorScheme)
        XCTAssertEqual(AppThemePreference.light.preferredColorScheme, .light)
        XCTAssertEqual(AppThemePreference.dark.preferredColorScheme, .dark)
        XCTAssertEqual(AppThemePreference.system.resolvedColorScheme(system: .light), .light)
        XCTAssertEqual(AppThemePreference.system.resolvedColorScheme(system: .dark), .dark)
        XCTAssertNotNil(AppThemePreference.light.nsAppearance)
        XCTAssertNotNil(AppThemePreference.dark.nsAppearance)
    }

    @MainActor
    func testFollowSystemRefreshesWhenEffectiveAppearanceChanges() throws {
        let suiteName = "CodexlingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(AppThemePreference.system.rawValue, forKey: "codexling.theme")

        let settings = AppSettingsStore(defaults: defaults)
        let nextScheme: ColorScheme = settings.systemColorScheme == .light ? .dark : .light
        var callbackCount = 0
        settings.onThemeChanged = { _ in callbackCount += 1 }

        settings.refreshSystemAppearanceIfNeeded(nextScheme)

        XCTAssertEqual(settings.resolvedColorScheme, nextScheme)
        XCTAssertEqual(callbackCount, 1)
    }

    func testCodexV2AnimationContractMatchesStandardRows() throws {
        let running = PetAnimationContract.sequence(for: .running, reducedMotion: false)
        XCTAssertEqual(running.frames.count, 24)
        XCTAssertEqual(running.loopStartIndex, 18)
        XCTAssertEqual(running.frames.first?.row, 7)
        XCTAssertEqual(try XCTUnwrap(running.frames.first?.duration), 0.12, accuracy: 0.0001)
        XCTAssertEqual(running.frames[5].duration, 0.22, accuracy: 0.0001)

        let waiting = PetAnimationContract.sequence(for: .waiting, reducedMotion: true)
        XCTAssertEqual(waiting.frames, [PetAnimationFrame(row: 6, column: 0, duration: 0.15)])
        XCTAssertNil(waiting.loopStartIndex)

        let wavingOneShot = PetAnimationContract.oneShotSequence(for: .waving, reducedMotion: false)
        XCTAssertEqual(wavingOneShot.frames.count, 12)
        XCTAssertNil(wavingOneShot.loopStartIndex)
        XCTAssertEqual(wavingOneShot.frames.first?.row, 3)
    }

    func testAutomaticPetBackgroundMapsQuotaHealth() {
        let automatic = StatusBarPetBackgroundColor.automatic
        XCTAssertEqual(automatic.resolved(for: .gray), .gray)
        XCTAssertEqual(automatic.resolved(for: .green), .green)
        XCTAssertEqual(automatic.resolved(for: .yellow), .yellow)
        XCTAssertEqual(automatic.resolved(for: .red), .red)
        XCTAssertEqual(StatusBarPetBackgroundColor.neutral.resolved(for: .red), .neutral)
    }

    @MainActor
    func testPetBackgroundDefaultsToFollowQuotaAndListsItFirst() throws {
        let suiteName = "CodexlingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(settings.petBackgroundColor, .automatic)
        XCTAssertEqual(StatusBarPetBackgroundColor.allCases.first, .automatic)
    }

    func testStatusPetBadgeKeepsPetVisibleOnWhiteBackdrop() {
        let pet = NSImage(size: NSSize(width: 24, height: 21))
        pet.lockFocus()
        NSColor.purple.setFill()
        NSBezierPath(rect: NSRect(x: 7, y: 4, width: 10, height: 13)).fill()
        pet.unlockFocus()

        let badge = StatusPetBadgeRenderer.render(pet)
        XCTAssertEqual(badge.size, StatusPetBadgeRenderer.size)
        XCTAssertFalse(badge.isTemplate)

        guard let tiff = badge.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return XCTFail("Pet badge should be renderable")
        }
        let center = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)
        let edge = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: 2)
        XCTAssertNotNil(center)
        XCTAssertNotNil(edge)
        XCTAssertGreaterThan(edge?.alphaComponent ?? 0, 0.5)
    }

    func testStatusPetFrameIsGeometricallyCenteredWithoutAssetCompensation() {
        let container = NSRect(x: 0, y: 0, width: 22, height: 22)
        let petRect = StatusPetBadgeRenderer.centeredRect(
            contentSize: NSSize(width: 13, height: 15),
            in: container
        )

        XCTAssertEqual(petRect.midX, container.midX, accuracy: 0.0001)
        XCTAssertEqual(petRect.midY, container.midY, accuracy: 0.0001)
    }

    func testHoverSafeTriangleKeepsPointerPathTowardCardOpen() {
        let triangle = HoverSafeTriangle(
            origin: CGPoint(x: 100, y: 200),
            targetFrame: CGRect(x: 20, y: 80, width: 200, height: 80),
            buffer: 4
        )

        XCTAssertTrue(triangle.contains(CGPoint(x: 100, y: 190)))
        XCTAssertTrue(triangle.contains(CGPoint(x: 60, y: 165)))
    }

    func testHoverSafeTriangleRejectsPointerMovingAwayFromCard() {
        let triangle = HoverSafeTriangle(
            origin: CGPoint(x: 100, y: 200),
            targetFrame: CGRect(x: 20, y: 80, width: 200, height: 80),
            buffer: 4
        )

        XCTAssertFalse(triangle.contains(CGPoint(x: 100, y: 210)))
        XCTAssertFalse(triangle.contains(CGPoint(x: 10, y: 190)))
    }

    func testHoverSafeTriangleToleratesJitterNearDeparturePoint() {
        let safeArea = HoverSafeTriangle(
            origin: CGPoint(x: 100, y: 200),
            targetFrame: CGRect(x: 20, y: 80, width: 200, height: 80),
            buffer: 8
        )

        XCTAssertTrue(safeArea.contains(CGPoint(x: 106, y: 199)))
        XCTAssertTrue(safeArea.contains(CGPoint(x: 94, y: 198)))
    }

    func testHoverSafeTriangleSupportsMovingBackUpToStatusCapsule() {
        let safeArea = HoverSafeTriangle(
            origin: CGPoint(x: 100, y: 100),
            targetFrame: CGRect(x: 80, y: 150, width: 40, height: 22),
            buffer: 8
        )

        XCTAssertTrue(safeArea.contains(CGPoint(x: 101, y: 120)))
        XCTAssertTrue(safeArea.contains(CGPoint(x: 96, y: 145)))
        XCTAssertFalse(safeArea.contains(CGPoint(x: 145, y: 115)))
    }

    @MainActor
    func testStatusCapsulePressInvokesClickAction() {
        let view = StatusCapsuleView(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        var clickCount = 0
        view.onClick = { clickCount += 1 }

        XCTAssertTrue(view.accessibilityPerformPress())
        XCTAssertEqual(clickCount, 1)
    }

    @MainActor
    func testStatusCapsuleMouseUpInsideInvokesClickAction() throws {
        let view = StatusCapsuleView(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        var clickCount = 0
        view.onClick = { clickCount += 1 }

        let mouseDown = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 20, y: 12),
            modifierFlags: [],
            timestamp: 10,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        let mouseUp = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: NSPoint(x: 20, y: 12),
            modifierFlags: [],
            timestamp: 10.05,
            windowNumber: 0,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 0
        ))

        view.mouseDown(with: mouseDown)
        view.mouseUp(with: mouseUp)
        XCTAssertEqual(clickCount, 1)
    }

    @MainActor
    func testPetBackgroundSelectionPersists() throws {
        let suiteName = "CodexlingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettingsStore(defaults: defaults)
        settings.petBackgroundColor = .yellow

        let restored = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(restored.petBackgroundColor, .yellow)
    }

    @MainActor
    func testStatusBarWaveDefaultsOnAndPersists() throws {
        let suiteName = "CodexlingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettingsStore(defaults: defaults)
        XCTAssertTrue(settings.statusBarWaveEnabled)

        settings.statusBarWaveEnabled = false
        let restored = AppSettingsStore(defaults: defaults)
        XCTAssertFalse(restored.statusBarWaveEnabled)
    }

    @MainActor
    func testStatusBarCornerPercentDefaultsPersistsAndClamps() throws {
        let suiteName = "CodexlingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(settings.statusBarCornerPercent, 50)

        settings.statusBarCornerPercent = 32
        XCTAssertEqual(AppSettingsStore(defaults: defaults).statusBarCornerPercent, 32)

        defaults.set(90.0, forKey: "codexling.statusBarCornerPercent")
        XCTAssertEqual(AppSettingsStore(defaults: defaults).statusBarCornerPercent, 50)
    }

    @MainActor
    func testDetachedWindowHeightNeverExceedsVisibleViewport() {
        let maximum = DetachedWindowMetrics.maximumContentHeight(for: NSScreen.main)
        if let visibleHeight = NSScreen.main?.visibleFrame.height {
            XCTAssertLessThanOrEqual(maximum, visibleHeight - 32)
        }

        let clamped = DetachedWindowMetrics.clampSettingsContentSize(
            NSSize(width: 460, height: 10_000),
            screen: NSScreen.main
        )
        XCTAssertGreaterThanOrEqual(clamped.width, DetachedWindowMetrics.dashboardWidth)
        XCTAssertLessThanOrEqual(clamped.height, maximum)
    }

    func testQuotaHealthColorThresholdsDriveRootGradient() {
        let window = UsageWindow(
            label: "周额度",
            remaining: 0,
            total: 100,
            resetsAt: ""
        )
        XCTAssertEqual(QuotaHealthLevel.from(window: window, isLoggedIn: false), .gray)
        XCTAssertEqual(
            QuotaHealthLevel.from(
                window: UsageWindow(label: "周额度", remaining: 60, total: 100, resetsAt: ""),
                isLoggedIn: true
            ),
            .green
        )
        XCTAssertEqual(
            QuotaHealthLevel.from(
                window: UsageWindow(label: "周额度", remaining: 30, total: 100, resetsAt: ""),
                isLoggedIn: true
            ),
            .yellow
        )
        XCTAssertEqual(
            QuotaHealthLevel.from(
                window: UsageWindow(label: "周额度", remaining: 10, total: 100, resetsAt: ""),
                isLoggedIn: true
            ),
            .red
        )
    }

    func testUsageParserReadsRateLimitInsideUsageAndOmitsMissingSecondaryWindow() throws {
        let payload: [String: Any] = [
            "plan_type": "free",
            "usage": [
                "rate_limit": [
                    "primary_window": [
                        "limit_window_seconds": 2_592_000,
                        "used_percent": 26,
                        "reset_after_seconds": 3_600
                    ]
                ]
            ]
        ]

        let snapshot = CodexlingParser().parse(
            usagePayload: payload,
            resetCreditsPayload: nil,
            email: nil,
            accountName: nil
        )

        let primary = try XCTUnwrap(snapshot.shortWindow)
        XCTAssertEqual(primary.label, "30 天")
        XCTAssertEqual(primary.remaining, 74)
        XCTAssertEqual(primary.total, 100)
        XCTAssertFalse(snapshot.hasWeeklyWindow)
    }

    func testUsageParserKeepsAvailableResetCouponsSortedByExpiration() {
        let formatter = ISO8601DateFormatter()
        let soon = formatter.string(from: Date().addingTimeInterval(3_600))
        let later = formatter.string(from: Date().addingTimeInterval(7_200))
        let expired = formatter.string(from: Date().addingTimeInterval(-3_600))
        let resetPayload: [String: Any] = [
            "credits": [
                ["id": "later", "expires_at": later, "status": "available"],
                ["id": "expired", "expires_at": expired, "status": "available"],
                ["id": "soon", "expires_at": soon, "status": "available"]
            ]
        ]

        let snapshot = CodexlingParser().parse(
            usagePayload: [String: Any](),
            resetCreditsPayload: resetPayload,
            email: nil,
            accountName: nil
        )

        XCTAssertEqual(snapshot.resetCoupons.count, 2)
        XCTAssertEqual(snapshot.resetCoupons.reduce(0) { $0 + $1.count }, 2)
        XCTAssertLessThan(snapshot.resetCoupons[0].expiresAt, snapshot.resetCoupons[1].expiresAt)
    }

    @MainActor
    func testRefreshStateKeepsLastSuccessfulFetchTimeUntilApply() {
        var snapshot = CodexUsageSnapshot.preview
        snapshot.fetchedAt = Date(timeIntervalSince1970: 123)
        let store = UsageSnapshotStore(
            snapshot: snapshot,
            isLoggedIn: true,
            persistsCache: false
        )

        store.markRefreshing(allowsAuthorization: false)
        XCTAssertEqual(store.snapshot.fetchedAt, snapshot.fetchedAt)

        store.markFailed("网络不可用")
        XCTAssertEqual(store.snapshot.fetchedAt, snapshot.fetchedAt)

        var refreshed = snapshot
        refreshed.fetchedAt = Date(timeIntervalSince1970: 456)
        store.apply(refreshed)
        XCTAssertEqual(store.snapshot.fetchedAt, refreshed.fetchedAt)
    }

    func testStatusBarQuotaTextOmitsZeroTotalSecondaryWindow() {
        var snapshot = CodexUsageSnapshot.preview
        snapshot.planName = "plus"
        snapshot.shortWindow = UsageWindow(label: "5 小时", remaining: 71, total: 100, resetsAt: "")
        snapshot.weekly = UsageWindow(label: "周额度", remaining: 0, total: 0, resetsAt: "")

        XCTAssertEqual(statusBarQuotaText(snapshot: snapshot, isLoggedIn: true), "5h 71%")
    }

    func testStatusBarQuotaTextUsesTheActualPrimaryWindowLabel() {
        var snapshot = CodexUsageSnapshot.preview
        snapshot.planName = "plus"
        snapshot.shortWindow = UsageWindow(label: "周额度", remaining: 51, total: 100, resetsAt: "")
        snapshot.weekly = UsageWindow(label: "周额度", remaining: 0, total: 0, resetsAt: "")

        XCTAssertEqual(statusBarQuotaText(snapshot: snapshot, isLoggedIn: true), "周 51%")
    }

    func testStatusBarQuotaTextHandlesNoValidQuota() {
        var snapshot = CodexUsageSnapshot.preview
        snapshot.shortWindow = nil
        snapshot.weekly = UsageWindow(label: "周额度", remaining: 0, total: 0, resetsAt: "未知")

        XCTAssertEqual(statusBarQuotaText(snapshot: snapshot, isLoggedIn: true), "无额度")
        XCTAssertEqual(statusBarQuotaText(snapshot: snapshot, isLoggedIn: false), "未登录")
    }

    func testDetailWindowFallsBackToThePrimaryWindow() throws {
        var snapshot = CodexUsageSnapshot.preview
        snapshot.shortWindow = UsageWindow(label: "周额度", remaining: 50, total: 100, resetsAt: "2026-07-21 15:12:08")
        snapshot.weekly = UsageWindow(label: "周额度", remaining: 0, total: 0, resetsAt: "未知")

        let detailWindow = try XCTUnwrap(snapshot.detailWindow)
        XCTAssertEqual(detailWindow.label, "周额度")
        XCTAssertEqual(detailWindow.resetsAt, "2026-07-21 15:12:08")
    }

    func testActivityParserDetectsWaitingForUser() {
        let jsonl = """
        {"timestamp":"2026-07-17T08:00:00Z","type":"event_msg","payload":{"type":"task_started"}}
        {"timestamp":"2026-07-17T08:00:01Z","type":"event_msg","payload":{"type":"agent_message","phase":"commentary","message":"我正在检查项目。"}}
        {"timestamp":"2026-07-17T08:00:02Z","type":"response_item","payload":{"type":"function_call","call_id":"call-1","name":"request_user_input","arguments":"{}"}}
        """
        let result = CodexActivityEventParser().parse(
            data: Data(jsonl.utf8),
            title: "测试任务",
            now: ISO8601DateFormatter().date(from: "2026-07-17T08:00:03Z")!
        )

        XCTAssertEqual(result.state, .waitingForUser)
        XCTAssertTrue(result.isActive)
        XCTAssertEqual(result.detail, "需要你的确认后才能继续")
    }

    func testActivityParserPreservesStableThreadID() {
        let jsonl = """
        {"timestamp":"2026-07-17T08:00:00Z","type":"event_msg","payload":{"type":"task_started"}}
        """
        let result = CodexActivityEventParser().parse(
            data: Data(jsonl.utf8),
            id: "thread-stable-id",
            title: "测试任务"
        )

        XCTAssertEqual(result.id, "thread-stable-id")
    }

    @MainActor
    func testCompanionStatsAccumulateOnlyActiveIntervalsAndPersist() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("companion-stats-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-22T08:00:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let store = CompanionStatsStore(fileURL: fileURL, now: start, calendar: calendar)

        store.setActivityState(.executing, now: start)
        store.tick(now: start.addingTimeInterval(60))
        store.setActivityState(.idle, now: start.addingTimeInterval(120))
        store.tick(now: start.addingTimeInterval(300))

        XCTAssertEqual(store.todayMinutes, 2)
        let restored = CompanionStatsStore(
            fileURL: fileURL,
            now: start.addingTimeInterval(300),
            calendar: calendar
        )
        XCTAssertEqual(restored.todayMinutes, 2)
    }

    @MainActor
    func testCompanionStatsCapSleepIntervalsAndResetAcrossDay() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("companion-stats-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-22T22:00:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let store = CompanionStatsStore(fileURL: fileURL, now: start, calendar: calendar)

        store.setActivityState(.thinking, now: start)
        store.tick(now: start.addingTimeInterval(600))
        XCTAssertEqual(store.todaySeconds, 90, accuracy: 0.001)

        store.tick(now: start.addingTimeInterval(7_200))
        XCTAssertEqual(store.todaySeconds, 0, accuracy: 0.001)
    }

    func testActivityParserKeepsRecentCompletionThenReturnsIdle() {
        let jsonl = """
        {"timestamp":"2026-07-17T08:00:00Z","type":"event_msg","payload":{"type":"task_started"}}
        {"timestamp":"2026-07-17T08:00:05Z","type":"event_msg","payload":{"type":"task_complete"}}
        """
        let parser = CodexActivityEventParser()
        let formatter = ISO8601DateFormatter()

        let recent = parser.parse(
            data: Data(jsonl.utf8),
            title: "测试任务",
            now: formatter.date(from: "2026-07-17T08:00:10Z")!
        )
        XCTAssertEqual(recent.state, .completed)

        let expired = parser.parse(
            data: Data(jsonl.utf8),
            title: "测试任务",
            now: formatter.date(from: "2026-07-17T08:00:30Z")!
        )
        XCTAssertEqual(expired.state, .idle)
    }

    func testActivityReaderExpandsPastFourMegabytesToKeepTaskState() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-activity-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var data = Data("{\"timestamp\":\"2026-07-17T08:00:00Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"}}\n".utf8)
        let filler = Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\"}}\n".utf8)
        while data.count < 5 * 1_024 * 1_024 {
            data.append(filler)
        }
        data.append(Data("{\"timestamp\":\"2026-07-17T08:01:00Z\",\"type\":\"response_item\",\"payload\":{\"type\":\"function_call\",\"call_id\":\"call-1\",\"name\":\"exec_command\",\"arguments\":\"{}\"}}\n".utf8))
        try data.write(to: fileURL)

        let service = CodexActivityService(databaseURLs: [])
        let parsed = CodexActivityEventParser().parse(
            data: try XCTUnwrap(service.readTail(of: fileURL)),
            title: "长任务"
        )

        XCTAssertEqual(parsed.state, .executing)
        XCTAssertTrue(parsed.isActive)
    }

    func testActivityServiceReturnsAllActiveTasksWithStableIDsAndPriority() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-activity-db-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executingURL = directory.appendingPathComponent("executing.jsonl")
        let waitingURL = directory.appendingPathComponent("waiting.jsonl")
        try Data("""
        {"timestamp":"2026-07-22T08:00:00Z","type":"event_msg","payload":{"type":"task_started"}}
        {"timestamp":"2026-07-22T08:00:01Z","type":"response_item","payload":{"type":"function_call","call_id":"call-1","name":"exec_command","arguments":"{}"}}
        """.utf8).write(to: executingURL)
        try Data("""
        {"timestamp":"2026-07-22T08:00:00Z","type":"event_msg","payload":{"type":"task_started"}}
        {"timestamp":"2026-07-22T08:00:02Z","type":"response_item","payload":{"type":"function_call","call_id":"call-2","name":"request_user_input","arguments":"{}"}}
        """.utf8).write(to: waitingURL)

        let databaseURL = directory.appendingPathComponent("state.sqlite")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, """
        CREATE TABLE threads (
            id TEXT PRIMARY KEY,
            rollout_path TEXT NOT NULL,
            title TEXT NOT NULL,
            archived INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        );
        """, nil, nil, nil), SQLITE_OK)
        let insert = """
        INSERT INTO threads VALUES
        ('thread-executing', '\(executingURL.path)', '执行任务', 0, 1),
        ('thread-waiting', '\(waitingURL.path)', '等待任务', 0, 2);
        """
        XCTAssertEqual(sqlite3_exec(database, insert, nil, nil, nil), SQLITE_OK)

        let snapshot = CodexActivityService(databaseURLs: [databaseURL]).loadSnapshot(
            now: ISO8601DateFormatter().date(from: "2026-07-22T08:00:03Z")!
        )

        XCTAssertEqual(snapshot.activeTaskCount, 1)
        XCTAssertEqual(snapshot.activeTasks.map(\.id), ["thread-waiting"])
        XCTAssertEqual(snapshot.activeTasks.map(\.state), [.waitingForUser])
        XCTAssertEqual(snapshot.state, .waitingForUser)
    }

    func testActivityServiceCountsOnlyConcurrentUserThreads() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-concurrent-db-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        func writeActivity(_ name: String, tool: String) throws -> URL {
            let url = directory.appendingPathComponent("\(name).jsonl")
            try Data("""
            {"timestamp":"2026-07-22T08:00:00Z","type":"event_msg","payload":{"type":"task_started"}}
            {"timestamp":"2026-07-22T08:00:01Z","type":"response_item","payload":{"type":"function_call","call_id":"\(name)","name":"\(tool)","arguments":"{}"}}
            """.utf8).write(to: url)
            return url
        }

        let firstURL = try writeActivity("first", tool: "exec_command")
        let secondURL = try writeActivity("second", tool: "view_image")
        let subagentURL = try writeActivity("guardian", tool: "exec_command")
        let databaseURL = directory.appendingPathComponent("state.sqlite")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, """
        CREATE TABLE threads (
            id TEXT PRIMARY KEY,
            rollout_path TEXT NOT NULL,
            title TEXT NOT NULL,
            archived INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            thread_source TEXT
        );
        """, nil, nil, nil), SQLITE_OK)
        let insert = """
        INSERT INTO threads VALUES
        ('thread-first', '\(firstURL.path)', '任务一', 0, 3, 'user'),
        ('thread-second', '\(secondURL.path)', '任务二', 0, 2, 'user'),
        ('thread-guardian', '\(subagentURL.path)', '守护进程', 0, 1, 'subagent');
        """
        XCTAssertEqual(sqlite3_exec(database, insert, nil, nil, nil), SQLITE_OK)

        let snapshot = CodexActivityService(databaseURLs: [databaseURL]).loadSnapshot(
            now: ISO8601DateFormatter().date(from: "2026-07-22T08:00:03Z")!
        )

        XCTAssertEqual(snapshot.activeTaskCount, 2)
        XCTAssertEqual(Set(snapshot.activeTasks.map(\.id)), ["thread-first", "thread-second"])
        XCTAssertFalse(snapshot.activeTasks.contains { $0.id == "thread-guardian" })
    }

    func testHoverContentUsesThreadTitleAndVisibleExecutionSummary() {
        let snapshot = CodexActivitySnapshot(
            state: .executing,
            detail: "正在运行本地命令",
            threadTitle: "规划状态栏 Pets 状态展示",
            activeTaskCount: 1,
            updatedAt: Date()
        )

        XCTAssertEqual(snapshot.hoverDisplayTitle, "规划状态栏 Pets 状态展示")
        XCTAssertEqual(snapshot.hoverSubtitle, "正在运行本地命令")
    }

    func testAsarArchiveReadsAndExtractsEntry() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let archiveURL = directory.appendingPathComponent("fixture.asar")
        let payload = Data("hello".utf8)
        let header = try JSONSerialization.data(withJSONObject: [
            "files": [
                "assets": [
                    "files": [
                        "hello.txt": ["size": payload.count, "offset": "0"]
                    ]
                ]
            ]
        ])
        var archiveData = Data()
        archiveData.append(littleEndian(4))
        archiveData.append(littleEndian(UInt32(header.count + 8)))
        archiveData.append(littleEndian(UInt32(header.count + 4)))
        archiveData.append(littleEndian(UInt32(header.count)))
        archiveData.append(header)
        archiveData.append(payload)
        try archiveData.write(to: archiveURL)

        let archive = try AsarArchive(url: archiveURL)
        let entry = try XCTUnwrap(archive.firstEntry { $0.hasSuffix("hello.txt") })
        let destination = directory.appendingPathComponent("out/hello.txt")
        try archive.extract(entry, to: destination)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "hello")
    }

    func testInstalledCodexBuiltInPetsAreDiscoverableWhenApplicationExists() throws {
        let application = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        guard FileManager.default.fileExists(atPath: application.path) else { return }

        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let catalog = CodexPetCatalog(
            customPetsRoot: temporaryRoot.appendingPathComponent("custom"),
            cacheRoot: temporaryRoot.appendingPathComponent("cache"),
            applicationURLs: [application]
        )
        let builtIns = catalog.discover().filter { $0.source == .codexBuiltIn }

        XCTAssertEqual(builtIns.count, 9)
        XCTAssertTrue(builtIns.allSatisfy { $0.rowCount >= 9 })
        XCTAssertTrue(builtIns.contains { $0.assetID == "codex" })
        XCTAssertTrue(builtIns.contains { $0.assetID == "hoots" })
    }

    func testInstalledCodexActivityIsReadableWhenDatabaseExists() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let database = home.appendingPathComponent(".codex/state_5.sqlite")
        guard FileManager.default.fileExists(atPath: database.path) else { return }

        let snapshot = CodexActivityService(databaseURLs: [database]).loadSnapshot()
        XCTAssertNotEqual(snapshot.state, .unavailable)
        XCTAssertFalse(snapshot.hoverSubtitle.isEmpty)
    }

    @MainActor
    func testLegacyTaskColorPreferenceMigratesToFollowQuota() throws {
        let suiteName = "CodexlingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("cyan", forKey: "codexling.petBackgroundColor")

        XCTAssertEqual(AppSettingsStore(defaults: defaults).petBackgroundColor, .automatic)
    }

    private func littleEndian(_ value: UInt32) -> Data {
        var little = value.littleEndian
        return withUnsafeBytes(of: &little) { Data($0) }
    }
}
