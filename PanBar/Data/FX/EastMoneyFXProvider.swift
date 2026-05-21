import Foundation

/// 货币对方向:`from → to`,持有 from 1 单位可换 to 多少。
struct FXRate: Equatable, Codable, Sendable {
    let from: Currency
    let to: Currency
    let rate: Decimal
    let asOf: Date
}

protocol FXProvider: Sendable {
    func fetch(pairs: [(Currency, Currency)]) async throws -> [FXRate]
}

/// 东方财富外汇接口。
///
/// 只拉 2 个基础对:
///   - USDCNY:`120.USDCNYC`(美元人民币中间价)
///   - HKDCNY:`120.HKDCNYC`(港币人民币中间价)
///
/// 其他所有方向(USD→HKD / CNY→USD / CNY→HKD / HKD→USD 等)
/// 在 FXService 里用 CNY 作枢轴换算。
struct EastMoneyFXProvider: FXProvider {
    let http: HTTPClient

    init(http: HTTPClient = HTTPClient(defaultHeaders: ["Referer": "https://quote.eastmoney.com/"])) {
        self.http = http
    }

    func fetch(pairs: [(Currency, Currency)]) async throws -> [FXRate] {
        // 只关心需要的基础对(USDCNY, HKDCNY),其它在 FXService 算。
        // 直接全拉,简化逻辑(2 个 secid 而已)。
        var rates: [FXRate] = []
        if let r = try? await fetchSecid("120.USDCNYC", from: .usd, to: .cny) {
            rates.append(r)
        }
        if let r = try? await fetchSecid("120.HKDCNYC", from: .hkd, to: .cny) {
            rates.append(r)
        }
        return rates
    }

    private func fetchSecid(_ secid: String, from: Currency, to: Currency) async throws -> FXRate? {
        var comps = URLComponents(string: "https://push2.eastmoney.com/api/qt/stock/get")!
        comps.queryItems = [
            URLQueryItem(name: "fltt", value: "2"),
            URLQueryItem(name: "invt", value: "2"),
            URLQueryItem(name: "fields", value: "f43,f57,f58"),
            URLQueryItem(name: "secid", value: secid)
        ]
        guard let url = comps.url else { return nil }
        let data = try await http.fetchData(url: url)

        struct Resp: Decodable {
            let data: Item?
            struct Item: Decodable {
                let f43: Double?
            }
        }
        let resp = try JSONDecoder().decode(Resp.self, from: data)
        guard let raw = resp.data?.f43, raw > 0 else { return nil }
        return FXRate(from: from, to: to, rate: Decimal(raw), asOf: Date())
    }
}
