import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusBarController?
    private var windowController: DetachedWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var standalonePetWindowController: StandalonePetWindowController?
    private let snapshotStore = UsageSnapshotStore()
    private let settingsStore = AppSettingsStore()
    private let multiAgentSettingsStore = MultiAgentSettingsStore()
    private let activityStore = CodexActivityStore()
    private let agentEventSocketService = AgentEventSocketService()
    private let frameStore = PetFrameStore()
    private let companionStatsStore = CompanionStatsStore()
    private let updateController = AppUpdateController()
    private var actions: UsageActions?
    private var autoRefreshTimer: Timer?
    private var accountCarouselTimer: Timer?
    /// Invalidates callbacks that were already queued when the previous
    /// one-shot timer was cancelled (for example, immediately after a logo
    /// click).
    private var accountCarouselTimerGeneration = 0
    private var notchRefreshStateGeneration = 0
    private var codexPetSelectionMonitor: CodexPetSelectionMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        settingsStore.applyAppearance()
        settingsStore.onAutoRefreshIntervalChanged = { [weak self] _ in
            self?.startAutoRefreshTimer()
        }
        settingsStore.onAccountCarouselIntervalChanged = { [weak self] _ in
            self?.startAccountCarouselTimer()
            self?.statusController?.refreshProviderCarouselTimer()
        }
        settingsStore.onMainWindowProviderCarouselEnabledChanged = { [weak self] _ in
            self?.startAccountCarouselTimer()
        }
        multiAgentSettingsStore.onSelectedConnectionChanged = { [weak self] in
            self?.syncSelectedCodexProjection()
            self?.startAccountCarouselTimer()
            self?.statusController?.refreshStatusTitle()
        }
        multiAgentSettingsStore.onAccountCarouselPauseChanged = { [weak self] _ in
            self?.startAccountCarouselTimer()
        }
        settingsStore.onThemeChanged = { [weak self] _ in
            self?.statusController?.refreshThemeAppearance()
            self?.windowController?.refreshThemeAppearance()
            self?.settingsWindowController?.refreshThemeAppearance()
        }
        settingsStore.onWindowAlwaysOnTopChanged = { [weak self] _ in
            self?.windowController?.refreshAlwaysOnTop()
        }
        settingsStore.onNotchDisplayTargetChanged = { [weak self] target in
            self?.statusController?.refreshNotchDisplay()
            // 选择具体显示器后，在该屏幕边缘闪红边提示。
            if case .specificScreen(let number) = target,
               let screen = NSScreen.screens.first(where: { $0.screenNumber == number }) {
                self?.statusController?.highlightScreen(screen)
            }
        }
        settingsStore.onPetSettingsChanged = { [weak self] in
            self?.syncCompanionState()
            self?.statusController?.refreshStatusTitle()
        }
        settingsStore.onStandalonePetEnabledChanged = { [weak self] _ in
            self?.applyStandalonePetVisibility()
        }
        activityStore.onSnapshotChanged = { [weak self] snapshot in
            self?.frameStore.update(
                pet: self?.settingsStore.selectedPet,
                activityState: snapshot.state
            )
            self?.companionStatsStore.setActivityState(snapshot.state)
            self?.statusController?.refreshStatusTitle()
        }

        let actions = UsageActions(
            refresh: { [weak self] in
                guard let self else { return }
                if self.hasAnyConnection {
                    self.manualRefreshUsage()
                } else {
                    self.loginAndFetchUsage()
                }
            },
            openUsagePage: {
                if let url = URL(string: "https://chatgpt.com/codex/settings/usage") {
                    NSWorkspace.shared.open(url)
                }
            },
            loginAndFetch: { [weak self] in
                self?.loginAndFetchUsage()
            },
            disconnect: { [weak self] in
                self?.disconnect()
            },
            openDetachedWindow: { [weak self] in
                self?.openDetachedWindow()
            },
            quit: {
                NSApp.terminate(nil)
            }
        )

        self.actions = actions
        statusController = StatusBarController(
            store: snapshotStore,
            settings: settingsStore,
            activityStore: activityStore,
            multiAgentSettings: multiAgentSettingsStore,
            frameStore: frameStore,
            companionStatsStore: companionStatsStore,
            actions: actions,
            openDetachedWindowFromStatusItem: { [weak self] screen in
                self?.openDetachedWindow(on: screen)
            }
        )
        statusController?.onProviderSelection = { [weak self] in
            // Restart even when the user clicks the already-selected logo;
            // selectedConnectionKey does not change in that case.
            self?.startAccountCarouselTimer()
        }
        statusController?.onRefreshProvider = { [weak self] in
            guard let self else { return }
            if self.hasAnyConnection {
                self.manualRefreshUsage(showsToast: false)
            } else {
                self.loginAndFetchUsage()
            }
        }
        startAutoRefreshTimer()
        startAccountCarouselTimer()
        activityStore.start()
        do {
            try agentEventSocketService.start { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.activityStore.ingest(event)
                }
            }
        } catch {
            NSLog("Codexling Agent event listener unavailable: %@", error.localizedDescription)
        }
        companionStatsStore.start()
        let petSelectionMonitor = CodexPetSelectionMonitor { [weak self] in
            self?.settingsStore.refreshPetsAndSyncSelectionFromCodex()
        }
        petSelectionMonitor.start()
        codexPetSelectionMonitor = petSelectionMonitor
        syncCompanionState()
        applyStandalonePetVisibility()
        syncSelectedCodexProjection()
        openDetachedWindow()
        autoRefreshUsage()
    }

    func applicationWillTerminate(_ notification: Notification) {
        multiAgentSettingsStore.stopCodexAppServers()
        agentEventSocketService.stop()
        activityStore.stop()
        companionStatsStore.stop()
        frameStore.stop()
        codexPetSelectionMonitor?.stop()
    }

    func applicationDidUpdate(_ notification: Notification) {
        settingsStore.refreshSystemAppearanceIfNeeded()
    }

    private func autoRefreshUsage() {
        // 启动和定时刷新不改变刘海面板按钮的结果状态；只有用户主动
        // 点击刷新时，按钮才显示 loading / success / warning。
        performUnifiedRefresh(showsToast: false, updatesNotchIndicator: false)
    }

    /// 是否已有任一可刷新的供应商连接。
    /// 只有完全没有连接时才把「刷新」升级成「登录」。
    private var hasAnyConnection: Bool {
        !multiAgentSettingsStore.codexAccounts.isEmpty
            || !multiAgentSettingsStore.deepSeekConnections.isEmpty
            || !multiAgentSettingsStore.openCodeConnections.isEmpty
    }

    private func manualRefreshUsage(showsToast: Bool = true) {
        // 手动刷新：先重置自动刷新倒计时，等本次刷新全部加载结束后再重新计时。
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
        performUnifiedRefresh(showsToast: showsToast)
    }

    /// OAuth 登录流程：创建一个新的 Codex 连接并刷新额度。
    private func loginAndFetchUsage() {
        Task { [weak self] in
            guard let self else { return }
            _ = await self.multiAgentSettingsStore.addCodexAccount()
            self.syncSelectedCodexProjection()
            self.statusController?.refreshStatusTitle()
        }
    }

    private func performUnifiedRefresh(
        showsToast: Bool,
        updatesNotchIndicator: Bool = true
    ) {
        guard !snapshotStore.isUnifiedRefreshing else {
            if showsToast {
                snapshotStore.showManualRefreshToast(for: RefreshOutcome(failures: ["正在刷新，请稍候"]))
            }
            return
        }

        snapshotStore.setUnifiedRefreshing(true)
        if updatesNotchIndicator {
            statusController?.updateNotchProviderRefreshState(.loading)
        }
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.multiAgentSettingsStore.refreshAllConnections()
            self.syncSelectedCodexProjection()
            self.statusController?.refreshStatusTitle()
            self.snapshotStore.setUnifiedRefreshing(false)
            if updatesNotchIndicator {
                self.finishNotchRefresh(outcome)
            }
            // 本次刷新（手动或自动）全部结束后，重新开始自动刷新倒计时。
            self.startAutoRefreshTimer()
            if showsToast {
                self.snapshotStore.showManualRefreshToast(for: outcome)
            }
        }
    }

    private func finishNotchRefresh(_ outcome: RefreshOutcome) {
        notchRefreshStateGeneration &+= 1
        let generation = notchRefreshStateGeneration
        if outcome.failures.isEmpty {
            statusController?.updateNotchProviderRefreshState(.success)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.notchRefreshStateGeneration == generation else { return }
                self.statusController?.updateNotchProviderRefreshState(.idle)
            }
        } else {
            // A warning is intentionally sticky until the next refresh.
            statusController?.updateNotchProviderRefreshState(.warning)
        }
    }

    private func disconnect() {
        multiAgentSettingsStore.disconnectSelectedConnection()
        syncSelectedCodexProjection()
        statusController?.refreshStatusTitle()
    }

    /// The legacy snapshot store is now only a view projection of the selected
    /// Codex connection; it is no longer an independent account/auth store.
    private func syncSelectedCodexProjection() {
        guard let account = multiAgentSettingsStore.selectedCodexAccount else {
            snapshotStore.markDisconnected()
            return
        }
        snapshotStore.isLoggedIn = account.authenticationState == .connected
        if let usage = account.usage {
            snapshotStore.apply(usage)
        } else if snapshotStore.snapshot.sourceURL == "preview" {
            snapshotStore.snapshot = .empty(refreshState: "等待刷新")
        }
    }

    private func openDetachedWindow(on screen: NSScreen? = nil) {
        guard let actions else { return }
        settingsStore.syncPetSelectionFromCodex()

        if windowController == nil {
            windowController = DetachedWindowController(
                store: snapshotStore,
                settings: settingsStore,
                multiAgentSettings: multiAgentSettingsStore,
                activityStore: activityStore,
                frameStore: frameStore,
                companionStatsStore: companionStatsStore,
                updater: updateController,
                actions: actions,
                onOpenSettings: { [weak self] in
                    self?.openSettingsWindow()
                },
                onClose: { [weak self] in
                    self?.handleDetachedWindowClosed()
                }
            )
        }

        // Present first. Changing activation policy can synchronously ask Dock
        // and WindowServer to re-register the app, which made a capsule click
        // feel delayed when the app was in menu-bar-only mode.
        windowController?.show(on: screen)
        NSApp.activate(ignoringOtherApps: true)

        guard NSApp.activationPolicy() != .regular else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.windowController != nil else { return }
            NSApp.setActivationPolicy(.regular)
            self.windowController?.show(on: screen)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func syncCompanionState() {
        frameStore.update(
            pet: settingsStore.selectedPet,
            activityState: activityStore.snapshot.state
        )
    }

    private func applyStandalonePetVisibility() {
        guard settingsStore.standalonePetEnabled else {
            standalonePetWindowController?.hide()
            return
        }
        if standalonePetWindowController == nil {
            standalonePetWindowController = StandalonePetWindowController(
                activityStore: activityStore,
                frameStore: frameStore,
                settings: settingsStore
            )
        }
        standalonePetWindowController?.show()
    }

    private func openSettingsWindow() {
        guard let actions else { return }
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                store: snapshotStore,
                settings: settingsStore,
                multiAgentSettings: multiAgentSettingsStore,
                updater: updateController,
                actions: actions,
                onClose: { [weak self] in
                    self?.handleSettingsWindowClosed()
                }
            )
        }

        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        let targetScreen = windowController?.currentScreen
        settingsWindowController?.show(on: targetScreen)
        DispatchQueue.main.async { [weak self] in
            self?.settingsWindowController?.show(on: targetScreen)
        }
    }

    private func handleDetachedWindowClosed() {
        windowController = nil
        if settingsWindowController == nil {
            // Return to menu-bar-only mode only after both independent windows close.
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func handleSettingsWindowClosed() {
        settingsWindowController = nil
        if windowController == nil {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openDetachedWindow()
        }
        return true
    }

    /// 自动刷新调度：one-shot timer，每次刷新全部结束后重新计时，
    /// 保证倒计时从「上次刷新完成」开始算，而不是固定时钟。
    /// 手动刷新会先重置倒计时（见 `manualRefreshUsage`），
    /// 等手动刷新全部加载完后再由 `performUnifiedRefresh` 的收尾重新启动。
    private func startAutoRefreshTimer() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil

        guard let interval = settingsStore.autoRefreshInterval.timeInterval else { return }

        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.autoRefreshUsage()
            }
        }
    }

    /// 唯一的账号轮播调度源。one-shot timer 会在手动或自动选择后重新完整计时，
    /// 避免 SwiftUI 为布局测量创建视图副本时产生重复轮播任务。
    ///
    /// 「供应商自动轮播」开关只决定推进时是否改变全局选中账号：
    /// 开启 → 主窗口与刘海面板同步轮播选中项；关闭 → 仅推进刘海面板自身的
    /// 显示轮播，主窗口选中保持不变。因此开关本身不会停掉刘海面板的轮播。
    private func startAccountCarouselTimer() {
        accountCarouselTimerGeneration &+= 1
        let generation = accountCarouselTimerGeneration
        accountCarouselTimer?.invalidate()
        accountCarouselTimer = nil

        guard let interval = settingsStore.accountCarouselInterval.timeInterval,
              !multiAgentSettingsStore.isAccountCarouselPaused
        else { return }

        accountCarouselTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      generation == self.accountCarouselTimerGeneration
                else { return }
                self.accountCarouselTimer = nil
                self.advanceAccountCarousel()
            }
        }
    }

    private func advanceAccountCarousel() {
        if settingsStore.mainWindowProviderCarouselEnabled {
            // 自动轮播开启：推进全局选中账号。选中变化会触发
            // onSelectedConnectionChanged → startAccountCarouselTimer() 重新计时。
            multiAgentSettingsStore.selectNextConnection()
        } else {
            // 自动轮播关闭：主窗口选中保持不变，仅推进刘海面板自身的账号轮播。
            let advanced = statusController?.advanceNotchProviderCarousel() ?? false
            if advanced {
                startAccountCarouselTimer()
            }
        }
    }
}
