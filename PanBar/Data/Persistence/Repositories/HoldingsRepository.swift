import Foundation
import GRDB

/// 内部 GRDB record。
private struct HoldingRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "holding"

    var id: String
    var code: String
    var market: String
    var name: String
    var quantity: String
    var costPrice: String
    var currency: String
    var note: String?
    var inTicker: Bool
    var sortOrder: Int
    var createdAt: Date

    func toDomain() -> Holding? {
        guard let market = Market(rawValue: market),
              let currency = Currency(rawValue: currency),
              let quantity = Decimal(string: quantity),
              let cost = Decimal(string: costPrice),
              let id = UUID(uuidString: id) else { return nil }
        return Holding(
            id: id,
            symbol: SymbolID(code: code, market: market),
            name: name,
            quantity: quantity,
            costPrice: cost,
            currency: currency,
            note: note,
            inTicker: inTicker,
            sortOrder: sortOrder,
            createdAt: createdAt
        )
    }

    static func from(_ h: Holding) -> HoldingRecord {
        HoldingRecord(
            id: h.id.uuidString,
            code: h.symbol.code,
            market: h.symbol.market.rawValue,
            name: h.name,
            quantity: "\(h.quantity)",
            costPrice: "\(h.costPrice)",
            currency: h.currency.rawValue,
            note: h.note,
            inTicker: h.inTicker,
            sortOrder: h.sortOrder,
            createdAt: h.createdAt
        )
    }
}

struct HoldingsRepository {
    let dbPool: DatabasePool

    func all() throws -> [Holding] {
        try dbPool.read { db in
            // sortOrder 优先,相同 order(没拖过)再按 createdAt 升序兜底
            try HoldingRecord
                .order(Column("sortOrder").asc, Column("createdAt").asc)
                .fetchAll(db)
        }.compactMap { $0.toDomain() }
    }

    func upsert(_ holding: Holding) throws {
        try dbPool.write { db in
            try HoldingRecord.from(holding).save(db)
        }
    }

    func delete(id: UUID) throws {
        _ = try dbPool.write { db in
            try HoldingRecord.deleteOne(db, key: id.uuidString)
        }
    }

    func deleteAll() throws {
        _ = try dbPool.write { db in
            try HoldingRecord.deleteAll(db)
        }
    }

    /// 用户拖拽改顺序后,把当前完整 id 序列 → 各自 sortOrder = 数组下标。
    /// 一次性 batch 写,避免 N 次写盘。
    func reorder(ids: [UUID]) throws {
        try dbPool.write { db in
            for (i, id) in ids.enumerated() {
                try db.execute(
                    sql: "UPDATE holding SET sortOrder = ? WHERE id = ?",
                    arguments: [i, id.uuidString]
                )
            }
        }
    }

    /// 提供给 SwiftUI 的 Combine-style 监听(简化版,改为 ObservableObject 自己 poll)。
    func observeAll() -> AsyncStream<[Holding]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db -> [Holding] in
                try HoldingRecord
                    .order(Column("sortOrder").asc, Column("createdAt").asc)
                    .fetchAll(db).compactMap { $0.toDomain() }
            }
            let cancellable = observation.start(in: dbPool, onError: { _ in }) { holdings in
                continuation.yield(holdings)
            }
            continuation.onTermination = { @Sendable _ in
                cancellable.cancel()
            }
        }
    }
}
