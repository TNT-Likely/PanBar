import Foundation

/// 腾讯财经 qt.gtimg.cn 接口实现。支持 A/HK/US 批量混合查询。
///
/// 返回示例(GBK):
///     v_sh600519="1~贵州茅台~600519~1685.00~1670.50~1675.00~...";
///
/// 字段索引(0-based):
///   - 1: name
///   - 3: current price
///   - 4: prev close
///   - 5: open
///   - 6: volume (hands)
///   - 30: time string (yyyyMMddHHmmss)
///   - 33: pe
struct TencentProvider: QuoteProvider {
    let id = "tencent"
    let supportedMarkets: Set<Market> = [.a, .hk, .us]

    let http: HTTPClient

    init(http: HTTPClient = HTTPClient(defaultHeaders: ["Referer": "https://gu.qq.com/"])) {
        self.http = http
    }

    func fetch(_ symbols: [SymbolID]) async throws -> [SymbolID: Quote] {
        guard !symbols.isEmpty else { return [:] }

        // 拼接 provider-specific 编码;同时记录回写映射。
        var encodedPairs: [(String, SymbolID)] = []
        for s in symbols {
            if let enc = SymbolEncoder.tencent(s) {
                encodedPairs.append((enc, s))
            } else {
                Log.quote.warning("Tencent: cannot encode \(s.description, privacy: .public)")
            }
        }
        guard !encodedPairs.isEmpty else { return [:] }

        let codesParam = encodedPairs.map { $0.0 }.joined(separator: ",")
        var comps = URLComponents(string: "https://qt.gtimg.cn/")!
        comps.queryItems = [URLQueryItem(name: "q", value: codesParam)]
        guard let url = comps.url else { throw ProviderError.empty }

        let text = try await http.fetchString(url: url, encoding: GBKDecoder.encoding)
        return parse(text, encodedPairs: encodedPairs)
    }

    func parse(_ text: String, encodedPairs: [(String, SymbolID)]) -> [SymbolID: Quote] {
        let encodedMap = Dictionary(uniqueKeysWithValues: encodedPairs)
        var result: [SymbolID: Quote] = [:]
        let lines = text.split(whereSeparator: { $0 == "\n" || $0 == ";" })
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("v_") else { continue }
            guard let eqIdx = line.firstIndex(of: "=") else { continue }
            let encoded = String(line[line.index(line.startIndex, offsetBy: 2)..<eqIdx])
            guard let symbolID = encodedMap[encoded] else { continue }

            // value 形如 "1~Name~code~price~..."
            let valueRaw = line[line.index(after: eqIdx)...]
            let stripped = valueRaw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let fields = stripped.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 7 else { continue }

            let name = fields[safe: 1] ?? symbolID.code
            let price = Decimal(string: fields[safe: 3] ?? "0") ?? 0
            let prevClose = Decimal(string: fields[safe: 4] ?? "0") ?? 0
            let open = Decimal(string: fields[safe: 5] ?? "")
            let volume = Decimal(string: fields[safe: 6] ?? "")
            let high = Decimal(string: fields[safe: 33] ?? "")
            let low = Decimal(string: fields[safe: 34] ?? "")
            let timestamp = parseTencentTime(fields[safe: 30]) ?? Date()

            result[symbolID] = Quote(
                symbol: symbolID,
                name: name.isEmpty ? symbolID.code : name,
                price: price,
                prevClose: prevClose,
                open: open,
                high: high,
                low: low,
                volume: volume,
                currency: symbolID.market.defaultCurrency,
                timestamp: timestamp,
                isClosed: false
            )
        }
        return result
    }

    private func parseTencentTime(_ s: String?) -> Date? {
        guard let s = s, s.count >= 14 else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMddHHmmss"
        fmt.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return fmt.date(from: String(s.prefix(14)))
    }
}

extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}
