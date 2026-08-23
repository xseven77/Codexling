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

    func testActivityShimmerMotionAdvancesAndWrapsDeterministically() {
        let start = ActivityShimmerMotion.offset(
            canvasWidth: 100,
            bandWidth: 40,
            at: 0
        )
        let halfway = ActivityShimmerMotion.offset(
            canvasWidth: 100,
            bandWidth: 40,
            at: ActivityShimmerMotion.duration / 2
        )
        let wrapped = ActivityShimmerMotion.offset(
            canvasWidth: 100,
            bandWidth: 40,
            at: ActivityShimmerMotion.duration
        )

        XCTAssertEqual(start, -40, accuracy: 0.0001)
        XCTAssertGreaterThan(halfway, start)
        XCTAssertEqual(wrapped, start, accuracy: 0.0001)
    }

    func testStatusCapsuleReminderColorOnlyDefinesForeground() {
        XCTAssertNotEqual(
            StatusBarPetBackgroundColor.green.foregroundColor(for: .light),
            StatusBarPetBackgroundColor.yellow.foregroundColor(for: .light)
        )
        XCTAssertNotEqual(
            StatusBarPetBackgroundColor.yellow.foregroundColor(for: .light),
            StatusBarPetBackgroundColor.red.foregroundColor(for: .light)
        )
        XCTAssertNotEqual(
            StatusBarPetBackgroundColor.gray.foregroundColor(for: .light),
            StatusBarPetBackgroundColor.gray.foregroundColor(for: .dark)
        )
    }

    @MainActor
    func testStatusCapsuleUsesThemeLockedNeutralSurface() {
        let view = StatusCapsuleView(
            frame: NSRect(x: 0, y: 0, width: 120, height: 26)
        )
        XCTAssertTrue(
            view.usesThemeLockedNeutralSurfaceForTesting,
            "状态栏胶囊必须使用不随壁纸明暗翻转的主题中性色"
        )
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

    @MainActor
    func testAccountCarouselDefaultsOffAndPersistsInterval() throws {
        let suiteName = "CodexlingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(settings.accountCarouselInterval, .off)

        settings.accountCarouselInterval = .seconds10

        XCTAssertEqual(defaults.integer(forKey: "codexling.accountCarouselInterval"), 10)
        XCTAssertEqual(AppSettingsStore(defaults: defaults).accountCarouselInterval, .seconds10)
    }

    @MainActor
    func testSilentLaunchDefaultsOffAndPersists() throws {
        let suiteName = "CodexlingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettingsStore(defaults: defaults)
        XCTAssertFalse(settings.silentLaunchEnabled)
        XCTAssertTrue(settings.shouldOpenMainWindowAtLaunch)

        settings.silentLaunchEnabled = true

        let restored = AppSettingsStore(defaults: defaults)
        XCTAssertTrue(restored.silentLaunchEnabled)
        XCTAssertFalse(restored.shouldOpenMainWindowAtLaunch)
    }

    func testConnectionCarouselAdvancesWrapsAndRecoversMissingSelection() {
        let keys = ["codex.first", "codex.second", "deepseek.first"]

        XCTAssertEqual(ConnectionCarousel.nextKey(after: keys[0], availableKeys: keys), keys[1])
        XCTAssertEqual(ConnectionCarousel.nextKey(after: keys[2], availableKeys: keys), keys[0])
        XCTAssertEqual(ConnectionCarousel.nextKey(after: "missing", availableKeys: keys), keys[0])
        XCTAssertNil(ConnectionCarousel.nextKey(after: keys[0], availableKeys: [keys[0]]))
        XCTAssertNil(ConnectionCarousel.nextKey(after: keys[0], availableKeys: []))
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

    func testCompanionPanelRoutesOverlappingAnchorClickToDismiss() throws {
        let anchor = NSRect(x: 100, y: 300, width: 120, height: 30)
        let overlappingPanel = NSRect(x: 80, y: 160, width: 286, height: 150)
        let capture = try XCTUnwrap(
            CompanionPanelAnchorClickRouting.captureRect(
                anchorFrame: anchor,
                panelFrame: overlappingPanel
            )
        )
        XCTAssertEqual(capture, NSRect(x: 20, y: 140, width: 120, height: 10))

        let detachedPanel = NSRect(x: 80, y: 140, width: 286, height: 150)
        XCTAssertNil(
            CompanionPanelAnchorClickRouting.captureRect(
                anchorFrame: anchor,
                panelFrame: detachedPanel
            )
        )
    }

    @MainActor
    func testStatusCapsulePressInvokesClickAction() async {
        let view = StatusCapsuleView(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        var clickCount = 0
        let pressed = expectation(description: "accessibility press finishes asynchronously")
        view.onClick = {
            clickCount += 1
            pressed.fulfill()
        }

        XCTAssertTrue(view.accessibilityPerformPress())
        await fulfillment(of: [pressed], timeout: 1)
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
    func testStatusCapsuleHoverCallbacksRemainConnected() throws {
        let view = StatusCapsuleView(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        var entries = 0
        var exits = 0
        view.onMouseEntered = { entries += 1 }
        view.onMouseExited = { exits += 1 }
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved,
            location: NSPoint(x: 20, y: 12),
            modifierFlags: [],
            timestamp: 10,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 0,
            pressure: 0
        ))

        view.mouseEntered(with: event)
        view.mouseExited(with: event)

        XCTAssertEqual(entries, 1)
        XCTAssertEqual(exits, 1)
    }

    @MainActor
    func testStatusCapsuleReceivesPointerEvents() {
        let view = StatusCapsuleView(frame: NSRect(x: 0, y: 0, width: 120, height: 24))

        XCTAssertTrue(view.hitTest(NSPoint(x: 40, y: 12)) === view)
        XCTAssertNil(view.hitTest(NSPoint(x: 140, y: 12)))
    }

    @MainActor
    func testStatusCapsulePressCreatesMaterialRipple() throws {
        let view = StatusCapsuleView(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 40, y: 12),
            modifierFlags: [],
            timestamp: 10,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))

        view.mouseDown(with: event)

        XCTAssertEqual(view.activeMaterialRippleCountForTesting, 1)
    }

    @MainActor
    func testStatusCapsuleUsesTheSharedRotatingBorderFlow() {
        let view = StatusCapsuleView(frame: NSRect(x: 0, y: 0, width: 120, height: 24))

        XCTAssertEqual(
            view.activityFlowPresentationForTesting,
            .rotatingBorder(lineWidth: 2)
        )
    }

    func testActivityWaveTimingsRemainSharedAcrossSurfaces() {
        XCTAssertEqual(ActivityWaveTiming.duration, 3.6)
        XCTAssertEqual(ActivityWaveTiming.capsuleDuration, 1.8)
        XCTAssertEqual(ActivityWaveTiming.rotatingBorderDuration, 2.4)
        XCTAssertEqual(ActivityWaveTiming.progress(at: 0), 0, accuracy: 0.001)
        XCTAssertEqual(ActivityWaveTiming.progress(at: 1.8), 0.5, accuracy: 0.001)
        XCTAssertEqual(ActivityWaveTiming.progress(at: 3.6), 0, accuracy: 0.001)
        XCTAssertEqual(ActivityWaveTiming.capsuleProgress(at: 0), 0, accuracy: 0.001)
        XCTAssertEqual(ActivityWaveTiming.capsuleProgress(at: 0.9), 0.5, accuracy: 0.001)
        XCTAssertEqual(ActivityWaveTiming.capsuleProgress(at: 1.8), 0, accuracy: 0.001)
        XCTAssertEqual(ActivityWaveTiming.capsuleProgress(at: 3.6), 0, accuracy: 0.001)
        XCTAssertEqual(ActivityWaveTiming.rotatingBorderProgress(at: 1.2), 0.5, accuracy: 0.001)
        XCTAssertEqual(ActivityWaveTiming.rotatingBorderProgress(at: 2.4), 0, accuracy: 0.001)
    }

    func testOnlyActiveCodexStatesShowTheSharedActivityWave() {
        XCTAssertFalse(CodexActivityState.unavailable.showsActivityWave)
        XCTAssertFalse(CodexActivityState.idle.showsActivityWave)

        let activeStates: [CodexActivityState] = [
            .thinking,
            .executing,
            .reviewing,
            .waitingForUser,
            .completed,
            .interrupted,
        ]
        XCTAssertTrue(activeStates.allSatisfy(\.showsActivityWave))
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
    func testStatusBarIndicatorDefaultsToActivityStateAndPersists() throws {
        let suiteName = "CodexlingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(settings.statusBarIndicatorColorMode, .activityState)

        settings.statusBarIndicatorColorMode = .quotaHealth
        XCTAssertEqual(
            AppSettingsStore(defaults: defaults).statusBarIndicatorColorMode,
            .quotaHealth
        )
    }

    @MainActor
    func testStatusCapsuleSolidColorsPersistAndLegacyNeutralMigrates() throws {
        let suiteName = "CodexlingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettingsStore(defaults: defaults)
        settings.statusBarIndicatorColorMode = .cyan
        settings.statusBarWaveColorMode = .orange

        let restored = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(restored.statusBarIndicatorColorMode, .cyan)
        XCTAssertEqual(restored.statusBarWaveColorMode, .orange)
        XCTAssertFalse(StatusCapsuleColorMode.allCases.map(\.rawValue).contains("neutral"))
        XCTAssertFalse(StatusCapsuleColorMode.activityFlowCases.contains(.quotaHealth))

        defaults.set("neutral", forKey: "codexling.statusBarWaveColorMode")
        XCTAssertEqual(
            AppSettingsStore(defaults: defaults).statusBarWaveColorMode,
            .activityState
        )

        defaults.set("quotaHealth", forKey: "codexling.statusBarWaveColorMode")
        XCTAssertEqual(
            AppSettingsStore(defaults: defaults).statusBarWaveColorMode,
            .activityState
        )
    }

    @MainActor
    func testStatusCapsuleAutomaticForegroundFollowsMenuBarAppearanceWithoutVibrancy() throws {
        let view = StatusCapsuleView(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        let vibrantLight = try XCTUnwrap(NSAppearance(named: .vibrantLight))
        let vibrantDark = try XCTUnwrap(NSAppearance(named: .vibrantDark))

        XCTAssertFalse(view.allowsVibrancy)
        XCTAssertEqual(
            StatusCapsuleView.automaticMenuBarForegroundColor(appearance: vibrantLight),
            .black
        )
        XCTAssertEqual(
            StatusCapsuleView.automaticMenuBarForegroundColor(appearance: vibrantDark),
            .white
        )
    }

    func testTaskHoverDismissalLastsUntilActiveTasksEnd() {
        var state = TaskHoverPresentationState()
        state.update(hasActiveTasks: true)
        XCTAssertTrue(state.shouldAutoPresent(isEnabled: true))

        state.dismiss()
        XCTAssertFalse(state.shouldAutoPresent(isEnabled: true))
        state.update(hasActiveTasks: true)
        XCTAssertFalse(state.shouldAutoPresent(isEnabled: true))

        state.update(hasActiveTasks: false)
        state.update(hasActiveTasks: true)
        XCTAssertTrue(state.shouldAutoPresent(isEnabled: true))
        XCTAssertFalse(state.shouldAutoPresent(isEnabled: false))
    }

    func testTaskHoverCloseButtonStaysInsideCardAndClearOfContent() {
        let cardSize = NSSize(width: 340, height: 112)
        let cardBounds = NSRect(origin: .zero, size: cardSize)
        let closeFrame = PetHoverCloseButtonLayout.frame(in: cardSize)
        let contentMaxX =
            cardSize.width - PetHoverCloseButtonLayout.activeContentTrailingPadding

        XCTAssertTrue(cardBounds.contains(closeFrame))
        XCTAssertEqual(
            cardBounds.maxX - closeFrame.maxX,
            PetHoverCloseButtonLayout.edgeInset
        )
        XCTAssertEqual(
            cardBounds.maxY - closeFrame.maxY,
            PetHoverCloseButtonLayout.edgeInset
        )
        XCTAssertGreaterThanOrEqual(
            closeFrame.minX - contentMaxX,
            PetHoverCloseButtonLayout.edgeInset
        )
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
    func testStatusBarOpacityDefaultsToTwentyPersistsAndClamps() throws {
        let suiteName = "CodexlingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(settings.statusBarOpacityPercent, 20)

        settings.statusBarOpacityPercent = 45
        XCTAssertEqual(AppSettingsStore(defaults: defaults).statusBarOpacityPercent, 45)

        defaults.set(140.0, forKey: "codexling.statusBarOpacityPercent")
        XCTAssertEqual(AppSettingsStore(defaults: defaults).statusBarOpacityPercent, 50)
    }

    @MainActor
    func testDetachedWindowHeightsRespectVisibleViewport() {
        let dashboardMaximum = DetachedWindowMetrics.maximumContentHeight(for: NSScreen.main)
        if let visibleHeight = NSScreen.main?.visibleFrame.height {
            XCTAssertLessThanOrEqual(dashboardMaximum, visibleHeight - 32)
        }

        let clamped = DetachedWindowMetrics.clampSettingsContentSize(
            NSSize(width: 460, height: 10_000),
            screen: NSScreen.main
        )
        let settingsMaximum = DetachedWindowMetrics.maximumSettingsWindowHeight(for: NSScreen.main)
        XCTAssertGreaterThanOrEqual(clamped.width, DetachedWindowMetrics.dashboardWidth)
        XCTAssertLessThanOrEqual(clamped.height, settingsMaximum)
    }

    @MainActor
    func testSettingsWindowStartsCompactAndUsesNaturalContentHeight() {
        let settingsMaximum = DetachedWindowMetrics.maximumSettingsWindowHeight(for: NSScreen.main)
        let provisional = DetachedWindowMetrics.settingsWindowProvisionalHeight(screen: NSScreen.main)
        XCTAssertEqual(provisional, min(560, settingsMaximum))

        let shortContent = DetachedWindowMetrics.preferredSettingsWindowSize(
            contentHeight: 240,
            screen: NSScreen.main
        )
        XCTAssertEqual(shortContent.height, min(DetachedWindowMetrics.settingsMinWindowHeight, settingsMaximum))

        let naturalContentHeight = min(480, settingsMaximum)
        let naturalContent = DetachedWindowMetrics.preferredSettingsWindowSize(
            contentHeight: naturalContentHeight,
            screen: NSScreen.main
        )
        XCTAssertEqual(naturalContent.height, max(
            min(naturalContentHeight, settingsMaximum),
            min(DetachedWindowMetrics.settingsMinWindowHeight, settingsMaximum)
        ))
    }

    @MainActor
    func testNativeWindowDraggingDoesNotInjectTitlebarHitTestOverlays() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 610, height: 420),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let frameView = try XCTUnwrap(window.contentView?.superview)
        let originalSubviews = frameView.subviews

        WindowDraggingPolicy.apply(to: window)

        XCTAssertTrue(window.isMovableByWindowBackground)
        XCTAssertEqual(frameView.subviews, originalSubviews)
    }

    @MainActor
    func testLogoRowHoverCanTemporarilyDisableNativeWindowDragging() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 610, height: 420),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        WindowDraggingPolicy.apply(to: window, isEnabled: false)
        XCTAssertFalse(window.isMovableByWindowBackground)

        WindowDraggingPolicy.apply(to: window, isEnabled: true)
        XCTAssertTrue(window.isMovableByWindowBackground)
    }

    @MainActor
    func testTrafficLightsAndCustomTitleControlsRemainClickableWithNativeDragging() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 610, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        WindowDraggingPolicy.apply(to: window)
        let frameView = try XCTUnwrap(window.contentView?.superview)
        frameView.layoutSubtreeIfNeeded()
        let closeButton = try XCTUnwrap(window.standardWindowButton(.closeButton))
        let closeCenter = frameView.convert(
            NSPoint(x: closeButton.bounds.midX, y: closeButton.bounds.midY),
            from: closeButton
        )
        XCTAssertTrue(frameView.hitTest(closeCenter) === closeButton)

        let controls = TitleControlsView(onToggleOrientation: {}, onTogglePin: {})
        controls.frame = NSRect(x: 200, y: 388, width: 66, height: 28)
        frameView.addSubview(controls, positioned: .above, relativeTo: nil)
        controls.update(
            orientation: .horizontal,
            isPinned: false,
            appearance: try XCTUnwrap(NSAppearance(named: .aqua))
        )
        let titleButtons = controls.subviews.compactMap { $0 as? NSButton }
        XCTAssertEqual(titleButtons.count, 2)
        XCTAssertTrue(titleButtons.allSatisfy { !$0.mouseDownCanMoveWindow })
    }

    @MainActor
    func testClosingAndRecreatingWindowPreservesDraggingAndTrafficLightHitTesting() throws {
        func makeWindow() throws -> NSWindow {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 610, height: 420),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            WindowDraggingPolicy.apply(to: window)
            return window
        }

        let first = try makeWindow()
        first.close()
        let reopened = try makeWindow()
        let frameView = try XCTUnwrap(reopened.contentView?.superview)
        frameView.layoutSubtreeIfNeeded()
        let closeButton = try XCTUnwrap(reopened.standardWindowButton(.closeButton))
        let closeCenter = frameView.convert(
            NSPoint(x: closeButton.bounds.midX, y: closeButton.bounds.midY),
            from: closeButton
        )

        XCTAssertTrue(reopened.isMovableByWindowBackground)
        XCTAssertTrue(frameView.hitTest(closeCenter) === closeButton)
    }

    @MainActor
    func testWindowEventScopeKeepsMainAndSettingsWindowsIndependent() {
        let mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 610, height: 420),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 610, height: 520),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(WindowEventScope.matches(eventWindow: mainWindow, targetWindow: mainWindow))
        XCTAssertTrue(WindowEventScope.matches(eventWindow: settingsWindow, targetWindow: settingsWindow))
        XCTAssertFalse(WindowEventScope.matches(eventWindow: settingsWindow, targetWindow: mainWindow))
        XCTAssertFalse(WindowEventScope.matches(eventWindow: mainWindow, targetWindow: settingsWindow))
        XCTAssertFalse(WindowEventScope.matches(eventWindow: nil, targetWindow: mainWindow))
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

    func testSubscriptionParserReadsActiveUntilAndWillRenew() {
        let payload: [String: Any] = [
            "plan_type": "plus",
            "active_until": "2026-08-21T06:22:29Z",
            "will_renew": 1,
        ]
        let parsed = CodexlingParser().parseSubscription(payload)
        XCTAssertEqual(parsed.activeUntilISO, "2026-08-21T06:22:29Z")
        XCTAssertEqual(parsed.willRenew, true)
    }

    func testSubscriptionExpiryReminderWithinSevenDays() {
        let expiry = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        let iso = ISO8601DateFormatter().string(from: expiry)
        var snapshot = CodexUsageSnapshot.preview
        snapshot.subscriptionActiveUntilISO = iso
        snapshot.subscriptionWillRenew = false
        XCTAssertTrue(snapshot.showsSubscriptionExpiryReminder)
        XCTAssertNotNil(snapshot.subscriptionExpiryReminderMessage)
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

    func testResetCouponTimelineHasATenDayMinimumAndPreservesLongerExpiry() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let formatter = ISO8601DateFormatter()
        let now = try XCTUnwrap(formatter.date(from: "2026-07-30T12:00:00Z"))
        let today = calendar.startOfDay(for: now)

        let shortCoupon = ResetCoupon(
            name: "Short",
            count: 1,
            expiresAt: formatter.string(from: calendar.date(byAdding: .day, value: 2, to: today)!),
            source: "Codex"
        )
        let minimumRange = ResetCouponDateParser.timelineRange(
            for: [shortCoupon],
            relativeTo: now,
            calendar: calendar
        )
        XCTAssertEqual(
            calendar.dateComponents([.day], from: minimumRange.min, to: minimumRange.max).day,
            10
        )
        let shortExpiry = try XCTUnwrap(ResetCouponDateParser.date(from: shortCoupon.expiresAt))
        XCTAssertEqual(
            ResetCouponDateParser.fraction(of: shortExpiry, in: minimumRange),
            0.2,
            accuracy: 0.0001
        )

        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        let tomorrowRange = ResetCouponDateParser.timelineRange(
            for: [shortCoupon],
            relativeTo: tomorrow,
            calendar: calendar
        )
        XCTAssertEqual(
            ResetCouponDateParser.fraction(of: shortExpiry, in: tomorrowRange),
            0.1,
            accuracy: 0.0001
        )

        let laterExpiry = try XCTUnwrap(calendar.date(byAdding: .day, value: 14, to: today))
        let longCoupon = ResetCoupon(
            name: "Long",
            count: 1,
            expiresAt: formatter.string(from: laterExpiry),
            source: "Codex"
        )
        let extendedRange = ResetCouponDateParser.timelineRange(
            for: [longCoupon],
            relativeTo: now,
            calendar: calendar
        )
        XCTAssertEqual(extendedRange.max, laterExpiry)
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

    @MainActor
    func testStatusCapsuleReservesStableWidthForEachQuotaLayout() {
        var snapshot = CodexUsageSnapshot.preview
        snapshot.shortWindow = UsageWindow(label: "5 小时", remaining: 71, total: 100, resetsAt: "")
        snapshot.weekly = UsageWindow(label: "周额度", remaining: 0, total: 0, resetsAt: "")
        XCTAssertEqual(
            statusCapsuleReservedText(snapshot: snapshot, isLoggedIn: true, showsActivity: false),
            "5h 99%"
        )

        snapshot.shortWindow = nil
        snapshot.weekly = UsageWindow(label: "周额度", remaining: 51, total: 100, resetsAt: "")
        XCTAssertEqual(
            statusCapsuleReservedText(snapshot: snapshot, isLoggedIn: true, showsActivity: false),
            "周 99%"
        )

        snapshot.shortWindow = UsageWindow(label: "5 小时", remaining: 71, total: 100, resetsAt: "")
        XCTAssertEqual(
            statusCapsuleReservedText(snapshot: snapshot, isLoggedIn: true, showsActivity: false),
            "5h 99%·周 99%"
        )
        XCTAssertEqual(
            statusCapsuleReservedText(snapshot: snapshot, isLoggedIn: true, showsActivity: true),
            "思考中·5h 99%·周 99%"
        )

        if let outputPath = ProcessInfo.processInfo.environment["CODEXLING_CAPSULE_DEBUG_OUTPUT"] {
            try? renderStatusCapsuleDebugGallery(to: outputPath)
        }
    }

    @MainActor
    func testEveryActivityStateUsesTheExpectedCompactCapsuleWidth() {
        let expectedLabels: [CodexActivityState: String?] = [
            .unavailable: nil,
            .idle: nil,
            .thinking: "思考中",
            .executing: "工作中",
            .reviewing: "检查中",
            .waitingForUser: "待确认",
            .completed: "已完成",
            .interrupted: "已中止",
        ]
        XCTAssertEqual(CodexActivityState.allCases.count, expectedLabels.count)

        var widths: [CGFloat] = []
        for state in CodexActivityState.allCases {
            XCTAssertEqual(state.statusBarText, expectedLabels[state] ?? nil)
            guard let statusText = state.statusBarText else { continue }
            XCTAssertEqual(statusText.count, 3, "\(state.rawValue) 不应超过三个字符")

            let capsule = StatusCapsuleView(frame: NSRect(x: 0, y: 0, width: 1, height: 26))
            capsule.update(
                background: .neutral,
                text: "\(statusText)·周 90%",
                reservedText: "思考中·周 99%",
                foregroundColor: StatusBarPetBackgroundColor.neutral.foregroundColor,
                showsPet: false,
                indicatorColor: .systemGreen,
                showsWave: false,
                cornerRatio: 0.5
            )
            widths.append(capsule.preferredWidth)
        }

        XCTAssertEqual(Set(widths).count, 1, "所有有文案的活动状态必须保持相同胶囊宽度")

        if let outputPath = ProcessInfo.processInfo.environment[
            "CODEXLING_CAPSULE_COLOR_DEBUG_OUTPUT"
        ] {
            try? renderStatusCapsuleColorAndIndicatorGallery(to: outputPath)
        }
    }

    @MainActor
    private func renderStatusCapsuleDebugGallery(to outputPath: String) throws {
        var cases: [(String, String, String)] = [
            ("仅周 · 单位数", "周 9%", "周 99%"),
            ("仅周 · 常态", "周 90%", "周 99%"),
            ("仅周 · 满额", "周 100%", "周 99%"),
            ("仅 5h", "5h 90%", "5h 99%"),
            ("双额度", "5h 90%·周 90%", "5h 99%·周 99%"),
        ]
        cases.append(contentsOf: CodexActivityState.allCases.map { state in
            let text = state.statusBarText.map { "\($0)·周 90%" } ?? "周 90%"
            let reserved = state.statusBarText == nil ? "周 99%" : "思考中·周 99%"
            return ("状态 · \(state.rawValue)", text, reserved)
        })
        cases.append(
            ("状态 + 双额度", "工作中·5h 90%·周 90%", "思考中·5h 99%·周 99%")
        )
        let rowHeight: CGFloat = 44
        let canvasSize = NSSize(width: 470, height: rowHeight * CGFloat(cases.count) + 20)
        let image = NSImage(size: canvasSize)

        image.lockFocus()
        NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
        NSRect(origin: .zero, size: canvasSize).fill()

        for (index, item) in cases.enumerated() {
            let y = canvasSize.height - 20 - rowHeight * CGFloat(index + 1)
            item.0.draw(
                at: NSPoint(x: 16, y: y + 13),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            )

            let capsule = StatusCapsuleView(frame: NSRect(x: 0, y: 0, width: 1, height: 26))
            capsule.update(
                background: .neutral,
                text: item.1,
                reservedText: item.2,
                foregroundColor: StatusBarPetBackgroundColor.neutral.foregroundColor,
                showsPet: false,
                indicatorColor: .systemGreen,
                showsWave: false,
                cornerRatio: 0.5
            )
            capsule.frame.size.width = capsule.preferredWidth
            guard let representation = capsule.bitmapImageRepForCachingDisplay(in: capsule.bounds) else {
                continue
            }
            capsule.cacheDisplay(in: capsule.bounds, to: representation)
            representation.draw(
                in: NSRect(
                    x: 150,
                    y: y + 8,
                    width: capsule.bounds.width,
                    height: capsule.bounds.height
                )
            )
        }
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
    }

    @MainActor
    private func renderStatusCapsuleColorAndIndicatorGallery(to outputPath: String) throws {
        let backgrounds: [(String, StatusBarPetBackgroundColor)] = [
            ("健康绿", .green),
            ("提醒黄", .yellow),
            ("告警红", .red),
            ("未知灰", .gray),
        ]
        let states = CodexActivityState.allCases
        let columnWidth: CGFloat = 220
        let rowHeight: CGFloat = 47
        let canvasSize = NSSize(
            width: 132 + columnWidth * CGFloat(backgrounds.count),
            height: 100 + rowHeight * CGFloat(states.count)
        )
        let image = NSImage(size: canvasSize)

        image.lockFocus()
        NSGradient(colors: [
            NSColor(srgbRed: 0.93, green: 0.95, blue: 0.87, alpha: 1),
            NSColor(srgbRed: 0.98, green: 0.98, blue: 0.97, alpha: 1),
        ])?.draw(
            from: NSPoint(x: canvasSize.width / 2, y: 0),
            to: NSPoint(x: canvasSize.width / 2, y: canvasSize.height),
            options: []
        )

        "固定中性底 × 提醒文字色 × 任务圆灯".draw(
            at: NSPoint(x: 20, y: canvasSize.height - 34),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: NSColor.labelColor,
            ]
        )

        for (column, background) in backgrounds.enumerated() {
            background.0.draw(
                at: NSPoint(
                    x: 132 + CGFloat(column) * columnWidth + 72,
                    y: canvasSize.height - 64
                ),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: background.1.foregroundColor,
                ]
            )
        }

        for (row, state) in states.enumerated() {
            let rowY = canvasSize.height - 94 - rowHeight * CGFloat(row + 1)
            state.rawValue.draw(
                at: NSPoint(x: 20, y: rowY + 9),
                withAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            )

            for (column, background) in backgrounds.enumerated() {
                let statusText = state.statusBarText
                let text = statusText.map { "\($0)·周 82%" } ?? "周 82%"
                let reservedText = statusText == nil ? "周 99%" : "思考中·周 99%"
                let capsule = StatusCapsuleView(
                    frame: NSRect(x: 0, y: 0, width: 1, height: 26)
                )
                capsule.update(
                    background: background.1,
                    text: text,
                    reservedText: reservedText,
                    foregroundColor: background.1.foregroundColor,
                    showsPet: false,
                    indicatorColor: state.statusNSColor,
                    showsWave: false,
                    cornerRatio: 0.5
                )
                capsule.frame.size.width = capsule.preferredWidth

                let x = 132
                    + CGFloat(column) * columnWidth
                    + (columnWidth - capsule.bounds.width) / 2
                let scale: CGFloat = 2
                guard let representation = NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: Int(capsule.bounds.width * scale),
                    pixelsHigh: Int(capsule.bounds.height * scale),
                    bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true,
                    isPlanar: false,
                    colorSpaceName: .deviceRGB,
                    bytesPerRow: 0,
                    bitsPerPixel: 0
                ) else {
                    continue
                }
                representation.size = capsule.bounds.size
                if let bitmapContext = NSGraphicsContext(bitmapImageRep: representation) {
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = bitmapContext
                    NSColor.clear.setFill()
                    capsule.bounds.fill(using: .copy)
                    NSGraphicsContext.restoreGraphicsState()
                }
                capsule.cacheDisplay(in: capsule.bounds, to: representation)
                let targetRect = NSRect(
                    x: x,
                    y: rowY + 3,
                    width: capsule.bounds.width,
                    height: capsule.bounds.height
                )
                NSGraphicsContext.saveGraphicsState()
                let capsuleClipRect = targetRect.insetBy(dx: 0.5, dy: 0.5)
                NSBezierPath(
                    roundedRect: capsuleClipRect,
                    xRadius: capsuleClipRect.height / 2,
                    yRadius: capsuleClipRect.height / 2
                ).addClip()
                representation.draw(in: targetRect)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
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

    func testActivitySnapshotStabilizerIgnoresOneTransientTaskRemoval() {
        let now = Date()
        let first = CodexTaskActivity(
            id: "first",
            state: .thinking,
            detail: "分析中",
            title: "任务一",
            updatedAt: now
        )
        let second = CodexTaskActivity(
            id: "second",
            state: .executing,
            detail: "执行中",
            title: "任务二",
            updatedAt: now
        )
        let current = CodexActivitySnapshot(
            state: .thinking,
            detail: first.detail,
            threadTitle: first.title,
            activeTaskCount: 2,
            updatedAt: now,
            activeTasks: [first, second]
        )
        let transient = CodexActivitySnapshot(
            state: .thinking,
            detail: first.detail,
            threadTitle: first.title,
            activeTaskCount: 1,
            updatedAt: now,
            activeTasks: [first]
        )
        var stabilizer = CodexActivitySnapshotStabilizer()

        XCTAssertNil(stabilizer.resolve(current: current, candidate: transient))
        XCTAssertEqual(
            stabilizer.resolve(current: current, candidate: current),
            current
        )
        XCTAssertNil(stabilizer.resolve(current: current, candidate: transient))
    }

    func testActivitySnapshotStabilizerAcceptsConfirmedTaskRemoval() {
        let now = Date()
        let task = CodexTaskActivity(
            id: "task",
            state: .executing,
            detail: "执行中",
            title: "任务",
            updatedAt: now
        )
        let current = CodexActivitySnapshot(
            state: .executing,
            detail: task.detail,
            threadTitle: task.title,
            activeTaskCount: 1,
            updatedAt: now,
            activeTasks: [task]
        )
        let idle = CodexActivitySnapshot(
            state: .idle,
            detail: "当前没有正在执行的 Codex 任务",
            threadTitle: task.title,
            activeTaskCount: 0,
            updatedAt: now
        )
        var stabilizer = CodexActivitySnapshotStabilizer()

        XCTAssertNil(stabilizer.resolve(current: current, candidate: idle))
        XCTAssertEqual(
            stabilizer.resolve(current: current, candidate: idle),
            idle
        )
    }

    func testActiveAgentStatusesGroupTasksAndKeepFreshestAgentState() {
        let now = Date()
        let snapshot = CodexActivitySnapshot(
            state: .executing,
            detail: "多个 Agent 正在工作",
            threadTitle: "多 Agent",
            activeTaskCount: 3,
            updatedAt: now,
            activeTasks: [
                CodexTaskActivity(
                    id: "codex-task",
                    state: .thinking,
                    detail: "Codex 正在思考",
                    title: "规划轮播状态",
                    updatedAt: now.addingTimeInterval(-2),
                    model: "gpt-5.6-sol"
                ),
                CodexTaskActivity(
                    id: "hermes-new",
                    state: .executing,
                    detail: "Hermes 正在使用工具",
                    title: "Hermes · CLI",
                    updatedAt: now,
                    model: "Hermes"
                ),
                CodexTaskActivity(
                    id: "hermes-old",
                    state: .thinking,
                    detail: "Hermes 正在思考",
                    title: "Hermes · CLI",
                    updatedAt: now.addingTimeInterval(-5),
                    model: "Hermes"
                )
            ]
        )

        XCTAssertEqual(snapshot.activeAgentStatuses.map(\.agentName), ["Hermes", "Codex"])
        XCTAssertEqual(snapshot.activeAgentStatuses[0].state, .executing)
        XCTAssertEqual(snapshot.activeAgentStatuses[0].taskCount, 2)
        XCTAssertEqual(snapshot.activeAgentStatuses[1].taskCount, 1)
    }

    func testActivityServicePrefersIndexedThreadNameAndLoadsTaskMetadata() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-title-db-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let rolloutURL = directory.appendingPathComponent("activity.jsonl")
        try Data("""
        {"timestamp":"2026-07-22T08:00:00Z","type":"event_msg","payload":{"type":"task_started"}}
        """.utf8).write(to: rolloutURL)
        let sessionIndexURL = directory.appendingPathComponent("session_index.jsonl")
        try Data("""
        {"id":"thread-title","thread_name":"评估并更新 Codexling UI","updated_at":"2026-07-22T08:00:00Z"}
        """.utf8).write(to: sessionIndexURL)

        let databaseURL = directory.appendingPathComponent("state.sqlite")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, """
        CREATE TABLE threads (
            id TEXT PRIMARY KEY,
            rollout_path TEXT NOT NULL,
            title TEXT NOT NULL,
            name TEXT,
            cwd TEXT,
            git_branch TEXT,
            model TEXT,
            archived INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        );
        INSERT INTO threads VALUES (
            'thread-title',
            '\(rolloutURL.path)',
            '/goal /tmp/Codexling',
            '',
            '/tmp/Codexling',
            'main',
            'gpt-5.6-sol',
            0,
            1
        );
        """, nil, nil, nil), SQLITE_OK)

        let snapshot = CodexActivityService(
            databaseURLs: [databaseURL],
            sessionIndexURLs: [sessionIndexURL]
        ).loadSnapshot(now: ISO8601DateFormatter().date(from: "2026-07-22T08:00:01Z")!)

        XCTAssertEqual(snapshot.threadTitle, "评估并更新 Codexling UI")
        XCTAssertEqual(snapshot.activeTasks.first?.title, "评估并更新 Codexling UI")
        XCTAssertEqual(snapshot.activeTasks.first?.workspaceName, "Codexling")
        XCTAssertEqual(snapshot.activeTasks.first?.gitBranch, "main")
        XCTAssertEqual(snapshot.activeTasks.first?.model, "gpt-5.6-sol")
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

    func testCodexPetSelectionSyncReadsAndMapsPetIDs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-pet-sync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("config.toml")
        try """
        model = "gpt-5"

        [desktop]
        selected-avatar-id = "custom:nimbus"
        avatar-overlay-mascot-width-px = 155
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let sync = CodexPetSelectionSync(configURL: configURL)
        XCTAssertEqual(sync.readSelectedPetID(), "custom:nimbus")
        XCTAssertEqual(sync.codexPetID(fromAppID: "builtin:hoots"), "hoots")
        XCTAssertEqual(sync.appPetID(fromCodexID: "hoots"), "builtin:hoots")
    }

    func testCodexPetSelectionSyncUpdatesOnlyDesktopSelection() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-pet-write-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("config.toml")
        try """
        selected-avatar-id = "leave-this-alone"

        [desktop]
        selected-avatar-id = "custom:nimbus"
        avatar-overlay-mascot-width-px = 155

        [desktop.open-in-target-preferences]
        global = "cursor"
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let sync = CodexPetSelectionSync(configURL: configURL)
        XCTAssertTrue(try sync.writeSelectedPetID("builtin:hoots"))
        let updated = try String(contentsOf: configURL, encoding: .utf8)

        XCTAssertTrue(updated.contains("selected-avatar-id = \"leave-this-alone\""))
        XCTAssertTrue(updated.contains("[desktop]\nselected-avatar-id = \"hoots\""))
        XCTAssertTrue(updated.contains("avatar-overlay-mascot-width-px = 155"))
        XCTAssertEqual(sync.readSelectedPetID(), "builtin:hoots")
        XCTAssertFalse(try sync.writeSelectedPetID("builtin:hoots"))
    }

    @MainActor
    func testCodexPetSelectionMonitorDetectsAtomicConfigReplacement() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-pet-monitor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("config.toml")
        try """
        [desktop]
        selected-avatar-id = "custom:nimbus"
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let changeDetected = expectation(description: "Pet config change detected")
        let monitor = CodexPetSelectionMonitor(
            configURL: configURL,
            debounceInterval: 0.05
        ) {
            changeDetected.fulfill()
        }
        monitor.start()

        try """
        [desktop]
        selected-avatar-id = "custom:levi"
        """.write(to: configURL, atomically: true, encoding: .utf8)

        await fulfillment(of: [changeDetected], timeout: 2)
        monitor.stop()
    }

    @MainActor
    func testWindowAlwaysOnTopPreferencePersists() throws {
        let suiteName = "CodexlingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettingsStore(defaults: defaults)
        XCTAssertFalse(settings.windowAlwaysOnTop)

        settings.windowAlwaysOnTop = true
        XCTAssertTrue(defaults.bool(forKey: "codexling.windowAlwaysOnTop"))

        let restored = AppSettingsStore(defaults: defaults)
        XCTAssertTrue(restored.windowAlwaysOnTop)
    }

    @MainActor
    func testDashboardOrientationDefaultsToHorizontalAndPersists() throws {
        let suiteName = "CodexlingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(settings.dashboardOrientation, .horizontal)

        var notified: DashboardOrientation?
        settings.onDashboardOrientationChanged = { notified = $0 }
        settings.dashboardOrientation = .vertical

        XCTAssertEqual(notified, .vertical)
        XCTAssertEqual(defaults.string(forKey: "codexling.dashboardOrientation"), "vertical")

        let restored = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(restored.dashboardOrientation, .vertical)
    }

    func testVerticalDashboardKeepsNarrowWidthAndFollowsMeasuredHeight() {
        let horizontal = DetachedWindowMetrics.fixedDashboardContentSize(
            isLoggedIn: true,
            orientation: .horizontal
        )
        XCTAssertEqual(horizontal.width, DetachedWindowMetrics.dashboardWidth)
        XCTAssertEqual(horizontal.height, DetachedWindowMetrics.loggedInDashboardHeight)

        let horizontalMeasured = DetachedWindowMetrics.fixedDashboardContentSize(
            isLoggedIn: true,
            orientation: .horizontal,
            measuredHeight: 548
        )
        XCTAssertEqual(horizontalMeasured.height, DetachedWindowMetrics.loggedInDashboardHeight)

        let unmeasured = DetachedWindowMetrics.fixedDashboardContentSize(
            isLoggedIn: true,
            orientation: .vertical
        )
        XCTAssertEqual(unmeasured.width, DetachedWindowMetrics.verticalDashboardWidth)
        XCTAssertEqual(unmeasured.height, DetachedWindowMetrics.verticalProvisionalHeight)
        XCTAssertEqual(
            DetachedWindowMetrics.verticalProvisionalHeight,
            DetachedWindowMetrics.loggedInDashboardHeight
        )

        XCTAssertFalse(
            DetachedWindowMetrics.isValidVerticalMeasurement(
                CGSize(width: DetachedWindowMetrics.dashboardWidth, height: 480)
            )
        )
        XCTAssertTrue(
            DetachedWindowMetrics.isValidVerticalMeasurement(
                CGSize(width: DetachedWindowMetrics.verticalDashboardWidth, height: 638.4)
            )
        )

        let measured = DetachedWindowMetrics.fixedDashboardContentSize(
            isLoggedIn: true,
            orientation: .vertical,
            measuredHeight: 638.4
        )
        XCTAssertEqual(measured.width, DetachedWindowMetrics.verticalDashboardWidth)
        XCTAssertEqual(measured.height, 639)

        // 内容过矮时不塌陷，未登录时复用登录页高度。
        let clamped = DetachedWindowMetrics.fixedDashboardContentSize(
            isLoggedIn: true,
            orientation: .vertical,
            measuredHeight: 40
        )
        XCTAssertEqual(clamped.height, DetachedWindowMetrics.verticalMinHeight)

        let loggedOut = DetachedWindowMetrics.fixedDashboardContentSize(
            isLoggedIn: false,
            orientation: .vertical,
            measuredHeight: 900
        )
        XCTAssertEqual(loggedOut.height, DetachedWindowMetrics.loginDashboardHeight)
    }

    @MainActor
    func testPetInteractionRemainsAvailableWhileCodexIsWorking() {
        let pet = CodexPet(
            id: "custom:test",
            assetID: "test",
            displayName: "Test",
            description: "",
            source: .custom,
            spriteVersionNumber: 2,
            spritesheetURL: URL(fileURLWithPath: "/private/tmp/nonexistent-pet.png"),
            rowCount: 9
        )
        let frameStore = PetFrameStore()

        frameStore.update(pet: pet, activityState: .executing)

        XCTAssertTrue(frameStore.canPlayIdleInteraction)
        let firstAction = frameStore.playRandomIdleAction()
        let secondAction = frameStore.playRandomIdleAction()
        XCTAssertNotNil(firstAction)
        XCTAssertNotNil(secondAction)
        XCTAssertNotEqual(firstAction, secondAction)
        frameStore.stop()
    }

    func testInstalledCodexActivityIsReadableWhenDatabaseExists() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let database = home.appendingPathComponent(".codex/state_5.sqlite")
        guard FileManager.default.fileExists(atPath: database.path) else { return }

        let snapshot = CodexActivityService(databaseURLs: [database]).loadSnapshot()
        XCTAssertNotEqual(snapshot.state, .unavailable)
        XCTAssertFalse(snapshot.hoverSubtitle.isEmpty)
    }

    func testOAuthCallbackServerCanBeCancelledImmediately() async throws {
        let server = OAuthCallbackServer(expectedState: "test-state")
        let waiting = Task {
            try await server.waitForCode(timeoutSeconds: 5)
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        server.cancel()

        do {
            _ = try await waiting.value
            XCTFail("Expected OAuth cancellation")
        } catch let error as CodexUsageError {
            XCTAssertEqual(error, .oauthCancelled)
        } catch {
            XCTFail("Unexpected cancellation error: \(error)")
        }
    }

    @MainActor
    func testLegacyTaskColorPreferenceMigratesToFollowQuota() throws {
        let suiteName = "CodexlingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("cyan", forKey: "codexling.petBackgroundColor")

        XCTAssertEqual(AppSettingsStore(defaults: defaults).petBackgroundColor, .neutral)
    }

    private func littleEndian(_ value: UInt32) -> Data {
        var little = value.littleEndian
        return withUnsafeBytes(of: &little) { Data($0) }
    }
}
