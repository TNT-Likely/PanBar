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
    // v4
    var secondaryCondition: String?
    var secondaryThreshold: String?
    var conditionLogic: String
    var maxTriggersPerDay: Int?
    var triggerCountToday: Int
    var lastTriggerDay: String?
    var tradingHoursOnly: Bool
    var weekdaysOnly: Bool

    func toDomain() -> Alert? {
        guard let market = Market(rawValue: market),
              let cond = AlertCondition(rawValue: condition),
              let th = Decimal(string: threshold),
              let id = UUID(uuidString: id) else { return nil }
        let secCond = secondaryCondition.flatMap { AlertCondition(rawValue: $0) }
        let secTh = secondaryThreshold.flatMap { Decimal(string: $0) }
        let logic = ConditionLogic(rawValue: conditionLogic) ?? .and
        return Alert(
            id: id,
            symbol: SymbolID(code: code, market: market),
            name: name,
            condition: cond,
            threshold: th,
            secondaryCondition: secCond,
            secondaryThreshold: secTh,
            conditionLogic: logic,
            isActive: isActive,
            lastTriggeredAt: lastTriggeredAt,
            cooldownSeconds: cooldownSeconds,
            maxTriggersPerDay: maxTriggersPerDay,
            triggerCountToday: triggerCountToday,
            lastTriggerDay: lastTriggerDay,
            tradingHoursOnly: tradingHoursOnly,
            weekdaysOnly: weekdaysOnly,
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
            createdAt: a.createdAt,
            secondaryCondition: a.secondaryCondition?.rawValue,
            secondaryThreshold: a.secondaryThreshold.map { "\($0)" },
            conditionLogic: a.conditionLogic.rawValue,
            maxTriggersPerDay: a.maxTriggersPerDay,
            triggerCountToday: a.triggerCountToday,
            lastTriggerDay: a.lastTriggerDay,
            tradingHoursOnly: a.tradingHoursOnly,
            weekdaysOnly: a.weekdaysOnly
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

    func deleteAll() throws {
        _ = try dbPool.write { db in
            try AlertRecord.deleteAll(db)
        }
    }

    /// 标记触发:更新 lastTriggeredAt + 累加当天计数。
    func markTriggered(id: UUID, at date: Date, todayKey: String) throws {
        try dbPool.write { db in
            // 跨天先重置 count
            try db.execute(
                sql: """
                UPDATE alert
                SET triggerCountToday = CASE WHEN lastTriggerDay = ? THEN triggerCountToday + 1 ELSE 1 END,
                    lastTriggerDay = ?,
                    lastTriggeredAt = ?
                WHERE id = ?
                """,
                arguments: [todayKey, todayKey, date, id.uuidString]
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
