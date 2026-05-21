import SwiftUI

struct IndicesTab: View {
    @EnvironmentObject var refresher: QuoteRefresher
    @EnvironmentObject var prefs: TickerPreferences

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if refresher.indexQuotes.isEmpty {
                    emptyState
                } else {
                    ForEach(refresher.indexQuotes) { q in
                        IndexRow(quote: q, scheme: prefs.colorScheme)
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .frame(maxHeight: 320)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text(L("indices.empty", comment: ""))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

private struct IndexRow: View {
    let quote: IndexQuote
    let scheme: TickerColorScheme

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(quote.descriptor.displayName)
                    .font(.system(size: 13, weight: .semibold))
                Text(quote.descriptor.market.displayName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatPrice(quote.price))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                HStack(spacing: 4) {
                    let color: Color = quote.change >= 0 ? SemanticColors.up(scheme: scheme) : SemanticColors.down(scheme: scheme)
                    Text(signed(quote.change))
                        .font(.system(size: 10))
                        .foregroundColor(color)
                        .monospacedDigit()
                    Text(String(format: "%+.2f%%", quote.changePct * 100))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(color)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func formatPrice(_ price: Decimal) -> String {
        let fmt = NumberFormatter()
        fmt.minimumFractionDigits = 2
        fmt.maximumFractionDigits = 2
        fmt.usesGroupingSeparator = true
        return fmt.string(from: NSDecimalNumber(decimal: price)) ?? "\(price)"
    }

    private func signed(_ value: Decimal) -> String {
        let sign = value >= 0 ? "+" : ""
        let fmt = NumberFormatter()
        fmt.minimumFractionDigits = 2
        fmt.maximumFractionDigits = 2
        return sign + (fmt.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)")
    }
}
