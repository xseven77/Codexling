import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let autoRefreshInterval: TimeInterval = 60
    private var statusController: StatusBarController?
    private var windowController: DetachedWindowController?
    private let snapshotStore = UsageSnapshotStore()
    private let usageService = CodexUsageService()
    private var actions: UsageActions?
    private var autoRefreshTimer: Timer?
    private var isRefreshing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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
        statusController = StatusBarController(store: snapshotStore, actions: actions)
        startAutoRefreshTimer()
        migrateLegacyTokenIfNeeded()
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
            windowController = DetachedWindowController(store: snapshotStore, actions: actions)
        }

        windowController?.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func startAutoRefreshTimer() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: autoRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.autoRefreshUsage()
            }
        }
    }
}
