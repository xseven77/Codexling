import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusBarController?
    private var windowController: DetachedWindowController?
    private let snapshotStore = UsageSnapshotStore()
    private let settingsStore = AppSettingsStore()
    private let activityStore = CodexActivityStore()
    private let updateController = AppUpdateController()
    private let usageService = CodexUsageService()
    private var actions: UsageActions?
    private var autoRefreshTimer: Timer?
    private var isRefreshing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        settingsStore.applyAppearance()
        settingsStore.onAutoRefreshIntervalChanged = { [weak self] _ in
            self?.startAutoRefreshTimer()
        }
        settingsStore.onThemeChanged = { [weak self] _ in
            self?.statusController?.refreshThemeAppearance()
            self?.windowController?.refreshThemeAppearance()
        }
        settingsStore.onPetSettingsChanged = { [weak self] in
            self?.statusController?.refreshStatusTitle()
        }
        activityStore.onSnapshotChanged = { [weak self] _ in
            self?.statusController?.refreshStatusTitle()
        }

        let actions = UsageActions(
            refresh: { [weak self] in
                self?.loginAndFetchUsage()
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
            updater: updateController,
            actions: actions
        )
        startAutoRefreshTimer()
        activityStore.start()
        migrateLegacyTokenIfNeeded()
        openDetachedWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        activityStore.stop()
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

    private func loginAndFetchUsage() {
        refreshUsage(allowOAuthLogin: true)
    }

    private func autoRefreshUsage() {
        refreshUsage(allowOAuthLogin: false)
    }

    private func refreshUsage(allowOAuthLogin: Bool) {
        guard !isRefreshing else { return }
        guard allowOAuthLogin || snapshotStore.isLoggedIn else { return }

        isRefreshing = true
        snapshotStore.markRefreshing(allowsAuthorization: allowOAuthLogin)
        statusController?.refreshStatusTitle()

        Task { [weak self] in
            guard let self else { return }

            do {
                let snapshot = allowOAuthLogin
                    ? try await self.usageService.connectAndFetch()
                    : try await self.usageService.fetchWithStoredToken()
                await MainActor.run {
                    self.snapshotStore.apply(snapshot)
                    self.isRefreshing = false
                    self.statusController?.refreshStatusTitle()
                }
            } catch {
                await MainActor.run {
                    self.isRefreshing = false
                    if !allowOAuthLogin, let codexError = error as? CodexUsageError, codexError == .noStoredToken {
                        return
                    }
                    self.snapshotStore.markFailed(error.localizedDescription)
                    self.statusController?.refreshStatusTitle()
                }
            }
        }
    }

    private func disconnect() {
        Task { [weak self] in
            guard let self else { return }

            await self.usageService.disconnect()
            await MainActor.run {
                self.snapshotStore.markDisconnected()
                self.statusController?.refreshStatusTitle()
            }
        }
    }

    private func openDetachedWindow() {
        guard let actions else { return }

        if windowController == nil {
            windowController = DetachedWindowController(
                store: snapshotStore,
                settings: settingsStore,
                updater: updateController,
                actions: actions,
                onClose: { [weak self] in
                    self?.handleDetachedWindowClosed()
                }
            )
        }

        // Show Dock icon (and app logo) while the detached window is open.
        NSApp.setActivationPolicy(.regular)
        windowController?.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func handleDetachedWindowClosed() {
        // Return to menu-bar-only mode after the window is closed.
        NSApp.setActivationPolicy(.accessory)
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
}
