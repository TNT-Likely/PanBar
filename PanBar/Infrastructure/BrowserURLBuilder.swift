import Foundation

/// 把 SymbolID 拼成第三方网站 URL。模板内置三套,可自定义。
enum BrowserURLBuilder {
    static let templateKey = "browser_url_template"

    enum Template: String, CaseIterable, Identifiable, Codable {
        case xueqiu
        case yahoo
        case tradingview

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .xueqiu:      return "雪球 / Xueqiu"
            case .yahoo:       return "Yahoo Finance"
            case .tradingview: return "TradingView"
            }
        }
    }

    static func url(template: String, symbol: SymbolID) -> URL? {
        let key = Template(rawValue: template) ?? .xueqiu
        switch key {
        case .xueqiu:      return xueqiu(symbol)
        case .yahoo:       return yahoo(symbol)
        case .tradingview: return tradingview(symbol)
        }
    }

    private static func xueqiu(_ s: SymbolID) -> URL? {
        let code: String
        switch s.market {
        case .a:
            switch SymbolEncoder.aShareExchange(s.code) {
            case "sh": code = "SH\(s.code)"
            case "sz": code = "SZ\(s.code)"
            default:   return nil
            }
        case .hk:
            code = s.code.leftPadded(toLength: 5, withPad: "0")
        case .us:
            code = s.code.uppercased()
        }
        return URL(string: "https://xueqiu.com/S/\(code)")
    }

    private static func yahoo(_ s: SymbolID) -> URL? {
        guard let symbol = SymbolEncoder.yahoo(s) else { return nil }
        guard let escaped = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://finance.yahoo.com/quote/\(escaped)")
    }

    private static func tradingview(_ s: SymbolID) -> URL? {
        let prefix: String
        let code: String
        switch s.market {
        case .a:
            switch SymbolEncoder.aShareExchange(s.code) {
            case "sh": prefix = "SSE";  code = s.code
            case "sz": prefix = "SZSE"; code = s.code
            default:   return nil
            }
        case .hk:
            prefix = "HKEX"
            code = s.code.leftPadded(toLength: 4, withPad: "0")
        case .us:
            prefix = "NASDAQ"   // 简化:统一走 NASDAQ,TV 大多自动 redirect
            code = s.code.uppercased()
        }
        return URL(string: "https://www.tradingview.com/symbols/\(prefix)-\(code)/")
    }
}
