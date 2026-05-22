import Foundation

/// 搜索结果的一条匹配。
struct SymbolSearchResult: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let symbol: SymbolID
    let name: String

    init(symbol: SymbolID, name: String) {
        self.id = symbol.description
        self.symbol = symbol
        self.name = name
    }
}

/// 用腾讯 smartbox 做股票搜索(代码 / 名称 / 拼音)。
/// 接口:`https://smartbox.gtimg.cn/s3/?v=2&q={query}&t=all&c=1`
///
/// 返回(GBK):
///   `v_hint="us~aapl.oq~\u82f9\u679c~pg~GP^hk~00700~\u817e\u8baf\u63a7\u80a1~txkg~GP^...";`
///
/// 格式说明:
///   - items 用 `^` 分隔
///   - 每个 item 5 字段用 `~` 分隔:
///       [0] market = sh / sz / hk / us
///       [1] code   = 数字 / "aapl.oq"
///       [2] name   = JSON \uXXXX 转义的中文
///       [3] pinyin abbrev
///       [4] type   = GP / GP-A(股票)/ ZS(指数)/ QZ(权证)/ JJ(基金)
///
///   - 空结果:`v_hint="N";`
final class SymbolSearch: Sendable {
    let http: HTTPClient

    /// 允许的类型:股票(GP*) + 基金 / ETF / LOF / 可转债。
    /// 腾讯 smartbox 返回的 type 字段可能是 GP / GP-A / GP-B / ETF / LOF / JJ / ZQ 等;
    /// 过滤掉 ZS(指数,在大盘里展示)/ QZ(权证)就够了。
    private static let allowedTypes: Set<String> = [
        "GP", "GP-A", "GP-B",
        "ETF", "LOF", "JJ", "ZQ",
    ]

    init(http: HTTPClient = HTTPClient(defaultHeaders: ["Referer": "https://gu.qq.com/"])) {
        self.http = http
    }

    func search(_ query: String) async throws -> [SymbolSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        guard let url = URL(string: "https://smartbox.gtimg.cn/s3/?v=2&q=\(encoded)&t=all&c=1") else { return [] }
        let text = try await http.fetchString(url: url, encoding: GBKDecoder.encoding)
        return parse(text)
    }

    func parse(_ raw: String) -> [SymbolSearchResult] {
        guard let eqIdx = raw.firstIndex(of: "=") else { return [] }
        let after = raw[raw.index(after: eqIdx)...]
        let stripped = after.trimmingCharacters(in: CharacterSet(charactersIn: " ;\"\n\r"))
        // 空结果用 "N" 标识
        if stripped.isEmpty || stripped == "N" { return [] }

        let items = stripped.split(separator: "^").map(String.init)
        var seen = Set<String>()
        var out: [SymbolSearchResult] = []

        for item in items {
            let fields = item.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 5 else { continue }
            let marketStr = fields[0]
            let rawCode = fields[1]
            let nameRaw = fields[2]
            let type = fields[4]

            guard Self.allowedTypes.contains(type) else { continue }
            guard let sid = decodeSymbol(market: marketStr, rawCode: rawCode) else { continue }
            if !seen.insert(sid.storageKey).inserted { continue }

            let name = decodeJSONString(nameRaw)
            out.append(SymbolSearchResult(symbol: sid, name: name.isEmpty ? sid.code : name))
            if out.count >= 30 { break }
        }
        return out
    }

    private func decodeSymbol(market: String, rawCode: String) -> SymbolID? {
        let m = market.lowercased()
        let code = rawCode.trimmingCharacters(in: .whitespaces)
        switch m {
        case "sh", "sz":
            return SymbolID(code: code, market: .a)
        case "hk":
            // HK 5 位数,前导补零(腾讯可能返回 "00700" 或 "700")
            let padded = code.leftPadded(toLength: 5, withPad: "0")
            return SymbolID(code: padded, market: .hk)
        case "us":
            // 去掉 .oq / .n / .ps 等后缀,转大写
            let body: String
            if let dot = code.firstIndex(of: ".") {
                body = String(code[..<dot])
            } else {
                body = code
            }
            return SymbolID(code: body.uppercased(), market: .us)
        default:
            return nil
        }
    }

    /// 解码 JSON 风格的 \uXXXX 转义。
    /// 包一层引号丢给 JSONDecoder 是最稳的做法。
    private func decodeJSONString(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\"", with: "\\\"")
        let wrapped = "\"\(escaped)\""
        guard let data = wrapped.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(String.self, from: data) else {
            return s
        }
        return decoded
    }
}
