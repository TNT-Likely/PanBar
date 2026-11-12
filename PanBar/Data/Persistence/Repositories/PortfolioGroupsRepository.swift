import Foundation
import GRDB

private struct PortfolioGroupRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "portfolioGroup"
    var id: String
    var name: String
    var kind: String
    var sortOrder: Int

    func toDomain() -> PortfolioGroup? {
        guard let id = UUID(uuidString: id), let kind = PortfolioGroupKind(rawValue: kind) else { return nil }
        return PortfolioGroup(id: id, name: name, kind: kind, sortOrder: sortOrder)
    }

    static func from(_ group: PortfolioGroup) -> PortfolioGroupRecord {
        PortfolioGroupRecord(id: group.id.uuidString, name: group.name, kind: group.kind.rawValue, sortOrder: group.sortOrder)
    }
}

struct PortfolioGroupsRepository {
    let dbPool: DatabasePool

    enum OrderError: Error { case staleGroups }

    func all() throws -> [PortfolioGroup] {
        try dbPool.read { db in
            try PortfolioGroupRecord.order(Column("sortOrder").asc, Column("name").asc)
                .fetchAll(db).compactMap { $0.toDomain() }
        }
    }

    func upsert(_ group: PortfolioGroup) throws {
        try dbPool.write { db in
            try PortfolioGroupRecord.from(group).save(db)
        }
    }

    func reorder(ids: [UUID?], kind: PortfolioGroupKind) throws {
        try dbPool.write { db in
            let groupIDs = ids.compactMap { $0?.uuidString }
            let currentIDs = try String.fetchAll(db, sql: "SELECT id FROM portfolioGroup WHERE kind = ?",
                                                arguments: [kind.rawValue])
            guard Set(groupIDs) == Set(currentIDs), Set(groupIDs).count == groupIDs.count,
                  ids.count - groupIDs.count <= 1 else { throw OrderError.staleGroups }
            for (order, id) in groupIDs.enumerated() {
                try db.execute(sql: "UPDATE portfolioGroup SET sortOrder = ? WHERE id = ? AND kind = ?",
                               arguments: [order, id, kind.rawValue])
            }
            // 虚拟的“未分组”没有数据库行，其位置与真实分组顺序一起提交。
            if let position = ids.firstIndex(where: { $0 == nil }) {
                try db.execute(sql: "INSERT OR REPLACE INTO appSetting (key, value) VALUES (?, ?)",
                               arguments: [SettingsRepository.Keys.ungroupedPosition(kind), String(position)])
            }
        }
    }

    func delete(id: UUID) throws {
        _ = try dbPool.write { db in
            try PortfolioGroupRecord.deleteOne(db, key: id.uuidString)
        }
    }

    func deleteAll() throws {
        _ = try dbPool.write { db in
            try PortfolioGroupRecord.deleteAll(db)
        }
    }

    func observeAll() -> AsyncStream<[PortfolioGroup]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try PortfolioGroupRecord.order(Column("sortOrder").asc, Column("name").asc)
                    .fetchAll(db).compactMap { $0.toDomain() }
            }
            let cancellable = observation.start(in: dbPool, onError: { _ in }) { groups in
                continuation.yield(groups)
            }
            continuation.onTermination = { @Sendable _ in cancellable.cancel() }
        }
    }
}
