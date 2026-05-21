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

        self.clock = MarketClock()
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

    func warmup() async {
        // 用户配置的自动刷新间隔在 warmup 内传给 FXService,免去 actor 外部读 settings
        let interval = settingsRepo.fxRefreshInterval
        await fx.setAutoRefreshInterval(interval)
        await fx.warmup()
        // FX 就绪后,把磁盘里 seed 的 quote 现成跑一次 computeSnapshot,
        // 让 popover 第一次打开就有完整数据(包含本位币换算)
        refresher.seedSnapshotFromCacheIfNeeded()
    }
}
