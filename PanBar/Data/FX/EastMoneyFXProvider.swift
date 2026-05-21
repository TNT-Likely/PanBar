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
/// 示例:USDCNH(美元对离岸人民币)
///   secid = 119.USDCNH(根据 EM 内部市场号,有时是 133. / 119.)
/// 实际上,免费、最稳的做法是直接拉外汇牌价(中国银行 / EM)然后做转换。
///
/// 这里实现一个最小可用版本:对每个 (from→to) 拉一次 EM 报价。
struct EastMoneyFXProvider: FXProvider {
    let http: HTTPClient

    init(http: HTTPClient = HTTPClient(defaultHeaders: ["Referer": "https://quote.eastmoney.com/"])) {
        self.http = http
    }

    func fetch(pairs: [(Currency, Currency)]) async throws -> [FXRate] {
        var rates: [FXRate] = []
        for (from, to) in pairs {
            if from == to {
                rates.append(FXRate(from: from, to: to, rate: 1, asOf: Date()))
                continue
            }
            if let rate = try? await fetchOne(from: from, to: to) {
                rates.append(rate)
            }
        }
        return rates
    }

    private func fetchOne(from: Currency, to: Currency) async throws -> FXRate? {
        // 用 USD 作为枢轴汇率(USDCNH / USDHKD),其他对走两段换算。
        guard let secid = secidFor(from: from, to: to) else { return nil }
        var comps = URLComponents(string: "https://push2.eastmoney.com/api/qt/stock/get")!
        comps.queryItems = [
            URLQueryItem(name: "fltt", value: "2"),
            URLQueryItem(name: "invt", value: "2"),
            URLQueryItem(name: "fields", value: "f43,f44,f45,f46,f60,f57,f58"),
            URLQueryItem(name: "secid", value: secid)
        ]
        guard let url = comps.url else { return nil }
        let data = try await http.fetchData(url: url)

        struct Resp: Decodable {
            let data: Item?
            struct Item: Decodable {
                let f43: Double?    // current
                let f57: String?    // code
            }
        }
        let resp = try JSONDecoder().decode(Resp.self, from: data)
        guard let raw = resp.data?.f43 else { return nil }
        let rate = Decimal(raw)
        // 处理反向(如 HKD→CNY 用 USDCNH/USDHKD)
        // 这里 secidFor 返回的方向就是 from→to,直接使用。
        return FXRate(from: from, to: to, rate: rate, asOf: Date())
    }

    /// 简化映射:直接命中 EM 货币对。仅支持 USD/CNY、USD/HKD、HKD/CNY、CNY/USD、HKD/USD、CNY/HKD 几个常见对。
    private func secidFor(from: Currency, to: Currency) -> String? {
        switch (from, to) {
        case (.usd, .cny): return "133.USDCNYC"   // 中国银行 USD/CNY 中间价(EM 该 secid 多变,如不可用回退)
        case (.usd, .hkd): return "133.USDHKDC"
        case (.hkd, .cny): return "133.HKDCNYC"
        default:           return nil // 反向 / 不支持:由 FXService 通过枢轴计算
        }
    }
}
