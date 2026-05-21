import SwiftUI

struct PortfolioPane: View {
    @Environment(\.container) private var container
    @State private var holdings: [Holding] = []
    @State private var showAdd: Bool = false
    @State private var editing: Holding?
    @State private var deleting: Holding?     // 二次确认前临时保存待删
    @State private var selection: Set<Holding.ID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("settings.portfolio", comment: ""))
                    .font(.title3)
                Spacer()
                Button(action: importCSV) {
                    Label(L("action.importCSV", comment: ""), systemImage: "square.and.arrow.down")
                }
                Button(action: exportCSV) {
                    Label(L("action.exportCSV", comment: ""), systemImage: "square.and.arrow.up")
                }
                .disabled(holdings.isEmpty)
                Button(action: { showAdd = true }) {
                    Label(L("action.add", comment: ""), systemImage: "plus")
                }
            }

            holdingsList

            if holdings.isEmpty {
                Text(L("holdings.empty", comment: ""))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
            }
        }
        .padding(20)
        .onAppear {
            reload()
            switch SettingsWindowController.pendingAction {
            case .addHolding:
                SettingsWindowController.pendingAction = nil
                showAdd = true
            case .editHolding(let id):
                SettingsWindowController.pendingAction = nil
                if let h = holdings.first(where: { $0.id == id }) {
                    editing = h
                }
            default:
                break
            }
        }
        .sheet(isPresented: $showAdd) {
            HoldingEditorSheet(initial: nil, onSaved: {
                showAdd = false
                reload()
                container?.refresher.refreshNow()
            }, onCancel: { showAdd = false })
        }
        .sheet(item: $editing) { existing in
            HoldingEditorSheet(initial: existing, onSaved: {
                editing = nil
                reload()
                container?.refresher.refreshNow()
            }, onCancel: { editing = nil })
        }
        .alert(
            String(format: L("delete.confirm.title", comment: ""), deleting?.name ?? ""),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button(L("action.cancel", comment: ""), role: .cancel) { deleting = nil }
            Button(L("action.delete", comment: ""), role: .destructive) {
                if let h = deleting {
                    try? container?.holdingsRepo.delete(id: h.id)
                    reload()
                    container?.refresher.refreshNow()
                }
                deleting = nil
            }
        } message: {
            Text(L("delete.confirm.body", comment: ""))
        }
    }

    private func reload() {
        holdings = (try? container?.holdingsRepo.all()) ?? []
    }

    /// 用 List 替代 Table 是为了支持 .onMove 拖拽改顺序;Table 在 SwiftUI 里目前
    /// 没有 onMove API。手撸列宽对齐成「类表格」外观:左侧三道杠作拖拽手柄。
    /// 「在滚动条显示」的开关已经在 设置 → 滚动 那 pane 里有了,这里删掉省空间。
    private var holdingsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("").frame(width: 18)  // 拖拽手柄列
                Text(L("col.symbol", comment: "")).frame(width: 70, alignment: .leading)
                Text(L("col.name", comment: "")).frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                Text(L("col.market", comment: "")).frame(width: 56, alignment: .leading)
                Text(L("col.qty", comment: "")).frame(width: 70, alignment: .trailing)
                Text(L("col.cost", comment: "")).frame(width: 100, alignment: .trailing)
                Spacer().frame(width: 56)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            List(selection: $selection) {
                ForEach(holdings) { h in
                    holdingRow(h).tag(h.id)
                }
                .onMove(perform: move)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
        }
    }

    @ViewBuilder
    private func holdingRow(_ h: Holding) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.55))
                .frame(width: 18)
                .help(L("action.dragToReorder", comment: ""))
            Text(h.symbol.market == .us ? h.symbol.code.uppercased() : h.symbol.code)
                .monospacedDigit()
                .frame(width: 70, alignment: .leading)
            Text(h.name)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
            Text(h.symbol.market.displayName)
                .frame(width: 56, alignment: .leading)
                .foregroundColor(.secondary)
            Text("\(h.quantity)")
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)
            Text(h.currency.format(h.costPrice))
                .monospacedDigit()
                .frame(width: 100, alignment: .trailing)
            HStack(spacing: 4) {
                Button { editing = h } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help(L("action.edit", comment: ""))
                Button(role: .destructive) {
                    deleting = h
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            .frame(width: 56)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editing = h }
    }

    private func move(from source: IndexSet, to destination: Int) {
        holdings.move(fromOffsets: source, toOffset: destination)
        let ids = holdings.map { $0.id }
        try? container?.holdingsRepo.reorder(ids: ids)
        container?.refresher.refreshNow()
    }

    private func exportCSV() {
        let csv = CSVPortfolioIO.exportHoldings(holdings)
        CSVPortfolioIO.presentExportPanel(suggestedName: "panbar-holdings.csv", content: csv)
    }

    private func importCSV() {
        CSVPortfolioIO.presentImportPanel { text in
            guard let text = text else { return }
            let imported = CSVPortfolioIO.importHoldings(text)
            for h in imported {
                try? container?.holdingsRepo.upsert(h)
            }
            reload()
            container?.refresher.refreshNow()
        }
    }
}

private struct HoldingEditorSheet: View {
    @Environment(\.container) private var container
    let initial: Holding?
    var onSaved: () -> Void
    var onCancel: () -> Void

    @State private var market: Market = .a
    @State private var code: String = ""
    @State private var name: String = ""
    @State private var quantity: String = ""
    @State private var costPrice: String = ""
    @State private var error: String?

    @StateObject private var searchVM = SymbolSearchViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(initial == nil ? L("holdings.addTitle", comment: "") : L("holdings.editTitle", comment: ""))
                .font(.title3)

            SymbolSearchField(vm: searchVM, onPick: { result in
                market = result.symbol.market
                code = result.symbol.code
                name = result.name
            })

            Form {
                Picker(L("col.market", comment: ""), selection: $market) {
                    ForEach(Market.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                TextField(L("col.symbol", comment: ""), text: $code)
                    .textFieldStyle(.roundedBorder)
                TextField(L("col.name", comment: ""), text: $name)
                    .textFieldStyle(.roundedBorder)
                TextField(L("col.qty", comment: ""), text: $quantity)
                    .textFieldStyle(.roundedBorder)
                TextField(L("col.cost", comment: ""), text: $costPrice)
                    .textFieldStyle(.roundedBorder)
            }

            if let error = error {
                Text(error).foregroundColor(.red).font(.caption)
            }

            HStack {
                Spacer()
                Button(L("action.cancel", comment: ""), action: onCancel)
                Button(L("action.save", comment: ""), action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            prefill()
            searchVM.bind(container?.symbolSearch)
        }
    }

    private func prefill() {
        guard let h = initial else { return }
        market = h.symbol.market
        code = h.symbol.code
        name = h.name
        quantity = "\(h.quantity)"
        costPrice = "\(h.costPrice)"
    }

    private func save() {
        guard !code.isEmpty else { error = L("error.codeRequired", comment: ""); return }
        guard let qty = Decimal(string: quantity.trimmingCharacters(in: .whitespaces)), qty > 0 else {
            error = L("error.qtyInvalid", comment: ""); return
        }
        guard let cost = Decimal(string: costPrice.trimmingCharacters(in: .whitespaces)), cost > 0 else {
            error = L("error.costInvalid", comment: ""); return
        }
        let sid = SymbolID(code: code.trimmingCharacters(in: .whitespaces), market: market)
        let holding: Holding
        if var existing = initial {
            existing.symbol = sid
            existing.name = name.isEmpty ? code : name
            existing.quantity = qty
            existing.costPrice = cost
            existing.currency = sid.market.defaultCurrency
            holding = existing
        } else {
            holding = Holding(
                symbol: sid,
                name: name.isEmpty ? code : name,
                quantity: qty,
                costPrice: cost
            )
        }
        do {
            try container?.holdingsRepo.upsert(holding)
            onSaved()
        } catch {
            self.error = "\(error)"
        }
    }
}
