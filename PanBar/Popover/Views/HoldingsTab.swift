import SwiftUI

struct HoldingsTab: View {
    @EnvironmentObject var vm: PopoverViewModel
    @EnvironmentObject var refresher: QuoteRefresher
    @EnvironmentObject var appearance: AppearancePreferences
    @EnvironmentObject var prefs: TickerPreferences

    /// 把 snapshot.positions 按 holding.id 建索引,O(1) 查找。
    /// snapshot 还没合成时(冷启动一瞬间)返回空,行会用 fallback 渲染。
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
                        // 列表来源是 vm.holdings(DB 同步可读),不依赖 snapshot 的合成进度。
                        // 价格 / 盈亏 / 本位币换算从 snapshot 找,找不到就降级展示(只显示代码 + 成本)。
                        ForEach(vm.holdings) { holding in
                            HoldingRow(
                                holding: holding,
                                position: positionsByID[holding.id],
                                density: appearance.density,
                                scheme: prefs.colorScheme,
                                baseCurrency: refresher.snapshot.baseCurrency
                            )
                                .contextMenu {
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
    let holding: Holding
    /// snapshot 还没合成时为 nil,行降级为「只有代码 + 成本」的骨架。
    let position: HoldingPosition?
    let density: PopoverDensity
    let scheme: TickerColorScheme
    let baseCurrency: Currency

    var body: some View {
        let q = position?.quote
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
                    if let q = q {
                        Text(holding.currency.format(q.price))
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                        pctPill(q.changePct)
                    } else {
                        // 还没价格 —— 占位,避免行高跳动
                        Text("—")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
                if let pos = position, q != nil {
                    Text(signedPnL(pos.pnl, currency: holding.currency))
                        .font(.system(size: 11))
                        .foregroundColor(pnlColor(pos.pnl))
                        .monospacedDigit()
                    if holding.currency != baseCurrency, let basePnL = pos.basePnL {
                        Text("≈ " + signedPnL(basePnL, currency: baseCurrency))
                            .font(.system(size: 10))
                            .foregroundColor(pnlColor(pos.pnl).opacity(0.7))
                            .monospacedDigit()
                    }
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
