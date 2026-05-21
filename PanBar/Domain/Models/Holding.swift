import Foundation

struct Holding: Equatable, Codable, Sendable, Identifiable {
    let id: UUID
    var symbol: SymbolID
    var name: String
    var quantity: Decimal
    var costPrice: Decimal
    var currency: Currency
    var note: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        symbol: SymbolID,
        name: String,
        quantity: Decimal,
        costPrice: Decimal,
        currency: Currency? = nil,
        note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.quantity = quantity
        self.costPrice = costPrice
        self.currency = currency ?? symbol.market.defaultCurrency
        self.note = note
        self.createdAt = createdAt
    }
}
