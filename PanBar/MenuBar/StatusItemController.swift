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
        var items: [TickerItem] = []

        // 1) Summary 三件套(用户在 Settings → Ticker 单独勾选)
        let snap = refresher.snapshot
        if prefs.showTodayPnL {
            let dir: TickerDirection = snap.todayPnL > 0 ? .up : (snap.todayPnL < 0 ? .down : .neutral)
            let sign = snap.todayPnL >= 0 ? "+" : "-"
            let value = sign + snap.baseCurrency.format(snap.todayPnL.magnitude) +
                String(format: " (%+.2f%%)", snap.todayPnLPct * 100)
            items.append(.summary(label: L("summary.today", comment: ""), value: value, direction: dir))
        }
        if prefs.showTotalAssets {
            items.append(.summary(
                label: L("summary.totalAssets", comment: ""),
                value: snap.baseCurrency.format(snap.totalAssets),
                direction: .neutral
            ))
        }
        if prefs.showAllTimePnL {
            let dir: TickerDirection = snap.allTimePnL > 0 ? .up : (snap.allTimePnL < 0 ? .down : .neutral)
            let sign = snap.allTimePnL >= 0 ? "+" : "-"
            let value = sign + snap.baseCurrency.format(snap.allTimePnL.magnitude) +
                String(format: " (%+.2f%%)", snap.allTimePnLPct * 100)
            items.append(.summary(label: L("summary.allTime", comment: ""), value: value, direction: dir))
        }

        // 2) 持仓行情:只取勾选 inTicker=true 的
        var seen = Set<SymbolID>()
        for p in snap.positions where p.holding.inTicker {
            if let q = quotes[p.holding.symbol] {
                items.append(.quote(q))
                seen.insert(p.holding.symbol)
            }
        }
        // 3) 自选行情:只取勾选 inTicker=true 的
        let watchlist = (try? holdingsRepoFetchSiblingWatch()) ?? []
        for w in watchlist where w.inTicker && !seen.contains(w.symbol) {
            if let q = quotes[w.symbol] {
                items.append(.quote(q))
            }
        }

        // 4) 应用上限(只对股票行情生效,summary 始终都展示)
        let stockCap = max(1, prefs.maxItems)
        let summaries = items.filter { if case .summary = $0 { return true } else { return false } }
        let quotesItems = items.filter { if case .quote = $0 { return true } else { return false } }
        let cappedQuotes = Array(quotesItems.prefix(stockCap))
        items = summaries + cappedQuotes

        let attr = renderer.render(items: items)
        tickerView.update(attributed: attr)
        statusItem.length = tickerView.totalWidth
    }

    /// 从持仓 repo 同级的 watchlist repo 拿数据。通过弱引用注入避免循环引用。
    private func holdingsRepoFetchSiblingWatch() throws -> [WatchItem] {
        guard let container = DependencyContainer.shared else { return [] }
        return try container.watchlistRepo.all()
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
