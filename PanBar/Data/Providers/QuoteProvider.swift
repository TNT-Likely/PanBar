import Foundation

protocol QuoteProvider: Sendable {
    var id: String { get }
    var supportedMarkets: Set<Market> { get }
    func fetch(_ symbols: [SymbolID]) async throws -> [SymbolID: Quote]
}

enum ProviderError: Error, CustomStringConvertible {
    case unsupportedMarket(Market)
    case parsing(String)
    case empty

    var description: String {
        switch self {
        case .unsupportedMarket(let m): return "unsupported market: \(m.rawValue)"
        case .parsing(let msg):         return "parse error: \(msg)"
        case .empty:                    return "empty response"
        }
    }
}
