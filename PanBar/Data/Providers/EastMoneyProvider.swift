import Foundation

/// 东方财富 push2.eastmoney.com 接口实现。批量行情走 ulist.np/get。
///
/// 字段:
///   - f12: code
///   - f13: market id
///   - f14: name
///   - f2:  当前价(已经是 price * 10^decimals,需除以 10^f1)
///   - f1:  小数位数(通常 2)
///   - f3:  涨跌幅 %(例如 +0.62 表示 0.62%)
///   - f17: open
///   - f18: prev close
///   - f15: high
///   - f16: low
///   - f5:  volume
struct EastMoneyProvider: QuoteProvider {
    let id = "eastmoney"
    let supportedMarkets: Set<Market> = [.a, .hk, .us]

    let http: HTTPClient

    init(http: HTTPClient = HTTPClient(defaultHeaders: ["Referer": "https://quote.eastmoney.com/"])) {
        self.http = http
    }

    func fetch(_ symbols: [SymbolID]) async throws -> [SymbolID: Quote] {
        guard !symbols.isEmpty else { return [:] }

        var encodedPairs: [(String, SymbolID)] = []
        for s in symbols {
            if let enc = SymbolEncoder.eastMoney(s) {
                encodedPairs.append((enc, s))
            }
        }
        guard !encodedPairs.isEmpty else { return [:] }

        let secids = encodedPairs.map { $0.0 }.joined(separator: ",")
        var comps = URLComponents(string: "https://push2.eastmoney.com/api/qt/ulist.np/get")!
        comps.queryItems = [
            URLQueryItem(name: "fltt", value: "2"),  // 价格小数原值
            URLQueryItem(name: "invt", value: "2"),
            URLQueryItem(name: "fields", value: "f1,f2,f3,f4,f5,f12,f13,f14,f15,f16,f17,f18"),
            URLQueryItem(name: "secids", value: secids),
            URLQueryItem(name: "_", value: "\(Int(Date().timeIntervalSince1970 * 1000))")
        ]
        guard let url = comps.url else { throw ProviderError.empty }

        let data = try await http.fetchData(url: url)
        return try parse(data, encodedPairs: encodedPairs)
    }

    func parse(_ data: Data, encodedPairs: [(String, SymbolID)]) throws -> [SymbolID: Quote] {
        struct Resp: Decodable {
            let data: DataBlock?
            struct DataBlock: Decodable {
                let diff: [Item]?
            }
            struct Item: Decodable {
                let f1: Int?      // decimals
                let f2: Double?   // price
                let f3: Double?   // change pct (already %)
                let f4: Double?   // change abs
                let f5: Double?   // volume
                let f12: String?  // code
                let f13: Int?     // market id
                let f14: String?  // name
                let f15: Double?  // high
                let f16: Double?  // low
                let f17: Double?  // open
                let f18: Double?  // prev close
            }
        }

        let decoder = JSONDecoder()
        let resp: Resp
        do {
            resp = try decoder.decode(Resp.self, from: data)
        } catch {
            throw ProviderError.parsing("eastmoney: \(error)")
        }
        guard let items = resp.data?.diff, !items.isEmpty else { return [:] }

        // 用 (marketID, code) → SymbolID 反查
        let lookup = Dictionary(uniqueKeysWithValues: encodedPairs.map { ($0.0, $0.1) })

        var out: [SymbolID: Quote] = [:]
        for item in items {
            guard let code = item.f12, let marketID = item.f13 else { continue }
            let secid = "\(marketID).\(code)"
            guard let symbolID = lookup[secid] else { continue }

            let price = Decimal(item.f2 ?? 0)
            let prevClose = Decimal(item.f18 ?? 0)
            let open = item.f17.map { Decimal($0) }
            let high = item.f15.map { Decimal($0) }
            let low = item.f16.map { Decimal($0) }
            let volume = item.f5.map { Decimal($0) }

            out[symbolID] = Quote(
                symbol: symbolID,
                name: item.f14 ?? symbolID.code,
                price: price,
                prevClose: prevClose,
                open: open,
                high: high,
                low: low,
                volume: volume,
                currency: symbolID.market.defaultCurrency,
                timestamp: Date(),
                isClosed: false
            )
        }
        return out
    }
}
