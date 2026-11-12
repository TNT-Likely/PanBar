import Foundation
import GRDB

private struct WatchRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "watchItem"

    var id: String
    var code: String
    var market: String
    var name: String
    var groupID: String?
    var order: Int
    var inTicker: Bool
    var createdAt: Date

    func toDomain() -> WatchItem? {
        guard let market = Market(rawValue: market),
              let id = UUID(uuidString: id) else { return nil }
        return WatchItem(
            id: id,
            symbol: SymbolID(code: code, market: market),
            name: name,
            order: order,
            inTicker: inTicker,
            createdAt: createdAt,
            groupID: groupID.flatMap(UUID.init(uuidString:))
        )
    }

    static func from(_ w: WatchItem) -> WatchRecord {
        WatchRecord(
            id: w.id.uuidString,
            code: w.symbol.code,
            market: w.symbol.market.rawValue,
            name: w.name,
            groupID: w.groupID?.uuidString,
            order: w.order,
            inTicker: w.inTicker,
            createdAt: w.createdAt
        )
    }
}

struct WatchlistRepository {
    let dbPool: DatabasePool

    func all() throws -> [WatchItem] {
        try dbPool.read { db in
            try WatchRecord.order(Column("order").asc, Column("createdAt").asc).fetchAll(db)
        }.compactMap { $0.toDomain() }
    }

    func upsert(_ item: WatchItem) throws {
        try dbPool.write { db in
            try WatchRecord.from(item).save(db)
        }
    }

    func update(id: UUID, _ changes: (inout WatchItem) -> Void) throws -> Bool {
        try dbPool.write { db in
            guard var item = try WatchRecord.fetchOne(db, key: id.uuidString)?.toDomain() else { return false }
            changes(&item)
            try WatchRecord.from(item).update(db)
            return true
        }
    }

    func delete(id: UUID) throws {
        _ = try dbPool.write { db in
            try WatchRecord.deleteOne(db, key: id.uuidString)
        }
    }

    func deleteAll() throws {
        _ = try dbPool.write { db in
            try WatchRecord.deleteAll(db)
        }
    }

    /// 用户拖拽改顺序后,把当前完整 id 序列 → 各自 order = 数组下标。
    func reorder(ids: [UUID]) throws {
        try dbPool.write { db in
            for (i, id) in ids.enumerated() {
                try db.execute(
                    sql: "UPDATE watchItem SET \"order\" = ? WHERE id = ?",
                    arguments: [i, id.uuidString]
                )
            }
        }
    }

    func move(id: UUID, toGroup groupID: UUID?, before target: UUID?) throws -> [WatchItem]? {
        try dbPool.write { db in
            if let groupID {
                guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM portfolioGroup WHERE id = ? AND kind = ?)",
                                        arguments: [groupID.uuidString, PortfolioGroupKind.watchlist.rawValue]) == true else { return nil }
            }
            let current = try WatchRecord.order(Column("order").asc, Column("createdAt").asc)
                .fetchAll(db).compactMap { $0.toDomain() }
            guard let ids = PopoverOrder.movingItem(id, toGroup: groupID, before: target,
                                                   in: current, groupID: \.groupID) else { return nil }
            try db.execute(sql: "UPDATE watchItem SET groupID = ? WHERE id = ?", arguments: [groupID?.uuidString, id.uuidString])
            for (order, itemID) in ids.enumerated() {
                try db.execute(sql: "UPDATE watchItem SET \"order\" = ? WHERE id = ?", arguments: [order, itemID.uuidString])
            }
            return try WatchRecord.order(Column("order").asc, Column("createdAt").asc)
                .fetchAll(db).compactMap { $0.toDomain() }
        }
    }

    func observeAll() -> AsyncStream<[WatchItem]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db -> [WatchItem] in
                try WatchRecord.order(Column("order").asc, Column("createdAt").asc).fetchAll(db).compactMap { $0.toDomain() }
            }
            let cancellable = observation.start(in: dbPool, onError: { _ in }) { items in
                continuation.yield(items)
            }
            continuation.onTermination = { @Sendable _ in
                cancellable.cancel()
            }
        }
    }
}
