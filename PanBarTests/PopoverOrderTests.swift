import XCTest
import GRDB
@testable import PanBar

final class PopoverOrderTests: XCTestCase {
    private var directory: URL!
    private var pool: DatabasePool!
    private let symbol = SymbolID(code: "600000", market: .a)
    private let createdAt = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        pool = try DatabasePool(path: directory.appendingPathComponent("order.sqlite").path)
        try Migrations.register(pool)
    }

    override func tearDownWithError() throws {
        try pool.close()
        pool = nil
        try FileManager.default.removeItem(at: directory)
    }

    func testAdjacentMovesAndFirstLastInsertion() {
        let ids = ["a", "b", "c", "d"]
        XCTAssertEqual(PopoverOrder.moving("a", to: "b", after: true, in: ids), ["b", "a", "c", "d"])
        XCTAssertEqual(PopoverOrder.moving("b", to: "a", after: false, in: ids), ["b", "a", "c", "d"])
        XCTAssertEqual(PopoverOrder.moving("a", to: "d", after: true, in: ids), ["b", "c", "d", "a"])
        XCTAssertEqual(PopoverOrder.moving("d", to: "a", after: false, in: ids), ["d", "a", "b", "c"])
        XCTAssertEqual(PopoverOrder.moving("d", to: "b", after: true, in: ids), ["a", "b", "d", "c"])
    }

    func testInvalidOrUnchangedDropHasNoOrderToSave() {
        XCTAssertNil(PopoverOrder.moving("a", to: "a", after: true, in: ["a", "b"]))
        XCTAssertNil(PopoverOrder.moving("a", to: "b", after: false, in: ["a", "b"]))
        XCTAssertNil(PopoverOrder.moving("missing", to: "a", after: true, in: ["a", "b"]))
        XCTAssertNil(PopoverOrder.moving("a", to: "missing", after: true, in: ["a", "b"]))
    }

    func testDragPayloadSeparatesKindsAndRejectsUnrelatedText() {
        let id = UUID()
        let holding = PopoverDragItem(kind: .holding, id: id.uuidString)
        XCTAssertEqual(PopoverDragItem(value: holding.value), holding)
        XCTAssertNotEqual(PopoverDragItem.group(nil, kind: .holdings), .group(nil, kind: .watchlist))
        for value in ["", "plain text", id.uuidString, "panbar:unknown:id", "panbar:holding:", "panbar:holding:id:extra"] {
            XCTAssertNil(PopoverDragItem(value: value))
        }
    }

    func testUngroupedDefaultsToEndAndClampsSavedPosition() {
        let first = PortfolioGroup(name: "一", kind: .holdings)
        let second = PortfolioGroup(name: "二", kind: .holdings)
        let foreign = PortfolioGroup(name: "自选", kind: .watchlist)
        let groups = [first, second, foreign]
        XCTAssertEqual(PopoverOrder.groupIDs(groups, kind: .holdings, hasUngrouped: true, ungroupedPosition: nil), [first.id, second.id, nil])
        XCTAssertEqual(PopoverOrder.groupIDs(groups, kind: .holdings, hasUngrouped: true, ungroupedPosition: 1), [first.id, nil, second.id])
        XCTAssertEqual(PopoverOrder.groupIDs(groups, kind: .holdings, hasUngrouped: true, ungroupedPosition: -1), [nil, first.id, second.id])
        XCTAssertEqual(PopoverOrder.groupIDs(groups, kind: .holdings, hasUngrouped: true, ungroupedPosition: 99), [first.id, second.id, nil])
        XCTAssertEqual(PopoverOrder.groupIDs(groups, kind: .holdings, hasUngrouped: false, ungroupedPosition: 0), [first.id, second.id])
    }

    @MainActor
    func testHoldingMovePreservesOtherGroupsAndAllFinancialFields() throws {
        let group = PortfolioGroup(name: "持仓", kind: .holdings)
        try PortfolioGroupsRepository(dbPool: pool).upsert(group)
        let repo = HoldingsRepository(dbPool: pool)
        let first = Holding(symbol: symbol, name: "一", quantity: 100, costPrice: 8, sortOrder: 0, createdAt: createdAt, groupID: group.id)
        let outside = Holding(symbol: symbol, name: "未分组", quantity: 200, costPrice: 9, sortOrder: 1, createdAt: createdAt)
        let second = Holding(symbol: symbol, name: "二", quantity: 300, costPrice: 10, sortOrder: 2, createdAt: createdAt, groupID: group.id)
        for holding in [first, outside, second] { try repo.upsert(holding) }
        let vm = makeViewModel()
        XCTAssertTrue(vm.moveHolding(.init(kind: .holding, id: first.id.uuidString), to: second.id, after: true))
        var expected = [second, outside, first]
        for index in expected.indices { expected[index].sortOrder = index }
        XCTAssertEqual(vm.holdings, expected)
        XCTAssertEqual(try repo.all(), expected)
        XCTAssertFalse(vm.moveHolding(.init(kind: .holding, id: first.id.uuidString), to: outside.id, after: true))
        XCTAssertFalse(vm.moveHolding(.init(kind: .watch, id: first.id.uuidString), to: second.id, after: false))
        XCTAssertEqual(try repo.all(), expected)
    }

    @MainActor
    func testWatchMoveWithinUngroupedPersistsWithoutChangingMembership() throws {
        let repo = WatchlistRepository(dbPool: pool)
        let first = WatchItem(symbol: symbol, name: "一", order: 0, createdAt: createdAt)
        let second = WatchItem(symbol: symbol, name: "二", order: 1, inTicker: false, createdAt: createdAt)
        try repo.upsert(first)
        try repo.upsert(second)
        let vm = makeViewModel()
        XCTAssertTrue(vm.moveWatchItem(.init(kind: .watch, id: first.id.uuidString), to: second.id, after: true))
        var expected = [second, first]
        for index in expected.indices { expected[index].order = index }
        XCTAssertEqual(vm.watchlist, expected)
        XCTAssertEqual(try repo.all(), expected)
        XCTAssertFalse(vm.moveWatchItem(.init(kind: .holding, id: first.id.uuidString), to: second.id, after: false))
    }

    @MainActor
    func testGroupAndUngroupedOrderSurvivesReloadForBothTabs() throws {
        let repo = PortfolioGroupsRepository(dbPool: pool)
        let held = PortfolioGroup(name: "持仓", kind: .holdings)
        let watched = PortfolioGroup(name: "自选", kind: .watchlist)
        try repo.upsert(held)
        try repo.upsert(watched)
        try HoldingsRepository(dbPool: pool).upsert(Holding(symbol: symbol, name: "持仓", quantity: 100, costPrice: 8))
        try WatchlistRepository(dbPool: pool).upsert(WatchItem(symbol: symbol, name: "自选"))
        let vm = makeViewModel()
        vm.toggleGroup(held.id, kind: .holdings)
        XCTAssertTrue(vm.moveGroup(.group(nil, kind: .holdings), to: held.id, kind: .holdings, after: false))
        XCTAssertEqual(vm.groupIDs(for: .watchlist), [watched.id, nil])
        XCTAssertTrue(vm.moveGroup(.group(nil, kind: .watchlist), to: watched.id, kind: .watchlist, after: false))
        XCTAssertFalse(vm.moveGroup(.group(held.id, kind: .holdings), to: watched.id, kind: .watchlist, after: false))
        let restored = makeViewModel()
        XCTAssertEqual(restored.groupIDs(for: .holdings), [nil, held.id])
        XCTAssertEqual(restored.groupIDs(for: .watchlist), [nil, watched.id])
        XCTAssertTrue(restored.isExpanded(held.id, kind: .holdings))
    }

    func testGroupReorderIsScopedAndPersistsAcrossDatabaseReopen() throws {
        let repo = PortfolioGroupsRepository(dbPool: pool)
        let first = PortfolioGroup(name: "一", kind: .holdings, sortOrder: 0)
        let second = PortfolioGroup(name: "二", kind: .holdings, sortOrder: 1)
        let foreign = PortfolioGroup(name: "自选", kind: .watchlist, sortOrder: 7)
        for group in [first, second, foreign] { try repo.upsert(group) }
        try repo.reorder(ids: [second.id, nil, first.id], kind: .holdings)
        let reopened = try DatabasePool(path: directory.appendingPathComponent("order.sqlite").path)
        defer { try? reopened.close() }
        let groups = try PortfolioGroupsRepository(dbPool: reopened).all()
        XCTAssertEqual(groups.filter { $0.kind == .holdings }.map(\.id), [second.id, first.id])
        XCTAssertEqual(groups.first { $0.id == foreign.id }, foreign)
        XCTAssertEqual(SettingsRepository(dbPool: reopened).string(SettingsRepository.Keys.ungroupedPosition(.holdings)), "1")
        XCTAssertThrowsError(try repo.reorder(ids: [foreign.id, first.id], kind: .holdings))
        XCTAssertEqual(try repo.all(), groups)
    }

    @MainActor
    func testGroupAndUngroupedWriteRollBackTogetherOnFailure() throws {
        let repo = PortfolioGroupsRepository(dbPool: pool)
        let first = PortfolioGroup(name: "一", kind: .holdings, sortOrder: 0)
        let second = PortfolioGroup(name: "二", kind: .holdings, sortOrder: 1)
        try repo.upsert(first)
        try repo.upsert(second)
        try HoldingsRepository(dbPool: pool).upsert(Holding(symbol: symbol, name: "未分组", quantity: 1, costPrice: 1))
        let vm = makeViewModel()
        try pool.write { db in
            try db.execute(sql: "CREATE TRIGGER fail_order BEFORE INSERT ON appSetting BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        }
        XCTAssertFalse(vm.moveGroup(.group(second.id, kind: .holdings), to: first.id, kind: .holdings, after: false))
        XCTAssertEqual(vm.groupIDs(for: .holdings), [first.id, second.id, nil])
        XCTAssertEqual(try repo.all(), [first, second])
        XCTAssertNil(SettingsRepository(dbPool: pool).string(SettingsRepository.Keys.ungroupedPosition(.holdings)))
        XCTAssertNotNil(vm.reorderError)
    }

    @MainActor
    func testFailedHoldingWriteKeepsDisplayedAndPersistedOrder() throws {
        let repo = HoldingsRepository(dbPool: pool)
        let first = Holding(symbol: symbol, name: "一", quantity: 100, costPrice: 8, sortOrder: 0, createdAt: createdAt)
        let second = Holding(symbol: symbol, name: "二", quantity: 200, costPrice: 9, sortOrder: 1, createdAt: createdAt)
        try repo.upsert(first)
        try repo.upsert(second)
        let vm = makeViewModel()
        try pool.write { db in
            try db.execute(sql: "CREATE TRIGGER fail_order BEFORE UPDATE OF sortOrder ON holding BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        }
        XCTAssertFalse(vm.moveHolding(.init(kind: .holding, id: first.id.uuidString), to: second.id, after: true))
        XCTAssertEqual(vm.holdings, [first, second])
        XCTAssertEqual(try repo.all(), [first, second])
        XCTAssertNotNil(vm.reorderError)
    }

    func testIndexOrderHandlesOldSettingsDuplicatesAndUnknownIDs() {
        let catalog = IndexCatalog.all.map(\.id)
        XCTAssertEqual(PopoverOrder.indexIDs(stored: []), catalog)
        XCTAssertEqual(PopoverOrder.indexIDs(stored: ["SPX", "invalid", "SPX"]), ["SPX"] + catalog.filter { $0 != "SPX" })
    }

    @MainActor
    func testIndexOrderSurvivesMissingQuotesRefreshAndReload() throws {
        let vm = makeViewModel()
        let catalog = IndexCatalog.all
        let first = try XCTUnwrap(catalog.first)
        let last = try XCTUnwrap(catalog.last)
        XCTAssertTrue(vm.moveIndex(.init(kind: .index, id: last.id), to: first.id, after: false))
        let quote: (IndexDescriptor) -> IndexQuote = {
            IndexQuote(descriptor: $0, price: 100, prevClose: 99, change: 1, changePct: 0.01)
        }
        XCTAssertEqual(vm.orderedIndexQuotes([quote(first)]).map(\.id), [first.id])
        let restored = makeViewModel()
        XCTAssertEqual(restored.orderedIndexQuotes(catalog.map(quote)).map(\.id), [last.id] + catalog.dropLast().map(\.id))
        XCTAssertEqual(restored.orderedIndexQuotes(catalog.reversed().map(quote)).map(\.id), [last.id] + catalog.dropLast().map(\.id))
        XCTAssertEqual((SettingsRepository(dbPool: pool).string(SettingsRepository.Keys.popoverIndexOrder) ?? "").split(separator: ",").count, catalog.count)
    }

    @MainActor
    private func makeViewModel() -> PopoverViewModel {
        let holdings = HoldingsRepository(dbPool: pool)
        let watches = WatchlistRepository(dbPool: pool)
        let settings = SettingsRepository(dbPool: pool)
        let service = PortfolioService(holdingsRepo: holdings, watchlistRepo: watches,
                                       alertsRepo: AlertsRepository(dbPool: pool), settingsRepo: settings,
                                       provider: ReorderQuoteProvider(), fx: FXService(provider: ReorderFXProvider()))
        let refresher = QuoteRefresher(service: service, indexService: IndexService(), clock: MarketClock())
        return PopoverViewModel(refresher: refresher, holdingsRepo: holdings, watchlistRepo: watches,
                                settingsRepo: settings, groupsRepo: PortfolioGroupsRepository(dbPool: pool))
    }
}

private struct ReorderQuoteProvider: QuoteProvider {
    let id = "reorder-test"
    let supportedMarkets: Set<Market> = [.a, .hk, .us]
    func fetch(_ symbols: [SymbolID]) async throws -> [SymbolID: Quote] {
        XCTFail("Sorting must not request quotes")
        return [:]
    }
}

private struct ReorderFXProvider: FXProvider {
    func fetch(pairs: [(Currency, Currency)]) async throws -> [FXRate] {
        XCTFail("Sorting must not request exchange rates")
        return []
    }
}
