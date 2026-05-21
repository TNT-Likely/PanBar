import Foundation

/// 各市场交易时段判定。本期使用静态规则,不处理节假日(后续 P2 加节假日表)。
enum MarketStatus: Equatable, Sendable {
    case open
    case lunchBreak
    case closed
}

struct MarketClock: Sendable {
    func status(_ market: Market, at date: Date = Date()) -> MarketStatus {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = market.timeZone

        let comps = cal.dateComponents([.weekday, .hour, .minute], from: date)
        let weekday = comps.weekday ?? 1
        let minutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)

        // 周末
        if weekday == 1 || weekday == 7 { return .closed }

        switch market {
        case .a:
            // 09:30-11:30 + 13:00-15:00
            if minutes >= 9 * 60 + 30 && minutes <= 11 * 60 + 30 { return .open }
            if minutes >= 13 * 60 && minutes <= 15 * 60 { return .open }
            if minutes > 11 * 60 + 30 && minutes < 13 * 60 { return .lunchBreak }
            return .closed
        case .hk:
            // 09:30-12:00 + 13:00-16:00
            if minutes >= 9 * 60 + 30 && minutes <= 12 * 60 { return .open }
            if minutes >= 13 * 60 && minutes <= 16 * 60 { return .open }
            if minutes > 12 * 60 && minutes < 13 * 60 { return .lunchBreak }
            return .closed
        case .us:
            // 09:30-16:00 (no lunch break)
            if minutes >= 9 * 60 + 30 && minutes <= 16 * 60 { return .open }
            return .closed
        }
    }

    /// 任一市场开盘则视为活跃。
    func anyOpen(at date: Date = Date()) -> Bool {
        for m in Market.allCases where status(m, at: date) == .open {
            return true
        }
        return false
    }
}
