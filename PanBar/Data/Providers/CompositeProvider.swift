import Foundation

/// 多 provider 串行 fallback。失败计数 + 冷却窗口避免反复打死同一接口。
actor CompositeProvider: QuoteProvider {
    let id = "composite"
    let supportedMarkets: Set<Market> = [.a, .hk, .us]

    private let providers: [QuoteProvider]
    private var cooldownUntil: [String: Date] = [:]
    private let cooldownDuration: TimeInterval = 30 // s

    init(providers: [QuoteProvider]) {
        self.providers = providers
    }

    func fetch(_ symbols: [SymbolID]) async throws -> [SymbolID: Quote] {
        var lastError: Error?
        let now = Date()

        for p in providers {
            if let until = cooldownUntil[p.id], until > now {
                Log.quote.debug("skip provider \(p.id, privacy: .public) (cooldown)")
                continue
            }
            do {
                let result = try await p.fetch(symbols)
                if !result.isEmpty {
                    Log.quote.info("provider \(p.id, privacy: .public) returned \(result.count) quotes")
                    return result
                }
            } catch {
                Log.quote.warning("provider \(p.id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                cooldownUntil[p.id] = now.addingTimeInterval(cooldownDuration)
                lastError = error
            }
        }
        if let lastError = lastError {
            throw lastError
        }
        return [:]
    }
}
