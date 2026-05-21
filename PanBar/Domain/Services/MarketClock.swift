import Foundation

/// 各市场交易时段判定。
///
/// 默认规则:
///   - A 股:09:30-11:30 + 13:00-15:00(Asia/Shanghai),周六/日休市
///   - 港股:09:30-12:00 + 13:00-16:00(Asia/Shanghai),周六/日休市
///   - 美股:09:30-16:00(America/New_York),周六/日休市
///
/// 节假日:无法做到 100% 准确(没有可靠免费 API),依赖用户手动 override
/// (`market_override_<market>` 设置,格式 `YYYY-MM-DD:open|closed`),
/// 当 override 日期等于「该市场所在时区今天」时生效。
enum MarketStatus: Equatable, Sendable {
    case open
    case lunchBreak
    case closed
}

enum MarketOverride: String, Equatable, Sendable {
    case forceOpen = "open"
    case forceClosed = "closed"
}

final class MarketClock: @unchecked Sendable {
    private let settingsRepo: SettingsRepository?

    init(settingsRepo: SettingsRepository? = nil) {
        self.settingsRepo = settingsRepo
    }

    func status(_ market: Market, at date: Date = Date()) -> MarketStatus {
        // 1) 用户 override 优先
        switch overrideToday(for: market, at: date) {
        case .forceClosed:
            return .closed
        case .forceOpen:
            return statusByHours(market, at: date)  // 跳过周末检查,只看时段
        case nil:
            break
        }

        // 2) 周末
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = market.timeZone
        let weekday = cal.dateComponents([.weekday], from: date).weekday ?? 1
        if weekday == 1 || weekday == 7 { return .closed }

        return statusByHours(market, at: date)
    }

    /// 不考虑周末/节假日,仅根据时段判断(午休 / 开盘 / 收盘)。
    /// forceOpen 用户认为今天该开,我们就跳过周末检查走这里。
    private func statusByHours(_ market: Market, at date: Date) -> MarketStatus {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = market.timeZone
        let comps = cal.dateComponents([.hour, .minute], from: date)
        let minutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)

        switch market {
        case .a:
            if minutes >= 9 * 60 + 30 && minutes <= 11 * 60 + 30 { return .open }
            if minutes >= 13 * 60 && minutes <= 15 * 60 { return .open }
            if minutes > 11 * 60 + 30 && minutes < 13 * 60 { return .lunchBreak }
            return .closed
        case .hk:
            if minutes >= 9 * 60 + 30 && minutes <= 12 * 60 { return .open }
            if minutes >= 13 * 60 && minutes <= 16 * 60 { return .open }
            if minutes > 12 * 60 && minutes < 13 * 60 { return .lunchBreak }
            return .closed
        case .us:
            if minutes >= 9 * 60 + 30 && minutes <= 16 * 60 { return .open }
            return .closed
        }
    }

    /// 任一市场开盘则视为活跃。午休不算活跃(行情确实不动)。
    func anyOpen(at date: Date = Date()) -> Bool {
        for m in Market.allCases where status(m, at: date) == .open {
            return true
        }
        return false
    }

    // MARK: - Override(节假日纠错)

    /// 读取 settings 里这个市场的 override,仅当 override 日期匹配「该市场时区下今天」时才生效。
    /// 隔天会因为日期对不上自动失效。
    func overrideToday(for market: Market, at date: Date = Date()) -> MarketOverride? {
        guard let repo = settingsRepo,
              let raw = repo.string(SettingsRepository.Keys.marketOverride(market)) else { return nil }
        // 格式 "YYYY-MM-DD:open" / "YYYY-MM-DD:closed"
        let parts = raw.split(separator: ":")
        guard parts.count == 2 else { return nil }
        let savedDate = String(parts[0])
        guard savedDate == Self.dateString(date, tz: market.timeZone) else { return nil }
        return MarketOverride(rawValue: String(parts[1]))
    }

    static func dateString(_ date: Date, tz: TimeZone) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = tz
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
