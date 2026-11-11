import Foundation

enum PortfolioGroupKind: String, Codable, Sendable {
    case holdings, watchlist
}

struct PortfolioGroup: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var name: String
    let kind: PortfolioGroupKind
    var sortOrder: Int

    init(id: UUID = UUID(), name: String, kind: PortfolioGroupKind, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.kind = kind
        self.sortOrder = sortOrder
    }
}
