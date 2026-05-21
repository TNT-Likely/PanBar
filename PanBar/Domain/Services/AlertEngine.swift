import Foundation

/// AlertEngine 根据最新行情判定预警规则触发。
/// 由 QuoteRefresher 在每次 tick 后调用 `evaluate(:_:)`。
@MainActor
final class AlertEngine {
    private let alertsRepo: AlertsRepository
    private let notifier: NotificationService

    init(alertsRepo: AlertsRepository, notifier: NotificationService) {
        self.alertsRepo = alertsRepo
        self.notifier = notifier
    }

    /// 评估所有活跃规则。命中后:
    ///  1. 持久化 lastTriggeredAt
    ///  2. 触发本地通知
    /// 在冷却期内的规则跳过。
    @discardableResult
    func evaluate(quotes: [SymbolID: Quote]) -> [Alert] {
        guard let alerts = try? alertsRepo.active() else { return [] }
        var triggered: [Alert] = []
        let now = Date()

        for alert in alerts {
            guard let quote = quotes[alert.symbol] else { continue }
            if alert.inCooldown(at: now) { continue }
            guard matches(alert: alert, quote: quote) else { continue }

            triggered.append(alert)
            do {
                try alertsRepo.markTriggered(id: alert.id, at: now)
            } catch {
                Log.app.warning("markTriggered failed: \(String(describing: error), privacy: .public)")
            }
            fire(alert: alert, quote: quote)
        }
        return triggered
    }

    func matches(alert: Alert, quote: Quote) -> Bool {
        switch alert.condition {
        case .priceAbove:
            return quote.price >= alert.threshold
        case .priceBelow:
            return quote.price <= alert.threshold
        case .changePctAbove:
            return Decimal(quote.changePct) >= alert.threshold
        case .changePctBelow:
            return Decimal(quote.changePct) <= alert.threshold
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
        switch alert.condition {
        case .priceAbove:
            return String(format: L("alert.body.priceAbove", comment: ""),
                          priceText,
                          alert.symbol.market.defaultCurrency.format(alert.threshold))
        case .priceBelow:
            return String(format: L("alert.body.priceBelow", comment: ""),
                          priceText,
                          alert.symbol.market.defaultCurrency.format(alert.threshold))
        case .changePctAbove:
            return String(format: L("alert.body.changePctAbove", comment: ""),
                          pctText,
                          decimalToPercent(alert.threshold))
        case .changePctBelow:
            return String(format: L("alert.body.changePctBelow", comment: ""),
                          pctText,
                          decimalToPercent(alert.threshold))
        }
    }

    private func decimalToPercent(_ d: Decimal) -> String {
        let v = NSDecimalNumber(decimal: d).doubleValue * 100
        return String(format: "%+.2f%%", v)
    }
}
