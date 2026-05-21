import Foundation

/// Finnhub quote 接口。免费档 60 req/min,仅支持美股(A/HK 需付费档)。
/// 用户在 Settings → Data Sources 填入 API Key。
final class FinnhubProvider: QuoteProvider, @unchecked Sendable {
    let id = "finnhub"
    let supportedMarkets: Set<Market> = [.us]

    let http: HTTPClient
    private var apiKey: String?
    private let lock = NSLock()

    init(http: HTTPClient = HTTPClient(), apiKey: String? = nil) {
        self.http = http
        self.apiKey = apiKey
    }

    func setApiKey(_ key: String?) {
        lock.lock(); defer { lock.unlock() }
        let trimmed = key?.trimmingCharacters(in: .whitespaces)
        self.apiKey = (trimmed?.isEmpty == false) ? trimmed : nil
    }

    private var currentKey: String? {
        lock.lock(); defer { lock.unlock() }
        return apiKey
    }

    func fetch(_ symbols: [SymbolID]) async throws -> [SymbolID: Quote] {
        guard let key = currentKey else { return [:] }   // 没填 key 就静默跳过
        let usSymbols = symbols.filter { $0.market == .us }
        guard !usSymbols.isEmpty else { return [:] }

        // 并发拉取,限制 6 并发
        let chunks = usSymbols.chunked(by: 6)
        var out: [SymbolID: Quote] = [:]
        for chunk in chunks {
            let pairs = try await withThrowingTaskGroup(of: (SymbolID, Quote?).self) { group in
                for s in chunk {
                    group.addTask { (s, try? await self.fetchOne(s, key: key)) }
                }
                var result: [(SymbolID, Quote)] = []
                for try await (s, q) in group {
                    if let q = q { result.append((s, q)) }
                }
                return result
            }
            for (s, q) in pairs { out[s] = q }
        }
        return out
    }

    private func fetchOne(_ symbol: SymbolID, key: String) async throws -> Quote? {
        guard let code = SymbolEncoder.finnhub(symbol) else { return nil }
        var comps = URLComponents(string: "https://finnhub.io/api/v1/quote")!
        comps.queryItems = [
            URLQueryItem(name: "symbol", value: code),
            URLQueryItem(name: "token", value: key)
        ]
        guard let url = comps.url else { return nil }
        let data = try await http.fetchData(url: url)
        return try parse(data, symbol: symbol)
    }

    private func parse(_ data: Data, symbol: SymbolID) throws -> Quote? {
        struct Resp: Decodable {
            let c: Double?   // current
            let d: Double?   // change
            let dp: Double?  // change pct
            let h: Double?   // high
            let l: Double?   // low
            let o: Double?   // open
            let pc: Double?  // prev close
            let t: Int?      // timestamp (sec)
        }
        let resp = try JSONDecoder().decode(Resp.self, from: data)
        guard let price = resp.c, price > 0 else { return nil }
        return Quote(
            symbol: symbol,
            name: symbol.code,
            price: Decimal(price),
            prevClose: Decimal(resp.pc ?? price),
            open: resp.o.map { Decimal($0) },
            high: resp.h.map { Decimal($0) },
            low: resp.l.map { Decimal($0) },
            volume: nil,
            currency: .usd,
            timestamp: resp.t.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date(),
            isClosed: false
        )
    }
}

private extension Array {
    func chunked(by size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var result: [[Element]] = []
        var i = 0
        while i < count {
            let end = Swift.min(i + size, count)
            result.append(Array(self[i..<end]))
            i = end
        }
        return result
    }
}
