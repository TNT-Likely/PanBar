import Foundation
import GRDB

/// 数据库门面:统一持有 DatabasePool,负责 schema 迁移。
final class Database {
    let dbPool: DatabasePool

    init(path: String) throws {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL;")
            try db.execute(sql: "PRAGMA foreign_keys = ON;")
        }
        self.dbPool = try DatabasePool(path: path, configuration: config)
        try Migrations.register(dbPool)
        Log.db.info("opened db at \(path, privacy: .public)")
    }

    /// 应用支持目录下的默认数据库路径。
    static func defaultPath() throws -> String {
        let fm = FileManager.default
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("PanBar", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("panbar.sqlite").path
    }
}
