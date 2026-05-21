import Foundation

enum Currency: String, Codable, CaseIterable, Sendable {
    case cny = "CNY"
    case usd = "USD"
    case hkd = "HKD"

    var symbol: String {
        switch self {
        case .cny: return "¥"
        case .usd: return "$"
        case .hkd: return "HK$"
        }
    }

    func format(_ value: Decimal, fractionDigits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        formatter.numberStyle = .decimal
        let n = NSDecimalNumber(decimal: value)
        let text = formatter.string(from: n) ?? "\(value)"
        return "\(symbol)\(text)"
    }
}
