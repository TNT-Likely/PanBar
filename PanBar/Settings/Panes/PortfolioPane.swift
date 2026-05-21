import SwiftUI

struct PortfolioPane: View {
    @Environment(\.container) private var container
    @State private var holdings: [Holding] = []
    @State private var showAdd: Bool = false
    @State private var editing: Holding?
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
    }

    private func reload() {
        holdings = (try? container?.holdingsRepo.all()) ?? []
    }

    /// 用 List 替代 Table 是为了支持 .onMove 拖拽改顺序;Table 在 SwiftUI 里目前
    /// 没有 onMove API。手撸列宽对齐成「类表格」外观,头部一行写死作伪表头。
    private var holdingsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 伪表头
            HStack(spacing: 8) {
                Text("").frame(width: 14)  // 留给 drag handle / spacing
                Text(L("col.symbol", comment: "")).frame(width: 80, alignment: .leading)
                Text(L("col.name", comment: "")).frame(maxWidth: .infinity, alignment: .leading)
                Text(L("col.market", comment: "")).frame(width: 60, alignment: .leading)
                Text(L("col.qty", comment: "")).frame(width: 70, alignment: .trailing)
                Text(L("col.cost", comment: "")).frame(width: 90, alignment: .trailing)
                Text(L("col.inTicker", comment: "")).frame(width: 50, alignment: .center)
                Spacer().frame(width: 60)  // 编辑/删除按钮列
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            List {
                ForEach(holdings) { h in
                    holdingRow(h)
                }
                .onMove(perform: move)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
        }
    }

    @ViewBuilder
    private func holdingRow(_ h: Holding) -> some View {
        HStack(spacing: 8) {
            Text(h.symbol.market == .us ? h.symbol.code.uppercased() : h.symbol.code)
                .monospacedDigit()
                .frame(width: 80, alignment: .leading)
            Text(h.name)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(h.symbol.market.displayName)
                .frame(width: 60, alignment: .leading)
                .foregroundColor(.secondary)
            Text("\(h.quantity)")
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)
            Text(h.currency.format(h.costPrice))
                .monospacedDigit()
                .frame(width: 90, alignment: .trailing)
            Toggle("", isOn: Binding(
                get: { h.inTicker },
                set: { newValue in
                    var copy = h
                    copy.inTicker = newValue
                    try? container?.holdingsRepo.upsert(copy)
                    reload()
                    container?.refresher.refreshNow()
                }
            ))
            .labelsHidden()
            .help(L("col.inTicker.help", comment: ""))
            .frame(width: 50, alignment: .center)
            HStack(spacing: 4) {
                Button { editing = h } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help(L("action.edit", comment: ""))
                Button(role: .destructive) {
                    try? container?.holdingsRepo.delete(id: h.id)
                    reload()
                    container?.refresher.refreshNow()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            .frame(width: 60)
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
