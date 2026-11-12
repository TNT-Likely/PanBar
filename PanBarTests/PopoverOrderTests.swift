import XCTest
import GRDB
import SwiftUI
import AppKit
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
        XCTAssertFalse(vm.moveHolding(.init(kind: .holding, id: first.id.uuidString), toGroup: group.id, before: nil))
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

    @MainActor
    func testHoldingCrossGroupMovePreservesLatestFieldsAndPersists() throws {
        let groups = PortfolioGroupsRepository(dbPool: pool)
        let source = PortfolioGroup(name: "原组", kind: .holdings)
        let target = PortfolioGroup(name: "目标组", kind: .holdings)
        for group in [source, target] { try groups.upsert(group) }
        let repo = HoldingsRepository(dbPool: pool)
        let a = Holding(symbol: symbol, name: "移动项", quantity: 100, costPrice: 8, note: "保留备注",
                        inTicker: false, sortOrder: 0, createdAt: createdAt, groupID: source.id)
        let b = Holding(symbol: symbol, name: "目标首项", quantity: 200, costPrice: 9, sortOrder: 1, groupID: target.id)
        let c = Holding(symbol: symbol, name: "目标尾项", quantity: 300, costPrice: 10, sortOrder: 2, groupID: target.id)
        for item in [a, b, c] { try repo.upsert(item) }
        let vm = makeViewModel()
        XCTAssertTrue(try repo.update(id: a.id) { $0.quantity = 150 })
        XCTAssertTrue(vm.moveHolding(.init(kind: .holding, id: a.id.uuidString), toGroup: target.id, before: c.id))
        XCTAssertEqual(vm.holdings.map(\.id), [b.id, a.id, c.id])
        XCTAssertTrue(vm.isExpanded(target.id, kind: .holdings))
        var moved = a
        moved.quantity = 150
        moved.groupID = target.id
        moved.sortOrder = 1
        XCTAssertEqual(vm.holdings.first { $0.id == a.id }, moved)
        XCTAssertEqual(try repo.all(), vm.holdings)
        let payload = PopoverDragItem(kind: .holding, id: a.id.uuidString)
        XCTAssertTrue(vm.moveHolding(payload, toGroup: target.id, before: b.id))
        XCTAssertEqual(vm.holdings.map(\.id), [a.id, b.id, c.id])
        XCTAssertTrue(vm.moveHolding(payload, toGroup: target.id, before: nil))
        XCTAssertEqual(vm.holdings.map(\.id), [b.id, c.id, a.id])
        XCTAssertTrue(vm.moveHolding(payload, toGroup: source.id, before: nil))
        XCTAssertTrue(vm.isExpanded(source.id, kind: .holdings))
        XCTAssertTrue(vm.moveHolding(payload, toGroup: nil, before: nil))
        moved.groupID = nil
        moved.sortOrder = 2
        XCTAssertEqual(vm.holdings.first { $0.id == a.id }, moved)
        let reopened = try DatabasePool(path: directory.appendingPathComponent("order.sqlite").path)
        defer { try? reopened.close() }
        XCTAssertEqual(try HoldingsRepository(dbPool: reopened).all(), vm.holdings)
    }

    @MainActor
    func testWatchMovesToFirstLastEmptyAndUngrouped() throws {
        let groups = PortfolioGroupsRepository(dbPool: pool)
        let source = PortfolioGroup(name: "原组", kind: .watchlist)
        let target = PortfolioGroup(name: "目标组", kind: .watchlist)
        let empty = PortfolioGroup(name: "空组", kind: .watchlist)
        for group in [source, target, empty] { try groups.upsert(group) }
        let repo = WatchlistRepository(dbPool: pool)
        let a = WatchItem(symbol: symbol, name: "移动项", order: 0, inTicker: false, createdAt: createdAt, groupID: source.id)
        let b = WatchItem(symbol: symbol, name: "目标首项", order: 1, groupID: target.id)
        let c = WatchItem(symbol: symbol, name: "目标尾项", order: 2, groupID: target.id)
        for item in [a, b, c] { try repo.upsert(item) }
        let vm = makeViewModel()
        let payload = PopoverDragItem(kind: .watch, id: a.id.uuidString)
        XCTAssertTrue(vm.moveWatchItem(payload, to: b.id, after: false))
        XCTAssertEqual(vm.watchlist.filter { $0.groupID == target.id }.map(\.id), [a.id, b.id, c.id])
        XCTAssertTrue(vm.moveWatchItem(payload, toGroup: target.id, before: nil))
        XCTAssertEqual(vm.watchlist.filter { $0.groupID == target.id }.map(\.id), [b.id, c.id, a.id])
        XCTAssertTrue(vm.moveWatchItem(payload, toGroup: empty.id, before: nil))
        XCTAssertTrue(vm.isExpanded(empty.id, kind: .watchlist))
        XCTAssertEqual(vm.watchlist.filter { $0.groupID == empty.id }.map(\.id), [a.id])
        XCTAssertTrue(vm.moveWatchItem(payload, toGroup: nil, before: nil))
        var expected = a
        expected.groupID = nil
        expected.order = 2
        XCTAssertEqual(vm.watchlist.first { $0.id == a.id }, expected)
        let reopened = try DatabasePool(path: directory.appendingPathComponent("order.sqlite").path)
        defer { try? reopened.close() }
        XCTAssertEqual(try WatchlistRepository(dbPool: reopened).all(), vm.watchlist)
    }

    @MainActor
    func testInvalidCrossGroupTargetsAndNoOpMovesDoNotWrite() throws {
        let groups = PortfolioGroupsRepository(dbPool: pool)
        let held = PortfolioGroup(name: "持仓", kind: .holdings)
        let watched = PortfolioGroup(name: "自选", kind: .watchlist)
        let deleted = PortfolioGroup(name: "删除组", kind: .holdings)
        for group in [held, watched, deleted] { try groups.upsert(group) }
        let holdings = HoldingsRepository(dbPool: pool)
        let watches = WatchlistRepository(dbPool: pool)
        let h = Holding(symbol: symbol, name: "持仓", quantity: 1, costPrice: 1, createdAt: createdAt, groupID: held.id)
        let w = WatchItem(symbol: symbol, name: "自选", createdAt: createdAt, groupID: watched.id)
        try holdings.upsert(h)
        try watches.upsert(w)
        let vm = makeViewModel()
        try groups.delete(id: deleted.id)
        try pool.write { db in
            try db.execute(sql: "CREATE TRIGGER no_holding_write BEFORE UPDATE ON holding BEGIN SELECT RAISE(ABORT, 'unexpected write'); END")
            try db.execute(sql: "CREATE TRIGGER no_watch_write BEFORE UPDATE ON watchItem BEGIN SELECT RAISE(ABORT, 'unexpected write'); END")
        }
        let hp = PopoverDragItem(kind: .holding, id: h.id.uuidString)
        let wp = PopoverDragItem(kind: .watch, id: w.id.uuidString)
        XCTAssertFalse(vm.moveHolding(hp, toGroup: held.id, before: nil))
        XCTAssertFalse(vm.moveWatchItem(wp, toGroup: watched.id, before: nil))
        XCTAssertFalse(vm.moveHolding(hp, toGroup: deleted.id, before: nil))
        XCTAssertFalse(vm.moveHolding(hp, toGroup: watched.id, before: nil))
        XCTAssertFalse(vm.moveWatchItem(wp, toGroup: held.id, before: nil))
        XCTAssertFalse(vm.moveHolding(hp, toGroup: nil, before: UUID()))
        XCTAssertFalse(vm.moveHolding(hp, toGroup: nil, before: h.id))
        XCTAssertFalse(vm.moveWatchItem(.init(kind: .watch, id: UUID().uuidString), toGroup: nil, before: nil))
        XCTAssertNil(vm.reorderError)
        XCTAssertEqual(try holdings.all(), [h])
        XCTAssertEqual(try watches.all(), [w])
    }

    @MainActor
    func testCrossGroupMembershipAndOrderRollBackTogetherForBothKinds() throws {
        let holdings = HoldingsRepository(dbPool: pool)
        let watches = WatchlistRepository(dbPool: pool)
        let groups = PortfolioGroupsRepository(dbPool: pool)
        let held = PortfolioGroup(name: "持仓目标", kind: .holdings)
        let watched = PortfolioGroup(name: "自选目标", kind: .watchlist)
        try groups.upsert(held)
        try groups.upsert(watched)
        let h = Holding(symbol: symbol, name: "持仓", quantity: 1, costPrice: 1, createdAt: createdAt)
        let w = WatchItem(symbol: symbol, name: "自选", createdAt: createdAt)
        try holdings.upsert(h)
        try watches.upsert(w)
        let vm = makeViewModel()
        try pool.write { db in
            try db.execute(sql: "CREATE TRIGGER fail_holding_order BEFORE UPDATE OF sortOrder ON holding BEGIN SELECT RAISE(ABORT, 'test failure'); END")
            try db.execute(sql: "CREATE TRIGGER fail_watch_order BEFORE UPDATE OF \"order\" ON watchItem BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        }
        XCTAssertFalse(vm.moveHolding(.init(kind: .holding, id: h.id.uuidString), toGroup: held.id, before: nil))
        XCTAssertFalse(vm.moveWatchItem(.init(kind: .watch, id: w.id.uuidString), toGroup: watched.id, before: nil))
        XCTAssertEqual(vm.holdings, [h])
        XCTAssertEqual(vm.watchlist, [w])
        XCTAssertEqual(try holdings.all(), [h])
        XCTAssertEqual(try watches.all(), [w])
        XCTAssertNotNil(vm.reorderError)
    }

    @MainActor
    func testDragPreviewSlotsCancelAndRepeatedDrags() throws {
        let sourceGroup = UUID(), targetGroup = UUID()
        let a = UUID().uuidString, b = UUID().uuidString, c = UUID().uuidString
        let drag = PopoverItemDrag()
        drag.reduceMotion = true
        drag.configure(rows: [(a, sourceGroup), (b, targetGroup), (c, targetGroup)], groups: [sourceGroup, targetGroup, nil])
        drag.setViewport(CGSize(width: 360, height: 300))
        drag.setFrames([
            .row(a, group: sourceGroup): CGRect(x: 0, y: 30, width: 360, height: 40),
            .group(targetGroup): CGRect(x: 0, y: 80, width: 360, height: 40),
            .row(b, group: targetGroup): CGRect(x: 0, y: 120, width: 360, height: 40),
            .row(c, group: targetGroup): CGRect(x: 0, y: 160, width: 360, height: 40),
            .empty(nil): CGRect(x: 0, y: 220, width: 360, height: 80)
        ])
        drag.begin(at: CGPoint(x: 20, y: 50), kind: .holding)
        XCTAssertTrue(drag.showsPlaceholder(in: sourceGroup, before: a))
        drag.update(CGPoint(x: 20, y: 125))
        XCTAssertTrue(drag.showsPlaceholder(in: targetGroup, before: b))
        drag.update(CGPoint(x: 20, y: 155))
        XCTAssertTrue(drag.showsPlaceholder(in: targetGroup, before: c))
        drag.update(CGPoint(x: 20, y: 90))
        XCTAssertTrue(drag.showsPlaceholder(in: targetGroup, before: nil))
        drag.update(CGPoint(x: 20, y: 240))
        XCTAssertTrue(drag.showsPlaceholder(in: nil, before: nil))
        drag.cancel()
        XCTAssertNil(drag.active)
        XCTAssertNil(drag.destination)
        drag.finish(at: CGPoint(x: 20, y: 155)) { _, _ in XCTFail("Cancelled drag must not commit"); return true }

        drag.begin(at: CGPoint(x: 20, y: 50), kind: .holding)
        drag.update(CGPoint(x: 400, y: 155))
        XCTAssertNil(drag.active)
        drag.finish(at: CGPoint(x: 400, y: 155)) { _, _ in XCTFail("Outside drop must not commit"); return true }
        XCTAssertNil(drag.active)
        drag.begin(at: CGPoint(x: 20, y: 50), kind: .holding)
        var committed = false
        drag.finish(at: CGPoint(x: 20, y: 155)) { payload, target in
            XCTAssertEqual(payload.id, a)
            XCTAssertEqual(target, PopoverDropLocation(groupID: targetGroup, beforeID: c))
            committed = true
            return true
        }
        XCTAssertTrue(committed)
        XCTAssertEqual(drag.highlightedID, a)
        XCTAssertNil(drag.active)
        XCTAssertNil(drag.animation)
    }

    @MainActor
    func testMovingFromHeaderOntoFirstRowUsesItsCurrentFrame() {
        let a = UUID().uuidString, b = UUID().uuidString, first = UUID(), second = UUID()
        let drag = PopoverItemDrag()
        drag.configure(rows: [(a, first), (b, second)], groups: [first, second])
        drag.setViewport(CGSize(width: 360, height: 200))
        func frame(_ y: CGFloat) -> CGRect { CGRect(x: 0, y: y, width: 360, height: 40) }
        drag.setFrames([.row(a, group: first): frame(40), .group(second): frame(80), .row(b, group: second): frame(120)])
        drag.begin(at: CGPoint(x: 20, y: 79), kind: .holding)
        defer { drag.cancel() }
        drag.update(CGPoint(x: 20, y: 85))
        XCTAssertTrue(drag.showsPlaceholder(in: second, before: nil))

        // 源行收起后，第二组首行移到了原来的组头位置。
        drag.setFrames([.group(second): frame(40), .row(b, group: second): frame(80), .placeholder: frame(120)])
        XCTAssertTrue(drag.showsPlaceholder(in: second, before: nil))
        drag.update(CGPoint(x: 20, y: 90))
        XCTAssertTrue(drag.showsPlaceholder(in: second, before: b))
        drag.update(CGPoint(x: 20, y: 80))
        XCTAssertTrue(drag.showsPlaceholder(in: second, before: b), "首行上沿是组首插入点")
        drag.update(CGPoint(x: 20, y: 78))
        XCTAssertTrue(drag.showsPlaceholder(in: second, before: b), "略高于首行仍可插到组首")
    }

    @MainActor
    func testDragPreviewCancelsWhenTargetDisappearsOrTabChanges() throws {
        let vm = makeViewModel()
        let a = UUID().uuidString, group = UUID()
        let drag = vm.itemDrag
        drag.configure(rows: [(a, nil)], groups: [group, nil])
        drag.setViewport(CGSize(width: 360, height: 200))
        drag.setFrames([.row(a, group: nil): CGRect(x: 0, y: 0, width: 360, height: 40),
                        .group(group): CGRect(x: 0, y: 60, width: 360, height: 40)])
        drag.begin(at: CGPoint(x: 10, y: 20), kind: .holding)
        drag.update(CGPoint(x: 10, y: 80))
        drag.configure(rows: [(a, nil)], groups: [nil])
        XCTAssertNil(drag.active)
        drag.begin(at: CGPoint(x: 10, y: 20), kind: .holding)
        vm.currentTab = .watchlist
        XCTAssertNil(drag.active)
        XCTAssertNil(drag.destination)
    }

    @MainActor
    func testDragEdgeScrollOnlyRunsInsideViewport() {
        let viewport = CGRect(x: 0, y: 0, width: 360, height: 240)
        XCTAssertLessThan(PopoverItemDrag.scrollStep(at: CGPoint(x: 100, y: 5), in: viewport), 0)
        XCTAssertGreaterThan(PopoverItemDrag.scrollStep(at: CGPoint(x: 100, y: 235), in: viewport), 0)
        XCTAssertEqual(PopoverItemDrag.scrollStep(at: CGPoint(x: 100, y: 120), in: viewport), 0)
        XCTAssertEqual(PopoverItemDrag.scrollStep(at: CGPoint(x: 400, y: 235), in: viewport), 0)
        XCTAssertEqual(PopoverItemDrag.scrollStep(at: CGPoint(x: 100, y: -5), in: viewport), 0)
    }

    @MainActor
    func testRenderedTabsKeepPlaceholderAndRestoreSourceOnCancel() async throws {
        for kind in [PortfolioGroupKind.holdings, .watchlist] {
            let source = PortfolioGroup(name: "稳健配置", kind: kind, sortOrder: 0)
            let target = PortfolioGroup(name: "科技成长", kind: kind, sortOrder: 1)
            let groups = PortfolioGroupsRepository(dbPool: pool)
            try groups.upsert(source)
            try groups.upsert(target)
            let ids = (0..<4).map { _ in UUID() }
            let names = ["招商银行", "腾讯控股", "苹果", "微软"]
            for index in ids.indices {
                let group = index < 2 ? source.id : target.id
                if kind == .holdings {
                    try HoldingsRepository(dbPool: pool).upsert(Holding(id: ids[index], symbol: symbol, name: names[index],
                        quantity: 100, costPrice: 10, sortOrder: index, createdAt: createdAt, groupID: group))
                } else {
                    try WatchlistRepository(dbPool: pool).upsert(WatchItem(id: ids[index], symbol: symbol, name: names[index],
                        order: index, createdAt: createdAt, groupID: group))
                }
            }
            let vm = makeViewModel()
            vm.toggleGroup(source.id, kind: kind)
            vm.toggleGroup(target.id, kind: kind)
            let originalHoldings = vm.holdings
            let originalWatches = vm.watchlist
            let content = kind == .holdings ? AnyView(HoldingsTab()) : AnyView(WatchlistTab())
            let host = NSHostingView(rootView: content.environmentObject(vm).environmentObject(vm.refresher)
                .environmentObject(AppearancePreferences(repo: vm.settingsRepo))
                .environmentObject(TickerPreferences(repo: vm.settingsRepo))
                .environment(\.colorScheme, .light)
                .background(Color(nsColor: .windowBackgroundColor)))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 400),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            defer { vm.itemDrag.cancel(); window.close() }
            for _ in 0..<30 where vm.itemDrag.frames[.row(ids[1].uuidString, group: source.id)] == nil {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            let sourceFrame = try XCTUnwrap(vm.itemDrag.frames[.row(ids[1].uuidString, group: source.id)])
            vm.itemDrag.reduceMotion = kind == .watchlist
            vm.itemDrag.begin(at: CGPoint(x: sourceFrame.midX, y: sourceFrame.midY), kind: kind == .holdings ? .holding : .watch)
            XCTAssertNotNil(vm.itemDrag.active)
            try await Task.sleep(nanoseconds: 50_000_000)
            let targetFrame = try XCTUnwrap(vm.itemDrag.frames[.row(ids[2].uuidString, group: target.id)])
            vm.itemDrag.update(CGPoint(x: targetFrame.midX, y: targetFrame.minY + 3))
            try await Task.sleep(nanoseconds: 300_000_000)
            XCTAssertTrue(vm.itemDrag.showsPlaceholder(in: target.id, before: ids[2].uuidString))
            let placeholder = try XCTUnwrap(vm.itemDrag.frames[.placeholder])
            XCTAssertEqual(placeholder.height, sourceFrame.height, accuracy: 1)
            if kind == .watchlist { XCTAssertNil(vm.itemDrag.animation) }
            XCTAssertEqual(try HoldingsRepository(dbPool: pool).all(), originalHoldings)
            XCTAssertEqual(try WatchlistRepository(dbPool: pool).all(), originalWatches)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = "drag-\(kind.rawValue)-preview"
            attachment.lifetime = .keepAlways
            add(attachment)

            func findScrollView(in view: NSView) -> NSScrollView? {
                if let scroll = view as? NSScrollView { return scroll }
                return view.subviews.lazy.compactMap { findScrollView(in: $0) }.first
            }
            let scroll = try XCTUnwrap(findScrollView(in: host))
            let initialOffset = scroll.contentView.bounds.origin.y
            let viewport = vm.itemDrag.viewport
            vm.itemDrag.update(CGPoint(x: viewport.midX, y: viewport.maxY - 2))
            for _ in 0..<40 where !vm.itemDrag.showsPlaceholder(in: nil, before: nil)
                || abs(scroll.contentView.bounds.origin.y - initialOffset) <= 1
                || abs((vm.itemDrag.frames[.placeholder]?.height ?? 0) - sourceFrame.height) > 1 {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            let lowerOffset = scroll.contentView.bounds.origin.y
            XCTAssertGreaterThan(abs(lowerOffset - initialOffset), 1, "拖到下边缘应带动实际列表滚动")
            XCTAssertNotNil(vm.itemDrag.active)
            XCTAssertTrue(vm.itemDrag.showsPlaceholder(in: nil, before: nil))
            XCTAssertEqual(vm.itemDrag.frames[.placeholder]?.height ?? 0, sourceFrame.height, accuracy: 1)
            vm.itemDrag.update(CGPoint(x: viewport.midX, y: 2))
            try await Task.sleep(nanoseconds: 200_000_000)
            XCTAssertLessThan(abs(scroll.contentView.bounds.origin.y - initialOffset), abs(lowerOffset - initialOffset))
            vm.itemDrag.cancel()
            try await Task.sleep(nanoseconds: 250_000_000)
            XCTAssertNil(vm.itemDrag.active)
            XCTAssertNil(vm.itemDrag.frames[.placeholder])
            XCTAssertEqual(vm.itemDrag.frames[.row(ids[1].uuidString, group: source.id)]?.height ?? 0, sourceFrame.height, accuracy: 1)

            func sendMouse(_ type: NSEvent.EventType, at point: CGPoint) throws {
                let local = CGPoint(x: point.x, y: host.isFlipped ? point.y : host.bounds.height - point.y)
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: host.convert(local, to: nil),
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
                window.sendEvent(event)
            }
            let restoredFrame = try XCTUnwrap(vm.itemDrag.frames[.row(ids[1].uuidString, group: source.id)])
            let nextHeader = try XCTUnwrap(vm.itemDrag.frames[.group(target.id)])
            let start = CGPoint(x: restoredFrame.midX, y: (restoredFrame.maxY + nextHeader.minY) / 2)
            try sendMouse(.leftMouseDown, at: start)
            try sendMouse(.leftMouseDragged, at: CGPoint(x: start.x + 8, y: start.y))
            try await Task.sleep(nanoseconds: 50_000_000)
            XCTAssertEqual(vm.itemDrag.active?.id, ids[1].uuidString)
            let header = try XCTUnwrap(vm.itemDrag.frames[.group(target.id)])
            let end = CGPoint(x: header.midX, y: header.midY)
            try sendMouse(.leftMouseDragged, at: end)
            try await Task.sleep(nanoseconds: 220_000_000)
            let slot = try XCTUnwrap(vm.itemDrag.frames[.placeholder])
            let nextStart = CGPoint(x: slot.midX, y: slot.midY)
            try sendMouse(.leftMouseUp, at: end)
            try await Task.sleep(nanoseconds: 16_000_000)
            XCTAssertNil(vm.itemDrag.active)
            let movedIDs = kind == .holdings
                ? vm.holdings.filter { $0.groupID == target.id }.map(\.id)
                : vm.watchlist.filter { $0.groupID == target.id }.map(\.id)
            XCTAssertEqual(movedIDs, [ids[2], ids[3], ids[1]], "鼠标松手后应提交跨组移动")

            try sendMouse(.leftMouseDown, at: nextStart)
            try sendMouse(.leftMouseDragged, at: CGPoint(x: nextStart.x, y: nextStart.y - 8))
            try await Task.sleep(nanoseconds: 20_000_000)
            XCTAssertEqual(vm.itemDrag.active?.id, ids[1].uuidString, "刚落位的标的应能立刻再次起拖")
            let first = try XCTUnwrap(vm.itemDrag.frames[.row(ids[2].uuidString, group: target.id)])
            let head = CGPoint(x: first.midX, y: first.minY)
            try sendMouse(.leftMouseDragged, at: head)
            try await Task.sleep(nanoseconds: 20_000_000)
            XCTAssertTrue(vm.itemDrag.showsPlaceholder(in: target.id, before: ids[2].uuidString))
            try sendMouse(.leftMouseUp, at: head)
            try await Task.sleep(nanoseconds: 20_000_000)
            let finalIDs = kind == .holdings
                ? vm.holdings.filter { $0.groupID == target.id }.map(\.id)
                : vm.watchlist.filter { $0.groupID == target.id }.map(\.id)
            XCTAssertEqual(finalIDs, [ids[1], ids[2], ids[3]])
        }
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
        XCTAssertTrue(restored.moveIndex(.init(kind: .index, id: last.id), before: nil))
        XCTAssertEqual(restored.orderedIndexQuotes(catalog.reversed().map(quote)).map(\.id), catalog.map(\.id))
    }

    @MainActor
    func testAlertOrderPreservesLatestTriggerStateAndSurvivesReload() throws {
        let repo = AlertsRepository(dbPool: pool)
        let a = Alert(symbol: symbol, name: "价格预警", condition: .priceBelow, threshold: 9,
                      secondaryCondition: .changePctBelow, secondaryThreshold: -0.03, conditionLogic: .or,
                      cooldownSeconds: 120, maxTriggersPerDay: 3, tradingHoursOnly: true,
                      weekdaysOnly: true, createdAt: createdAt)
        let b = Alert(symbol: symbol, name: "暂停预警", condition: .priceAbove, threshold: 15,
                      isActive: false, createdAt: createdAt.addingTimeInterval(1))
        for alert in [a, b] { try repo.upsert(alert) }
        let vm = makeViewModel()
        try repo.markTriggered(id: a.id, at: createdAt.addingTimeInterval(60), todayKey: "2026-11-11")
        let latest = try repo.all()
        try pool.write { db in
            try db.execute(sql: "CREATE TRIGGER no_alert_write BEFORE UPDATE ON alert BEGIN SELECT RAISE(ABORT, 'unexpected write'); END")
        }
        XCTAssertTrue(vm.moveAlert(.init(kind: .alert, id: b.id.uuidString), before: a.id.uuidString))
        XCTAssertEqual(vm.orderedAlerts.map(\.id), [b.id, a.id])
        XCTAssertEqual(try repo.all(), latest)

        let reopened = try DatabasePool(path: directory.appendingPathComponent("order.sqlite").path)
        defer { try? reopened.close() }
        let restored = makeViewModel(database: reopened)
        XCTAssertEqual(restored.orderedAlerts, [latest[1], latest[0]])
        XCTAssertTrue(restored.moveAlert(.init(kind: .alert, id: b.id.uuidString), before: nil))
        XCTAssertEqual(restored.orderedAlerts, latest)
    }

    @MainActor
    func testAlertOrderHandlesDeletionNewRowsAndInvalidMoves() throws {
        let repo = AlertsRepository(dbPool: pool)
        let a = Alert(symbol: symbol, name: "一", condition: .priceAbove, threshold: 10, createdAt: createdAt)
        let b = Alert(symbol: symbol, name: "二", condition: .priceBelow, threshold: 8, createdAt: createdAt.addingTimeInterval(1))
        let c = Alert(symbol: symbol, name: "三", condition: .changePctAbove, threshold: 0.05, createdAt: createdAt.addingTimeInterval(2))
        for alert in [a, b] { try repo.upsert(alert) }
        let settings = SettingsRepository(dbPool: pool)
        let stored = "\(b.id.uuidString),unknown,\(b.id.uuidString)"
        try settings.set(SettingsRepository.Keys.popoverAlertOrder, stored)
        let vm = makeViewModel()
        XCTAssertEqual(vm.orderedAlerts.map(\.id), [b.id, a.id])
        try repo.upsert(c)
        try repo.delete(id: b.id)
        vm.reload()
        XCTAssertEqual(vm.orderedAlerts.map(\.id), [a.id, c.id])
        XCTAssertFalse(vm.moveAlert(.init(kind: .index, id: c.id.uuidString), before: a.id.uuidString))
        XCTAssertFalse(vm.moveAlert(.init(kind: .alert, id: b.id.uuidString), before: a.id.uuidString))
        XCTAssertFalse(vm.moveAlert(.init(kind: .alert, id: a.id.uuidString), before: b.id.uuidString))
        XCTAssertFalse(vm.moveAlert(.init(kind: .alert, id: c.id.uuidString), before: nil))
        XCTAssertEqual(settings.string(SettingsRepository.Keys.popoverAlertOrder), stored)
        XCTAssertNil(vm.reorderError)
    }

    @MainActor
    func testFailedIndexAndAlertOrderWritesKeepDisplayedOrder() throws {
        let repo = AlertsRepository(dbPool: pool)
        let a = Alert(symbol: symbol, name: "一", condition: .priceAbove, threshold: 10, createdAt: createdAt)
        let b = Alert(symbol: symbol, name: "二", condition: .priceBelow, threshold: 8, createdAt: createdAt.addingTimeInterval(1))
        for alert in [a, b] { try repo.upsert(alert) }
        let vm = makeViewModel()
        try pool.write { db in
            try db.execute(sql: "CREATE TRIGGER fail_order BEFORE INSERT ON appSetting BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        }
        XCTAssertFalse(vm.moveAlert(.init(kind: .alert, id: b.id.uuidString), before: a.id.uuidString))
        XCTAssertEqual(vm.orderedAlerts, [a, b])
        XCTAssertFalse(vm.moveIndex(.init(kind: .index, id: "SPX"), before: "SH000001"))
        let quotes = IndexCatalog.all.map { IndexQuote(descriptor: $0, price: 100, prevClose: 99, change: 1, changePct: 0.01) }
        XCTAssertEqual(vm.orderedIndexQuotes(quotes), quotes)
        XCTAssertNotNil(vm.reorderError)
        XCTAssertNil(vm.settingsRepo.string(SettingsRepository.Keys.popoverAlertOrder))
        XCTAssertNil(vm.settingsRepo.string(SettingsRepository.Keys.popoverIndexOrder))
    }

    @MainActor
    func testRenderedIndexAndAlertTabsReorderAndAllowImmediateRepeat() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReorderIndexProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let vm = makeViewModel(indexService: IndexService(http: HTTPClient(session: session)))
        vm.refresher.start()
        defer { vm.refresher.stop() }
        for _ in 0..<50 where vm.refresher.indexQuotes.isEmpty || vm.refresher.isRefreshing {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        vm.refresher.stop()
        XCTAssertEqual(vm.refresher.indexQuotes.count, 3)
        for index in 0..<3 {
            try vm.alertsRepo.upsert(Alert(symbol: symbol, name: "预警\(index)", condition: .priceAbove,
                threshold: Decimal(10 + index), isActive: index != 1,
                lastTriggeredAt: index == 2 ? createdAt : nil, createdAt: createdAt.addingTimeInterval(Double(index))))
        }
        vm.reload()

        for tab in [PopoverViewModel.Tab.indices, .alerts] {
            vm.currentTab = tab
            let content = tab == .indices ? AnyView(IndicesTab()) : AnyView(AlertsTab())
            let host = NSHostingView(rootView: content.environmentObject(vm).environmentObject(vm.refresher)
                .environmentObject(TickerPreferences(repo: vm.settingsRepo))
                .environment(\.colorScheme, .light)
                .background(Color(nsColor: .windowBackgroundColor)))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            defer { vm.itemDrag.cancel(); window.close() }
            func ids() -> [String] {
                tab == .indices ? vm.orderedIndexQuotes(vm.refresher.indexQuotes).map(\.id)
                    : vm.orderedAlerts.map { $0.id.uuidString }
            }
            let original = ids()
            let source = try XCTUnwrap(original.last)
            for _ in 0..<50 where vm.itemDrag.frames[.row(source, group: nil)] == nil {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            func frame(_ id: String) throws -> CGRect {
                try XCTUnwrap(vm.itemDrag.frames[.row(id, group: nil)])
            }
            func sendMouse(_ type: NSEvent.EventType, at point: CGPoint) throws {
                let local = CGPoint(x: point.x, y: host.isFlipped ? point.y : host.bounds.height - point.y)
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: host.convert(local, to: nil),
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
                window.sendEvent(event)
            }
            let first = try frame(original[0])
            let last = try frame(source)
            let start = CGPoint(x: last.midX, y: last.midY)
            let top = CGPoint(x: first.midX, y: first.minY + 2)
            try sendMouse(.leftMouseDown, at: start)
            try sendMouse(.leftMouseDragged, at: CGPoint(x: start.x + 8, y: start.y))
            try await Task.sleep(nanoseconds: 30_000_000)
            XCTAssertEqual(vm.itemDrag.active?.item.kind, tab == .indices ? .index : .alert)
            try sendMouse(.leftMouseDragged, at: top)
            try await Task.sleep(nanoseconds: 220_000_000)
            XCTAssertTrue(vm.itemDrag.showsPlaceholder(in: nil, before: original[0]))
            XCTAssertEqual(ids(), original, "松手前不应改动顺序")
            let slot = try XCTUnwrap(vm.itemDrag.frames[.placeholder])
            XCTAssertEqual(slot.height, last.height, accuracy: 1)
            try sendMouse(.leftMouseUp, at: top)
            try await Task.sleep(nanoseconds: 20_000_000)
            XCTAssertEqual(ids(), [source] + original.dropLast())
            XCTAssertNil(vm.itemDrag.active)

            let again = CGPoint(x: slot.midX, y: slot.midY)
            try sendMouse(.leftMouseDown, at: again)
            try sendMouse(.leftMouseDragged, at: CGPoint(x: again.x + 8, y: again.y))
            try await Task.sleep(nanoseconds: 20_000_000)
            XCTAssertEqual(vm.itemDrag.active?.id, source)
            let tail = try frame(original[1])
            let end = CGPoint(x: tail.midX, y: tail.maxY - 2)
            try sendMouse(.leftMouseDragged, at: end)
            try await Task.sleep(nanoseconds: 30_000_000)
            XCTAssertTrue(vm.itemDrag.showsPlaceholder(in: nil, before: nil))
            try sendMouse(.leftMouseUp, at: end)
            try await Task.sleep(nanoseconds: 20_000_000)
            XCTAssertEqual(ids(), original)

            if tab == .alerts {
                XCTAssertNil(vm.itemDrag.active)
                // 行内按钮按最终布局坐标点击，先等让位动画结束。
                try await Task.sleep(nanoseconds: 250_000_000)
                let row = try frame(original[0])
                let pause = CGPoint(x: row.maxX - 22, y: row.minY + 18)
                try sendMouse(.leftMouseDown, at: pause)
                try await Task.sleep(nanoseconds: 30_000_000)
                try sendMouse(.leftMouseUp, at: pause)
                for _ in 0..<30 where vm.orderedAlerts[0].isActive {
                    try await Task.sleep(nanoseconds: 20_000_000)
                }
                XCTAssertFalse(vm.orderedAlerts[0].isActive, "行内暂停按钮仍应响应单击")
                XCTAssertEqual(ids(), original)
            }
        }
    }

    @MainActor
    private func makeViewModel(database: DatabasePool? = nil, indexService: IndexService = IndexService()) -> PopoverViewModel {
        let pool = database ?? self.pool!
        let holdings = HoldingsRepository(dbPool: pool)
        let watches = WatchlistRepository(dbPool: pool)
        let settings = SettingsRepository(dbPool: pool)
        let service = PortfolioService(holdingsRepo: holdings, watchlistRepo: watches,
                                       alertsRepo: AlertsRepository(dbPool: pool), settingsRepo: settings,
                                       provider: ReorderQuoteProvider(), fx: FXService(provider: ReorderFXProvider()))
        let refresher = QuoteRefresher(service: service, indexService: indexService, clock: MarketClock())
        return PopoverViewModel(refresher: refresher, holdingsRepo: holdings, watchlistRepo: watches,
                                alertsRepo: AlertsRepository(dbPool: pool),
                                settingsRepo: settings, groupsRepo: PortfolioGroupsRepository(dbPool: pool))
    }
}

private final class ReorderIndexProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil) else { return }
        let data = Data("""
            {"data":{"diff":[
                {"f2":100,"f3":1,"f4":1,"f12":"000001","f13":1,"f18":99},
                {"f2":200,"f3":1,"f4":2,"f12":"399001","f13":0,"f18":198},
                {"f2":300,"f3":1,"f4":3,"f12":"399006","f13":0,"f18":297}
            ]}}
            """.utf8)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
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
