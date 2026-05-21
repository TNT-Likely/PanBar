import SwiftUI

struct IndicesTab: View {
    @Environment(\.container) private var container
    @State private var quotes: [IndexQuote] = []
    @State private var loading: Bool = false
    @State private var error: String?
    @State private var lastFetched: Date?
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if quotes.isEmpty && loading {
                    ProgressView()
                        .padding(.vertical, 40)
                } else if quotes.isEmpty {
                    emptyState
                } else {
                    ForEach(quotes) { q in
                        IndexRow(quote: q)
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .frame(maxHeight: 320)
        .onAppear {
            startAutoRefresh()
        }
        .onDisappear {
            refreshTask?.cancel()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text(L("indices.empty", comment: ""))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            if let err = error {
                Text(err).font(.system(size: 10)).foregroundColor(.red).padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            await refresh()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { break }
                await refresh()
            }
        }
    }

    private func refresh() async {
        guard let container = container else { return }
        if loading { return }
        await MainActor.run { loading = true; error = nil }
        do {
            let result = try await container.indexService.fetchAll()
            await MainActor.run {
                self.quotes = result
                self.loading = false
                self.lastFetched = Date()
            }
        } catch {
            await MainActor.run {
                self.error = "\(error)"
                self.loading = false
            }
        }
    }
}

private struct IndexRow: View {
    let quote: IndexQuote

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
                    Text(signed(quote.change))
                        .font(.system(size: 10))
                        .foregroundColor(quote.change >= 0 ? .red : .green)
                        .monospacedDigit()
                    Text(String(format: "%+.2f%%", quote.changePct * 100))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(quote.change >= 0 ? .red : .green)
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
