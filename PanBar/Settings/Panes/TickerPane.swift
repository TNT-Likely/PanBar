import SwiftUI

struct TickerPane: View {
    @Environment(\.container) private var container

    var body: some View {
        if let container = container {
            TickerPaneContent(container: container, prefs: container.tickerPrefs)
        } else {
            Text("Loading…")
        }
    }
}

private struct TickerPaneContent: View {
    let container: DependencyContainer
    @ObservedObject var prefs: TickerPreferences

    @State private var holdings: [Holding] = []
    @State private var watchlist: [WatchItem] = []

    var body: some View {
        Form {
            Section(header: Text(L("settings.ticker", comment: "")).font(.title3)) {
                Picker(L("settings.colorScheme", comment: ""), selection: $prefs.colorScheme) {
                    Text(L("scheme.east", comment: "")).tag(TickerColorScheme.east)
                    Text(L("scheme.west", comment: "")).tag(TickerColorScheme.west)
                    Text(L("scheme.mono", comment: "")).tag(TickerColorScheme.mono)
                }
                Picker(L("settings.scrollSpeed", comment: ""), selection: $prefs.scrollSpeed) {
                    ForEach(ScrollSpeed.allCases) { s in
                        Text(s.displayName).tag(s)
                    }
                }
                Toggle(L("settings.pauseOnHover", comment: ""), isOn: $prefs.pauseOnHover)
                Toggle(L("settings.pauseWhenClosed", comment: ""), isOn: $prefs.pauseWhenClosed)
                Stepper(value: $prefs.maxItems, in: 1...50) {
                    Text(String(format: L("settings.maxItems", comment: ""), prefs.maxItems))
                }
            }

            Section(header: Text(L("ticker.summarySection", comment: "")).font(.headline)) {
                Toggle(L("ticker.showTodayPnL", comment: ""), isOn: $prefs.showTodayPnL)
                Toggle(L("ticker.showTotalAssets", comment: ""), isOn: $prefs.showTotalAssets)
                Toggle(L("ticker.showAllTimePnL", comment: ""), isOn: $prefs.showAllTimePnL)
                Text(L("ticker.summaryHint", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text(L("ticker.indicesSection", comment: "")).font(.headline)) {
                ForEach(IndexCatalog.all) { desc in
                    Toggle(isOn: Binding(
                        get: { prefs.tickerIndexIDs.contains(desc.id) },
                        set: { newValue in
                            var s = prefs.tickerIndexIDs
                            if newValue { s.insert(desc.id) } else { s.remove(desc.id) }
                            prefs.tickerIndexIDs = s
                        }
                    )) {
                        HStack {
                            Text(desc.displayName)
                            marketBadge(desc.market)
                        }
                    }
                }
                Text(L("ticker.indicesHint", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text(L("ticker.holdingsSection", comment: "")).font(.headline)) {
                if holdings.isEmpty {
                    Text(L("holdings.empty", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(holdings) { h in
                        Toggle(isOn: bindingFor(holding: h)) {
                            HStack {
                                Text(h.symbol.market == .us ? h.symbol.code.uppercased() : h.symbol.code)
                                    .monospacedDigit()
                                Text(h.name)
                                    .foregroundColor(.secondary)
                                marketBadge(h.symbol.market)
                            }
                        }
                    }
                }
            }

            Section(header: Text(L("ticker.watchlistSection", comment: "")).font(.headline)) {
                if watchlist.isEmpty {
                    Text(L("watchlist.empty", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(watchlist) { w in
                        Toggle(isOn: bindingFor(watch: w)) {
                            HStack {
                                Text(w.symbol.market == .us ? w.symbol.code.uppercased() : w.symbol.code)
                                Text(w.name)
                                    .foregroundColor(.secondary)
                                marketBadge(w.symbol.market)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear(perform: reload)
    }

    private func marketBadge(_ m: Market) -> some View {
        Text(m.displayName)
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func reload() {
        holdings = (try? container.holdingsRepo.all()) ?? []
        watchlist = (try? container.watchlistRepo.all()) ?? []
    }

    private func bindingFor(holding: Holding) -> Binding<Bool> {
        Binding(
            get: { holding.inTicker },
            set: { newValue in
                var copy = holding
                copy.inTicker = newValue
                try? container.holdingsRepo.upsert(copy)
                reload()
                container.refresher.refreshNow()
            }
        )
    }

    private func bindingFor(watch: WatchItem) -> Binding<Bool> {
        Binding(
            get: { watch.inTicker },
            set: { newValue in
                var copy = watch
                copy.inTicker = newValue
                try? container.watchlistRepo.upsert(copy)
                reload()
                container.refresher.refreshNow()
            }
        )
    }
}
