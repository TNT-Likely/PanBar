import AppKit
import Combine

/// 持有 NSStatusItem 与自绘的 TickerView。
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let tickerView: TickerView
    private let popoverController: PopoverController
    private let refresher: QuoteRefresher
    private let prefs: TickerPreferences
    private let clock: MarketClock
    private var renderer: TickerRenderer
    private var cancellables = Set<AnyCancellable>()
    private var contextMenu: NSMenu

    init(
        refresher: QuoteRefresher,
        popoverController: PopoverController,
        prefs: TickerPreferences,
        clock: MarketClock
    ) {
        self.refresher = refresher
        self.popoverController = popoverController
        self.prefs = prefs
        self.clock = clock
        self.renderer = TickerRenderer(scheme: prefs.colorScheme)
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.tickerView = TickerView(frame: NSRect(x: 0, y: 0, width: 320, height: 22))
        self.contextMenu = NSMenu()

        configure()
        applyPrefs()
        bind()
    }

    private func applyPrefs() {
        renderer = TickerRenderer(scheme: prefs.colorScheme)
        tickerView.pixelsPerSecond = prefs.scrollSpeed.pixelsPerSecond
        tickerView.pauseOnHover = prefs.pauseOnHover
        let shouldPause = prefs.pauseWhenClosed && !clock.anyOpen()
        tickerView.setPaused(shouldPause)
        // 即时重渲染
        applyQuotes(refresher.quotes)
    }

    private func configure() {
        guard let button = statusItem.button else { return }
        button.frame = NSRect(x: 0, y: 0, width: tickerView.totalWidth, height: 22)
        tickerView.frame = button.bounds
        tickerView.autoresizingMask = [.width, .height]
        button.addSubview(tickerView)
        button.target = self
        button.action = #selector(onClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        statusItem.length = tickerView.totalWidth

        buildContextMenu()
    }

    private func buildContextMenu() {
        contextMenu.removeAllItems()
        contextMenu.addItem(withTitle: L("menu.refresh", comment: ""), action: #selector(refresh), keyEquivalent: "r").target = self
        contextMenu.addItem(withTitle: L("menu.showPopover", comment: ""), action: #selector(showPopover), keyEquivalent: "p").target = self
        contextMenu.addItem(.separator())
        contextMenu.addItem(withTitle: L("menu.settings", comment: ""), action: #selector(openSettings), keyEquivalent: ",").target = self
        contextMenu.addItem(withTitle: L("menu.checkForUpdates", comment: ""), action: #selector(checkForUpdates), keyEquivalent: "").target = self
        contextMenu.addItem(.separator())
        contextMenu.addItem(withTitle: L("menu.quit", comment: ""), action: #selector(quit), keyEquivalent: "q").target = self
    }

    private func bind() {
        refresher.$quotes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] quotes in
                self?.applyQuotes(quotes)
            }
            .store(in: &cancellables)

        // 任何 ticker 偏好变化 → 立即重渲染
        prefs.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // objectWillChange 触发时 prefs 旧值仍然存在,稍后异步读新值
                DispatchQueue.main.async { self?.applyPrefs() }
            }
            .store(in: &cancellables)
    }

    private func applyQuotes(_ quotes: [SymbolID: Quote]) {
        // 按持仓优先 + 自选其次的顺序展示
        let positions = refresher.snapshot.positions
        var ordered: [Quote] = []
        var seen = Set<SymbolID>()
        for p in positions {
            if let q = quotes[p.holding.symbol] {
                ordered.append(q)
                seen.insert(p.holding.symbol)
            }
        }
        // 补上自选(不在持仓里的)
        for (sid, q) in quotes where !seen.contains(sid) {
            ordered.append(q)
        }
        // 用户设置的上限
        let cap = max(1, prefs.maxItems)
        if ordered.count > cap { ordered = Array(ordered.prefix(cap)) }

        let attr = renderer.render(quotes: ordered)
        tickerView.update(attributed: attr)
        statusItem.length = tickerView.totalWidth
    }

    // MARK: actions

    @objc private func onClick(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        statusItem.menu = contextMenu
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popoverController.isShown {
            popoverController.close()
        } else {
            popoverController.show(relativeTo: button)
        }
    }

    /// 由全局快捷键调用。
    func toggleViaHotkey() {
        togglePopover()
    }

    @objc private func refresh() {
        refresher.refreshNow()
    }

    @objc private func showPopover() {
        guard let button = statusItem.button else { return }
        popoverController.show(relativeTo: button)
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func checkForUpdates() {
        Updater.shared.checkForUpdates()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
