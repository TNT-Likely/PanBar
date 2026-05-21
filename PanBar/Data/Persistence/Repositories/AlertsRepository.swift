import Foundation
import GRDB

private struct AlertRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "alert"

    var id: String
    var code: String
    var market: String
    var name: String
    var condition: String
    var threshold: String
    var isActive: Bool
    var lastTriggeredAt: Date?
    var cooldownSeconds: Int
    var createdAt: Date

    func toDomain() -> Alert? {
        guard let market = Market(rawValue: market),
              let condition = AlertCondition(rawValue: condition),
              let threshold = Decimal(string: threshold),
              let id = UUID(uuidString: id) else { return nil }
        return Alert(
            id: id,
            symbol: SymbolID(code: code, market: market),
            name: name,
            condition: condition,
            threshold: threshold,
            isActive: isActive,
            lastTriggeredAt: lastTriggeredAt,
            cooldownSeconds: cooldownSeconds,
            createdAt: createdAt
        )
    }

    static func from(_ a: Alert) -> AlertRecord {
        AlertRecord(
            id: a.id.uuidString,
            code: a.symbol.code,
            market: a.symbol.market.rawValue,
            name: a.name,
            condition: a.condition.rawValue,
            threshold: "\(a.threshold)",
            isActive: a.isActive,
            lastTriggeredAt: a.lastTriggeredAt,
            cooldownSeconds: a.cooldownSeconds,
            createdAt: a.createdAt
        )
    }
}

struct AlertsRepository {
    let dbPool: DatabasePool

    func all() throws -> [Alert] {
        try dbPool.read { db in
            try AlertRecord.order(Column("createdAt").asc).fetchAll(db)
        }.compactMap { $0.toDomain() }
    }

    func active() throws -> [Alert] {
        try all().filter { $0.isActive }
    }

    func upsert(_ alert: Alert) throws {
        try dbPool.write { db in
            try AlertRecord.from(alert).save(db)
        }
    }

    func delete(id: UUID) throws {
        _ = try dbPool.write { db in
            try AlertRecord.deleteOne(db, key: id.uuidString)
        }
    }

    /// 仅更新触发时间(避免回写整个对象)。
    func markTriggered(id: UUID, at date: Date) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "UPDATE alert SET lastTriggeredAt = ? WHERE id = ?",
                arguments: [date, id.uuidString]
            )
        }
    }

    func observeAll() -> AsyncStream<[Alert]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db -> [Alert] in
                try AlertRecord.order(Column("createdAt").asc).fetchAll(db).compactMap { $0.toDomain() }
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
