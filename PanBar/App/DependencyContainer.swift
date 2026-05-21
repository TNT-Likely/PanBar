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

        // 用 settings 里的代理配置初始化 NetworkConfig.sharedSession,
        // 之后所有 HTTPClient(走默认 session)会用上代理
        NetworkConfig.apply(
            mode: settingsRepo.proxyMode,
            host: settingsRepo.proxyHost,
            port: settingsRepo.proxyPort
        )

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
            fxCacheRepo: fxCacheRepo,
            holdingsRepo: holdingsRepo,
            settingsRepo: settingsRepo,
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

    /// 应用启动后的轻量启动:首屏 snapshot 已在 QuoteRefresher.init 用磁盘缓存
    /// 同步合成,popover 现在打开就有完整数据。warmup 只剩:
    ///   - 把用户设置传给 refresher / fx
    ///   - FXService 内部 seed disk(actor 内部走 disk → cache)
    ///   - start tick 循环
    ///   - 后台拉新 FX
    func warmup() async {
        let interval = settingsRepo.fxRefreshInterval
        await fx.setAutoRefreshInterval(interval)
        refresher.tickerInterval = TimeInterval(settingsRepo.quoteRefreshInterval)
        refresher.pauseWhenClosed = settingsRepo.pauseRefreshWhenClosed

        // FXService 也 seed 一遍(refresher.init 已经读过磁盘,但 FXService 自己
        // 内部的 cache dict 还是空的;后续 PortfolioService 走 await fx.convert
        // 需要它有数据)
        await fx.seedFromDisk()

        refresher.start()

        // 后台拉新值
        await fx.warmup()
    }
}
