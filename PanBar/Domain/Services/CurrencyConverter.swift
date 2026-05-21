import Foundation

/// 不可变的汇率快照 + 换算逻辑。值类型,无 actor,任意线程同步可用。
///
/// 把 FXService 的换算逻辑独立出来,主要是为了:冷启动时 QuoteRefresher 在
/// `init` 里就能基于磁盘 seed 的 FX 同步建出完整 snapshot,popover 一打开
/// 总资产 / 累计盈亏立即有值,不用等 `await fx.convert` 一来一回。
struct CurrencyConverter: Sendable, Equatable {
    let usdcny: Decimal?
    let hkdcny: Decimal?

    static let empty = CurrencyConverter(usdcny: nil, hkdcny: nil)

    func convert(_ value: Decimal, from: Currency, to: Currency) -> Decimal? {
        if from == to { return value }
        switch (from, to) {
        case (.usd, .cny): return usdcny.map { value * $0 }
        case (.hkd, .cny): return hkdcny.map { value * $0 }
        case (.cny, .usd): return usdcny.flatMap { $0 > 0 ? value / $0 : nil }
        case (.cny, .hkd): return hkdcny.flatMap { $0 > 0 ? value / $0 : nil }
        case (.usd, .hkd):
            guard let u = usdcny, let h = hkdcny, h > 0 else { return nil }
            return value * u / h
        case (.hkd, .usd):
            guard let u = usdcny, let h = hkdcny, u > 0 else { return nil }
            return value * h / u
        default: return nil
        }
    }

    /// 从磁盘缓存(已 load 的 FXRate 字典)构造。
    init(fromCache cache: [String: FXRate]) {
        self.usdcny = cache["USDCNY"]?.rate
        self.hkdcny = cache["HKDCNY"]?.rate
    }

    init(usdcny: Decimal?, hkdcny: Decimal?) {
        self.usdcny = usdcny
        self.hkdcny = hkdcny
    }
}
