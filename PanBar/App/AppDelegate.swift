import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var container: DependencyContainer?
    private var statusController: StatusItemController?
    private var popoverController: PopoverController?

    private func registerGlobalHotkeyIfEnabled(container: DependencyContainer) {
        let enabled = (container.settingsRepo.string(SettingsRepository.Keys.globalHotkeyEnabled) ?? "1") == "1"
        guard enabled else { return }
        GlobalHotkey.shared.registerDefault { [weak self] in
            self?.statusController?.toggleViaHotkey()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let container = try DependencyContainer.bootstrap()
            self.container = container

            let popover = PopoverController(
                refresher: container.refresher,
                holdingsRepo: container.holdingsRepo,
                watchlistRepo: container.watchlistRepo,
                settingsRepo: container.settingsRepo,
                appearancePrefs: container.appearancePrefs
            )
            self.popoverController = popover

            let status = StatusItemController(
                refresher: container.refresher,
                popoverController: popover,
                prefs: container.tickerPrefs,
                clock: container.clock
            )
            self.statusController = status

            // 网络状态 → 刷新泵
            container.networkMonitor.onChange = { [weak container] offline in
                container?.refresher.setOffline(offline)
            }
            container.networkMonitor.start()

            // Provider 偏好变更热更新
            container.dataSourcePrefs.onPreferencesChange = { [weak container] prefs in
                Task { await container?.orchestrator.updatePreferences(prefs) }
            }
            container.dataSourcePrefs.onFinnhubKeyChange = { [weak container] key in
                container?.finnhub.setApiKey(key)
            }

            container.refresher.start()

            // 通知权限
            NotificationService.shared.requestAuthorizationIfNeeded()

            // 全局快捷键 ⌘⇧P
            registerGlobalHotkeyIfEnabled(container: container)

            // Sparkle 自动更新(Release 配置才启动定时检查)
            _ = Updater.shared

            Task {
                await container.warmup()
                container.refresher.refreshNow()
            }

            // 首启 onboarding
            if !OnboardingWindowController.isOnboarded(repo: container.settingsRepo) {
                OnboardingWindowController.shared.show(container: container) {
                    container.refresher.refreshNow()
                }
            }
        } catch {
            Log.app.error("bootstrap failed: \(String(describing: error), privacy: .public)")
            NSApp.terminate(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }
}
