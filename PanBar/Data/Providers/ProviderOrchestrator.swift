import Foundation

/// Provider 标识。统一 ID 串便于持久化和 UI 显示。
enum ProviderID: String, Codable, CaseIterable, Sendable {
    case tencent
    case eastmoney
    case yahoo
    case finnhub

    var displayName: String {
        switch self {
        case .tencent:   return "腾讯财经"
        case .eastmoney: return "东方财富"
        case .yahoo:     return "Yahoo Finance"
        case .finnhub:   return "Finnhub"
        }
    }
}

/// 每市场的 provider 优先级列表 + 启用标志。
struct ProviderPreference: Codable, Equatable, Sendable {
    var order: [ProviderID]
    var enabled: [ProviderID: Bool]

    static let defaults: [Market: ProviderPreference] = [
        .a:  ProviderPreference(order: [.tencent, .eastmoney, .yahoo], enabled: [.tencent: true, .eastmoney: true, .yahoo: false, .finnhub: false]),
        .hk: ProviderPreference(order: [.tencent, .eastmoney, .yahoo], enabled: [.tencent: true, .eastmoney: true, .yahoo: false, .finnhub: false]),
        .us: ProviderPreference(order: [.tencent, .eastmoney, .yahoo, .finnhub], enabled: [.tencent: true, .eastmoney: true, .yahoo: true, .finnhub: false])
    ]
}

/// 编排多 provider:按市场拆分 symbols → 按用户设定顺序 fallback。
actor ProviderOrchestrator: QuoteProvider {
    let id = "orchestrator"
    let supportedMarkets: Set<Market> = [.a, .hk, .us]

    private let providers: [ProviderID: QuoteProvider]
    private var preferences: [Market: ProviderPreference]
    private var cooldownUntil: [String: Date] = [:]   // key = "providerID|market"
    private let cooldownDuration: TimeInterval = 30

    init(providers: [ProviderID: QuoteProvider], preferences: [Market: ProviderPreference]) {
        self.providers = providers
        self.preferences = preferences
    }

    func updatePreferences(_ prefs: [Market: ProviderPreference]) {
        self.preferences = prefs
    }

    func currentPreferences() -> [Market: ProviderPreference] {
        preferences
    }

    func fetch(_ symbols: [SymbolID]) async throws -> [SymbolID: Quote] {
        // 按市场分桶
        let byMarket = Dictionary(grouping: symbols, by: { $0.market })

        var combined: [SymbolID: Quote] = [:]
        var lastError: Error?

        for (market, marketSymbols) in byMarket {
            do {
                let result = try await fetchForMarket(market, symbols: marketSymbols)
                combined.merge(result, uniquingKeysWith: { _, new in new })
            } catch {
                lastError = error
                Log.quote.warning("market \(market.rawValue, privacy: .public) all providers failed: \(String(describing: error), privacy: .public)")
            }
        }

        if combined.isEmpty, let lastError = lastError {
            throw lastError
        }
        return combined
    }

    private func fetchForMarket(_ market: Market, symbols: [SymbolID]) async throws -> [SymbolID: Quote] {
        let pref = preferences[market] ?? ProviderPreference.defaults[market]!
        let now = Date()
        var lastError: Error?

        for pid in pref.order {
            guard pref.enabled[pid] == true else { continue }
            guard let provider = providers[pid] else { continue }
            guard provider.supportedMarkets.contains(market) else { continue }

            let cooldownKey = "\(pid.rawValue)|\(market.rawValue)"
            if let until = cooldownUntil[cooldownKey], until > now { continue }

            do {
                let result = try await provider.fetch(symbols)
                if !result.isEmpty {
                    Log.quote.info("market=\(market.rawValue, privacy: .public) provider=\(pid.rawValue, privacy: .public) ok (\(result.count) quotes)")
                    return result
                }
            } catch {
                lastError = error
                cooldownUntil[cooldownKey] = now.addingTimeInterval(cooldownDuration)
                Log.quote.warning("provider \(pid.rawValue, privacy: .public) failed for \(market.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }

        if let lastError = lastError {
            throw lastError
        }
        return [:]
    }
}
