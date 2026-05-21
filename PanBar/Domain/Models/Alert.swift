import Foundation

enum AlertCondition: String, Codable, CaseIterable, Sendable {
    case priceAbove          // 价格 ≥ 阈值
    case priceBelow          // 价格 ≤ 阈值
    case changePctAbove      // 日涨跌幅 ≥ 阈值 (0.05 = 5%)
    case changePctBelow      // 日涨跌幅 ≤ 阈值

    var displayName: String {
        switch self {
        case .priceAbove:     return L("alert.cond.priceAbove", comment: "")
        case .priceBelow:     return L("alert.cond.priceBelow", comment: "")
        case .changePctAbove: return L("alert.cond.changePctAbove", comment: "")
        case .changePctBelow: return L("alert.cond.changePctBelow", comment: "")
        }
    }

    /// 阈值是百分数还是绝对价格。
    var isPercent: Bool {
        switch self {
        case .changePctAbove, .changePctBelow: return true
        case .priceAbove, .priceBelow:         return false
        }
    }
}

struct Alert: Equatable, Codable, Sendable, Identifiable {
    let id: UUID
    var symbol: SymbolID
    var name: String
    var condition: AlertCondition
    /// 阈值;若是百分比条件,使用小数(0.05 = 5%)。
    var threshold: Decimal
    var isActive: Bool
    var lastTriggeredAt: Date?
    /// 冷却秒数,默认 300。在此期间同条件不会再次触发。
    var cooldownSeconds: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        symbol: SymbolID,
        name: String,
        condition: AlertCondition,
        threshold: Decimal,
        isActive: Bool = true,
        lastTriggeredAt: Date? = nil,
        cooldownSeconds: Int = 300,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.condition = condition
        self.threshold = threshold
        self.isActive = isActive
        self.lastTriggeredAt = lastTriggeredAt
        self.cooldownSeconds = cooldownSeconds
        self.createdAt = createdAt
    }

    /// 在冷却中?
    func inCooldown(at date: Date = Date()) -> Bool {
        guard let last = lastTriggeredAt else { return false }
        return date.timeIntervalSince(last) < TimeInterval(cooldownSeconds)
    }
}
