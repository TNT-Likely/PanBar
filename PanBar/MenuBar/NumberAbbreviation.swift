import Foundation

/// 把大数字压成菜单栏能装的简写:
///   1234     → 1.2K
///   12345    → 12K
///   123456   → 123K
///   1234567  → 1.2M
///   12345678 → 12M
///   123456789→ 123M
///   1e9+     → 1.2B
///
/// 负号 / 货币符号由调用方拼接。
enum NumberAbbreviation {
    /// 返回不含符号 / 货币的纯简写字符串。
    static func format(_ value: Decimal, maxFractionDigits: Int = 1) -> String {
        let n = NSDecimalNumber(decimal: value.magnitude).doubleValue
        if n < 1000 {
            // 小数字保留 2 位
            return String(format: "%.2f", n)
        }
        if n < 10_000 {
            // 1.23K
            return String(format: "%.2fK", n / 1000)
        }
        if n < 1_000_000 {
            // 12K / 123K(整数即可,菜单栏小)
            return String(format: "%.0fK", n / 1000)
        }
        if n < 10_000_000 {
            // 1.23M
            return String(format: "%.2fM", n / 1_000_000)
        }
        if n < 1_000_000_000 {
            // 12M / 123M
            return String(format: "%.0fM", n / 1_000_000)
        }
        if n < 10_000_000_000 {
            return String(format: "%.2fB", n / 1_000_000_000)
        }
        return String(format: "%.0fB", n / 1_000_000_000)
    }

    /// 货币 + 简写。符号在最前(¥ / $ / HK$),负号在最前(-¥1.2K)。
    static func formatCurrency(_ value: Decimal, currency: Currency) -> String {
        let sign = value < 0 ? "-" : ""
        return sign + currency.symbol + format(value)
    }
}
