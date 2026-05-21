import Foundation

/// 批量拉取大盘指数报价(走 EM `ulist.np/get`,因为指数 secid 在 EM 上是公开的)。
actor IndexService {
    private let http: HTTPClient

    init(http: HTTPClient = HTTPClient(defaultHeaders: ["Referer": "https://quote.eastmoney.com/"])) {
        self.http = http
    }

    func fetchAll(_ indices: [IndexDescriptor] = IndexCatalog.all) async throws -> [IndexQuote] {
        guard !indices.isEmpty else { return [] }
        let secids = indices.map { $0.emSecid }.joined(separator: ",")
        var comps = URLComponents(string: "https://push2.eastmoney.com/api/qt/ulist.np/get")!
        comps.queryItems = [
            URLQueryItem(name: "fltt", value: "2"),
            URLQueryItem(name: "invt", value: "2"),
            URLQueryItem(name: "fields", value: "f2,f3,f4,f12,f13,f14,f18"),
            URLQueryItem(name: "secids", value: secids),
            URLQueryItem(name: "_", value: "\(Int(Date().timeIntervalSince1970 * 1000))")
        ]
        guard let url = comps.url else { return [] }
        let data = try await http.fetchData(url: url)
        return try parse(data, indices: indices)
    }

    private func parse(_ data: Data, indices: [IndexDescriptor]) throws -> [IndexQuote] {
        struct Resp: Decodable {
            let data: Block?
            struct Block: Decodable { let diff: [Item]? }
            struct Item: Decodable {
                let f2: Double?
                let f3: Double?
                let f4: Double?
                let f12: String?
                let f13: Int?
                let f14: String?
                let f18: Double?
            }
        }
        let resp = try JSONDecoder().decode(Resp.self, from: data)
        guard let items = resp.data?.diff else { return [] }

        let lookup = Dictionary(uniqueKeysWithValues: indices.map { ($0.emSecid, $0) })
        var out: [IndexQuote] = []
        for item in items {
            guard let code = item.f12, let marketID = item.f13 else { continue }
            let secid = "\(marketID).\(code)"
            guard let desc = lookup[secid] else { continue }
            let price = Decimal(item.f2 ?? 0)
            let prevClose = Decimal(item.f18 ?? 0)
            let change = Decimal(item.f4 ?? 0)
            let pct = (item.f3 ?? 0) / 100.0   // EM 返回的是百分数 (e.g. 0.62 = 0.62%)
            out.append(IndexQuote(
                descriptor: desc,
                price: price,
                prevClose: prevClose,
                change: change,
                changePct: pct
            ))
        }
        // 按 IndexCatalog 顺序排序
        let order = Dictionary(uniqueKeysWithValues: indices.enumerated().map { ($0.element.id, $0.offset) })
        out.sort { (order[$0.descriptor.id] ?? 0) < (order[$1.descriptor.id] ?? 0) }
        return out
    }
}
