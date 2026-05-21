import Foundation

/// AlertEngine 根据最新行情判定预警规则触发。
@MainActor
final class AlertEngine {
    private let alertsRepo: AlertsRepository
    private let notifier: NotificationService
    private let clock: MarketClock

    init(alertsRepo: AlertsRepository, notifier: NotificationService, clock: MarketClock = MarketClock()) {
        self.alertsRepo = alertsRepo
        self.notifier = notifier
        self.clock = clock
    }

    @discardableResult
    func evaluate(quotes: [SymbolID: Quote]) -> [Alert] {
        guard let alerts = try? alertsRepo.active() else { return [] }
        var triggered: [Alert] = []
        let now = Date()
        let todayKey = Alert.todayKey()

        for alert in alerts {
            guard let quote = quotes[alert.symbol] else { continue }
            guard passesGuards(alert: alert, now: now, todayKey: todayKey) else { continue }
            guard matchesAllConditions(alert: alert, quote: quote) else { continue }

            triggered.append(alert)
            do {
                try alertsRepo.markTriggered(id: alert.id, at: now, todayKey: todayKey)
            } catch {
                Log.app.warning("markTriggered failed: \(String(describing: error), privacy: .public)")
            }
            fire(alert: alert, quote: quote)
        }
        return triggered
    }

    /// 所有非条件类的限制(冷却 / 每日上限 / 时间窗口)。
    private func passesGuards(alert: Alert, now: Date, todayKey: String) -> Bool {
        if alert.inCooldown(at: now) { return false }

        // 每日上限
        if let cap = alert.maxTriggersPerDay {
            let countForToday = alert.lastTriggerDay == todayKey ? alert.triggerCountToday : 0
            if countForToday >= cap { return false }
        }

        // 仅工作日(Asia/Shanghai 时区,周末跳过)
        if alert.weekdaysOnly {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
            let weekday = cal.component(.weekday, from: now)
            // 1 = Sunday, 7 = Saturday
            if weekday == 1 || weekday == 7 { return false }
        }

        // 仅交易时段(任一市场开盘即可,因为多市场场景下可能有错峰)
        if alert.tradingHoursOnly {
            if !clock.anyOpen(at: now) { return false }
        }

        return true
    }

    /// 主条件 + 可选副条件,按 ConditionLogic 组合。
    func matchesAllConditions(alert: Alert, quote: Quote) -> Bool {
        let primary = match(cond: alert.condition, threshold: alert.threshold, quote: quote)
        guard let secCond = alert.secondaryCondition,
              let secTh = alert.secondaryThreshold else {
            return primary
        }
        let secondary = match(cond: secCond, threshold: secTh, quote: quote)
        switch alert.conditionLogic {
        case .and: return primary && secondary
        case .or:  return primary || secondary
        }
    }

    func match(cond: AlertCondition, threshold: Decimal, quote: Quote) -> Bool {
        switch cond {
        case .priceAbove:     return quote.price >= threshold
        case .priceBelow:     return quote.price <= threshold
        case .changePctAbove: return Decimal(quote.changePct) >= threshold
        case .changePctBelow: return Decimal(quote.changePct) <= threshold
        }
    }

    private func fire(alert: Alert, quote: Quote) {
        let title = alert.name.isEmpty ? alert.symbol.code : alert.name
        let body = alertBody(alert: alert, quote: quote)
        notifier.send(
            identifier: "alert.\(alert.id.uuidString)",
            title: title,
            body: body
        )
        Log.app.info("alert fired: \(alert.symbol.description, privacy: .public)")
    }

    private func alertBody(alert: Alert, quote: Quote) -> String {
        let priceText = alert.symbol.market.defaultCurrency.format(quote.price)
        let pctText = String(format: "%+.2f%%", quote.changePct * 100)

        var parts: [String] = []
        parts.append(describe(cond: alert.condition, threshold: alert.threshold, price: priceText, pct: pctText, alert: alert))
        if let secCond = alert.secondaryCondition, let secTh = alert.secondaryThreshold {
            let glue = alert.conditionLogic == .and ? " & " : " | "
            parts.append(glue + describe(cond: secCond, threshold: secTh, price: priceText, pct: pctText, alert: alert))
        }
        return parts.joined()
    }

    private func describe(cond: AlertCondition, threshold: Decimal, price: String, pct: String, alert: Alert) -> String {
        switch cond {
        case .priceAbove:
            return String(format: L("alert.body.priceAbove", comment: ""),
                          price, alert.symbol.market.defaultCurrency.format(threshold))
        case .priceBelow:
            return String(format: L("alert.body.priceBelow", comment: ""),
                          price, alert.symbol.market.defaultCurrency.format(threshold))
        case .changePctAbove:
            return String(format: L("alert.body.changePctAbove", comment: ""),
                          pct, decimalToPercent(threshold))
        case .changePctBelow:
            return String(format: L("alert.body.changePctBelow", comment: ""),
                          pct, decimalToPercent(threshold))
        }
    }

    private func decimalToPercent(_ d: Decimal) -> String {
        let v = NSDecimalNumber(decimal: d).doubleValue * 100
        return String(format: "%+.2f%%", v)
    }
}
