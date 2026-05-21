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
                Button(action: testNotification) {
                    Label(L("alerts.testNotification", comment: ""), systemImage: "bell.badge")
                }
                Button(action: { showAdd = true }) {
                    Label(L("action.add", comment: ""), systemImage: "plus")
                }
            }

            permissionBanner

            Table(alerts) {
                TableColumn(L("col.symbol", comment: "")) { (a: Alert) in
                    Text(a.symbol.market == .us ? a.symbol.code.uppercased() : a.symbol.code)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { editing = a }
                }
                TableColumn(L("col.condition", comment: "")) { (a: Alert) in
                    Text(conditionText(a))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { editing = a }
                }
                TableColumn(L("alerts.col.todayCount", comment: "")) { (a: Alert) in
                    let cap = a.maxTriggersPerDay.map { "/\($0)" } ?? ""
                    let count = a.lastTriggerDay == Alert.todayKey() ? a.triggerCountToday : 0
                    Text("\(count)\(cap)")
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { editing = a }
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
        .onAppear {
            reload()
            if SettingsWindowController.pendingAction == .addAlert {
                SettingsWindowController.pendingAction = nil
                showAdd = true
            }
        }
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

    private func testNotification() {
        NotificationService.shared.sendTest()
    }

    private func conditionText(_ a: Alert) -> String {
        var s = describe(cond: a.condition, threshold: a.threshold, market: a.symbol.market)
        if let sc = a.secondaryCondition, let st = a.secondaryThreshold {
            s += " " + (a.conditionLogic == .and ? "&" : "|") + " "
            s += describe(cond: sc, threshold: st, market: a.symbol.market)
        }
        return s
    }

    private func describe(cond: AlertCondition, threshold: Decimal, market: Market) -> String {
        let v: String
        if cond.isPercent {
            v = String(format: "%+.2f%%", (threshold as NSDecimalNumber).doubleValue * 100)
        } else {
            v = market.defaultCurrency.format(threshold)
        }
        return "\(cond.displayName) \(v)"
    }

    @ViewBuilder
    private var permissionBanner: some View {
        let status = NotificationService.shared.authorizationStatus
        if status == .denied {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("alerts.permission.denied.title", comment: ""))
                        .font(.system(size: 12, weight: .semibold))
                    Text(L("alerts.permission.denied.body", comment: ""))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Button(L("notification.openSettings", comment: "")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
            }
            .padding(10)
            .background(Color.orange.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else if status == .notDetermined {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.accentColor)
                Text(L("alerts.permission.notDetermined", comment: ""))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Button(L("alerts.permission.request", comment: "")) {
                    NotificationService.shared.requestAuthorizationIfNeeded()
                }
                .controlSize(.small)
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

// MARK: - 编辑 sheet

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

    // 副条件
    @State private var hasSecondary: Bool = false
    @State private var secondaryCondition: AlertCondition = .changePctAbove
    @State private var secondaryThresholdText: String = ""
    @State private var conditionLogic: ConditionLogic = .and

    // 频率 / 时间
    @State private var cooldownText: String = "300"
    @State private var hasDailyCap: Bool = false
    @State private var dailyCapText: String = "3"
    @State private var tradingHoursOnly: Bool = false
    @State private var weekdaysOnly: Bool = false
    @State private var showAdvanced: Bool = false

    @State private var error: String?
    @StateObject private var searchVM = SymbolSearchViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(initial == nil ? L("alerts.addTitle", comment: "") : L("alerts.editTitle", comment: ""))
                    .font(.title3)

                SymbolSearchField(vm: searchVM, onPick: { result in
                    market = result.symbol.market
                    code = result.symbol.code
                    name = result.name
                })

                basicSection
                primaryConditionSection
                secondaryConditionSection
                advancedDisclosure

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
        }
        .frame(width: 520, height: 620)
        .onAppear {
            prefill()
            searchVM.bind(container?.symbolSearch)
        }
    }

    private var basicSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Picker(L("col.market", comment: ""), selection: $market) {
                    ForEach(Market.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                TextField(L("col.symbol", comment: ""), text: $code).textFieldStyle(.roundedBorder)
                TextField(L("col.name", comment: ""), text: $name).textFieldStyle(.roundedBorder)
            }
        }
    }

    private var primaryConditionSection: some View {
        GroupBox(label: Text(L("alerts.primary", comment: "")).font(.system(size: 12, weight: .semibold))) {
            VStack(alignment: .leading, spacing: 8) {
                Picker(L("col.condition", comment: ""), selection: $condition) {
                    ForEach(AlertCondition.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                TextField(thresholdLabel(condition), text: $thresholdText).textFieldStyle(.roundedBorder)
            }
        }
    }

    private var secondaryConditionSection: some View {
        GroupBox(label:
            HStack {
                Text(L("alerts.secondary", comment: "")).font(.system(size: 12, weight: .semibold))
                Spacer()
                Toggle(L("alerts.secondary.enable", comment: ""), isOn: $hasSecondary)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
        ) {
            if hasSecondary {
                VStack(alignment: .leading, spacing: 8) {
                    Picker(L("alerts.logic", comment: ""), selection: $conditionLogic) {
                        ForEach(ConditionLogic.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker(L("col.condition", comment: ""), selection: $secondaryCondition) {
                        ForEach(AlertCondition.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    TextField(thresholdLabel(secondaryCondition), text: $secondaryThresholdText).textFieldStyle(.roundedBorder)
                }
            } else {
                Text(L("alerts.secondary.disabled", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var advancedDisclosure: some View {
        GroupBox(label:
            Button(action: { withAnimation { showAdvanced.toggle() } }) {
                HStack {
                    Image(systemName: showAdvanced ? "chevron.down" : "chevron.right")
                    Text(L("alerts.advanced", comment: "")).font(.system(size: 12, weight: .semibold))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        ) {
            if showAdvanced {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(L("alerts.cooldown", comment: ""))
                        Spacer()
                        TextField("", text: $cooldownText).textFieldStyle(.roundedBorder).frame(width: 80)
                    }
                    HStack {
                        Toggle(L("alerts.dailyCap", comment: ""), isOn: $hasDailyCap)
                        Spacer()
                        TextField("", text: $dailyCapText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .disabled(!hasDailyCap)
                    }
                    Toggle(L("alerts.tradingHoursOnly", comment: ""), isOn: $tradingHoursOnly)
                    Toggle(L("alerts.weekdaysOnly", comment: ""), isOn: $weekdaysOnly)
                    Text(L("alerts.advanced.hint", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func thresholdLabel(_ cond: AlertCondition) -> String {
        cond.isPercent ? L("alerts.thresholdPct", comment: "") : L("alerts.thresholdPrice", comment: "")
    }

    private func prefill() {
        guard let a = initial else { return }
        market = a.symbol.market
        code = a.symbol.code
        name = a.name
        condition = a.condition
        thresholdText = decimalToText(a.threshold, isPercent: a.condition.isPercent)

        if let sc = a.secondaryCondition, let st = a.secondaryThreshold {
            hasSecondary = true
            secondaryCondition = sc
            secondaryThresholdText = decimalToText(st, isPercent: sc.isPercent)
        }
        conditionLogic = a.conditionLogic

        cooldownText = "\(a.cooldownSeconds)"
        if let cap = a.maxTriggersPerDay {
            hasDailyCap = true
            dailyCapText = "\(cap)"
        }
        tradingHoursOnly = a.tradingHoursOnly
        weekdaysOnly = a.weekdaysOnly
    }

    private func decimalToText(_ d: Decimal, isPercent: Bool) -> String {
        if isPercent {
            return String(format: "%.2f", (d as NSDecimalNumber).doubleValue * 100)
        }
        return "\(d)"
    }

    private func parseThreshold(_ text: String, isPercent: Bool) -> Decimal? {
        guard let raw = Decimal(string: text.trimmingCharacters(in: .whitespaces)) else { return nil }
        return isPercent ? raw / 100 : raw
    }

    private func save() {
        guard !code.isEmpty else { error = L("error.codeRequired", comment: ""); return }
        guard let primaryTh = parseThreshold(thresholdText, isPercent: condition.isPercent) else {
            error = L("error.thresholdInvalid", comment: ""); return
        }
        var secCond: AlertCondition? = nil
        var secTh: Decimal? = nil
        if hasSecondary {
            guard let th = parseThreshold(secondaryThresholdText, isPercent: secondaryCondition.isPercent) else {
                error = L("error.thresholdInvalid", comment: ""); return
            }
            secCond = secondaryCondition
            secTh = th
        }
        let cooldown = Int(cooldownText) ?? 300
        let cap: Int? = hasDailyCap ? Int(dailyCapText) : nil

        let symbol = SymbolID(code: code.trimmingCharacters(in: .whitespaces), market: market)
        var alert: Alert
        if let initial = initial {
            alert = initial
            alert.symbol = symbol
            alert.name = name.isEmpty ? code : name
            alert.condition = condition
            alert.threshold = primaryTh
            alert.secondaryCondition = secCond
            alert.secondaryThreshold = secTh
            alert.conditionLogic = conditionLogic
            alert.cooldownSeconds = cooldown
            alert.maxTriggersPerDay = cap
            alert.tradingHoursOnly = tradingHoursOnly
            alert.weekdaysOnly = weekdaysOnly
        } else {
            alert = Alert(
                symbol: symbol,
                name: name.isEmpty ? code : name,
                condition: condition,
                threshold: primaryTh,
                secondaryCondition: secCond,
                secondaryThreshold: secTh,
                conditionLogic: conditionLogic,
                cooldownSeconds: cooldown,
                maxTriggersPerDay: cap,
                tradingHoursOnly: tradingHoursOnly,
                weekdaysOnly: weekdaysOnly
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
