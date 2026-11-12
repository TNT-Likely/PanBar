import XCTest
import GRDB
import Combine
@testable import PanBar

final class EditorDraftTests: XCTestCase {
    private var directory: URL!
    private var pool: DatabasePool!
    private let symbol = SymbolID(code: "600000", market: .a)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        pool = try DatabasePool(path: directory.appendingPathComponent("test.sqlite").path)
        try Migrations.register(pool)
    }

    override func tearDownWithError() throws {
        try pool.close()
        pool = nil
        try FileManager.default.removeItem(at: directory)
    }

    @MainActor
    func testNewItemsSaveToTheirSelectedGroups() throws {
        let groups = PortfolioGroupsRepository(dbPool: pool)
        let watched = PortfolioGroup(name: "关注", kind: .watchlist)
        let held = PortfolioGroup(name: "持有", kind: .holdings)
        try groups.upsert(watched)
        try groups.upsert(held)
        let watch = WatchEditorDraft()
        XCTAssertNil(watch.groupID)
        watch.pick(SymbolSearchResult(symbol: symbol, name: "测试"))
        watch.groupID = watched.id
        try watch.save(to: WatchlistRepository(dbPool: pool), groups: groups)
        XCTAssertEqual(try WatchlistRepository(dbPool: pool).all().first?.groupID, watched.id)

        let holding = HoldingEditorDraft()
        XCTAssertNil(holding.groupID)
        holding.pick(SymbolSearchResult(symbol: symbol, name: "测试"))
        holding.quantity = "100"
        holding.costPrice = "8.25"
        holding.groupID = held.id
        try holding.save(to: HoldingsRepository(dbPool: pool), groups: groups)
        let saved = try XCTUnwrap(HoldingsRepository(dbPool: pool).all().first)
        XCTAssertEqual(saved.groupID, held.id)
        XCTAssertEqual(saved.quantity, 100)
        XCTAssertEqual(saved.costPrice, Decimal(string: "8.25"))
    }

    @MainActor
    func testHoldingEditPreservesLatestFieldsOutsideForm() throws {
        let repo = HoldingsRepository(dbPool: pool)
        var holding = Holding(symbol: symbol, name: "旧名称", quantity: 100, costPrice: 8,
                              createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        try repo.upsert(holding)
        let draft = HoldingEditorDraft(initial: holding)
        draft.name = "新名称"
        draft.quantity = "200"
        holding.sortOrder = 7
        holding.note = "期间修改的备注"
        holding.inTicker = false
        try repo.upsert(holding)
        try draft.save(to: repo, groups: PortfolioGroupsRepository(dbPool: pool))
        holding.name = "新名称"
        holding.quantity = 200
        XCTAssertEqual(try repo.all(), [holding])
    }

    @MainActor
    func testWatchEditPreservesLatestOrderAndVisibility() throws {
        let repo = WatchlistRepository(dbPool: pool)
        var item = WatchItem(symbol: symbol, name: "旧名称", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        try repo.upsert(item)
        let draft = WatchEditorDraft(initial: item)
        draft.name = "新名称"
        item.order = 5
        item.inTicker = false
        try repo.upsert(item)
        try draft.save(to: repo, groups: PortfolioGroupsRepository(dbPool: pool))
        item.name = "新名称"
        XCTAssertEqual(try repo.all(), [item])
    }

    @MainActor
    func testAlertPrefillAndCompoundConditionsRoundTrip() throws {
        let repo = AlertsRepository(dbPool: pool)
        let draft = AlertEditorDraft(symbol: SymbolSearchResult(symbol: symbol, name: "快捷预警"))
        XCTAssertTrue(try repo.all().isEmpty)
        XCTAssertNil(draft.id)
        XCTAssertEqual(draft.code, symbol.code)
        XCTAssertEqual(draft.market, symbol.market)
        draft.condition = .changePctAbove
        draft.thresholdText = "5.125"
        draft.hasSecondary = true
        draft.secondaryCondition = .priceBelow
        draft.secondaryThresholdText = "9.25"
        draft.conditionLogic = .or
        draft.cooldownText = "600"
        draft.hasDailyCap = true
        draft.dailyCapText = "2"
        draft.tradingHoursOnly = true
        draft.weekdaysOnly = true
        try draft.save(to: repo)
        let saved = try XCTUnwrap(repo.all().first)
        XCTAssertEqual(saved.symbol, symbol)
        XCTAssertEqual(saved.name, "快捷预警")
        XCTAssertEqual(saved.threshold, Decimal(string: "0.05125"))
        XCTAssertEqual(saved.secondaryThreshold, Decimal(string: "9.25"))
        XCTAssertEqual(saved.conditionLogic, .or)
        XCTAssertEqual(saved.cooldownSeconds, 600)
        XCTAssertEqual(saved.maxTriggersPerDay, 2)
        XCTAssertTrue(saved.tradingHoursOnly && saved.weekdaysOnly)
        XCTAssertTrue(saved.conditionText.contains(ConditionLogic.or.displayName))
        XCTAssertTrue(saved.conditionText.contains(AlertCondition.priceBelow.displayName))
        let editing = AlertEditorDraft(initial: saved)
        XCTAssertEqual(editing.thresholdText, "5.125")
        try editing.save(to: repo)
        XCTAssertEqual(try repo.all(), [saved])
        editing.hasSecondary = false
        try editing.save(to: repo)
        let simplified = try XCTUnwrap(repo.all().first)
        XCTAssertNil(simplified.secondaryCondition)
        XCTAssertNil(simplified.secondaryThreshold)
    }

    @MainActor
    func testPortfolioAlertRequiresSelectionAndPrefillsSymbol() throws {
        let repo = AlertsRepository(dbPool: pool)
        let draft = AlertEditorDraft(usesPortfolioSymbols: true)
        draft.thresholdText = "300"
        XCTAssertTrue(draft.usesPortfolioSymbols)
        XCTAssertNil(draft.selectedSymbolKey)
        XCTAssertFalse(draft.hasSymbol)
        XCTAssertFalse(draft.canSave(symbols: []))
        XCTAssertThrowsError(try draft.save(to: repo))

        let item = SymbolSearchResult(symbol: SymbolID(code: "00700", market: .hk), name: "自选港股")
        draft.pick(item)
        XCTAssertFalse(draft.hasSymbol)
        draft.selectSymbol(item)
        XCTAssertEqual(draft.selectedSymbolKey, item.symbol.storageKey)
        XCTAssertEqual(draft.market, .hk)
        XCTAssertEqual(draft.code, "00700")
        XCTAssertEqual(draft.name, item.name)
        XCTAssertTrue(draft.hasSymbol)
        XCTAssertTrue(try repo.all().isEmpty)
        XCTAssertTrue(draft.canSave(symbols: [item]))
        try draft.save(to: repo, symbols: [item])
        let saved = try XCTUnwrap(repo.all().first)
        XCTAssertEqual(saved.symbol, item.symbol)
        XCTAssertEqual(saved.name, item.name)
        XCTAssertEqual(saved.threshold, 300)
    }

    @MainActor
    func testChangingAlertSymbolKeepsConditionsAndClearsSelection() throws {
        let draft = AlertEditorDraft(usesPortfolioSymbols: true)
        draft.selectSymbol(SymbolSearchResult(symbol: symbol, name: "持仓"))
        draft.condition = .priceBelow
        draft.thresholdText = "8.25"
        draft.hasSecondary = true
        draft.secondaryCondition = .changePctAbove
        draft.secondaryThresholdText = "5"
        draft.conditionLogic = .or
        draft.cooldownText = "600"
        draft.hasDailyCap = true
        draft.dailyCapText = "2"
        draft.tradingHoursOnly = true
        draft.weekdaysOnly = true
        draft.showAdvanced = true
        draft.selectSymbol(nil)
        XCTAssertNil(draft.selectedSymbolKey)
        XCTAssertFalse(draft.hasSymbol)
        draft.selectSymbol(SymbolSearchResult(symbol: SymbolID(code: "AAPL", market: .us), name: "自选"))
        XCTAssertTrue(draft.hasSymbol)
        draft.selectSymbol(nil)
        XCTAssertFalse(draft.hasSymbol)
        XCTAssertTrue(draft.code.isEmpty && draft.name.isEmpty)
        XCTAssertEqual(draft.condition, .priceBelow)
        XCTAssertEqual(draft.thresholdText, "8.25")
        XCTAssertTrue(draft.hasSecondary)
        XCTAssertEqual(draft.secondaryCondition, .changePctAbove)
        XCTAssertEqual(draft.secondaryThresholdText, "5")
        XCTAssertEqual(draft.conditionLogic, .or)
        XCTAssertEqual(draft.cooldownText, "600")
        XCTAssertTrue(draft.hasDailyCap)
        XCTAssertEqual(draft.dailyCapText, "2")
        XCTAssertTrue(draft.tradingHoursOnly && draft.weekdaysOnly && draft.showAdvanced)
        XCTAssertThrowsError(try draft.save(to: AlertsRepository(dbPool: pool)))
    }

    @MainActor
    func testAlertSymbolsFollowHoldingAndWatchlistOrder() throws {
        let groups = PortfolioGroupsRepository(dbPool: pool)
        let heldFirst = PortfolioGroup(name: "持仓第一组", kind: .holdings, sortOrder: 0)
        let heldSecond = PortfolioGroup(name: "持仓第二组", kind: .holdings, sortOrder: 1)
        let first = PortfolioGroup(name: "第一组", kind: .watchlist, sortOrder: 0)
        let second = PortfolioGroup(name: "第二组", kind: .watchlist, sortOrder: 1)
        for group in [second, first, heldSecond, heldFirst] { try groups.upsert(group) }
        let holdings = HoldingsRepository(dbPool: pool)
        let h1 = Holding(symbol: SymbolID(code: "600001", market: .a), name: "持仓第二组", quantity: 1,
                         costPrice: 10, sortOrder: 0, groupID: heldSecond.id)
        let h2 = Holding(symbol: SymbolID(code: "600002", market: .a), name: "持仓未分组", quantity: 1,
                         costPrice: 10, sortOrder: 1)
        let h3 = Holding(symbol: SymbolID(code: "600003", market: .a), name: "持仓第一组首项", quantity: 1,
                         costPrice: 10, sortOrder: 2, groupID: heldFirst.id)
        let h4 = Holding(symbol: SymbolID(code: "600004", market: .a), name: "持仓第一组次项", quantity: 1,
                         costPrice: 10, sortOrder: 3, groupID: heldFirst.id)
        for holding in [h1, h2, h3, h4] { try holdings.upsert(holding) }
        let repo = WatchlistRepository(dbPool: pool)
        let a = WatchItem(symbol: SymbolID(code: "00700", market: .hk), name: "第二组标的", order: 0, groupID: second.id)
        let b = WatchItem(symbol: SymbolID(code: "00941", market: .hk), name: "未分组标的", order: 1)
        let c = WatchItem(symbol: SymbolID(code: "AAPL", market: .us), name: "第一组首项", order: 2, groupID: first.id)
        let d = WatchItem(symbol: SymbolID(code: "MSFT", market: .us), name: "第一组次项", order: 3, groupID: first.id)
        for item in [a, b, c, d] { try repo.upsert(item) }
        let vm = makeViewModel()
        XCTAssertEqual(vm.alertSymbols.map(\.symbol), [h3.symbol, h4.symbol, h1.symbol, h2.symbol,
                                                      c.symbol, d.symbol, a.symbol, b.symbol])
    }

    @MainActor
    func testAlertSymbolsDeduplicateByMarketAndNormalizedCode() throws {
        let holdings = HoldingsRepository(dbPool: pool)
        let watches = WatchlistRepository(dbPool: pool)
        let first = Holding(symbol: SymbolID(code: "aapl", market: .us), name: "首个持仓", quantity: 1,
                            costPrice: 10, sortOrder: 0)
        let duplicate = Holding(symbol: SymbolID(code: "AAPL", market: .us), name: "重复持仓", quantity: 1,
                                costPrice: 10, sortOrder: 1)
        for item in [first, duplicate] { try holdings.upsert(item) }
        try watches.upsert(WatchItem(symbol: duplicate.symbol, name: "重复自选", order: 0))
        try watches.upsert(WatchItem(symbol: SymbolID(code: "600000", market: .a), name: "A 股", order: 1))
        try watches.upsert(WatchItem(symbol: SymbolID(code: "600000", market: .hk), name: "同代码港股", order: 2))
        let vm = makeViewModel()
        XCTAssertEqual(vm.alertSymbols.map { $0.symbol.storageKey }, [first.symbol.storageKey,
                                                                     SymbolID(code: "600000", market: .a).storageKey,
                                                                     SymbolID(code: "600000", market: .hk).storageKey])
        XCTAssertEqual(vm.alertSymbols.first?.name, first.name)
    }

    @MainActor
    func testPortfolioAlertCannotSaveAfterSymbolIsRemovedFromBothSources() throws {
        let holdings = HoldingsRepository(dbPool: pool)
        let watches = WatchlistRepository(dbPool: pool)
        let alerts = AlertsRepository(dbPool: pool)
        let holding = Holding(symbol: symbol, name: "持仓", quantity: 1, costPrice: 10)
        let watch = WatchItem(symbol: symbol, name: "自选")
        try holdings.upsert(holding)
        try watches.upsert(watch)
        let vm = makeViewModel()
        vm.currentTab = .alerts
        vm.openAlertEditor()
        guard case .alert(let draft) = vm.editors[.alerts] else { return XCTFail("Missing alert draft") }
        draft.selectSymbol(try XCTUnwrap(vm.alertSymbols.first))
        draft.thresholdText = "12"
        XCTAssertTrue(draft.canSave(symbols: vm.alertSymbols))

        try holdings.delete(id: holding.id)
        vm.reload()
        XCTAssertTrue(draft.canSave(symbols: vm.alertSymbols))
        try watches.delete(id: watch.id)
        vm.reload()
        XCTAssertTrue(vm.alertSymbols.isEmpty)
        XCTAssertFalse(draft.canSave(symbols: vm.alertSymbols))
        XCTAssertThrowsError(try draft.save(to: alerts, symbols: vm.alertSymbols))
        XCTAssertTrue(try alerts.all().isEmpty)

        try watches.upsert(WatchItem(symbol: symbol, name: "重新添加"))
        vm.reload()
        XCTAssertTrue(draft.canSave(symbols: vm.alertSymbols))
        try draft.save(to: alerts, symbols: vm.alertSymbols)
        XCTAssertEqual(try alerts.all().first?.symbol, symbol)
    }

    @MainActor
    func testPortfolioAlertDraftSurvivesTabSwitchAndCancelsWithoutSaving() throws {
        let vm = makeViewModel()
        vm.currentTab = .alerts
        vm.openAlertEditor()
        guard case .alert(let draft) = vm.editors[.alerts] else { return XCTFail("Missing alert draft") }
        let item = SymbolSearchResult(symbol: symbol, name: "自选")
        draft.selectSymbol(item)
        draft.thresholdText = "12"
        vm.currentTab = .holdings
        vm.reload()
        vm.currentTab = .alerts
        vm.openAlertEditor()
        guard case .alert(let restored) = vm.editors[.alerts] else { return XCTFail("Lost alert draft") }
        XCTAssertTrue(restored === draft)
        XCTAssertTrue(restored.usesPortfolioSymbols)
        XCTAssertEqual(restored.selectedSymbolKey, item.symbol.storageKey)
        XCTAssertEqual(restored.thresholdText, "12")
        vm.cancelEditor(in: .alerts)
        XCTAssertNil(vm.editors[.alerts])
        XCTAssertTrue(try AlertsRepository(dbPool: pool).all().isEmpty)
        vm.openAlertEditor()
        guard case .alert(let fresh) = vm.editors[.alerts] else { return XCTFail("Missing fresh draft") }
        XCTAssertNil(fresh.selectedSymbolKey)
        XCTAssertTrue(fresh.thresholdText.isEmpty)
    }

    @MainActor
    func testSettingsAndPrefilledAlertsKeepTheirOriginalSymbolFlow() throws {
        let settings = AlertEditorDraft()
        XCTAssertFalse(settings.usesPortfolioSymbols)
        let vm = makeViewModel()
        vm.currentTab = .watchlist
        vm.openAlertEditor(symbol: SymbolSearchResult(symbol: symbol, name: "右键入口"))
        guard case .alert(let prefilled) = vm.editors[.watchlist] else { return XCTFail("Missing prefilled draft") }
        XCTAssertFalse(prefilled.usesPortfolioSymbols)
        XCTAssertEqual(prefilled.code, symbol.code)
        vm.currentTab = .alerts
        let existing = Alert(symbol: symbol, name: "已有预警", condition: .priceAbove, threshold: 12)
        vm.openAlertEditor(existing)
        guard case .alert(let editing) = vm.editors[.alerts] else { return XCTFail("Missing editing draft") }
        XCTAssertFalse(editing.usesPortfolioSymbols)
        XCTAssertEqual(editing.id, existing.id)
        XCTAssertEqual(editing.thresholdText, "12")
    }

    @MainActor
    func testAlertEditKeepsTriggersAndPauseChangedDuringEditing() throws {
        let repo = AlertsRepository(dbPool: pool)
        let alert = Alert(symbol: symbol, name: "预警", condition: .priceAbove, threshold: 9,
                          createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        try repo.upsert(alert)
        let draft = AlertEditorDraft(initial: alert)
        draft.thresholdText = "12"
        let triggeredAt = Date(timeIntervalSince1970: 1_700_000_000)
        try repo.markTriggered(id: alert.id, at: triggeredAt, todayKey: "2026-11-11")
        XCTAssertTrue(try repo.update(id: alert.id) { $0.isActive = false })
        try draft.save(to: repo)
        let saved = try XCTUnwrap(repo.all().first)
        XCTAssertEqual(saved.id, alert.id)
        XCTAssertEqual(saved.createdAt, alert.createdAt)
        XCTAssertEqual(saved.threshold, 12)
        XCTAssertFalse(saved.isActive)
        XCTAssertEqual(saved.lastTriggeredAt, triggeredAt)
        XCTAssertEqual(saved.triggerCountToday, 1)
        XCTAssertEqual(saved.lastTriggerDay, "2026-11-11")
    }

    @MainActor
    func testDeletedRecordsAreNotRecreatedByDrafts() throws {
        let groups = PortfolioGroupsRepository(dbPool: pool)
        let holding = Holding(symbol: symbol, name: "持仓", quantity: 100, costPrice: 8)
        let watch = WatchItem(symbol: symbol, name: "自选")
        let alert = Alert(symbol: symbol, name: "预警", condition: .priceAbove, threshold: 9)
        let holdings = HoldingsRepository(dbPool: pool)
        let watches = WatchlistRepository(dbPool: pool)
        let alerts = AlertsRepository(dbPool: pool)
        try holdings.upsert(holding)
        try watches.upsert(watch)
        try alerts.upsert(alert)
        let holdingDraft = HoldingEditorDraft(initial: holding)
        let watchDraft = WatchEditorDraft(initial: watch)
        let alertDraft = AlertEditorDraft(initial: alert)
        try holdings.delete(id: holding.id)
        try watches.delete(id: watch.id)
        try alerts.delete(id: alert.id)
        XCTAssertThrowsError(try holdingDraft.save(to: holdings, groups: groups))
        XCTAssertThrowsError(try watchDraft.save(to: watches, groups: groups))
        XCTAssertThrowsError(try alertDraft.save(to: alerts))
        XCTAssertTrue(try holdings.all().isEmpty)
        XCTAssertTrue(try watches.all().isEmpty)
        XCTAssertTrue(try alerts.all().isEmpty)
        XCTAssertEqual(holdingDraft.quantity, "100")
        XCTAssertEqual(watchDraft.code, symbol.code)
        XCTAssertEqual(alertDraft.thresholdText, "9")
    }

    @MainActor
    func testValidationAndWriteFailuresDoNotClearInputs() throws {
        let repo = HoldingsRepository(dbPool: pool)
        let groups = PortfolioGroupsRepository(dbPool: pool)
        let draft = HoldingEditorDraft()
        draft.code = "  \n"
        draft.quantity = "100"
        draft.costPrice = "8.25"
        XCTAssertThrowsError(try draft.save(to: repo, groups: groups))
        draft.code = symbol.code
        draft.quantity = "0"
        XCTAssertThrowsError(try draft.save(to: repo, groups: groups))
        draft.quantity = "100"
        let wrongGroup = PortfolioGroup(name: "自选分组", kind: .watchlist)
        try groups.upsert(wrongGroup)
        draft.groupID = wrongGroup.id
        XCTAssertThrowsError(try draft.save(to: repo, groups: groups))
        draft.groupID = nil
        try pool.write { db in
            try db.execute(sql: "CREATE TRIGGER fail_insert BEFORE INSERT ON holding BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        }
        XCTAssertThrowsError(try draft.save(to: repo, groups: groups))
        XCTAssertEqual(draft.code, symbol.code)
        XCTAssertEqual(draft.quantity, "100")
        XCTAssertEqual(draft.costPrice, "8.25")
        XCTAssertTrue(try repo.all().isEmpty)
    }

    @MainActor
    func testTabDraftsSurviveReloadAndCancelIndependently() throws {
        let vm = makeViewModel()
        vm.openHoldingEditor()
        guard case .holding(let holding) = vm.editors[.holdings] else { return XCTFail("Missing holding draft") }
        holding.code = "600000"
        holding.quantity = "100"
        holding.searchVM.query = "搜索草稿"
        vm.currentTab = .watchlist
        vm.openAlertEditor(symbol: SymbolSearchResult(symbol: symbol, name: "来源自选"))
        guard case .alert(let alert) = vm.editors[.watchlist] else { return XCTFail("Missing alert draft") }
        alert.thresholdText = "12"
        alert.showAdvanced = true
        vm.currentTab = .alerts
        vm.openAlertEditor()
        vm.reload()
        vm.currentTab = .holdings
        vm.openHoldingEditor()
        guard case .holding(let restored) = vm.editors[.holdings] else { return XCTFail("Lost holding draft") }
        XCTAssertTrue(restored === holding)
        XCTAssertEqual(restored.quantity, "100")
        XCTAssertEqual(restored.searchVM.query, "搜索草稿")
        XCTAssertTrue(alert.showAdvanced)
        XCTAssertEqual(alert.thresholdText, "12")
        XCTAssertEqual(vm.editors.count, 3)
        vm.cancelEditor(in: .watchlist)
        XCTAssertNil(vm.editors[.watchlist])
        XCTAssertNotNil(vm.editors[.holdings])
        XCTAssertNotNil(vm.editors[.alerts])
        vm.currentTab = .watchlist
        vm.openWatchEditor()
        guard case .watch(let watch) = vm.editors[.watchlist] else { return XCTFail("Missing fresh draft") }
        XCTAssertTrue(watch.code.isEmpty)
        XCTAssertTrue(try AlertsRepository(dbPool: pool).all().isEmpty)
        XCTAssertTrue(makeViewModel().editors.isEmpty)
    }

    @MainActor
    func testSavedDraftClearsOnlyItsTabAndExpandsGroup() throws {
        let group = PortfolioGroup(name: "持仓分组", kind: .holdings)
        let groups = PortfolioGroupsRepository(dbPool: pool)
        try groups.upsert(group)
        let vm = makeViewModel()
        vm.openHoldingEditor()
        guard case .holding(let draft) = vm.editors[.holdings] else { return XCTFail("Missing draft") }
        draft.pick(SymbolSearchResult(symbol: symbol, name: "持仓"))
        draft.quantity = "100"
        draft.costPrice = "8"
        draft.groupID = group.id
        try draft.save(to: HoldingsRepository(dbPool: pool), groups: groups)
        vm.currentTab = .alerts
        vm.openAlertEditor()
        let refreshed = expectation(description: "Saved portfolio refreshes with test quotes")
        let observation = vm.refresher.$lastUpdated.compactMap { $0 }.first().sink { _ in refreshed.fulfill() }
        vm.finishEditor(in: .holdings)
        XCTAssertNil(vm.editors[.holdings])
        XCTAssertNotNil(vm.editors[.alerts])
        XCTAssertEqual(vm.currentTab, .alerts)
        XCTAssertTrue(vm.isExpanded(group.id, kind: .holdings))
        XCTAssertEqual(vm.holdings.first?.groupID, group.id)
        wait(for: [refreshed], timeout: 2)
        withExtendedLifetime(observation) {}
    }

    @MainActor
    private func makeViewModel() -> PopoverViewModel {
        let holdings = HoldingsRepository(dbPool: pool)
        let watches = WatchlistRepository(dbPool: pool)
        let settings = SettingsRepository(dbPool: pool)
        let service = PortfolioService(holdingsRepo: holdings, watchlistRepo: watches,
                                       alertsRepo: AlertsRepository(dbPool: pool), settingsRepo: settings,
                                       provider: EditorQuoteProvider(), fx: FXService(provider: EditorFXProvider()))
        let refresher = QuoteRefresher(service: service, indexService: IndexService(), clock: MarketClock())
        return PopoverViewModel(refresher: refresher, holdingsRepo: holdings, watchlistRepo: watches,
                                alertsRepo: AlertsRepository(dbPool: pool),
                                settingsRepo: settings, groupsRepo: PortfolioGroupsRepository(dbPool: pool))
    }
}

private struct EditorQuoteProvider: QuoteProvider {
    let id = "editor-test"
    let supportedMarkets: Set<Market> = [.a, .hk, .us]
    func fetch(_ symbols: [SymbolID]) async throws -> [SymbolID: Quote] {
        Dictionary(uniqueKeysWithValues: symbols.map { symbol in
            (symbol, Quote(symbol: symbol, name: "测试", price: 10, prevClose: 9,
                           open: nil, high: nil, low: nil, volume: nil,
                           currency: symbol.market.defaultCurrency, timestamp: Date(), isClosed: false))
        })
    }
}

private struct EditorFXProvider: FXProvider {
    func fetch(pairs: [(Currency, Currency)]) async throws -> [FXRate] { [] }
}
