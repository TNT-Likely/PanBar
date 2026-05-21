import Foundation

/// 多币种换算服务。
///
/// 内部只存两个基础汇率:`USD→CNY` 和 `HKD→CNY`。
/// 其它 6 个方向都用 CNY 作枢轴计算:
///   - CNY→USD = 1 / USDCNY
///   - CNY→HKD = 1 / HKDCNY
///   - USD→HKD = USDCNY / HKDCNY
///   - HKD→USD = HKDCNY / USDCNY
actor FXService {
    private let provider: FXProvider
    private var cache: [String: FXRate] = [:]
    private let ttl: TimeInterval = 300
    private var lastFetch: Date = .distantPast

    init(provider: FXProvider) {
        self.provider = provider
    }

    /// 把 `value` 从 `from` 换算到 `to`。返回 nil 表示当前无法换算。
    func convert(_ value: Decimal, from: Currency, to: Currency) async -> Decimal? {
        if from == to { return value }
        guard let rate = await rate(from: from, to: to) else { return nil }
        return value * rate
    }

    /// 实际汇率(浮点数)。CNY 作为唯一枢轴。
    func rate(from: Currency, to: Currency) async -> Decimal? {
        if from == to { return 1 }
        // 确保两个基础对已加载
        await refreshIfNeeded()

        let usdcny = cache["USDCNY"]?.rate
        let hkdcny = cache["HKDCNY"]?.rate

        switch (from, to) {
        case (.usd, .cny): return usdcny
        case (.hkd, .cny): return hkdcny
        case (.cny, .usd): return usdcny.flatMap { $0 > 0 ? 1 / $0 : nil }
        case (.cny, .hkd): return hkdcny.flatMap { $0 > 0 ? 1 / $0 : nil }
        case (.usd, .hkd):
            guard let u = usdcny, let h = hkdcny, h > 0 else { return nil }
            return u / h
        case (.hkd, .usd):
            guard let u = usdcny, let h = hkdcny, u > 0 else { return nil }
            return h / u
        default: return nil
        }
    }

    /// 预热(应用启动时调一次)。
    func warmup() async {
        await refreshIfNeeded(force: true)
    }

    private func refreshIfNeeded(force: Bool = false) async {
        let stale = Date().timeIntervalSince(lastFetch) >= ttl
        if !force && !stale && !cache.isEmpty { return }
        let rates = (try? await provider.fetch(pairs: [(.usd, .cny), (.hkd, .cny)])) ?? []
        for r in rates {
            // 用语义化 key 存(不依赖 enum rawValue 拼接)
            if r.from == .usd, r.to == .cny { cache["USDCNY"] = r }
            if r.from == .hkd, r.to == .cny { cache["HKDCNY"] = r }
        }
        if !rates.isEmpty { lastFetch = Date() }
    }
}
