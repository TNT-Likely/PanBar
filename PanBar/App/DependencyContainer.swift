import Foundation

/// 应用全局依赖。AppDelegate 启动时构造一次,然后通过 `shared` 提供。
@MainActor
final class DependencyContainer {
    static private(set) var shared: DependencyContainer?

    let database: Database
    let holdingsRepo: HoldingsRepository
    let watchlistRepo: WatchlistRepository
    let settingsRepo: SettingsRepository
    let alertsRepo: AlertsRepository
    let fxCacheRepo: FXCacheRepository
    let quoteCacheRepo: QuoteCacheRepository
    let orchestrator: ProviderOrchestrator
    let finnhub: FinnhubProvider
    let provider: QuoteProvider
    let indexService: IndexService
    let symbolSearch: SymbolSearch
    let fx: FXService
    let portfolioService: PortfolioService
    let clock: MarketClock
    let alertEngine: AlertEngine
    let refresher: QuoteRefresher
    let networkMonitor: NetworkMonitor
    let tickerPrefs: TickerPreferences
    let dataSourcePrefs: DataSourcePreferences
    let appearancePrefs: AppearancePreferences

    init() throws {
        let dbPath = try Database.defaultPath()
        let database = try Database(path: dbPath)
        self.database = database
        self.holdingsRepo = HoldingsRepository(dbPool: database.dbPool)
        self.watchlistRepo = WatchlistRepository(dbPool: database.dbPool)
        self.settingsRepo = SettingsRepository(dbPool: database.dbPool)
        self.alertsRepo = AlertsRepository(dbPool: database.dbPool)
        self.fxCacheRepo = FXCacheRepository(dbPool: database.dbPool)
        self.quoteCacheRepo = QuoteCacheRepository(dbPool: database.dbPool)

        let tencent = TencentProvider()
        let eastMoney = EastMoneyProvider()
        let yahoo = YahooProvider()
        let finnhub = FinnhubProvider()
        self.finnhub = finnhub
        self.dataSourcePrefs = DataSourcePreferences(repo: settingsRepo)
        finnhub.setApiKey(dataSourcePrefs.finnhubKey)
        let registry: [ProviderID: QuoteProvider] = [
            .tencent: tencent,
            .eastmoney: eastMoney,
            .yahoo: yahoo,
            .finnhub: finnhub
        ]
        let orchestrator = ProviderOrchestrator(
            providers: registry,
            preferences: dataSourcePrefs.preferences
        )
        self.orchestrator = orchestrator
        self.provider = orchestrator
        self.indexService = IndexService()
        self.symbolSearch = SymbolSearch()

        let fxProvider = EastMoneyFXProvider()
        let fx = FXService(provider: fxProvider, cacheRepo: fxCacheRepo)
        self.fx = fx

        self.clock = MarketClock(settingsRepo: settingsRepo)
        self.portfolioService = PortfolioService(
            holdingsRepo: holdingsRepo,
            watchlistRepo: watchlistRepo,
            settingsRepo: settingsRepo,
            provider: orchestrator,
            fx: fx
        )
        self.alertEngine = AlertEngine(alertsRepo: alertsRepo, notifier: NotificationService.shared, clock: clock)
        self.refresher = QuoteRefresher(
            service: portfolioService,
            indexService: indexService,
            clock: clock,
            quoteCacheRepo: quoteCacheRepo,
            alertEngine: alertEngine
        )
        self.networkMonitor = NetworkMonitor()
        self.tickerPrefs = TickerPreferences(repo: settingsRepo)
        self.appearancePrefs = AppearancePreferences(repo: settingsRepo)
    }

    static func bootstrap() throws -> DependencyContainer {
        let container = try DependencyContainer()
        shared = container
        return container
    }

    /// 应用启动的"冷启动序列",必须严格按以下顺序跑:
    ///   1. FXService.seedFromDisk()        ← 磁盘汇率灌进内存
    ///   2. refresher.seedSnapshotFromCacheIfNeeded() ← 基于本地持仓+缓存行情合成首屏 snapshot
    ///   3. refresher.start()                ← 启动 tick 循环(此时 lastUpdated 还没设)
    ///   4. fx 网络拉新值(后台)+ 自动刷新 timer
    /// 一旦顺序乱了,tick 先跑就会把 lastUpdated 写上,seed 的 guard 会跳过,
    /// 用户首次打开 popover 还是空。
    func warmup() async {
        let interval = settingsRepo.fxRefreshInterval
        await fx.setAutoRefreshInterval(interval)
        refresher.tickerInterval = TimeInterval(settingsRepo.quoteRefreshInterval)

        // 同步动作:磁盘 seed,必须先于 start() 完成
        await fx.seedFromDisk()
        await refresher.seedSnapshotFromCacheIfNeeded()

        // 现在再启动 tick 循环
        refresher.start()

        // 后台拉新值
        await fx.warmup()
    }
}
