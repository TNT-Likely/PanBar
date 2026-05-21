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

    /// 大盘指数的浏览器 URL。code 空间和股票冲突(000001 是上证指数也是平安银行),
    /// 所以按 IndexDescriptor.id 单独维护映射。
    static func url(template: String, index: IndexDescriptor) -> URL? {
        let key = Template(rawValue: template) ?? .xueqiu
        switch key {
        case .xueqiu:
            switch index.id {
            case "SH000001": return URL(string: "https://xueqiu.com/S/SH000001")
            case "SZ399001": return URL(string: "https://xueqiu.com/S/SZ399001")
            case "SZ399006": return URL(string: "https://xueqiu.com/S/SZ399006")
            case "SH000300": return URL(string: "https://xueqiu.com/S/SH000300")
            case "HSI":      return URL(string: "https://xueqiu.com/S/HKHSI")
            case "DJIA":     return URL(string: "https://xueqiu.com/S/.DJI")
            case "NDX":      return URL(string: "https://xueqiu.com/S/.IXIC")
            case "SPX":      return URL(string: "https://xueqiu.com/S/.INX")
            default: return nil
            }
        case .yahoo:
            let sym: String
            switch index.id {
            case "SH000001": sym = "000001.SS"
            case "SZ399001": sym = "399001.SZ"
            case "SZ399006": sym = "399006.SZ"
            case "SH000300": sym = "000300.SS"
            case "HSI":      sym = "%5EHSI"
            case "DJIA":     sym = "%5EDJI"
            case "NDX":      sym = "%5ENDX"
            case "SPX":      sym = "%5EGSPC"
            default: return nil
            }
            return URL(string: "https://finance.yahoo.com/quote/\(sym)")
        case .tradingview:
            let path: String
            switch index.id {
            case "SH000001": path = "SSE-000001"
            case "SZ399001": path = "SZSE-399001"
            case "SZ399006": path = "SZSE-399006"
            case "SH000300": path = "SSE-000300"
            case "HSI":      path = "HSI-HSI"
            case "DJIA":     path = "DJ-DJI"
            case "NDX":      path = "NASDAQ-NDX"
            case "SPX":      path = "SP-SPX"
            default: return nil
            }
            return URL(string: "https://www.tradingview.com/symbols/\(path)/")
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
