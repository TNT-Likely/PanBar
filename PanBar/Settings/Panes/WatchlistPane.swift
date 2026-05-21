import SwiftUI

struct WatchlistPane: View {
    @Environment(\.container) private var container
    @State private var items: [WatchItem] = []
    @State private var showAdd: Bool = false
    @State private var editing: WatchItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("settings.watchlist", comment: ""))
                    .font(.title3)
                Spacer()
                Button(action: importCSV) {
                    Label(L("action.importCSV", comment: ""), systemImage: "square.and.arrow.down")
                }
                Button(action: exportCSV) {
                    Label(L("action.exportCSV", comment: ""), systemImage: "square.and.arrow.up")
                }
                .disabled(items.isEmpty)
                Button(action: { showAdd = true }) {
                    Label(L("action.add", comment: ""), systemImage: "plus")
                }
            }
            Table(items) {
                TableColumn(L("col.symbol", comment: "")) { (w: WatchItem) in
                    Text(w.symbol.market == .us ? w.symbol.code.uppercased() : w.symbol.code)
                }
                TableColumn(L("col.name", comment: "")) { (w: WatchItem) in Text(w.name) }
                TableColumn(L("col.market", comment: "")) { (w: WatchItem) in Text(w.symbol.market.displayName) }
                TableColumn(L("col.inTicker", comment: "")) { (w: WatchItem) in
                    Toggle("", isOn: Binding(
                        get: { w.inTicker },
                        set: { newValue in
                            var copy = w
                            copy.inTicker = newValue
                            try? container?.watchlistRepo.upsert(copy)
                            reload()
                            container?.refresher.refreshNow()
                        }
                    ))
                    .labelsHidden()
                    .help(L("col.inTicker.help", comment: ""))
                }
                TableColumn("") { (w: WatchItem) in
                    HStack(spacing: 4) {
                        Button { editing = w } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help(L("action.edit", comment: ""))
                        Button(role: .destructive) {
                            try? container?.watchlistRepo.delete(id: w.id)
                            reload()
                            container?.refresher.refreshNow()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            if items.isEmpty {
                Text(L("watchlist.empty", comment: ""))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
            }
        }
        .padding(20)
        .onAppear(perform: reload)
        .sheet(isPresented: $showAdd) {
            WatchEditorSheet(initial: nil, onSaved: {
                showAdd = false
                reload()
                container?.refresher.refreshNow()
            }, onCancel: { showAdd = false })
        }
        .sheet(item: $editing) { existing in
            WatchEditorSheet(initial: existing, onSaved: {
                editing = nil
                reload()
                container?.refresher.refreshNow()
            }, onCancel: { editing = nil })
        }
    }

    private func reload() {
        items = (try? container?.watchlistRepo.all()) ?? []
    }

    private func exportCSV() {
        let csv = CSVPortfolioIO.exportWatchlist(items)
        CSVPortfolioIO.presentExportPanel(suggestedName: "panbar-watchlist.csv", content: csv)
    }

    private func importCSV() {
        CSVPortfolioIO.presentImportPanel { text in
            guard let text = text else { return }
            let imported = CSVPortfolioIO.importWatchlist(text)
            for w in imported {
                try? container?.watchlistRepo.upsert(w)
            }
            reload()
            container?.refresher.refreshNow()
        }
    }
}

private struct WatchEditorSheet: View {
    @Environment(\.container) private var container
    let initial: WatchItem?
    var onSaved: () -> Void
    var onCancel: () -> Void

    @State private var market: Market = .a
    @State private var code: String = ""
    @State private var name: String = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(initial == nil ? L("watchlist.addTitle", comment: "") : L("watchlist.editTitle", comment: ""))
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
            }
            if let error = error {
                Text(error).foregroundColor(.red).font(.caption)
            }
            HStack {
                Spacer()
                Button(L("action.cancel", comment: ""), action: onCancel)
                Button(L("action.save", comment: ""), action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear(perform: prefill)
    }

    private func prefill() {
        guard let w = initial else { return }
        market = w.symbol.market
        code = w.symbol.code
        name = w.name
    }

    private func save() {
        guard !code.isEmpty else { error = L("error.codeRequired", comment: ""); return }
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        let sid = SymbolID(code: trimmed, market: market)
        let item: WatchItem
        if var existing = initial {
            existing.symbol = sid
            existing.name = name.isEmpty ? trimmed : name
            item = existing
        } else {
            item = WatchItem(symbol: sid, name: name.isEmpty ? trimmed : name)
        }
        do {
            try container?.watchlistRepo.upsert(item)
            onSaved()
        } catch {
            self.error = "\(error)"
        }
    }
}
