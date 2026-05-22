import Foundation

enum SymbolEncoder {
    // MARK: Tencent (qt.gtimg.cn)

    /// "sh600519" / "sz000001" / "hk00700" / "usAAPL"
    static func tencent(_ s: SymbolID) -> String? {
        switch s.market {
        case .a:
            return aSharePrefix(s.code).map { "\($0)\(s.code)" }
        case .hk:
            return "hk\(s.code.leftPadded(toLength: 5, withPad: "0"))"
        case .us:
            return "us\(s.code.uppercased())"
        }
    }

    // MARK: EastMoney (push2.eastmoney.com)

    /// "1.600519" / "0.000001" / "116.00700" / "105.AAPL"
    static func eastMoney(_ s: SymbolID) -> String? {
        switch s.market {
        case .a:
            switch aShareExchange(s.code) {
            case "sh": return "1.\(s.code)"
            case "sz": return "0.\(s.code)"
            default:   return nil
            }
        case .hk:
            return "116.\(s.code.leftPadded(toLength: 5, withPad: "0"))"
        case .us:
            // 默认 105 (NASDAQ);若不识别再让上层 fallback
            return "105.\(s.code.uppercased())"
        }
    }

    // MARK: Yahoo Finance

    /// "AAPL" / "0700.HK" / "600519.SS" / "000001.SZ"
    static func yahoo(_ s: SymbolID) -> String? {
        switch s.market {
        case .a:
            switch aShareExchange(s.code) {
            case "sh": return "\(s.code).SS"
            case "sz": return "\(s.code).SZ"
            default:   return nil
            }
        case .hk:
            return "\(s.code.leftPadded(toLength: 4, withPad: "0")).HK"
        case .us:
            return s.code.uppercased()
        }
    }

    /// 反向(Yahoo → SymbolID)。供解析回写。
    static func decodeYahoo(_ yahooSymbol: String) -> SymbolID? {
        if yahooSymbol.hasSuffix(".SS") {
            let code = String(yahooSymbol.dropLast(3))
            return SymbolID(code: code, market: .a)
        }
        if yahooSymbol.hasSuffix(".SZ") {
            let code = String(yahooSymbol.dropLast(3))
            return SymbolID(code: code, market: .a)
        }
        if yahooSymbol.hasSuffix(".HK") {
            let code = String(yahooSymbol.dropLast(3))
            return SymbolID(code: code, market: .hk)
        }
        return SymbolID(code: yahooSymbol, market: .us)
    }

    // MARK: Finnhub

    /// Finnhub 美股直接使用代码;A 股 / 港股需要付费档,这里只编码美股,其余返回 nil。
    static func finnhub(_ s: SymbolID) -> String? {
        switch s.market {
        case .us: return s.code.uppercased()
        case .a, .hk: return nil
        }
    }

    // MARK: helpers

    /// A 股代码 → "sh" / "sz"。返回 nil 表示不识别。
    /// 用 2 位前缀做主分类(避开 SSE 可转债 11x/13x 与 SZSE 基金 1xx 同首位字符歧义)。
    static func aShareExchange(_ code: String) -> String? {
        if code.count >= 2 {
            switch code.prefix(2) {
            // SSE:主板 6 / 科创板 68 / B 股 9 / 可转债 11/13 / ETF 50-58 / 基金
            case "60", "68", "11", "13",
                 "50", "51", "52", "53", "56", "58",
                 "90":
                return "sh"
            // SZSE:主板 00 / 中小 002 / 创业板 30 / B 股 20 / 债 12 / ETF/LOF 15-18
            case "00", "30", "20",
                 "12", "15", "16", "17", "18":
                return "sz"
            // 北交所(本期不支持)
            case "43", "83", "87", "88", "92":
                return nil
            default:
                break
            }
        }
        guard let first = code.first else { return nil }
        switch first {
        case "6", "9", "5": return "sh"
        case "0", "2", "3", "1": return "sz"
        default: return nil
        }
    }

    static func aSharePrefix(_ code: String) -> String? {
        aShareExchange(code)
    }
}

extension String {
    func leftPadded(toLength: Int, withPad: Character) -> String {
        if count >= toLength { return self }
        return String(repeating: String(withPad), count: toLength - count) + self
    }
}
