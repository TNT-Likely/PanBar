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
            createdAt: h.createdAt
        )
    }
}

struct HoldingsRepository {
    let dbPool: DatabasePool

    func all() throws -> [Holding] {
        try dbPool.read { db in
            try HoldingRecord
                .order(Column("createdAt").asc)
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

    /// 提供给 SwiftUI 的 Combine-style 监听(简化版,改为 ObservableObject 自己 poll)。
    func observeAll() -> AsyncStream<[Holding]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db -> [Holding] in
                try HoldingRecord.order(Column("createdAt").asc).fetchAll(db).compactMap { $0.toDomain() }
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
