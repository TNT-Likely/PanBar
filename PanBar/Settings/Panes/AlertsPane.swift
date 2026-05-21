import SwiftUI

struct AlertsPane: View {
    @Environment(\.container) private var container
    @State private var alerts: [Alert] = []
    @State private var showAdd: Bool = false
    @State private var editing: Alert?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("settings.alerts", comment: ""))
                    .font(.title3)
                Spacer()
                Button(action: { showAdd = true }) {
                    Label(L("action.add", comment: ""), systemImage: "plus")
                }
            }

            Table(alerts) {
                TableColumn(L("col.symbol", comment: "")) { (a: Alert) in
                    Text(a.symbol.market == .us ? a.symbol.code.uppercased() : a.symbol.code)
                }
                TableColumn(L("col.condition", comment: "")) { (a: Alert) in
                    Text(a.condition.displayName)
                }
                TableColumn(L("col.threshold", comment: "")) { (a: Alert) in
                    Text(thresholdText(a))
                        .monospacedDigit()
                }
                TableColumn(L("col.active", comment: "")) { (a: Alert) in
                    Toggle("", isOn: Binding(
                        get: { a.isActive },
                        set: { newValue in
                            var copy = a
                            copy.isActive = newValue
                            try? container?.alertsRepo.upsert(copy)
                            reload()
                        }
                    ))
                    .labelsHidden()
                }
                TableColumn("") { (a: Alert) in
                    HStack(spacing: 4) {
                        Button { editing = a } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless)
                        Button(role: .destructive) {
                            try? container?.alertsRepo.delete(id: a.id)
                            reload()
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }

            if alerts.isEmpty {
                Text(L("alerts.empty", comment: ""))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
            }
        }
        .padding(20)
        .onAppear(perform: reload)
        .sheet(isPresented: $showAdd) {
            AlertEditorSheet(initial: nil) {
                showAdd = false
                reload()
            } onCancel: {
                showAdd = false
            }
        }
        .sheet(item: $editing) { existing in
            AlertEditorSheet(initial: existing) {
                editing = nil
                reload()
            } onCancel: { editing = nil }
        }
    }

    private func reload() {
        alerts = (try? container?.alertsRepo.all()) ?? []
    }

    private func thresholdText(_ a: Alert) -> String {
        if a.condition.isPercent {
            let pct = (a.threshold as NSDecimalNumber).doubleValue * 100
            return String(format: "%+.2f%%", pct)
        }
        return a.symbol.market.defaultCurrency.format(a.threshold)
    }
}

private struct AlertEditorSheet: View {
    @Environment(\.container) private var container
    let initial: Alert?
    var onSaved: () -> Void
    var onCancel: () -> Void

    @State private var market: Market = .a
    @State private var code: String = ""
    @State private var name: String = ""
    @State private var condition: AlertCondition = .priceAbove
    @State private var thresholdText: String = ""
    @State private var cooldownText: String = "300"
    @State private var error: String?
    @StateObject private var searchVM = SymbolSearchViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(initial == nil ? L("alerts.addTitle", comment: "") : L("alerts.editTitle", comment: ""))
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
                TextField(L("col.symbol", comment: ""), text: $code).textFieldStyle(.roundedBorder)
                TextField(L("col.name", comment: ""), text: $name).textFieldStyle(.roundedBorder)
                Picker(L("col.condition", comment: ""), selection: $condition) {
                    ForEach(AlertCondition.allCases, id: \.self) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                TextField(thresholdLabel, text: $thresholdText).textFieldStyle(.roundedBorder)
                TextField(L("alerts.cooldown", comment: ""), text: $cooldownText).textFieldStyle(.roundedBorder)
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
        .frame(width: 480)
        .onAppear {
            prefill()
            searchVM.bind(container?.symbolSearch)
        }
    }

    private var thresholdLabel: String {
        condition.isPercent ? L("alerts.thresholdPct", comment: "") : L("alerts.thresholdPrice", comment: "")
    }

    private func prefill() {
        guard let a = initial else { return }
        market = a.symbol.market
        code = a.symbol.code
        name = a.name
        condition = a.condition
        if a.condition.isPercent {
            let pct = (a.threshold as NSDecimalNumber).doubleValue * 100
            thresholdText = String(format: "%.2f", pct)
        } else {
            thresholdText = "\(a.threshold)"
        }
        cooldownText = "\(a.cooldownSeconds)"
    }

    private func save() {
        guard !code.isEmpty else { error = L("error.codeRequired", comment: ""); return }
        guard let parsedTh = Decimal(string: thresholdText.trimmingCharacters(in: .whitespaces)) else {
            error = L("error.thresholdInvalid", comment: ""); return
        }
        let stored: Decimal = condition.isPercent ? parsedTh / 100 : parsedTh
        let cooldown = Int(cooldownText) ?? 300

        let symbol = SymbolID(code: code.trimmingCharacters(in: .whitespaces), market: market)
        var alert: Alert
        if let initial = initial {
            alert = initial
            alert.symbol = symbol
            alert.name = name.isEmpty ? code : name
            alert.condition = condition
            alert.threshold = stored
            alert.cooldownSeconds = cooldown
        } else {
            alert = Alert(
                symbol: symbol,
                name: name.isEmpty ? code : name,
                condition: condition,
                threshold: stored,
                cooldownSeconds: cooldown
            )
        }

        do {
            try container?.alertsRepo.upsert(alert)
            onSaved()
        } catch {
            self.error = "\(error)"
        }
    }
}
