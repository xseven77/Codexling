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
    private let usageService = CodexUsageService()
    private var actions: UsageActions?
    private var autoRefreshTimer: Timer?
    private var accountCarouselTimer: Timer?
    private var codexPetSelectionMonitor: CodexPetSelectionMonitor?
    private var isRefreshing = false

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
        multiAgentSettingsStore.onSelectedConnectionChanged = { [weak self] in
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
        migrateLegacyTokenIfNeeded()
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

    private func migrateLegacyTokenIfNeeded() {
        Task { [weak self] in
            guard let self else { return }
            let migrated = await self.usageService.migrateLegacyTokenIfNeeded()
            guard migrated else { return }

            await MainActor.run {
                self.snapshotStore.isLoggedIn = true
                self.statusController?.refreshStatusTitle()
                self.autoRefreshUsage()
            }
        }
    }

    private func autoRefreshUsage() {
        performUnifiedRefresh(showsToast: false)
    }

    /// 是否已有任一可刷新的连接（主 Codex 已登录、附加 Codex 账号或 DeepSeek Key）。
    /// 只有完全没有连接时才把「刷新」升级成「登录」。
    private var hasAnyConnection: Bool {
        snapshotStore.isLoggedIn
            || !multiAgentSettingsStore.codexAccounts.isEmpty
            || !multiAgentSettingsStore.deepSeekConnections.isEmpty
    }

    private func manualRefreshUsage() {
        performUnifiedRefresh(showsToast: true)
    }

    /// 登录主流程：未登录时拉起 OAuth 授权，成功后 token 落盘并刷新额度。
    private func loginAndFetchUsage() {
        Task { [weak self] in
            guard let self else { return }
            _ = await self.refreshUsage(allowOAuthLogin: true)
            if self.snapshotStore.isLoggedIn {
                // 主账号登录成功后切回「当前 Codex」。
                // 即使额度抓取失败，只要 token 已落盘也视为已登录。
                self.multiAgentSettingsStore.selectCurrentCodexConnection()
            }
        }
    }

    private func performUnifiedRefresh(showsToast: Bool) {
        guard !snapshotStore.isUnifiedRefreshing else {
            if showsToast {
                snapshotStore.showManualRefreshToast(for: RefreshOutcome(failures: ["正在刷新，请稍候"]))
            }
            return
        }

        snapshotStore.setUnifiedRefreshing(true)
        Task { [weak self] in
            guard let self else { return }
            var outcome = await self.multiAgentSettingsStore.refreshAllConnections()
            self.statusController?.refreshStatusTitle()
            outcome.merge(await self.refreshUsage(allowOAuthLogin: false))
            self.snapshotStore.setUnifiedRefreshing(false)
            if showsToast {
                self.snapshotStore.showManualRefreshToast(for: outcome)
            }
        }
    }

    private func refreshUsage(allowOAuthLogin: Bool) async -> RefreshOutcome {
        guard !isRefreshing else { return RefreshOutcome(failures: ["Codex 正在刷新"]) }
        guard allowOAuthLogin || snapshotStore.isLoggedIn else { return RefreshOutcome() }

        isRefreshing = true
        snapshotStore.markRefreshing(allowsAuthorization: allowOAuthLogin)
        statusController?.refreshStatusTitle()

        do {
            let snapshot = allowOAuthLogin
                ? try await usageService.connectAndFetch()
                : try await usageService.fetchWithStoredToken()
            snapshotStore.apply(snapshot)
            isRefreshing = false
            statusController?.refreshStatusTitle()
            return RefreshOutcome(successCount: 1)
        } catch {
            isRefreshing = false
            if allowOAuthLogin, await usageService.hasStoredToken() {
                // OAuth 已成功并落盘 token，只是额度抓取失败（如请求超时）→
                // 视为已登录，仅提示额度获取失败，避免误报成「登录失败」。
                snapshotStore.markAuthenticated(message: "额度获取失败：\(error.localizedDescription)")
            } else if !allowOAuthLogin,
                      let codexError = error as? CodexUsageError,
                      codexError == .noStoredToken || codexError == .invalidTokenResponse {
                snapshotStore.markAuthenticationExpired()
            } else {
                snapshotStore.markFailed(error.localizedDescription)
            }
            statusController?.refreshStatusTitle()
            return RefreshOutcome(failures: ["Codex：\(error.localizedDescription)"])
        }
    }

    private func disconnect() {
        snapshotStore.markDisconnected()
        statusController?.refreshStatusTitle()

        Task { [weak self] in
            guard let self else { return }

            await self.usageService.disconnect()
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

    private func startAutoRefreshTimer() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil

        guard let interval = settingsStore.autoRefreshInterval.timeInterval else { return }

        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.autoRefreshUsage()
            }
        }
    }

    /// 唯一的账号轮播调度源。one-shot timer 会在手动或自动选择后重新完整计时，
    /// 避免 SwiftUI 为布局测量创建视图副本时产生重复轮播任务。
    private func startAccountCarouselTimer() {
        accountCarouselTimer?.invalidate()
        accountCarouselTimer = nil

        guard let interval = settingsStore.accountCarouselInterval.timeInterval,
              !multiAgentSettingsStore.isAccountCarouselPaused
        else { return }

        accountCarouselTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.multiAgentSettingsStore.selectNextConnection(
                    includesCurrentCodex: self.snapshotStore.isLoggedIn
                )
            }
        }
    }
}
