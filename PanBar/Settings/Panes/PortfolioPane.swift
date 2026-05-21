import SwiftUI

struct PortfolioPane: View {
    @Environment(\.container) private var container
    @State private var holdings: [Holding] = []
    @State private var showAdd: Bool = false

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

            Table(holdings) {
                TableColumn(L("col.symbol", comment: "")) { (h: Holding) in
                    Text(h.symbol.market == .us ? h.symbol.code.uppercased() : h.symbol.code)
                        .monospacedDigit()
                }
                TableColumn(L("col.name", comment: "")) { (h: Holding) in Text(h.name) }
                TableColumn(L("col.market", comment: "")) { (h: Holding) in Text(h.symbol.market.displayName) }
                TableColumn(L("col.qty", comment: "")) { (h: Holding) in Text("\(h.quantity)").monospacedDigit() }
                TableColumn(L("col.cost", comment: "")) { (h: Holding) in Text(h.currency.format(h.costPrice)).monospacedDigit() }
                TableColumn("") { (h: Holding) in
                    Button(role: .destructive) {
                        try? container?.holdingsRepo.delete(id: h.id)
                        reload()
                        container?.refresher.refreshNow()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if holdings.isEmpty {
                Text(L("holdings.empty", comment: ""))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
            }
        }
        .padding(20)
        .onAppear(perform: reload)
        .sheet(isPresented: $showAdd) {
            AddHoldingSheet(onSaved: {
                showAdd = false
                reload()
                container?.refresher.refreshNow()
            }, onCancel: { showAdd = false })
        }
    }

    private func reload() {
        holdings = (try? container?.holdingsRepo.all()) ?? []
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

private struct AddHoldingSheet: View {
    @Environment(\.container) private var container
    var onSaved: () -> Void
    var onCancel: () -> Void

    @State private var market: Market = .a
    @State private var code: String = ""
    @State private var name: String = ""
    @State private var quantity: String = ""
    @State private var costPrice: String = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("holdings.addTitle", comment: ""))
                .font(.title3)

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
        .frame(width: 420)
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
        let holding = Holding(
            symbol: sid,
            name: name.isEmpty ? code : name,
            quantity: qty,
            costPrice: cost
        )
        do {
            try container?.holdingsRepo.upsert(holding)
            onSaved()
        } catch {
            self.error = "\(error)"
        }
    }
}
