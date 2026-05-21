import Foundation

/// 持仓服务:加载行情后,计算每只持仓的盈亏与汇总到本位币的 PortfolioSnapshot。
actor PortfolioService {
    private let holdingsRepo: HoldingsRepository
    private let watchlistRepo: WatchlistRepository
    private let settingsRepo: SettingsRepository
    private let provider: QuoteProvider
    private let fx: FXService

    init(
        holdingsRepo: HoldingsRepository,
        watchlistRepo: WatchlistRepository,
        settingsRepo: SettingsRepository,
        provider: QuoteProvider,
        fx: FXService
    ) {
        self.holdingsRepo = holdingsRepo
        self.watchlistRepo = watchlistRepo
        self.settingsRepo = settingsRepo
        self.provider = provider
        self.fx = fx
    }

    /// 拉取所有持仓 + 自选 → 一次性请求行情 → 构建快照。
    func computeSnapshot() async throws -> PortfolioSnapshot {
        let holdings = (try? holdingsRepo.all()) ?? []
        let watchlist = (try? watchlistRepo.all()) ?? []

        // 合并所有 SymbolID(持仓 + 自选),去重后一次拉取
        var allSymbols = Set<SymbolID>()
        for h in holdings { allSymbols.insert(h.symbol) }
        for w in watchlist { allSymbols.insert(w.symbol) }

        let quotes: [SymbolID: Quote]
        if allSymbols.isEmpty {
            quotes = [:]
        } else {
            quotes = (try? await provider.fetch(Array(allSymbols))) ?? [:]
        }

        let converter = await fx.currentConverter()
        let baseCurrency = settingsRepo.baseCurrency
        return Self.computeSnapshotSync(
            holdings: holdings,
            quotes: quotes,
            converter: converter,
            baseCurrency: baseCurrency
        )
    }

    /// 不走网络,只用调用方提供的行情。用于「秒出 + 后台刷新」。
    func computeSnapshot(usingCachedQuotes cached: [SymbolID: Quote]) async -> PortfolioSnapshot {
        let holdings = (try? holdingsRepo.all()) ?? []
        let converter = await fx.currentConverter()
        let baseCurrency = settingsRepo.baseCurrency
        return Self.computeSnapshotSync(
            holdings: holdings,
            quotes: cached,
            converter: converter,
            baseCurrency: baseCurrency
        )
    }

    /// 纯函数版本 —— 无 actor 调用、无 await,可在 @MainActor init 里直接用,
    /// 让 popover 一打开就有完整 totalAssets / pnl(冷启动场景)。
    static func computeSnapshotSync(
        holdings: [Holding],
        quotes: [SymbolID: Quote],
        converter: CurrencyConverter,
        baseCurrency: Currency
    ) -> PortfolioSnapshot {
        var positions: [HoldingPosition] = []
        var totalAssets: Decimal = 0
        var totalCost: Decimal = 0
        var todayPnL: Decimal = 0
        var allTimePnL: Decimal = 0

        for h in holdings {
            let q = quotes[h.symbol]
            let price = q?.price ?? h.costPrice
            let prevClose = q?.prevClose ?? price
            let marketValue = price * h.quantity
            let costValue = h.costPrice * h.quantity
            let pnl = marketValue - costValue
            let pnlPct: Double = {
                guard costValue > 0 else { return 0 }
                return (pnl / costValue as NSDecimalNumber).doubleValue
            }()
            let dayPnL = (price - prevClose) * h.quantity

            let baseMarketValue = converter.convert(marketValue, from: h.currency, to: baseCurrency)
            let baseTodayPnL = converter.convert(dayPnL, from: h.currency, to: baseCurrency)
            let basePnL = converter.convert(pnl, from: h.currency, to: baseCurrency)
            let baseCost = converter.convert(costValue, from: h.currency, to: baseCurrency)

            positions.append(HoldingPosition(
                holding: h,
                quote: q,
                marketValue: marketValue,
                pnl: pnl,
                pnlPct: pnlPct,
                todayPnL: dayPnL,
                baseMarketValue: baseMarketValue,
                baseTodayPnL: baseTodayPnL,
                basePnL: basePnL
            ))

            if let bv = baseMarketValue { totalAssets += bv }
            if let bc = baseCost { totalCost += bc }
            if let bt = baseTodayPnL { todayPnL += bt }
            if let bp = basePnL { allTimePnL += bp }
        }

        let todayPnLPct: Double = {
            let base = totalAssets - todayPnL
            guard base > 0 else { return 0 }
            return (todayPnL / base as NSDecimalNumber).doubleValue
        }()
        let allTimePnLPct: Double = {
            guard totalCost > 0 else { return 0 }
            return (allTimePnL / totalCost as NSDecimalNumber).doubleValue
        }()

        return PortfolioSnapshot(
            baseCurrency: baseCurrency,
            totalAssets: totalAssets,
            totalCost: totalCost,
            todayPnL: todayPnL,
            todayPnLPct: todayPnLPct,
            allTimePnL: allTimePnL,
            allTimePnLPct: allTimePnLPct,
            positions: positions,
            allQuotes: quotes,
            asOf: Date()
        )
    }

    /// 仅返回行情字典(供 ticker 使用)。
    func fetchQuotes(for symbols: [SymbolID]) async throws -> [SymbolID: Quote] {
        try await provider.fetch(symbols)
    }
}
