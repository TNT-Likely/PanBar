import Foundation

/// 搜索结果的一条匹配。
struct SymbolSearchResult: Identifiable, Equatable, Hashable, Sendable {
    let id: String       // "a:600519"
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
/// 返回(GBK):`v_hint="GZMT~sh600519~贵州茅台~...|...";`
final class SymbolSearch: Sendable {
    let http: HTTPClient

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
        // raw: v_hint="...";  其中 "..." 可能是空,或者多条用 | 分隔
        guard let eqIdx = raw.firstIndex(of: "=") else { return [] }
        let after = raw[raw.index(after: eqIdx)...]
        let stripped = after.trimmingCharacters(in: CharacterSet(charactersIn: " ;\"\n\r"))
        if stripped.isEmpty { return [] }
        let items = stripped.split(separator: "|").map(String.init)
        var seen = Set<String>()
        var out: [SymbolSearchResult] = []
        for item in items {
            let fields = item.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3 else { continue }
            let fullCode = fields[1]
            let name = fields[2].trimmingCharacters(in: .whitespaces)
            guard let sid = decodeFullCode(fullCode) else { continue }
            if !seen.insert(sid.storageKey).inserted { continue }
            out.append(SymbolSearchResult(symbol: sid, name: name.isEmpty ? sid.code : name))
            if out.count >= 30 { break } // 上限
        }
        return out
    }

    private func decodeFullCode(_ s: String) -> SymbolID? {
        let lower = s.lowercased()
        if lower.hasPrefix("sh") || lower.hasPrefix("sz") {
            return SymbolID(code: String(s.dropFirst(2)), market: .a)
        }
        if lower.hasPrefix("hk") {
            return SymbolID(code: String(s.dropFirst(2)), market: .hk)
        }
        if lower.hasPrefix("us") {
            // 腾讯 us 代码后可能跟 .OQ / .N 后缀,统一去掉
            let body = String(s.dropFirst(2))
            if let dot = body.firstIndex(of: ".") {
                return SymbolID(code: String(body[..<dot]).uppercased(), market: .us)
            }
            return SymbolID(code: body.uppercased(), market: .us)
        }
        return nil
    }
}
