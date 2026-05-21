import SwiftUI

struct HoldingsTab: View {
    @EnvironmentObject var vm: PopoverViewModel
    @EnvironmentObject var refresher: QuoteRefresher
    @EnvironmentObject var appearance: AppearancePreferences
    @EnvironmentObject var prefs: TickerPreferences
    /// 当前 hover 的行 id;有值时该行尾露出铅笔编辑按钮。
    @State private var hoveredID: UUID?

    /// 把 snapshot.positions 按 holding.id 建索引,O(1) 查找。
    private var positionsByID: [UUID: HoldingPosition] {
        Dictionary(uniqueKeysWithValues: refresher.snapshot.positions.map { ($0.holding.id, $0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if vm.holdings.isEmpty {
                        emptyState
                    } else {
                        ForEach(vm.holdings) { holding in
                            ZStack(alignment: .trailing) {
                                HoldingRow(
                                    holding: holding,
                                    quote: refresher.quotes[holding.symbol],
                                    position: positionsByID[holding.id],
                                    density: appearance.density,
                                    scheme: prefs.colorScheme,
                                    baseCurrency: refresher.snapshot.baseCurrency
                                )
                                // hover 浮出的铅笔编辑按钮(只对持仓有,自选 / 大盘不需要编辑)
                                if hoveredID == holding.id {
                                    Button(action: { openEdit(holding) }) {
                                        Image(systemName: "pencil.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(.accentColor)
                                            .padding(4)
                                            .background(
                                                Circle().fill(.regularMaterial).shadow(radius: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.trailing, 6)
                                    .help(L("action.edit", comment: ""))
                                    .transition(.opacity.combined(with: .scale))
                                }
                            }
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    hoveredID = hovering ? holding.id : (hoveredID == holding.id ? nil : hoveredID)
                                }
                            }
                            .contextMenu {
                                Button(L("action.edit", comment: "")) { openEdit(holding) }
                                Button(L("action.openInBrowser", comment: "")) {
                                    openInBrowser(holding.symbol)
                                }
                                Divider()
                                Button(L("action.delete", comment: ""), role: .destructive) {
                                    vm.deleteHolding(holding.id)
                                }
                            }
                            .onTapGesture(count: 2) {
                                openInBrowser(holding.symbol)
                            }
                            Divider().opacity(0.4)
                        }
                    }
                }
            }
            .frame(maxHeight: 290)

            if !vm.holdings.isEmpty {
                quickAddButton
            }
        }
    }

    private func openEdit(_ holding: Holding) {
        SettingsWindowController.shared.show(initialAction: .editHolding(holding.id))
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
    let holding: Holding
    /// 行情:从 refresher.quotes 同步取(冷启动时已从磁盘 seed)。
    let quote: Quote?
    /// snapshot.positions 中匹配的那条:含本位币换算等字段。snapshot 异步合成,可能晚于 quote。
    let position: HoldingPosition?
    let density: PopoverDensity
    let scheme: TickerColorScheme
    let baseCurrency: Currency

    /// 只要有 quote(无论 position 有没有),立即就能算出原币种的盈亏。
    /// 本位币换算需要 FX,只能依赖 position。
    private var nativePnL: Decimal? {
        guard let q = quote else { return nil }
        return (q.price - holding.costPrice) * holding.quantity
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(displayCode(holding.symbol))
                        .font(.system(size: 13, weight: .semibold))
                    Text(holding.name)
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
                    if let q = quote {
                        Text(holding.currency.format(q.price))
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                        pctPill(q.changePct)
                    } else {
                        Text("—")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
                if let pnl = nativePnL {
                    Text(signedPnL(pnl, currency: holding.currency))
                        .font(.system(size: 11))
                        .foregroundColor(pnlColor(pnl))
                        .monospacedDigit()
                }
                // 本位币换算依赖 FX,只能从 snapshot 拿
                if holding.currency != baseCurrency,
                   let pos = position, let basePnL = pos.basePnL {
                    Text("≈ " + signedPnL(basePnL, currency: baseCurrency))
                        .font(.system(size: 10))
                        .foregroundColor(pnlColor(pos.pnl).opacity(0.7))
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
        let qtyDisplay = "\(holding.quantity)"
        let costDisplay = holding.currency.format(holding.costPrice)
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
