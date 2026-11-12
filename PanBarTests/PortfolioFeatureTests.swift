import XCTest
import GRDB
@testable import PanBar

final class PortfolioFeatureTests: XCTestCase {
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

    func testGroupsKeepSeparateMembershipAndDeletionPreservesRecords() throws {
        let groups = PortfolioGroupsRepository(dbPool: pool)
        let holdings = HoldingsRepository(dbPool: pool)
        let watchlist = WatchlistRepository(dbPool: pool)
        var heldGroup = PortfolioGroup(name: "长期", kind: .holdings)
        let watchedGroup = PortfolioGroup(name: "长期", kind: .watchlist)
        try groups.upsert(heldGroup)
        try groups.upsert(watchedGroup)
        let holding = Holding(symbol: symbol, name: "测试", quantity: 100, costPrice: 8, createdAt: Date(timeIntervalSince1970: 1_700_000_000), groupID: heldGroup.id)
        let watch = WatchItem(symbol: symbol, name: "测试", createdAt: Date(timeIntervalSince1970: 1_700_000_000), groupID: watchedGroup.id)
        try holdings.upsert(holding)
        try watchlist.upsert(watch)
        heldGroup.name = "红利"
        try groups.upsert(heldGroup)
        XCTAssertEqual(try groups.all().count, 2)
        XCTAssertEqual(try holdings.all().first?.groupID, heldGroup.id)
        XCTAssertEqual(try watchlist.all().first?.groupID, watchedGroup.id)

        try groups.delete(id: heldGroup.id)
        var ungrouped = holding
        ungrouped.groupID = nil
        XCTAssertEqual(try holdings.all(), [ungrouped])
        XCTAssertEqual(try watchlist.all(), [watch])
        XCTAssertEqual(try groups.all(), [watchedGroup])
        try groups.delete(id: watchedGroup.id)
        XCTAssertNil(try watchlist.all().first?.groupID)
        XCTAssertEqual(try watchlist.all().first?.id, watch.id)
    }

    func testMovingMembershipKeepsQuantityCostAndOrder() throws {
        let groups = PortfolioGroupsRepository(dbPool: pool)
        let first = PortfolioGroup(name: "组合一", kind: .holdings)
        let second = PortfolioGroup(name: "组合二", kind: .holdings)
        try groups.upsert(first)
        try groups.upsert(second)
        let repo = HoldingsRepository(dbPool: pool)
        var holding = Holding(symbol: symbol, name: "测试", quantity: 200, costPrice: 9, sortOrder: 3, createdAt: Date(timeIntervalSince1970: 1_700_000_000), groupID: first.id)
        try repo.upsert(holding)
        holding.groupID = second.id
        try repo.upsert(holding)
        XCTAssertEqual(try repo.all(), [holding])
        try groups.delete(id: first.id)
        XCTAssertEqual(try repo.all(), [holding])
    }

    func testLegacyDatabaseMigrationKeepsExistingHoldingsAndWatchlist() throws {
        let legacyPool = try DatabasePool(path: directory.appendingPathComponent("legacy.sqlite").path)
        defer { try? legacyPool.close() }
        var legacy = DatabaseMigrator()
        legacy.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE holding (id TEXT PRIMARY KEY, code TEXT NOT NULL, market TEXT NOT NULL,
                    name TEXT NOT NULL, quantity TEXT NOT NULL, costPrice TEXT NOT NULL, currency TEXT NOT NULL,
                    note TEXT, inTicker BOOLEAN NOT NULL, sortOrder INTEGER NOT NULL, createdAt DATETIME NOT NULL);
                CREATE TABLE watchItem (id TEXT PRIMARY KEY, code TEXT NOT NULL, market TEXT NOT NULL,
                    name TEXT NOT NULL, "order" INTEGER NOT NULL, inTicker BOOLEAN NOT NULL, createdAt DATETIME NOT NULL);
                """)
        }
        for name in ["v2_alerts", "v3_in_ticker", "v4_alert_advanced", "v5_quote_cache", "v6_holding_sort_order"] {
            legacy.registerMigration(name) { _ in }
        }
        try legacy.migrate(legacyPool)
        let id = UUID()
        try legacyPool.write { db in
            try db.execute(sql: "INSERT INTO holding VALUES (?, '600000', 'a', '旧持仓', '100', '8.50', 'CNY', '备注', 1, 4, ?)", arguments: [id.uuidString, Date()])
            try db.execute(sql: "INSERT INTO watchItem VALUES (?, '00700', 'hk', '旧自选', 2, 0, ?)", arguments: [UUID().uuidString, Date()])
        }
        try Migrations.register(legacyPool)
        let holding = try XCTUnwrap(HoldingsRepository(dbPool: legacyPool).all().first)
        XCTAssertEqual(holding.id, id)
        XCTAssertEqual(holding.quantity, 100)
        XCTAssertEqual(holding.costPrice, Decimal(string: "8.50"))
        XCTAssertEqual(holding.sortOrder, 4)
        XCTAssertEqual(holding.note, "备注")
        XCTAssertNil(holding.groupID)
        let watch = try XCTUnwrap(WatchlistRepository(dbPool: legacyPool).all().first)
        XCTAssertNil(watch.groupID)
        XCTAssertEqual(watch.order, 2)
        XCTAssertFalse(watch.inTicker)
    }

    func testNewBackupRoundTripAndLegacyBackupWithoutGroupFields() throws {
        let group = PortfolioGroup(name: "长期", kind: .holdings)
        let holding = Holding(symbol: symbol, name: "测试", quantity: 100, costPrice: 8, groupID: group.id)
        let watch = WatchItem(symbol: symbol, name: "测试")
        let bundle = BackupBundle(schemaVersion: 2, exportedAt: Date(), appVersion: "test", holdings: [holding], watchlist: [watch], alerts: [], settings: [:], groups: [group])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(bundle)
        let restored = try decoder.decode(BackupBundle.self, from: data)
        try restored.validate()
        XCTAssertEqual(restored.groups, [group])
        XCTAssertEqual(restored.holdings.first?.groupID, group.id)

        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy["schemaVersion"] = 1
        legacy.removeValue(forKey: "groups")
        var legacyHoldings = try XCTUnwrap(legacy["holdings"] as? [[String: Any]])
        legacyHoldings[0].removeValue(forKey: "groupID")
        legacy["holdings"] = legacyHoldings
        let old = try decoder.decode(BackupBundle.self, from: JSONSerialization.data(withJSONObject: legacy))
        try old.validate()
        XCTAssertNil(old.groups)
        XCTAssertNil(old.holdings.first?.groupID)
        XCTAssertNil(old.watchlist.first?.groupID)
        XCTAssertEqual(old.holdings.first?.quantity, holding.quantity)
    }

    func testBackupRejectsDanglingOrWrongKindMembership() throws {
        let group = PortfolioGroup(name: "观察", kind: .watchlist)
        let holding = Holding(symbol: symbol, name: "测试", quantity: 100, costPrice: 8, groupID: group.id)
        for groups in [[], [group], [group, group]] {
            let bundle = BackupBundle(schemaVersion: 2, exportedAt: Date(), appVersion: "test", holdings: [holding], watchlist: [], alerts: [], settings: [:], groups: groups)
            XCTAssertThrowsError(try bundle.validate())
        }
    }

    func testAlertOnlySymbolsGetQuotesIncludingPausedAlerts() async throws {
        let alerts = AlertsRepository(dbPool: pool)
        let pausedSymbol = SymbolID(code: "AAPL", market: .us)
        try alerts.upsert(Alert(symbol: symbol, name: "仅预警", condition: .priceBelow, threshold: 9))
        try alerts.upsert(Alert(symbol: pausedSymbol, name: "暂停预警", condition: .priceAbove, threshold: 200, isActive: false))
        let provider = QuoteSpy()
        let snapshot = try await service(provider).computeSnapshot()
        let requested = await provider.requested
        XCTAssertEqual(Set(requested), [symbol, pausedSymbol])
        XCTAssertEqual(snapshot.allQuotes[symbol]?.price, 10)
        XCTAssertEqual(snapshot.allQuotes[pausedSymbol]?.price, 10)
        XCTAssertTrue(snapshot.positions.isEmpty)
        XCTAssertEqual(snapshot.totalAssets, 0)
        XCTAssertEqual(snapshot.allTimePnL, 0)
    }

    func testSharedSymbolsFetchOnceAndOnlyHoldingsCountTowardAssets() async throws {
        let groups = PortfolioGroupsRepository(dbPool: pool)
        let first = PortfolioGroup(name: "组合一", kind: .holdings)
        let second = PortfolioGroup(name: "组合二", kind: .holdings)
        try groups.upsert(first)
        try groups.upsert(second)
        let holdings = HoldingsRepository(dbPool: pool)
        try holdings.upsert(Holding(symbol: symbol, name: "测试", quantity: 100, costPrice: 8, groupID: first.id))
        try holdings.upsert(Holding(symbol: symbol, name: "测试", quantity: 50, costPrice: 9, groupID: second.id))
        try WatchlistRepository(dbPool: pool).upsert(WatchItem(symbol: symbol, name: "测试"))
        let alerts = AlertsRepository(dbPool: pool)
        try alerts.upsert(Alert(symbol: symbol, name: "测试", condition: .priceAbove, threshold: 11))
        try alerts.upsert(Alert(symbol: symbol, name: "测试", condition: .priceBelow, threshold: 9))
        let provider = QuoteSpy()
        let snapshot = try await service(provider).computeSnapshot()
        let requested = await provider.requested
        XCTAssertEqual(requested, [symbol])
        XCTAssertEqual(snapshot.positions.count, 2)
        XCTAssertEqual(snapshot.totalAssets, 1500)
        XCTAssertEqual(snapshot.totalCost, 1250)
        XCTAssertEqual(snapshot.allTimePnL, 250)
        XCTAssertEqual(snapshot.todayPnL, 150)
    }

    private func service(_ provider: QuoteSpy) throws -> PortfolioService {
        let settings = SettingsRepository(dbPool: pool)
        try settings.setBaseCurrency(.cny)
        return PortfolioService(holdingsRepo: HoldingsRepository(dbPool: pool), watchlistRepo: WatchlistRepository(dbPool: pool), alertsRepo: AlertsRepository(dbPool: pool), settingsRepo: settings, provider: provider, fx: FXService(provider: EmptyFXProvider()))
    }
}

private actor QuoteSpy: QuoteProvider {
    nonisolated let id = "test"
    nonisolated let supportedMarkets: Set<Market> = [.a, .hk, .us]
    private(set) var requested: [SymbolID] = []

    func fetch(_ symbols: [SymbolID]) async throws -> [SymbolID: Quote] {
        requested = symbols
        return Dictionary(uniqueKeysWithValues: symbols.map { symbol in
            (symbol, Quote(symbol: symbol, name: "测试", price: 10, prevClose: 9, open: nil, high: nil, low: nil, volume: nil, currency: symbol.market.defaultCurrency, timestamp: Date(), isClosed: false))
        })
    }
}

private struct EmptyFXProvider: FXProvider {
    func fetch(pairs: [(Currency, Currency)]) async throws -> [FXRate] { [] }
}
