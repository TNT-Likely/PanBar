import Foundation
import GRDB

enum Migrations {
    static func register(_ dbPool: DatabasePool) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "holding") { t in
                t.column("id", .text).primaryKey()
                t.column("code", .text).notNull()
                t.column("market", .text).notNull()
                t.column("name", .text).notNull().defaults(to: "")
                t.column("quantity", .text).notNull()      // Decimal 序列化为字符串保证精度
                t.column("costPrice", .text).notNull()
                t.column("currency", .text).notNull()
                t.column("note", .text)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "watchItem") { t in
                t.column("id", .text).primaryKey()
                t.column("code", .text).notNull()
                t.column("market", .text).notNull()
                t.column("name", .text).notNull().defaults(to: "")
                t.column("order", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "appSetting") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
            }

            try db.create(table: "fxCache") { t in
                t.column("pair", .text).primaryKey()
                t.column("rate", .text).notNull()
                t.column("asOf", .datetime).notNull()
            }
        }

        migrator.registerMigration("v2_alerts") { db in
            try db.create(table: "alert") { t in
                t.column("id", .text).primaryKey()
                t.column("code", .text).notNull()
                t.column("market", .text).notNull()
                t.column("name", .text).notNull().defaults(to: "")
                t.column("condition", .text).notNull()
                t.column("threshold", .text).notNull()
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("lastTriggeredAt", .datetime)
                t.column("cooldownSeconds", .integer).notNull().defaults(to: 300)
                t.column("createdAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v3_in_ticker") { db in
            // 给每只持仓 / 自选加 inTicker 标记(默认 true,保留现状)
            try db.alter(table: "holding") { t in
                t.add(column: "inTicker", .boolean).notNull().defaults(to: true)
            }
            try db.alter(table: "watchItem") { t in
                t.add(column: "inTicker", .boolean).notNull().defaults(to: true)
            }
        }

        try migrator.migrate(dbPool)
    }
}
