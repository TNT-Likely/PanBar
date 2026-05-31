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
                            // 编辑按钮以 hover 时是否显示的形式传给 HoldingRow,在 name 后面 inline 出现,
                            // 不再用 ZStack 覆盖右侧(挡住涨跌幅 pill)。
                            HoldingRow(
                                holding: holding,
                                quote: refresher.quotes[holding.symbol],
                                position: positionsByID[holding.id],
                                density: appearance.density,
                                scheme: prefs.colorScheme,
                                baseCurrency: refresher.snapshot.baseCurrency,
                                showEditButton: hoveredID == holding.id,
                                onEdit: { openEdit(holding) }
                            )
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
    /// hover 时显示 inline 编辑铅笔(放在 name 后面,不挡涨跌)
    let showEditButton: Bool
    let onEdit: () -> Void
    private let allTimeColumnWidth: CGFloat = 84
    private let priceColumnWidth: CGFloat = 104

    /// 只要有 quote(无论 position 有没有),立即就能算出原币种的盈亏。
    /// 本位币换算需要 FX,只能依赖 position。
    private var nativePnL: Decimal? {
        guard let q = quote else { return nil }
        return (q.price - holding.costPrice) * holding.quantity
    }

    private var nativeTodayPnL: Decimal? {
        guard let q = quote else { return nil }
        return (q.price - q.prevClose) * holding.quantity
    }

    /// 右侧是否要显示「≈ 本位币」第三行。决定左侧布局是否要 Spacer 撑底。
    private var hasBaseConversion: Bool {
        guard holding.currency != baseCurrency else { return false }
        return position?.basePnL != nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(displayCode(holding.symbol))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(holding.name)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help(L("action.edit", comment: ""))
                    .opacity(showEditButton ? 1 : 0)
                    .disabled(!showEditButton)
                    .frame(width: 10, height: 12)
                    .accessibilityHidden(!showEditButton)
                }
                // 右侧 3 行时,在两条左侧文字之间塞 Spacer 把第二行推到底,
                // 跟右侧的第三行(≈ base)平齐。右侧 2 行时不撑,正常紧贴排。
                if hasBaseConversion {
                    Spacer(minLength: 0)
                }
                Text(detailText)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.85))
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxHeight: hasBaseConversion ? .infinity : nil, alignment: .top)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            allTimeColumn
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
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                if let pnl = nativeTodayPnL {
                    labeledPnL(
                        label: L("summary.today", comment: ""),
                        value: pnl,
                        currency: holding.currency,
                        fontSize: 11
                    )
                }
            }
            .frame(width: priceColumnWidth, alignment: .trailing)
            .layoutPriority(2)
        }
        .padding(.horizontal, density.rowHorizontalPadding)
        .padding(.vertical, density.rowVerticalPadding)
    }

    @ViewBuilder
    private var allTimeColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L("summary.allTime", comment: ""))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
            if let pnl = nativePnL {
                Text(signedPnL(pnl, currency: holding.currency))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(pnlColor(pnl))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text("—")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            // 本位币换算依赖 FX,只能从 snapshot 拿。
            if holding.currency != baseCurrency,
               let pos = position, let basePnL = pos.basePnL {
                Text("≈ " + signedPnL(basePnL, currency: baseCurrency))
                    .font(.system(size: 10))
                    .foregroundColor(pnlColor(pos.pnl).opacity(0.7))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(width: allTimeColumnWidth, alignment: .leading)
        .layoutPriority(1)
    }

    private func labeledPnL(label: String, value: Decimal, currency: Currency, fontSize: CGFloat) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundColor(.secondary)
            Text(signedPnL(value, currency: currency))
                .foregroundColor(pnlColor(value))
        }
        .font(.system(size: fontSize))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func displayCode(_ s: SymbolID) -> String {
        s.market == .us ? s.code.uppercased() : s.code
    }

    private var detailText: String {
        let qtyDisplay = "\(holding.quantity)"
        let costDisplay = holding.currency.format(holding.costPrice, fractionDigits: 3)
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
