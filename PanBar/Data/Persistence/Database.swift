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
    /// 同时,如果当前路径(沙盒)还没数据但 ~/Library/Application Support/PanBar 有,
    /// 就一次性把旧数据搬过来。避免 dev 期间签名状态翻转导致"数据消失"。
    static func defaultPath() throws -> String {
        let fm = FileManager.default
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("PanBar", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        let dbPath = base.appendingPathComponent("panbar.sqlite").path

        migrateFromLegacyIfNeeded(currentPath: dbPath)
        return dbPath
    }

    /// 检查并迁移 legacy(非沙盒)路径下的数据。
    /// 触发条件:当前路径不存在 / 文件为 0 字节,而 legacy 路径存在且 > 0 字节。
    private static func migrateFromLegacyIfNeeded(currentPath: String) {
        let fm = FileManager.default

        // 当前路径已有数据就跳过
        if fm.fileExists(atPath: currentPath),
           let attrs = try? fm.attributesOfItem(atPath: currentPath),
           let size = attrs[.size] as? UInt64, size > 0 {
            return
        }

        // 旧路径:固定写死 ~/Library/Application Support/PanBar (无沙盒)
        guard let home = ProcessInfo.processInfo.environment["HOME"] else { return }
        let legacyBase = "\(home)/Library/Application Support/PanBar"
        let legacyDB = "\(legacyBase)/panbar.sqlite"
        guard fm.fileExists(atPath: legacyDB) else { return }

        let currentURL = URL(fileURLWithPath: currentPath)
        let currentDir = currentURL.deletingLastPathComponent().path
        try? fm.createDirectory(atPath: currentDir, withIntermediateDirectories: true)

        // sqlite + WAL + SHM 一起拷
        for suffix in ["", "-wal", "-shm"] {
            let src = legacyDB + suffix
            let dst = currentPath + suffix
            if fm.fileExists(atPath: src) {
                try? fm.removeItem(atPath: dst)
                try? fm.copyItem(atPath: src, toPath: dst)
            }
        }
        Log.db.info("migrated legacy DB from \(legacyBase, privacy: .public)")
    }
}
