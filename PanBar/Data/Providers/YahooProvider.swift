import Foundation

/// Yahoo Finance v8 chart 接口。无需 crumb,覆盖全球。
/// 缺点:不支持批量,需要每个 symbol 并发请求。
struct YahooProvider: QuoteProvider {
    let id = "yahoo"
    let supportedMarkets: Set<Market> = [.a, .hk, .us]

    let http: HTTPClient

    init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    func fetch(_ symbols: [SymbolID]) async throws -> [SymbolID: Quote] {
        guard !symbols.isEmpty else { return [:] }

        // 并发拉取,限制最多 8 个并发避免反爬
        let chunks = symbols.chunked(by: 8)
        var result: [SymbolID: Quote] = [:]
        for chunk in chunks {
            let pairs = try await withThrowingTaskGroup(of: (SymbolID, Quote?).self) { group in
                for s in chunk {
                    group.addTask { (s, try? await self.fetchOne(s)) }
                }
                var out: [(SymbolID, Quote)] = []
                for try await (s, q) in group {
                    if let q = q { out.append((s, q)) }
                }
                return out
            }
            for (s, q) in pairs {
                result[s] = q
            }
        }
        return result
    }

    private func fetchOne(_ symbol: SymbolID) async throws -> Quote? {
        guard let yahooCode = SymbolEncoder.yahoo(symbol) else { return nil }
        guard let escaped = yahooCode.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(escaped)?interval=1d&range=1d")!
        let data = try await http.fetchData(url: url)
        return try parse(data, symbol: symbol)
    }

    private func parse(_ data: Data, symbol: SymbolID) throws -> Quote? {
        struct Resp: Decodable {
            let chart: Chart
            struct Chart: Decodable {
                let result: [Result]?
            }
            struct Result: Decodable {
                let meta: Meta
            }
            struct Meta: Decodable {
                let currency: String?
                let regularMarketPrice: Double?
                let previousClose: Double?
                let chartPreviousClose: Double?
                let regularMarketDayHigh: Double?
                let regularMarketDayLow: Double?
                let regularMarketVolume: Double?
                let longName: String?
                let shortName: String?
            }
        }
        let resp = try JSONDecoder().decode(Resp.self, from: data)
        guard let meta = resp.chart.result?.first?.meta else { return nil }
        guard let price = meta.regularMarketPrice else { return nil }
        let prevClose = meta.previousClose ?? meta.chartPreviousClose ?? price
        let currency = Currency(rawValue: meta.currency ?? "") ?? symbol.market.defaultCurrency

        return Quote(
            symbol: symbol,
            name: meta.longName ?? meta.shortName ?? symbol.code,
            price: Decimal(price),
            prevClose: Decimal(prevClose),
            open: nil,
            high: meta.regularMarketDayHigh.map { Decimal($0) },
            low: meta.regularMarketDayLow.map { Decimal($0) },
            volume: meta.regularMarketVolume.map { Decimal($0) },
            currency: currency,
            timestamp: Date(),
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
