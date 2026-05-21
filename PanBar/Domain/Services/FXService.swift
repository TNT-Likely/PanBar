import Foundation

/// 多币种换算服务。内存缓存 + 5 分钟 TTL。失败降级到最后一次成功值,再失败返回 nil(由上层显示 "--")。
actor FXService {
    private let provider: FXProvider
    private var cache: [String: FXRate] = [:]
    private let ttl: TimeInterval = 300
    private var lastFetch: Date = .distantPast

    init(provider: FXProvider) {
        self.provider = provider
    }

    /// 把 `value` 从 `from` 换算到 `to`。返回 nil 表示当前无法换算(汇率取不到)。
    func convert(_ value: Decimal, from: Currency, to: Currency) async -> Decimal? {
        if from == to { return value }

        if let direct = await rate(from: from, to: to) {
            return value * direct.rate
        }
        if let inverse = await rate(from: to, to: from), inverse.rate > 0 {
            return value / inverse.rate
        }
        // 用 USD 作为枢轴
        if from != .usd, to != .usd,
           let r1 = await rate(from: from, to: .usd),
           let r2 = await rate(from: .usd, to: to) {
            return value * r1.rate * r2.rate
        }
        return nil
    }

    func rate(from: Currency, to: Currency) async -> FXRate? {
        if from == to {
            return FXRate(from: from, to: to, rate: 1, asOf: Date())
        }
        let key = "\(from.rawValue)\(to.rawValue)"
        if let cached = cache[key], Date().timeIntervalSince(cached.asOf) < ttl {
            return cached
        }
        do {
            let pairs = neededPairs(from: from, to: to)
            let fetched = try await provider.fetch(pairs: pairs)
            for r in fetched {
                let k = "\(r.from.rawValue)\(r.to.rawValue)"
                cache[k] = r
            }
            lastFetch = Date()
            return cache[key] ?? cache[key]
        } catch {
            Log.quote.warning("FX fetch failed: \(String(describing: error), privacy: .public)")
            return cache[key]
        }
    }

    /// 预热常用货币对(应用启动时调用一次)。
    func warmup() async {
        _ = try? await provider.fetch(pairs: [
            (.usd, .cny),
            (.usd, .hkd),
            (.hkd, .cny)
        ])
    }

    private func neededPairs(from: Currency, to: Currency) -> [(Currency, Currency)] {
        if from == .usd || to == .usd {
            return [(from, to)]
        }
        return [(from, .usd), (.usd, to)]
    }
}
