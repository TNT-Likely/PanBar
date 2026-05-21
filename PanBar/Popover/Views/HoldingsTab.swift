import SwiftUI

struct HoldingsTab: View {
    @EnvironmentObject var vm: PopoverViewModel
    @EnvironmentObject var refresher: QuoteRefresher
    @EnvironmentObject var appearance: AppearancePreferences
    @EnvironmentObject var prefs: TickerPreferences

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if vm.holdings.isEmpty {
                    emptyState
                } else {
                    ForEach(refresher.snapshot.positions) { pos in
                        HoldingRow(position: pos, density: appearance.density, scheme: prefs.colorScheme)
                            .contextMenu {
                                Button(L("action.openInBrowser", comment: "")) {
                                    openInBrowser(pos.holding.symbol)
                                }
                                Divider()
                                Button(L("action.delete", comment: ""), role: .destructive) {
                                    vm.deleteHolding(pos.holding.id)
                                }
                            }
                            .onTapGesture(count: 2) {
                                openInBrowser(pos.holding.symbol)
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
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text(L("holdings.empty", comment: ""))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Button(L("holdings.addFirst", comment: "")) {
                SettingsWindowController.shared.show()
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

private struct HoldingRow: View {
    let position: HoldingPosition
    let density: PopoverDensity
    let scheme: TickerColorScheme

    var body: some View {
        let h = position.holding
        let q = position.quote
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(displayCode(h.symbol))
                        .font(.system(size: 13, weight: .semibold))
                    Text(h.name)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Text(detailText)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.85))
                    .monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 4) {
                    Text(h.currency.format(q?.price ?? h.costPrice))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                    if let q = q {
                        pctPill(q.changePct)
                    }
                }
                Text(signedPnL(position.pnl))
                    .font(.system(size: 11))
                    .foregroundColor(pnlColor(position.pnl))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, density.rowHorizontalPadding)
        .padding(.vertical, density.rowVerticalPadding)
    }

    private func displayCode(_ s: SymbolID) -> String {
        s.market == .us ? s.code.uppercased() : s.code
    }

    private var detailText: String {
        let qtyDisplay = "\(position.holding.quantity)"
        let costDisplay = position.holding.currency.format(position.holding.costPrice)
        return String(format: L("holding.detail", comment: ""), qtyDisplay, costDisplay)
    }

    private func signedPnL(_ value: Decimal) -> String {
        let sign = value >= 0 ? "+" : "-"
        return sign + position.holding.currency.format(value.magnitude)
    }

    private func pnlColor(_ value: Decimal) -> Color {
        SemanticColors.directional(value, scheme: scheme)
    }

    private func pctPill(_ pct: Double) -> some View {
        let text = String(format: "%+.2f%%", pct * 100)
        let color: Color = pct >= 0 ? SemanticColors.up(scheme: scheme) : SemanticColors.down(scheme: scheme)
        return Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .monospacedDigit()
    }
}
