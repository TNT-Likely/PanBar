import Foundation

/// 把大数字压成菜单栏能装的简写。
///
/// 单位选择跟着货币:
///   - CNY:0-9999 → 直接显示; ≥1万 → 万; ≥1亿 → 亿
///   - USD/HKD:0-999 → 直接显示; ≥1K → K; ≥1M → M; ≥1B → B
///
/// 这么做是因为「-¥359K」一个中国用户大脑要换算一次,「-¥36万」一眼就懂;
/// 反过来给美国用户看「+$1.2万」也是迷的。
enum NumberAbbreviation {
    /// 返回不含符号 / 货币的纯简写字符串。
    static func format(_ value: Decimal, currency: Currency) -> String {
        let n = NSDecimalNumber(decimal: value.magnitude).doubleValue
        switch currency {
        case .cny: return formatChinese(n)
        case .usd, .hkd: return formatWestern(n)
        }
    }

    /// 货币 + 简写:负号在最前,货币符号在数字前(-¥36万 / +$1.2K)。
    static func formatCurrency(_ value: Decimal, currency: Currency) -> String {
        let sign = value < 0 ? "-" : ""
        return sign + currency.symbol + format(value, currency: currency)
    }

    // MARK: 私有

    private static func formatChinese(_ n: Double) -> String {
        if n < 10_000 {
            // 1 万以下不加单位,直接显示整数(菜单栏窄,省点位)
            return String(format: "%.0f", n)
        }
        if n < 100_000_000 {
            // 万级
            let v = n / 10_000
            if v < 10 { return String(format: "%.2f万", v) }   // 1.23万
            if v < 100 { return String(format: "%.1f万", v) }  // 12.3万
            return String(format: "%.0f万", v)                 // 123万 / 1234万
        }
        // 亿级
        let v = n / 100_000_000
        if v < 10 { return String(format: "%.2f亿", v) }
        if v < 100 { return String(format: "%.1f亿", v) }
        return String(format: "%.0f亿", v)
    }

    private static func formatWestern(_ n: Double) -> String {
        if n < 1000 {
            return String(format: "%.2f", n)
        }
        if n < 1_000_000 {
            let v = n / 1000
            if v < 10 { return String(format: "%.2fK", v) }
            if v < 100 { return String(format: "%.1fK", v) }
            return String(format: "%.0fK", v)
        }
        if n < 1_000_000_000 {
            let v = n / 1_000_000
            if v < 10 { return String(format: "%.2fM", v) }
            if v < 100 { return String(format: "%.1fM", v) }
            return String(format: "%.0fM", v)
        }
        let v = n / 1_000_000_000
        if v < 10 { return String(format: "%.2fB", v) }
        if v < 100 { return String(format: "%.1fB", v) }
        return String(format: "%.0fB", v)
    }
}
