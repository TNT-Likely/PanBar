import SwiftUI

struct TickerPane: View {
    @Environment(\.container) private var container

    var body: some View {
        if let container = container {
            TickerPaneContent(container: container, prefs: container.tickerPrefs)
        } else {
            Text(L("loading", comment: ""))
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
                Picker(L("ticker.displayMode", comment: ""), selection: $prefs.displayMode) {
                    ForEach(TickerDisplayMode.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                Text(displayModeHint)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if prefs.displayMode == .scroll {
                    Picker(L("settings.scrollSpeed", comment: ""), selection: $prefs.scrollSpeed) {
                        ForEach(ScrollSpeed.allCases) { s in
                            Text(s.displayName).tag(s)
                        }
                    }
                    Toggle(L("settings.pauseOnHover", comment: ""), isOn: $prefs.pauseOnHover)
                }
                if prefs.displayMode == .carousel {
                    Toggle(L("settings.pauseOnHover", comment: ""), isOn: $prefs.pauseOnHover)
                    Picker(L("ticker.carouselDwell", comment: ""), selection: $prefs.carouselDwell) {
                        Text(L("ticker.dwell.2s", comment: "")).tag(2)
                        Text(L("ticker.dwell.3s", comment: "")).tag(3)
                        Text(L("ticker.dwell.4s", comment: "")).tag(4)
                        Text(L("ticker.dwell.6s", comment: "")).tag(6)
                        Text(L("ticker.dwell.10s", comment: "")).tag(10)
                    }
                }
                if prefs.displayMode == .minimal {
                    Picker(L("ticker.minimalMetric", comment: ""), selection: $prefs.minimalMetric) {
                        ForEach(MinimalMetric.allCases) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                }
                Toggle(L("settings.pauseWhenClosed", comment: ""), isOn: $prefs.pauseWhenClosed)
                if prefs.displayMode == .scroll || prefs.displayMode == .carousel {
                    Stepper(value: $prefs.maxItems, in: 1...50) {
                        Text(String(format: L("settings.maxItems", comment: ""), prefs.maxItems))
                    }
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

    private var displayModeHint: String {
        switch prefs.displayMode {
        case .scroll:   return L("displayMode.scroll.hint", comment: "")
        case .carousel: return L("displayMode.carousel.hint", comment: "")
        case .compact:  return L("displayMode.compact.hint", comment: "")
        case .minimal:  return L("displayMode.minimal.hint", comment: "")
        }
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
