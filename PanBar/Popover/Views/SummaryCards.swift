import SwiftUI

struct SummaryCards: View {
    let snapshot: PortfolioSnapshot
    @EnvironmentObject var prefs: TickerPreferences

    var body: some View {
        HStack(spacing: 8) {
            card(
                label: L("summary.today", comment: ""),
                value: signed(snapshot.todayPnL, currency: snapshot.baseCurrency),
                sub: pct(snapshot.todayPnLPct),
                tone: tone(for: snapshot.todayPnL),
                featured: false
            )
            card(
                label: L("summary.allTime", comment: ""),
                value: signed(snapshot.allTimePnL, currency: snapshot.baseCurrency),
                sub: pct(snapshot.allTimePnLPct),
                tone: tone(for: snapshot.allTimePnL),
                featured: false
            )
            card(
                label: L("summary.totalAssets", comment: ""),
                value: snapshot.baseCurrency.format(snapshot.totalAssets),
                sub: "\(snapshot.baseCurrency.rawValue) · " + String(format: L("summary.positions", comment: ""), snapshot.positions.count),
                tone: .neutral,
                featured: true
            )
        }
    }

    private enum Tone { case up, down, neutral }

    private func tone(for value: Decimal) -> Tone {
        if value > 0 { return .up }
        if value < 0 { return .down }
        return .neutral
    }

    private func toneColor(_ t: Tone) -> Color {
        switch t {
        case .up:      return SemanticColors.up(scheme: prefs.colorScheme)
        case .down:    return SemanticColors.down(scheme: prefs.colorScheme)
        case .neutral: return .primary
        }
    }

    private func signed(_ value: Decimal, currency: Currency) -> String {
        let sign = value >= 0 ? "+" : "-"
        let abs = value.magnitude
        return sign + currency.format(abs)
    }

    private func pct(_ value: Double) -> String {
        String(format: "%+.2f%%", value * 100)
    }

    private func card(label: String, value: String, sub: String, tone: Tone, featured: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(featured ? .secondary : .secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .foregroundColor(featured ? .primary : toneColor(tone))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(sub)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(featured ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}
