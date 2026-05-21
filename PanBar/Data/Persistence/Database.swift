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
    ///
    /// 目录名跟着 `CFBundleName`(Release 是 "PanBar",Debug 是 "PanBar-Dev"),
    /// 这样开发和正式版数据完全隔离,改 dev 的不会污染线上数据库。
    static func defaultPath() throws -> String {
        let fm = FileManager.default
        let folderName = appSupportFolderName()
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent(folderName, isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        let dbPath = base.appendingPathComponent("panbar.sqlite").path

        migrateFromLegacyIfNeeded(currentPath: dbPath, folderName: folderName)
        return dbPath
    }

    /// Release: "PanBar";Debug: "PanBar-Dev"。读 CFBundleName,fallback 到 "PanBar"。
    private static func appSupportFolderName() -> String {
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.isEmpty {
            return name
        }
        return "PanBar"
    }

    /// Legacy 迁移:
    /// - **Release**(folderName = "PanBar"):currentPath 等于 legacy path,等于自己,
    ///   早期版本本来就在这,无所谓迁不迁。
    /// - **Debug**(folderName = "PanBar-Dev"):current 是新位置,如果 legacy 有数据
    ///   就**一次性**拷过来,让开发首次启动有一份生产快照可以玩,之后两边各自独立。
    private static func migrateFromLegacyIfNeeded(currentPath: String, folderName: String) {
        let fm = FileManager.default

        // 当前路径已有数据就跳过
        if fm.fileExists(atPath: currentPath),
           let attrs = try? fm.attributesOfItem(atPath: currentPath),
           let size = attrs[.size] as? UInt64, size > 0 {
            return
        }

        guard let home = ProcessInfo.processInfo.environment["HOME"] else { return }
        let legacyBase = "\(home)/Library/Application Support/PanBar"
        let legacyDB = "\(legacyBase)/panbar.sqlite"

        // 如果 current 就是 legacy(folderName == "PanBar"),拷自己没意义
        let currentURL = URL(fileURLWithPath: currentPath)
        let currentDir = currentURL.deletingLastPathComponent().path
        if currentDir == legacyBase { return }

        guard fm.fileExists(atPath: legacyDB) else { return }

        try? fm.createDirectory(atPath: currentDir, withIntermediateDirectories: true)

        // sqlite + WAL + SHM 一起拷,保证 GRDB 不会因为 WAL 残留报错
        for suffix in ["", "-wal", "-shm"] {
            let src = legacyDB + suffix
            let dst = currentPath + suffix
            if fm.fileExists(atPath: src) {
                try? fm.removeItem(atPath: dst)
                try? fm.copyItem(atPath: src, toPath: dst)
            }
        }
        Log.db.info("seeded \(folderName, privacy: .public) DB from legacy at \(legacyBase, privacy: .public)")
    }
}
