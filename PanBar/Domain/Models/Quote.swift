import Foundation

struct Quote: Equatable, Codable, Sendable {
    let symbol: SymbolID
    let name: String
    let price: Decimal
    let prevClose: Decimal
    let open: Decimal?
    let high: Decimal?
    let low: Decimal?
    let volume: Decimal?
    let currency: Currency
    let timestamp: Date
    let isClosed: Bool

    var change: Decimal { price - prevClose }

    var changePct: Double {
        guard prevClose > 0 else { return 0 }
        let pct = (change / prevClose) as NSDecimalNumber
        return pct.doubleValue
    }
}
