import Foundation
import GRDB

/// 汇率磁盘缓存:启动期先从这里 seed,FXService 内存命中后再后台拉新值写回。
///
/// 用稳定的 "USDCNY" / "HKDCNY" 作 primary key,跟 FXService 内部 cache key 保持一致,
/// 避免某天加方向时还要做 schema migration。
private struct FXCacheRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "fxCache"
    var pair: String        // "USDCNY" / "HKDCNY"
    var rate: String        // Decimal 序列化为字符串,避免浮点漂移
    var asOf: Date
}

struct FXCacheRepository {
    let dbPool: DatabasePool

    /// 启动时一次性读出所有缓存对,返回 (pair → FXRate)。
    /// pair 解码失败的条目会被跳过,不抛错。
    func loadAll() -> [String: FXRate] {
        guard let records = try? dbPool.read({ db in
            try FXCacheRecord.fetchAll(db)
        }) else { return [:] }

        var out: [String: FXRate] = [:]
        for r in records {
            guard let (from, to) = decodePair(r.pair),
                  let rate = Decimal(string: r.rate) else { continue }
            out[r.pair] = FXRate(from: from, to: to, rate: rate, asOf: r.asOf)
        }
        return out
    }

    func upsert(pair: String, rate: FXRate) throws {
        try dbPool.write { db in
            try FXCacheRecord(
                pair: pair,
                rate: "\(rate.rate)",
                asOf: rate.asOf
            ).save(db)
        }
    }

    func upsertMany(_ rates: [String: FXRate]) throws {
        try dbPool.write { db in
            for (pair, r) in rates {
                try FXCacheRecord(pair: pair, rate: "\(r.rate)", asOf: r.asOf).save(db)
            }
        }
    }

    /// 把 "USDCNY" 拆成 (.usd, .cny)。无法识别时返回 nil。
    private func decodePair(_ pair: String) -> (Currency, Currency)? {
        guard pair.count == 6 else { return nil }
        let from = String(pair.prefix(3))
        let to = String(pair.suffix(3))
        guard let f = Currency(rawValue: from), let t = Currency(rawValue: to) else { return nil }
        return (f, t)
    }
}
