import SwiftUI

struct IndicesTab: View {
    @Environment(\.container) private var container
    @EnvironmentObject var prefs: TickerPreferences
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
                        IndexRow(quote: q, scheme: prefs.colorScheme)
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
            Image(systemName: error == nil ? "chart.line.uptrend.xyaxis" : "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text(error == nil ? L("indices.empty", comment: "") : L("indices.failed", comment: ""))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            if let err = error {
                Text(err).font(.system(size: 10)).foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                Button(L("action.retry", comment: "")) {
                    Task { await refresh() }
                }
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            // 始终先立即拉一次
            await refresh()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { break }
                await refresh()
            }
        }
    }

    private func refresh() async {
        diag("refresh start")
        guard let container = container else {
            diag("container is nil")
            return
        }
        await MainActor.run { loading = true; error = nil }
        diag("calling indexService.fetchAll()…")
        do {
            let result = try await container.indexService.fetchAll()
            diag("got \(result.count) quotes")
            await MainActor.run {
                self.quotes = result
                self.loading = false
                self.lastFetched = Date()
                if result.isEmpty {
                    self.error = "Empty response (parser matched 0 items)"
                }
            }
        } catch {
            let msg = "\(error)"
            diag("error: \(msg)")
            await MainActor.run {
                self.error = msg
                self.loading = false
            }
        }
    }

    private func diag(_ msg: String) {
        let line = "[\(Date())] IndicesTab: \(msg)\n"
        let url = URL(fileURLWithPath: "/tmp/panbar-indices.log")
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
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
