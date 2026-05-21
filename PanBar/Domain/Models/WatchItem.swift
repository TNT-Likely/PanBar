import Foundation

struct WatchItem: Equatable, Codable, Sendable, Identifiable {
    let id: UUID
    var symbol: SymbolID
    var name: String
    var order: Int
    var inTicker: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        symbol: SymbolID,
        name: String,
        order: Int = 0,
        inTicker: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.order = order
        self.inTicker = inTicker
        self.createdAt = createdAt
    }
}
