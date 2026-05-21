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

        return await buildSnapshot(holdings: holdings, quotes: quotes)
    }

    /// 不走网络,只用调用方提供的行情(通常来自磁盘缓存)。
    /// 用于 popover 首次打开的「秒出 + 后台刷新」场景。
    func computeSnapshot(usingCachedQuotes cached: [SymbolID: Quote]) async -> PortfolioSnapshot {
        let holdings = (try? holdingsRepo.all()) ?? []
        return await buildSnapshot(holdings: holdings, quotes: cached)
    }

    private func buildSnapshot(holdings: [Holding], quotes: [SymbolID: Quote]) async -> PortfolioSnapshot {
        let baseCurrency = settingsRepo.baseCurrency

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

            // 换算到本位币
            let baseMarketValue = await fx.convert(marketValue, from: h.currency, to: baseCurrency)
            let baseTodayPnL = await fx.convert(dayPnL, from: h.currency, to: baseCurrency)
            let basePnL = await fx.convert(pnl, from: h.currency, to: baseCurrency)
            let baseCost = await fx.convert(costValue, from: h.currency, to: baseCurrency)

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
