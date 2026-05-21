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
    static func aShareExchange(_ code: String) -> String? {
        guard let first = code.first else { return nil }
        switch first {
        case "6", "9":      return "sh"             // 沪市主板、B股
        case "0", "2", "3": return "sz"             // 深市主板、中小、创业
        case "4", "8":      return nil              // 北交所(本期不支持)
        default:            return nil
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
