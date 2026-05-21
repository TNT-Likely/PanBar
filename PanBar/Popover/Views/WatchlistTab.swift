import SwiftUI

struct WatchlistTab: View {
    @EnvironmentObject var vm: PopoverViewModel
    @EnvironmentObject var refresher: QuoteRefresher
    @EnvironmentObject var appearance: AppearancePreferences
    @EnvironmentObject var prefs: TickerPreferences

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if vm.watchlist.isEmpty {
                    emptyState
                } else {
                    ForEach(vm.watchlist) { item in
                        WatchRow(item: item, quote: refresher.quotes[item.symbol], density: appearance.density, scheme: prefs.colorScheme)
                            .contextMenu {
                                Button(L("action.openInBrowser", comment: "")) {
                                    openInBrowser(item.symbol)
                                }
                                Divider()
                                Button(L("action.delete", comment: ""), role: .destructive) {
                                    vm.deleteWatchItem(item.id)
                                }
                            }
                            .onTapGesture(count: 2) {
                                openInBrowser(item.symbol)
                            }
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .frame(maxHeight: 320)
    }

    private func openInBrowser(_ symbol: SymbolID) {
        let template = vm.settingsRepo.string(BrowserURLBuilder.templateKey) ?? BrowserURLBuilder.Template.xueqiu.rawValue
        if let url = BrowserURLBuilder.url(template: template, symbol: symbol) {
            NSWorkspace.shared.open(url)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "star")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text(L("watchlist.empty", comment: ""))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

private struct WatchRow: View {
    let item: WatchItem
    let quote: Quote?
    let density: PopoverDensity
    let scheme: TickerColorScheme

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.symbol.market == .us ? item.symbol.code.uppercased() : item.symbol.code)
                    .font(.system(size: 13, weight: .semibold))
                Text(item.name)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let q = quote {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.symbol.market.defaultCurrency.format(q.price))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                    Text(String(format: "%+.2f%%", q.changePct * 100))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(q.change >= 0 ? SemanticColors.up(scheme: scheme) : SemanticColors.down(scheme: scheme))
                        .monospacedDigit()
                }
            } else {
                Text("--")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, density.rowHorizontalPadding)
        .padding(.vertical, max(density.rowVerticalPadding - 1, 4))
    }
}
