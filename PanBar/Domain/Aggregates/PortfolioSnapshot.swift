import Foundation

struct HoldingPosition: Identifiable, Equatable, Sendable {
    var id: UUID { holding.id }
    let holding: Holding
    let quote: Quote?
    /// Current market value in the holding's native currency.
    let marketValue: Decimal
    /// P&L (current - cost) in native currency.
    let pnl: Decimal
    /// P&L percent (e.g. 0.12 = +12%).
    let pnlPct: Double
    /// Today's P&L (price change today * qty) in native currency.
    let todayPnL: Decimal
    /// Market value converted to base currency (nil if FX unavailable).
    let baseMarketValue: Decimal?
    let baseTodayPnL: Decimal?
    let basePnL: Decimal?
}

struct PortfolioSnapshot: Equatable, Sendable {
    let baseCurrency: Currency
    let totalAssets: Decimal      // sum of baseMarketValue
    let totalCost: Decimal        // sum of cost in base currency
    let todayPnL: Decimal
    let todayPnLPct: Double
    let allTimePnL: Decimal
    let allTimePnLPct: Double
    let positions: [HoldingPosition]
    let asOf: Date

    static let empty = PortfolioSnapshot(
        baseCurrency: .cny,
        totalAssets: 0,
        totalCost: 0,
        todayPnL: 0,
        todayPnLPct: 0,
        allTimePnL: 0,
        allTimePnLPct: 0,
        positions: [],
        asOf: Date()
    )
}
