import Foundation

/// 全局唯一的股票标识(代码 + 市场)。
struct SymbolID: Hashable, Codable, Sendable, CustomStringConvertible {
    let code: String   // "600519" / "AAPL" / "00700"
    let market: Market

    var description: String { "\(market.rawValue):\(code)" }

    /// 用于持久化或缓存的稳定 key。
    var storageKey: String { "\(market.rawValue)_\(code.uppercased())" }
}
