import SwiftUI

struct HoldingsTab: View {
    @EnvironmentObject var vm: PopoverViewModel
    @EnvironmentObject var refresher: QuoteRefresher
    @EnvironmentObject var appearance: AppearancePreferences
    @EnvironmentObject var prefs: TickerPreferences

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if vm.holdings.isEmpty {
                        emptyState
                    } else {
                        ForEach(refresher.snapshot.positions) { pos in
                            HoldingRow(
                                position: pos,
                                density: appearance.density,
                                scheme: prefs.colorScheme,
                                baseCurrency: refresher.snapshot.baseCurrency
                            )
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
            .frame(maxHeight: 290)

            // 底部快捷"+ 添加"行
            if !vm.holdings.isEmpty {
                quickAddButton
            }
        }
    }

    private var quickAddButton: some View {
        Button(action: openAddSheet) {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle.fill")
                Text(L("holdings.quickAdd", comment: ""))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            VStack(spacing: 0) {
                Divider().opacity(0.4)
                Spacer()
            }
        )
    }

    private func openAddSheet() {
        SettingsWindowController.shared.show(initialAction: .addHolding)
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
                openAddSheet()
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
    let baseCurrency: Currency

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
                Text(signedPnL(position.pnl, currency: h.currency))
                    .font(.system(size: 11))
                    .foregroundColor(pnlColor(position.pnl))
                    .monospacedDigit()
                // 本位币换算(原币种 != 本位币 时才显示)
                if h.currency != baseCurrency, let basePnL = position.basePnL {
                    Text("≈ " + signedPnL(basePnL, currency: baseCurrency))
                        .font(.system(size: 10))
                        .foregroundColor(pnlColor(position.pnl).opacity(0.7))
                        .monospacedDigit()
                }
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

    private func signedPnL(_ value: Decimal, currency: Currency) -> String {
        let sign = value >= 0 ? "+" : "-"
        return sign + currency.format(value.magnitude)
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
