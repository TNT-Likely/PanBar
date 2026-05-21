import Foundation
import GRDB

private struct WatchRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "watchItem"

    var id: String
    var code: String
    var market: String
    var name: String
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
            createdAt: createdAt
        )
    }

    static func from(_ w: WatchItem) -> WatchRecord {
        WatchRecord(
            id: w.id.uuidString,
            code: w.symbol.code,
            market: w.symbol.market.rawValue,
            name: w.name,
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
