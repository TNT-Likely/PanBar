import Foundation
import Combine
import AppKit

/// 全局行情刷新泵。根据当前可见性 / 系统休眠 / 市场状态切换不同刷新频率。
@MainActor
final class QuoteRefresher: ObservableObject {
    enum Pace {
        case popoverOpen   // 3s,用户正盯着,固定快
        case tickerOnly    // 用户配置的间隔(默认 5s)
        case sleeping      // 暂停(全市场休市 / 系统休眠 / 离线 都走这条)
    }

    /// 用户在设置里改了「行情刷新间隔」时,更新这个值;runLoop 下次循环生效。
    @Published var tickerInterval: TimeInterval = 5

    private func interval(for pace: Pace) -> TimeInterval {
        switch pace {
        case .popoverOpen: return min(tickerInterval, 3)  // popover 开着至少 3s,不能更慢
        case .tickerOnly:  return tickerInterval
        case .sleeping:    return .infinity
        }
    }

    @Published private(set) var snapshot: PortfolioSnapshot = .empty
    @Published private(set) var quotes: [SymbolID: Quote] = [:]
    @Published private(set) var indexQuotes: [IndexQuote] = []
    @Published private(set) var lastError: String?
    @Published private(set) var lastUpdated: Date?
    /// true 表示一次网络刷新正在进行中,UI 可以显示 spinner。
    @Published private(set) var isRefreshing: Bool = false
    /// snapshot/quotes 当前值的来源是否是磁盘缓存(尚未拿到任何成功的网络响应)。
    /// UI 据此显示「显示的是上次的数据,正在更新...」提示。
    @Published private(set) var snapshotIsFromCache: Bool = false

    private let service: PortfolioService
    private let indexService: IndexService
    private let clock: MarketClock
    private let quoteCacheRepo: QuoteCacheRepository?
    private let alertEngine: AlertEngine?
    private var task: Task<Void, Never>?
    private var indexTask: Task<Void, Never>?
    private var pace: Pace = .tickerOnly
    private var popoverOpen = false
    private var sleeping = false
    private var offline = false
    private var observers: [NSObjectProtocol] = []

    init(
        service: PortfolioService,
        indexService: IndexService,
        clock: MarketClock,
        quoteCacheRepo: QuoteCacheRepository? = nil,
        alertEngine: AlertEngine? = nil
    ) {
        self.service = service
        self.indexService = indexService
        self.clock = clock
        self.quoteCacheRepo = quoteCacheRepo
        self.alertEngine = alertEngine

        // 同步从磁盘 seed quotes,这样 popover 一打开就有数据。
        // 实际 snapshot 在 seedSnapshotFromCacheIfNeeded() 里异步算(需要 FX)。
        if let cached = quoteCacheRepo?.loadAll(), !cached.isEmpty {
            self.quotes = cached
            Log.quote.info("seeded \(cached.count, privacy: .public) quotes from disk")
        } else {
            Log.quote.info("quote disk cache is empty")
        }

        observeSystem()
    }

    /// 应用启动早期(在 FX warmup 之后)调一次,**同步合成**一个"基于磁盘缓存"的 snapshot,
    /// 让 popover 第一次打开就有完整持仓 + 本位币换算。
    /// 缓存为空时也会跑一次:持仓行会用 costPrice 作 fallback,至少行能展示出来。
    ///
    /// 必须在 `start()` 之前 await 完,否则首次 tick 会把 lastUpdated 占住,
    /// 这边的 guard 直接跳过,首屏又变回空白。
    func seedSnapshotFromCacheIfNeeded() async {
        let cached = quotes
        let snap = await service.computeSnapshot(usingCachedQuotes: cached)
        guard lastUpdated == nil else { return }
        snapshot = snap
        if !cached.isEmpty { snapshotIsFromCache = true }
    }

    func setOffline(_ value: Bool) {
        offline = value
        recomputePace()
    }

    var isOffline: Bool { offline }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        task?.cancel()
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            await self?.runLoop()
        }
        indexTask = Task { [weak self] in
            await self?.runIndexLoop()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        indexTask?.cancel()
        indexTask = nil
    }

    /// 触发立即刷新一次(不影响调度)。
    func refreshNow() {
        Task { await tick() }
    }

    func setPopoverOpen(_ open: Bool) {
        popoverOpen = open
        recomputePace()
    }

    private func observeSystem() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.sleeping = true
                self?.recomputePace()
            }
        })
        observers.append(nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.sleeping = false
                self?.recomputePace()
            }
        })
    }

    private func recomputePace() {
        let next: Pace
        if sleeping || offline {
            next = .sleeping
        } else if !clock.anyOpen() {
            // 全市场休市:完全暂停自动刷新,用户可点底部刷新按钮手动拉
            next = .sleeping
        } else if popoverOpen {
            next = .popoverOpen
        } else {
            next = .tickerOnly
        }
        pace = next
    }

    private func runLoop() async {
        await tick()
        while !Task.isCancelled {
            recomputePace()
            let nextInterval = await MainActor.run { self.interval(for: self.pace) }
            if nextInterval.isInfinite {
                // .sleeping:每 5s 轮询一次 pace,等市场开 / 用户开 popover 时立刻醒
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                continue
            }
            try? await Task.sleep(nanoseconds: UInt64(nextInterval * 1_000_000_000))
            if Task.isCancelled { break }
            await tick()
        }
    }

    /// 指数轮询:跑独立 Task,间隔比股票长(15s),休眠/离线时暂停。
    private func runIndexLoop() async {
        await tickIndices()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            if Task.isCancelled { break }
            if sleeping || offline { continue }
            await tickIndices()
        }
    }

    private func tickIndices() async {
        do {
            let result = try await indexService.fetchAll()
            await MainActor.run {
                self.indexQuotes = result
            }
        } catch {
            Log.quote.warning("index fetch failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func tick() async {
        await MainActor.run { self.isRefreshing = true }
        do {
            let snap = try await service.computeSnapshot()
            // 网络空响应(provider.fetch 失败 -> quotes 空)时,不要拿一个全 nil quote 的
            // snapshot 去覆盖磁盘 seed 的好数据;原样保留 cached snapshot,等下次 tick。
            let hasFreshData = !snap.allQuotes.isEmpty
            await MainActor.run {
                if hasFreshData {
                    self.snapshot = snap
                    self.snapshotIsFromCache = false
                    self.quotes.merge(snap.allQuotes) { _, new in new }
                    self.lastUpdated = Date()
                    self.lastError = nil
                    self.alertEngine?.evaluate(quotes: self.quotes)
                }
            }
            // 拉到了就异步写盘,下次冷启动可以秒读
            if hasFreshData {
                quoteCacheRepo?.upsertMany(snap.allQuotes)
            }
        } catch {
            await MainActor.run {
                self.lastError = String(describing: error)
            }
            Log.quote.error("refresh failed: \(String(describing: error), privacy: .public)")
        }
        await MainActor.run { self.isRefreshing = false }
    }
}
