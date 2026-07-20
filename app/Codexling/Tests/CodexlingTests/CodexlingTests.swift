import Foundation
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
    }

    func testAutomaticPetBackgroundMapsEveryActivityState() {
        let automatic = StatusBarPetBackgroundColor.automatic
        XCTAssertEqual(automatic.resolved(for: .unavailable), .neutral)
        XCTAssertEqual(automatic.resolved(for: .idle), .neutral)
        XCTAssertEqual(automatic.resolved(for: .thinking), .purple)
        XCTAssertEqual(automatic.resolved(for: .executing), .blue)
        XCTAssertEqual(automatic.resolved(for: .reviewing), .cyan)
        XCTAssertEqual(automatic.resolved(for: .waitingForUser), .amber)
        XCTAssertEqual(automatic.resolved(for: .completed), .green)
        XCTAssertEqual(automatic.resolved(for: .interrupted), .red)
        XCTAssertEqual(StatusBarPetBackgroundColor.green.resolved(for: .interrupted), .green)
    }

    @MainActor
    func testPetBackgroundDefaultsToNeutralAndListsItFirst() throws {
        let suiteName = "CodexlingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(settings.petBackgroundColor, .neutral)
        XCTAssertEqual(StatusBarPetBackgroundColor.allCases.first, .neutral)
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
    func testStatusCapsulePressInvokesPopoverAction() {
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
        settings.petBackgroundColor = .cyan

        let restored = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(restored.petBackgroundColor, .cyan)
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
    func testStatusBarClickBehaviorDefaultsToDetachedWindowAndPersists() throws {
        let suiteName = "CodexlingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(settings.statusBarClickBehavior, .detachedWindow)

        settings.statusBarClickBehavior = .popover
        let restored = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(restored.statusBarClickBehavior, .popover)
    }

    @MainActor
    func testDetachedWindowHeightNeverExceedsVisibleViewport() {
        let maximum = DetachedWindowMetrics.maximumContentHeight(for: NSScreen.main)
        if let visibleHeight = NSScreen.main?.visibleFrame.height {
            XCTAssertLessThanOrEqual(maximum, visibleHeight - 32)
        }

        let clamped = DetachedWindowMetrics.clampContentSize(
            NSSize(width: 460, height: 10_000),
            screen: NSScreen.main
        )
        XCTAssertLessThanOrEqual(clamped.height, maximum)
    }

    func testPopoverHeightFollowsContentAndNeverExceedsViewport() {
        XCTAssertEqual(
            PopoverMetrics.targetHeight(
                contentHeight: 620,
                visibleHeight: 900,
                margin: 28,
                minimumHeight: 760
            ),
            760
        )
        XCTAssertEqual(
            PopoverMetrics.targetHeight(
                contentHeight: 1_200,
                visibleHeight: 900,
                margin: 28,
                minimumHeight: 760
            ),
            872
        )
        XCTAssertEqual(
            PopoverMetrics.targetHeight(
                contentHeight: 620,
                visibleHeight: 700,
                margin: 28,
                minimumHeight: 760
            ),
            672
        )
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

    private func littleEndian(_ value: UInt32) -> Data {
        var little = value.littleEndian
        return withUnsafeBytes(of: &little) { Data($0) }
    }
}
