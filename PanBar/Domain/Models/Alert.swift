import Foundation

enum AlertCondition: String, Codable, CaseIterable, Sendable {
    case priceAbove          // 价格 ≥ 阈值
    case priceBelow          // 价格 ≤ 阈值
    case changePctAbove      // 日涨跌幅 ≥ 阈值(小数 0.05 = 5%)
    case changePctBelow

    var displayName: String {
        switch self {
        case .priceAbove:     return L("alert.cond.priceAbove", comment: "")
        case .priceBelow:     return L("alert.cond.priceBelow", comment: "")
        case .changePctAbove: return L("alert.cond.changePctAbove", comment: "")
        case .changePctBelow: return L("alert.cond.changePctBelow", comment: "")
        }
    }

    var isPercent: Bool {
        switch self {
        case .changePctAbove, .changePctBelow: return true
        case .priceAbove, .priceBelow:         return false
        }
    }
}

enum ConditionLogic: String, Codable, CaseIterable, Sendable {
    case and, or
    var displayName: String {
        switch self {
        case .and: return L("alert.logic.and", comment: "")
        case .or:  return L("alert.logic.or", comment: "")
        }
    }
}

struct Alert: Equatable, Codable, Sendable, Identifiable {
    let id: UUID
    var symbol: SymbolID
    var name: String

    // 主条件
    var condition: AlertCondition
    var threshold: Decimal

    // 可选副条件
    var secondaryCondition: AlertCondition?
    var secondaryThreshold: Decimal?
    var conditionLogic: ConditionLogic

    var isActive: Bool
    var lastTriggeredAt: Date?
    var cooldownSeconds: Int

    // 频率 + 时间窗口
    var maxTriggersPerDay: Int?            // nil = 无限
    var triggerCountToday: Int
    var lastTriggerDay: String?            // "YYYY-MM-DD",每过新一天重置 count
    var tradingHoursOnly: Bool
    var weekdaysOnly: Bool

    var createdAt: Date

    init(
        id: UUID = UUID(),
        symbol: SymbolID,
        name: String,
        condition: AlertCondition,
        threshold: Decimal,
        secondaryCondition: AlertCondition? = nil,
        secondaryThreshold: Decimal? = nil,
        conditionLogic: ConditionLogic = .and,
        isActive: Bool = true,
        lastTriggeredAt: Date? = nil,
        cooldownSeconds: Int = 300,
        maxTriggersPerDay: Int? = nil,
        triggerCountToday: Int = 0,
        lastTriggerDay: String? = nil,
        tradingHoursOnly: Bool = false,
        weekdaysOnly: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.condition = condition
        self.threshold = threshold
        self.secondaryCondition = secondaryCondition
        self.secondaryThreshold = secondaryThreshold
        self.conditionLogic = conditionLogic
        self.isActive = isActive
        self.lastTriggeredAt = lastTriggeredAt
        self.cooldownSeconds = cooldownSeconds
        self.maxTriggersPerDay = maxTriggersPerDay
        self.triggerCountToday = triggerCountToday
        self.lastTriggerDay = lastTriggerDay
        self.tradingHoursOnly = tradingHoursOnly
        self.weekdaysOnly = weekdaysOnly
        self.createdAt = createdAt
    }

    func inCooldown(at date: Date = Date()) -> Bool {
        guard let last = lastTriggeredAt else { return false }
        return date.timeIntervalSince(last) < TimeInterval(cooldownSeconds)
    }

    /// 当前日期(market 本地时区,A 股用上海)
    static func todayKey(in tz: TimeZone = TimeZone(identifier: "Asia/Shanghai")!) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = tz
        return fmt.string(from: Date())
    }
}
