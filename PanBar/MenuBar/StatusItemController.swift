import AppKit
import Carbon
import Combine

/// 持有 NSStatusItem 与自绘的 TickerView。
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    /// 真实的 ticker 视图,类型随 displayMode 变化(滚动/轮播/固定/极简)。
    private var tickerView: MenuBarTickerView
    private let popoverController: PopoverController
    private let refresher: QuoteRefresher
    private let prefs: TickerPreferences
    private let clock: MarketClock
    private let settingsRepo: SettingsRepository
    private var renderer: TickerRenderer
    private var cancellables = Set<AnyCancellable>()
    private var contextMenu: NSMenu
    private var screenSharingMonitor: ScreenSharingMonitor?
    private var privacyHidden: Bool = false
    private var currentMode: TickerDisplayMode = .scroll

    init(
        refresher: QuoteRefresher,
        popoverController: PopoverController,
        prefs: TickerPreferences,
        clock: MarketClock,
        settingsRepo: SettingsRepository
    ) {
        self.refresher = refresher
        self.popoverController = popoverController
        self.prefs = prefs
        self.clock = clock
        self.settingsRepo = settingsRepo
        self.renderer = TickerRenderer(scheme: prefs.colorScheme)
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // autosaveName 让 macOS 持久化用户 ⌘-拖到的位置,下次启动不重置。
        // 这是「被刘海挡掉」时唯一能做的:用户挪到 notch 左边后位置就保住了。
        self.statusItem.autosaveName = "app.panbar.PanBar.statusItem"
        self.currentMode = prefs.displayMode
        self.tickerView = Self.makeView(for: prefs.displayMode, scheme: prefs.colorScheme)
        self.contextMenu = NSMenu()

        // 屏幕共享检测
        privacyHidden = settingsRepo.string(SettingsRepository.Keys.privacyManualHide) == "1"
        let autoEnabled = settingsRepo.string(SettingsRepository.Keys.hideOnScreenShare) != "0"
        if autoEnabled {
            let monitor = ScreenSharingMonitor()
            monitor.onChange = { [weak self] sharing in
                self?.updateTickerVisibility(autoSharing: sharing)
            }
            monitor.start()
            screenSharingMonitor = monitor
        }

        configure()
        applyPrefs()
        bind()
    }

    private func applyPrefs() {
        renderer = TickerRenderer(scheme: prefs.colorScheme)
        // mode 变化:整个 view 都要换
        if prefs.displayMode != currentMode {
            swapTickerView(to: prefs.displayMode)
        }
        // 各模式独立配置
        if let scroll = tickerView as? TickerView {
            scroll.pixelsPerSecond = prefs.scrollSpeed.pixelsPerSecond
            scroll.pauseOnHover = prefs.pauseOnHover
        }
        if let carousel = tickerView as? CarouselTickerView {
            carousel.pauseOnHover = prefs.pauseOnHover
            carousel.dwell = CFTimeInterval(prefs.carouselDwell)
        }
        if let compact = tickerView as? CompactTickerView {
            compact.scheme = prefs.colorScheme
        }
        if let minimal = tickerView as? MinimalTickerView {
            minimal.scheme = prefs.colorScheme
        }
        let shouldPause = prefs.pauseWhenClosed && !clock.anyOpen()
        tickerView.setPaused(shouldPause)
        applyQuotes(refresher.quotes)
    }

    /// 创建对应模式的视图实例。
    private static func makeView(for mode: TickerDisplayMode, scheme: TickerColorScheme) -> MenuBarTickerView {
        let frame = NSRect(x: 0, y: 0, width: 200, height: 22)
        switch mode {
        case .scroll:
            return TickerView(frame: frame)
        case .carousel:
            return CarouselTickerView(frame: frame)
        case .compact:
            let v = CompactTickerView(frame: frame)
            v.scheme = scheme
            return v
        case .minimal:
            let v = MinimalTickerView(frame: frame)
            v.scheme = scheme
            return v
        }
    }

    /// 切换 ticker view 时,卸下旧的回调,接上新的。view 不挂到 button 子视图,
    /// 通过 onContentChanged 回调把渲染好的 NSImage 设给 button.image。
    private func swapTickerView(to mode: TickerDisplayMode) {
        tickerView.onContentChanged = nil
        tickerView = Self.makeView(for: mode, scheme: prefs.colorScheme)
        wireUpTickerView()
        currentMode = mode
    }

    /// NSTrackingArea 的 owner 必须是 NSObject + 响应 mouseEntered/Exited。
    /// 我们用这个小 helper 把回调桥到 controller(StatusItemController 不是 NSObject)。
    private let hoverProxy = HoverProxy()

    private func configure() {
        guard let button = statusItem.button else { return }
        button.frame = NSRect(x: 0, y: 0, width: tickerView.totalWidth, height: 22)
        button.target = self
        button.action = #selector(onClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        // 在 button 上加 tracking area,把 hover 状态转给 view
        // (view 不在 window 里,自己监听不到 mouseEntered/Exited)
        hoverProxy.onEnter = { [weak self] in self?.tickerView.hovered = true }
        hoverProxy.onExit  = { [weak self] in self?.tickerView.hovered = false }
        let tracking = NSTrackingArea(
            rect: button.bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: hoverProxy,
            userInfo: nil
        )
        button.addTrackingArea(tracking)

        wireUpTickerView()
        buildContextMenu()
    }

    /// 把当前 tickerView 接到 button:订阅内容变化 → 渲染 NSImage → 写回 button.image。
    /// view 始终不挂到 button 子视图;系统对菜单栏 subview 的 vibrancy 滤镜
    /// 只对 NSView 树生效,对 NSImage 不生效,这样能避免「app 不激活时颜色变浅」。
    private func wireUpTickerView() {
        tickerView.onContentChanged = { [weak self] in
            self?.refreshButtonImage()
        }
        refreshButtonImage()
    }

    /// 把当前 tickerView 渲染到 NSImage 并设给 button。
    private func refreshButtonImage() {
        guard let button = statusItem.button else { return }
        let image = tickerView.renderImage()
        button.image = image
        button.imagePosition = .imageOnly
        statusItem.length = tickerView.totalWidth
    }

    /// 各模式根据当前数据自己组装,写回到 statusItem.length。
    private func render(quotes: [SymbolID: Quote]) {
        switch currentMode {
        case .scroll:
            guard let view = tickerView as? TickerView else { return }
            let items = buildTickerItems(quotes: quotes)
            view.update(attributed: renderer.render(items: items))
        case .carousel:
            guard let view = tickerView as? CarouselTickerView else { return }
            // 汇总用 compact 简写格式拼成一条(「今 +¥8194  累 -¥29.6万  总 ¥64.9万」),
            // 个股 / 指数各自单条。这样首屏看到的是简写总览,后续轮播看个股。
            var slots: [NSAttributedString] = []
            if let summary = buildCompactSummaryString() {
                slots.append(summary)
            }
            let lineItems = buildLineItems(quotes: quotes)
            for it in lineItems {
                slots.append(renderer.render(items: [it]))
            }
            view.update(items: slots)
        case .compact:
            guard let view = tickerView as? CompactTickerView else { return }
            let snap = refresher.snapshot
            // 三个汇总开关同样适用于 compact —— 用户只想看其中一两个时,菜单栏更窄
            view.update(slots: CompactTickerView.Slots(
                todayPnL: prefs.showTodayPnL ? snap.todayPnL : nil,
                allTimePnL: prefs.showAllTimePnL ? snap.allTimePnL : nil,
                totalAssets: prefs.showTotalAssets ? snap.totalAssets : nil,
                baseCurrency: snap.baseCurrency
            ))
        case .minimal:
            guard let view = tickerView as? MinimalTickerView else { return }
            let snap = refresher.snapshot
            view.update(content: minimalContent(snap: snap, metric: prefs.minimalMetric))
        }
        statusItem.length = tickerView.totalWidth
    }

    private func minimalContent(snap: PortfolioSnapshot, metric: MinimalMetric) -> MinimalTickerView.Content? {
        switch metric {
        case .todayPnL:
            return MinimalTickerView.Content(
                label: L("compact.label.today", comment: ""),
                value: snap.todayPnL,
                direction: snap.todayPnL > 0 ? .up : (snap.todayPnL < 0 ? .down : .neutral),
                currency: snap.baseCurrency
            )
        case .allTimePnL:
            return MinimalTickerView.Content(
                label: L("compact.label.allTime", comment: ""),
                value: snap.allTimePnL,
                direction: snap.allTimePnL > 0 ? .up : (snap.allTimePnL < 0 ? .down : .neutral),
                currency: snap.baseCurrency
            )
        case .totalAssets:
            return MinimalTickerView.Content(
                label: L("compact.label.total", comment: ""),
                value: snap.totalAssets,
                direction: .neutral,
                currency: snap.baseCurrency
            )
        }
    }

    private func buildContextMenu() {
        contextMenu.removeAllItems()
        contextMenu.addItem(withTitle: L("menu.refresh", comment: ""), action: #selector(refresh), keyEquivalent: "r").target = self
        contextMenu.addItem(withTitle: L("menu.showPopover", comment: ""), action: #selector(showPopover), keyEquivalent: "p").target = self
        contextMenu.addItem(.separator())
        // 隐私快捷开关:跟用户自定义的全局快捷键保持一致
        let privacyItem = NSMenuItem(
            title: privacyHidden ? L("menu.privacy.show", comment: "") : L("menu.privacy.hideNow", comment: ""),
            action: #selector(togglePrivacy),
            keyEquivalent: ""
        )
        privacyItem.target = self
        if let custom = HotkeyStore.load(id: .togglePrivacy, from: settingsRepo) ?? Optional(GlobalHotkey.HotkeyID.togglePrivacy.defaultBinding),
           custom.isValid {
            // 把 Carbon keyCode + Carbon modifiers 翻译到 NSMenuItem 的格式
            privacyItem.keyEquivalent = HotkeyBinding.character(for: custom.keyCode).lowercased()
            var mask: NSEvent.ModifierFlags = []
            if custom.carbonModifiers & UInt32(cmdKey) != 0 { mask.insert(.command) }
            if custom.carbonModifiers & UInt32(shiftKey) != 0 { mask.insert(.shift) }
            if custom.carbonModifiers & UInt32(optionKey) != 0 { mask.insert(.option) }
            if custom.carbonModifiers & UInt32(controlKey) != 0 { mask.insert(.control) }
            privacyItem.keyEquivalentModifierMask = mask
        }
        contextMenu.addItem(privacyItem)
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

        // 指数变动也要重渲染(否则用户勾选了大盘但 ticker 不更新)
        refresher.$indexQuotes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.applyQuotes(self.refresher.quotes)
            }
            .store(in: &cancellables)

        // 任何 ticker 偏好变化 → 立即重渲染
        prefs.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.applyPrefs() }
            }
            .store(in: &cancellables)
    }

    private func applyQuotes(_ quotes: [SymbolID: Quote]) {
        render(quotes: quotes)
    }

    /// Carousel 模式:把启用的汇总指标拼成一条 compact 简写字符串。
    /// 没启用任何汇总时返回 nil。
    private func buildCompactSummaryString() -> NSAttributedString? {
        let snap = refresher.snapshot
        let font = NSFont.menuBarFont(ofSize: 0)
        var pieces: [NSAttributedString] = []

        let labelAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: font.pointSize - 1, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.55),
            .kern: 0.3
        ]
        func valueAttr(_ dir: TickerDirection) -> [NSAttributedString.Key: Any] {
            let color: NSColor
            switch dir {
            case .up:      color = SemanticColors.upNS(scheme: prefs.colorScheme)
            case .down:    color = SemanticColors.downNS(scheme: prefs.colorScheme)
            case .neutral: color = NSColor.white.withAlphaComponent(0.92)
            }
            return [
                .font: NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .semibold),
                .foregroundColor: color
            ]
        }

        func appendPiece(label: String, value: Decimal, direction: TickerDirection) {
            let s = NSMutableAttributedString()
            s.append(NSAttributedString(string: label + " ", attributes: labelAttr))
            let text: String
            if direction == .neutral {
                text = NumberAbbreviation.formatCurrency(value, currency: snap.baseCurrency)
            } else {
                let sign = value < 0 ? "-" : "+"
                text = sign + snap.baseCurrency.symbol +
                       NumberAbbreviation.format(value, currency: snap.baseCurrency)
            }
            s.append(NSAttributedString(string: text, attributes: valueAttr(direction)))
            pieces.append(s)
        }

        if prefs.showTodayPnL {
            let dir: TickerDirection = snap.todayPnL > 0 ? .up : (snap.todayPnL < 0 ? .down : .neutral)
            appendPiece(label: L("compact.label.today", comment: ""), value: snap.todayPnL, direction: dir)
        }
        if prefs.showAllTimePnL {
            let dir: TickerDirection = snap.allTimePnL > 0 ? .up : (snap.allTimePnL < 0 ? .down : .neutral)
            appendPiece(label: L("compact.label.allTime", comment: ""), value: snap.allTimePnL, direction: dir)
        }
        if prefs.showTotalAssets, snap.totalAssets > 0 {
            appendPiece(label: L("compact.label.total", comment: ""), value: snap.totalAssets, direction: .neutral)
        }

        guard !pieces.isEmpty else { return nil }
        let out = NSMutableAttributedString()
        let separator = NSAttributedString(string: "  ", attributes: labelAttr)
        for (i, p) in pieces.enumerated() {
            if i > 0 { out.append(separator) }
            out.append(p)
        }
        return out
    }

    /// 取 quotes / 指数那一类的 ticker item(不包含 summary),供 carousel 用。
    private func buildLineItems(quotes: [SymbolID: Quote]) -> [TickerItem] {
        return buildTickerItems(quotes: quotes).filter { item in
            switch item {
            case .summary: return false
            case .quote, .index: return true
            }
        }
    }

    /// 把 quotes / snapshot / 偏好聚合成 [TickerItem],scroll / carousel 共用。
    /// compact / minimal 直接从 snapshot 拿数字,不走这里。
    private func buildTickerItems(quotes: [SymbolID: Quote]) -> [TickerItem] {
        var items: [TickerItem] = []
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

        let enabledIDs = prefs.tickerIndexIDs
        if !enabledIDs.isEmpty {
            let byID = Dictionary(uniqueKeysWithValues: refresher.indexQuotes.map { ($0.descriptor.id, $0) })
            for desc in IndexCatalog.all where enabledIDs.contains(desc.id) {
                if let iq = byID[desc.id] {
                    items.append(.index(iq))
                }
            }
        }

        var seen = Set<SymbolID>()
        for p in snap.positions where p.holding.inTicker {
            if let q = quotes[p.holding.symbol] {
                items.append(.quote(q))
                seen.insert(p.holding.symbol)
            }
        }
        let watchlist = (try? holdingsRepoFetchSiblingWatch()) ?? []
        for w in watchlist where w.inTicker && !seen.contains(w.symbol) {
            if let q = quotes[w.symbol] {
                items.append(.quote(q))
            }
        }

        let stockCap = max(1, prefs.maxItems)
        var summaries: [TickerItem] = []
        var lineItems: [TickerItem] = []
        for it in items {
            switch it {
            case .summary: summaries.append(it)
            case .quote, .index: lineItems.append(it)
            }
        }
        let capped = Array(lineItems.prefix(stockCap))
        return summaries + capped
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

    /// 由全局快捷键 ⌘⌃M 调用,切换隐私模式。
    func togglePrivacyViaHotkey() {
        togglePrivacy()
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

    @objc private func togglePrivacy() {
        privacyHidden.toggle()
        try? settingsRepo.set(SettingsRepository.Keys.privacyManualHide, privacyHidden ? "1" : "0")
        buildContextMenu()
        updateTickerVisibility(autoSharing: screenSharingMonitor?.isSharing ?? false)
    }

    /// 综合手动 + 自动判断,决定 ticker 是显示还是显示为 "P •••" 占位。
    private func updateTickerVisibility(autoSharing: Bool) {
        let shouldHide = privacyHidden || autoSharing
        tickerView.privacyHidden = shouldHide
        refreshButtonImage()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
