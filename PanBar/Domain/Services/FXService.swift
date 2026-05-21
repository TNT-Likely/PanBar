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
    /// 自动刷新间隔(秒)。0 = 关闭自动刷新。
    /// `Int` 而非 `TimeInterval` 是为了让 settings 序列化简单 + UI Picker 用整数。
    static let intervalOff: Int = 0
    static let defaultInterval: Int = 86400   // 1 天(汇率变化很小,默认每天一次足够)

    private let provider: FXProvider
    private let cacheRepo: FXCacheRepository?
    private var cache: [String: FXRate] = [:]
    /// 内存命中的 TTL —— 用户读 rate 时,如果距上次成功拉取 < ttl 就直接复用,
    /// 不阻塞 UI(磁盘缓存负责覆盖冷启动场景)。
    private let ttl: TimeInterval = 300
    private var lastFetch: Date = .distantPast
    private var autoRefreshInterval: Int = defaultInterval
    private var autoRefreshTask: Task<Void, Never>?
    /// 缓存可观察的状态:供 UI 显示「最近更新时间」/「正在刷新」。
    private(set) var isRefreshing: Bool = false

    init(provider: FXProvider, cacheRepo: FXCacheRepository? = nil) {
        self.provider = provider
        self.cacheRepo = cacheRepo
    }

    /// 应用启动早期同步调用,从磁盘把上次保存的汇率灌进内存。
    /// 这样后续任何 `rate()` 调用即使网络挂着也能立即返回值,popover 一打开就有本位币换算。
    func seedFromDisk() {
        guard let repo = cacheRepo else {
            Log.fx.info("seedFromDisk: cacheRepo is nil")
            return
        }
        let disk = repo.loadAll()
        guard !disk.isEmpty else {
            Log.fx.info("seedFromDisk: disk cache is empty")
            return
        }
        cache = disk
        // 用磁盘最新一条的 asOf 作为 lastFetch,这样 UI 显示「N 分钟前更新」是有意义的
        // (而不是「尚未拉取」)。后续如果网络拉到新值会再覆盖。
        if let newest = disk.values.map({ $0.asOf }).max() {
            lastFetch = newest
        }
        Log.fx.info("seedFromDisk: loaded \(disk.count, privacy: .public) pairs from disk")
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
        return rateLocked(from: from, to: to)
    }

    /// 内部计算汇率,不触发网络拉取(假定 cache 已就绪)。
    private func rateLocked(from: Currency, to: Currency) -> Decimal? {
        if from == to { return 1 }
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

    /// 预热(应用启动时调一次)。先 seed 磁盘缓存,再异步拉新值。
    func warmup() async {
        seedFromDisk()
        await refreshIfNeeded(force: true)
        startAutoRefreshLoop()
    }

    /// 给 UI / 设置页用:返回所有已缓存的 pair → FXRate。
    func snapshot() -> (rates: [String: FXRate], lastFetch: Date, isRefreshing: Bool) {
        (cache, lastFetch, isRefreshing)
    }

    /// 抓一份当前汇率作 Sendable 值类型,后续可在任意线程同步换算。
    func currentConverter() -> CurrencyConverter {
        CurrencyConverter(fromCache: cache)
    }

    /// 用户在设置页点「立即刷新」。
    /// 不管 TTL,强制走网络;返回是否拿到了新值(false 表示请求挂了或空响应)。
    /// 失败时 cache 不被清掉,继续用旧值。
    @discardableResult
    func forceRefresh() async -> Bool {
        let before = lastFetch
        await refreshIfNeeded(force: true)
        return lastFetch > before
    }

    /// 用户改了「自动刷新间隔」设置后调用。0 = 关。
    func setAutoRefreshInterval(_ seconds: Int) {
        autoRefreshInterval = max(0, seconds)
        startAutoRefreshLoop()
    }

    private func startAutoRefreshLoop() {
        autoRefreshTask?.cancel()
        let interval = autoRefreshInterval
        guard interval > 0 else { return }
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                if Task.isCancelled { break }
                await self?.refreshIfNeeded(force: true)
            }
        }
    }

    private func refreshIfNeeded(force: Bool = false) async {
        let stale = Date().timeIntervalSince(lastFetch) >= ttl
        if !force && !stale && !cache.isEmpty { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let rates = (try? await provider.fetch(pairs: [(.usd, .cny), (.hkd, .cny)])) ?? []
        guard !rates.isEmpty else { return }

        var updated: [String: FXRate] = [:]
        for r in rates {
            // 用语义化 key 存(不依赖 enum rawValue 拼接)
            if r.from == .usd, r.to == .cny { updated["USDCNY"] = r }
            if r.from == .hkd, r.to == .cny { updated["HKDCNY"] = r }
        }
        guard !updated.isEmpty else { return }

        cache.merge(updated) { _, new in new }
        lastFetch = Date()
        // 落盘失败不影响内存值;下次有机会会再写回
        try? cacheRepo?.upsertMany(updated)
    }
}
