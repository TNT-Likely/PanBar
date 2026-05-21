import Foundation
import GRDB

/// 行情磁盘缓存。只存「展示所需」的最小字段(price / prevClose / name / asOf),
/// 高低开收 / volume 不缓存 —— 用户重新打开看到的还是上次快照,新值会被即时拉取覆盖。
///
/// 不做老化清理:用户删了持仓 / 自选,对应的 row 没人读到,占的空间也就几 KB,
/// 暂不上 retention 策略。后面真有问题再做。
private struct QuoteCacheRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "quoteCache"
    var symbolKey: String
    var code: String
    var market: String
    var name: String
    var price: String
    var prevClose: String
    var currency: String
    var isClosed: Bool
    var asOf: Date

    func toQuote() -> Quote? {
        guard let market = Market(rawValue: market),
              let currency = Currency(rawValue: currency),
              let price = Decimal(string: price),
              let prevClose = Decimal(string: prevClose) else { return nil }
        return Quote(
            symbol: SymbolID(code: code, market: market),
            name: name,
            price: price,
            prevClose: prevClose,
            open: nil, high: nil, low: nil, volume: nil,
            currency: currency,
            timestamp: asOf,
            isClosed: isClosed
        )
    }

    static func from(_ q: Quote) -> QuoteCacheRecord {
        QuoteCacheRecord(
            symbolKey: q.symbol.storageKey,
            code: q.symbol.code,
            market: q.symbol.market.rawValue,
            name: q.name,
            price: "\(q.price)",
            prevClose: "\(q.prevClose)",
            currency: q.currency.rawValue,
            isClosed: q.isClosed,
            asOf: q.timestamp
        )
    }
}

struct QuoteCacheRepository {
    let dbPool: DatabasePool

    /// 启动时同步读出。失败/空都返回 [:]。
    func loadAll() -> [SymbolID: Quote] {
        guard let records = try? dbPool.read({ db in
            try QuoteCacheRecord.fetchAll(db)
        }) else { return [:] }
        var out: [SymbolID: Quote] = [:]
        for r in records {
            guard let q = r.toQuote() else { continue }
            out[q.symbol] = q
        }
        return out
    }

    /// 批量写入。任何一条失败不抛错,只 log。
    func upsertMany(_ quotes: [SymbolID: Quote]) {
        guard !quotes.isEmpty else { return }
        do {
            try dbPool.write { db in
                for (_, q) in quotes {
                    try QuoteCacheRecord.from(q).save(db)
                }
            }
        } catch {
            Log.db.warning("quoteCache upsert failed: \(String(describing: error), privacy: .public)")
        }
    }
}
