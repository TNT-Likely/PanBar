import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var container: DependencyContainer?
    private var statusController: StatusItemController?
    private var popoverController: PopoverController?

    private func applyLanguageOverride() {
        // 这里直连 UserDefaults,不走 DependencyContainer(因为容器还没建)
        // 自己读 raw app_language 键(SettingsRepository 用同一个 key)
        // 但 SettingsRepository 是 SQLite 的,这里没法读 — 改成同时往 UserDefaults 也写一份。
        let key = SettingsRepository.Keys.language
        let raw = UserDefaults.standard.string(forKey: "panbar.\(key)") ?? "auto"
        let choice = LanguageManager.Choice(rawValue: raw) ?? .auto
        LanguageManager.applyOnLaunch(choice)
    }

    private func registerGlobalHotkeyIfEnabled(container: DependencyContainer) {
        let enabled = (container.settingsRepo.string(SettingsRepository.Keys.globalHotkeyEnabled) ?? "1") == "1"
        guard enabled else { return }
        applyHotkeys(container: container)
    }

    /// 读取 settings 中的自定义 binding,注册到 GlobalHotkey。设置页改动后调用。
    func applyHotkeys(container: DependencyContainer) {
        var bindings: [GlobalHotkey.HotkeyID: HotkeyBinding?] = [:]
        for id in GlobalHotkey.HotkeyID.allCases {
            bindings[id] = HotkeyStore.load(id: id, from: container.settingsRepo) ?? id.defaultBinding
        }
        GlobalHotkey.shared.register(bindings: bindings, actions: [
            .togglePopover: { [weak self] in self?.statusController?.toggleViaHotkey() },
            .togglePrivacy: { [weak self] in self?.statusController?.togglePrivacyViaHotkey() }
        ])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 语言覆盖必须在容器构建前生效,容器里就会触发 L() 加载本地化串
        applyLanguageOverride()

        do {
            let container = try DependencyContainer.bootstrap()
            self.container = container

            let popover = PopoverController(
                refresher: container.refresher,
                holdingsRepo: container.holdingsRepo,
                watchlistRepo: container.watchlistRepo,
                settingsRepo: container.settingsRepo,
                appearancePrefs: container.appearancePrefs,
                tickerPrefs: container.tickerPrefs,
                container: container
            )
            self.popoverController = popover

            let status = StatusItemController(
                refresher: container.refresher,
                popoverController: popover,
                prefs: container.tickerPrefs,
                clock: container.clock,
                settingsRepo: container.settingsRepo
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

            // 注意:不在这里直接 refresher.start() —— warmup() 内部按
            // (磁盘 seed → 合成 snapshot → start tick → 网络) 的固定顺序跑,
            // 避免 tick 先于 seed 把 lastUpdated 占住,导致首屏空。

            // 通知权限
            NotificationService.shared.requestAuthorizationIfNeeded()

            // 全局快捷键 ⌘⌃P
            registerGlobalHotkeyIfEnabled(container: container)

            // 启动后台静默检查一次:有新版才弹窗,没新版/网络挂安静通过
            Updater.shared.checkInBackground()

            Task {
                await container.warmup()
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
