import SwiftUI

struct AlertsPane: View {
    @Environment(\.container) private var container
    @EnvironmentObject private var refresher: QuoteRefresher
    @EnvironmentObject private var navigation: SettingsNavigation
    @State private var alerts: [Alert] = []
    @State private var showAdd: Bool = false
    @State private var editing: Alert?
    @State private var selection: Set<Alert.ID> = []

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

            AlertPermissionBanner()

            Table(alerts, selection: $selection) {
                TableColumn(L("col.symbol", comment: "")) { (a: Alert) in
                    Text(a.symbol.market == .us ? a.symbol.code.uppercased() : a.symbol.code)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { editing = a }
                }
                TableColumn(L("alerts.currentPrice")) { (a: Alert) in
                    let quote = refresher.quotes[a.symbol]
                    Text(quote.map { $0.currency.format($0.price) } ?? "--")
                        .monospacedDigit()
                        .help(quote.map { String(format: L("alerts.priceUpdated"), $0.timestamp.formatted(date: .abbreviated, time: .standard)) } ?? L("alerts.noQuote"))
                }
                TableColumn(L("col.condition", comment: "")) { (a: Alert) in
                    Text(a.conditionText)
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
            handlePendingAction()
        }
        .onChange(of: navigation.pendingAction) { _ in handlePendingAction() }
        .sheet(isPresented: $showAdd) {
            AlertEditorSheet(initial: nil) {
                showAdd = false
                reload()
            } onCancel: {
                showAdd = false
            }
        }
        .sheet(item: $editing, onDismiss: handlePendingAction) { existing in
            AlertEditorSheet(initial: existing) {
                editing = nil
                reload()
            } onCancel: { editing = nil }
        }
    }

    private func handlePendingAction() {
        // 等现有编辑弹窗关闭后再添加，避免打断未保存的编辑。
        guard navigation.pendingAction == .addAlert, editing == nil else { return }
        navigation.pendingAction = nil
        showAdd = true
    }

    private func reload() {
        alerts = (try? container?.alertsRepo.all()) ?? []
        refresher.refreshNow()
    }

    private func testNotification() {
        NotificationService.shared.sendTest()
    }
}

struct AlertPermissionBanner: View {
    @ObservedObject private var notificationService = NotificationService.shared

    @ViewBuilder
    var body: some View {
        let status = notificationService.authorizationStatus
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

@MainActor
struct AlertEditorSheet: View {
    @Environment(\.container) private var container
    @StateObject private var draft: AlertEditorDraft
    private let embedded: Bool
    private let symbols: [SymbolSearchResult]
    var onSaved: () -> Void
    var onCancel: () -> Void

    init(initial: Alert? = nil, symbol: SymbolSearchResult? = nil, draft: AlertEditorDraft? = nil,
         embedded: Bool = false, symbols: [SymbolSearchResult] = [],
         onSaved: @escaping () -> Void, onCancel: @escaping () -> Void) {
        _draft = StateObject(wrappedValue: draft ?? AlertEditorDraft(initial: initial, symbol: symbol))
        self.embedded = embedded
        self.symbols = symbols
        self.onSaved = onSaved
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L(draft.id == nil ? "alerts.addTitle" : "alerts.editTitle"))
                .font(embedded ? .system(size: 13, weight: .semibold) : .title3)
                .padding(.horizontal, 14)
                .padding(.top, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if embedded { AlertPermissionBanner() }
                    if embedded && draft.usesPortfolioSymbols {
                        portfolioSection
                    } else {
                        SymbolSearchField(vm: draft.searchVM, onPick: draft.pick)
                        basicSection
                    }
                    primaryConditionSection
                    secondaryConditionSection
                    advancedDisclosure
                }
                .frame(maxWidth: embedded ? .infinity : nil, alignment: .leading)
                .padding(14)
                .font(embedded ? .system(size: 12) : nil)
                .controlSize(embedded ? .small : .regular)
            }
            .frame(maxHeight: embedded ? .infinity : nil)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let error = draft.error {
                    Text(error).foregroundColor(.red).font(.caption).lineLimit(3).help(error)
                }
                HStack {
                    Spacer()
                    Button(L("action.cancel"), action: onCancel)
                    Button(L("action.save"), action: save).keyboardShortcut(.defaultAction)
                        .disabled(embedded && !draft.canSave(symbols: symbols))
                }
            }
            .padding(12)
        }
        .frame(maxWidth: embedded ? .infinity : nil, maxHeight: embedded ? .infinity : nil, alignment: .topLeading)
        .frame(width: embedded ? nil : 520, height: embedded ? nil : 620)
        .onAppear { draft.searchVM.bind(container?.symbolSearch) }
    }

    private var portfolioSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("alerts.portfolioTitle"))
                    .font(.system(size: 12, weight: .semibold))
                if symbols.isEmpty {
                    Text(L("alerts.portfolioEmpty"))
                        .foregroundColor(.secondary)
                } else {
                    Picker(L("alerts.portfolioTitle"), selection: Binding(
                        get: { symbols.first { $0.symbol.storageKey == draft.selectedSymbolKey }?.symbol.storageKey },
                        set: { key in draft.selectSymbol(symbols.first { $0.symbol.storageKey == key }) }
                    )) {
                        Text(L("alerts.choosePortfolio")).tag(nil as String?)
                        ForEach(symbols) { item in
                            Text("\(item.name) · \(item.symbol.market == .us ? item.symbol.code.uppercased() : item.symbol.code) · \(item.symbol.market.displayName)")
                                .tag(Optional(item.symbol.storageKey))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                }
                Button(L("alerts.otherSymbol")) {
                    SettingsWindowController.shared.show(initialAction: .addAlert)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var basicSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Picker(L("col.market", comment: ""), selection: $draft.market) {
                    ForEach(Market.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                TextField(L("col.symbol", comment: ""), text: $draft.code).textFieldStyle(.roundedBorder)
                TextField(L("col.name", comment: ""), text: $draft.name).textFieldStyle(.roundedBorder)
            }
            .frame(maxWidth: embedded ? .infinity : nil, alignment: .leading)
        }
    }

    private var primaryConditionSection: some View {
        GroupBox(label: Text(L("alerts.primary", comment: "")).font(.system(size: 12, weight: .semibold))) {
            VStack(alignment: .leading, spacing: 8) {
                Picker(L("col.condition", comment: ""), selection: $draft.condition) {
                    ForEach(AlertCondition.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                TextField(thresholdLabel(draft.condition), text: $draft.thresholdText).textFieldStyle(.roundedBorder)
            }
            .frame(maxWidth: embedded ? .infinity : nil, alignment: .leading)
        }
    }

    @ViewBuilder
    private var secondaryConditionSection: some View {
        if embedded {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    secondaryHeader
                    secondaryFields
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            GroupBox(label: secondaryHeader) { secondaryFields }
        }
    }

    private var secondaryHeader: some View {
        HStack {
            Text(L("alerts.secondary", comment: "")).font(.system(size: 12, weight: .semibold))
            Spacer()
            Toggle(L("alerts.secondary.enable", comment: ""), isOn: $draft.hasSecondary)
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }

    @ViewBuilder
    private var secondaryFields: some View {
        if draft.hasSecondary {
            VStack(alignment: .leading, spacing: 8) {
                Picker(L("alerts.logic", comment: ""), selection: $draft.conditionLogic) {
                    ForEach(ConditionLogic.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker(L("col.condition", comment: ""), selection: $draft.secondaryCondition) {
                    ForEach(AlertCondition.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                TextField(thresholdLabel(draft.secondaryCondition), text: $draft.secondaryThresholdText).textFieldStyle(.roundedBorder)
            }
        } else {
            Text(L("alerts.secondary.disabled", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var advancedDisclosure: some View {
        if embedded {
            VStack(alignment: .leading, spacing: 8) {
                advancedButton
                if draft.showAdvanced {
                    GroupBox {
                        advancedFields.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        } else {
            GroupBox(label: advancedButton) {
                if draft.showAdvanced { advancedFields }
            }
        }
    }

    private var advancedButton: some View {
        Button(action: { withAnimation { draft.showAdvanced.toggle() } }) {
            HStack {
                Image(systemName: draft.showAdvanced ? "chevron.down" : "chevron.right")
                Text(L("alerts.advanced", comment: "")).font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var advancedFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("alerts.cooldown", comment: ""))
                Spacer()
                TextField("", text: $draft.cooldownText).textFieldStyle(.roundedBorder).frame(width: 80)
            }
            HStack {
                Toggle(L("alerts.dailyCap", comment: ""), isOn: $draft.hasDailyCap)
                Spacer()
                TextField("", text: $draft.dailyCapText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .disabled(!draft.hasDailyCap)
            }
            Toggle(L("alerts.tradingHoursOnly", comment: ""), isOn: $draft.tradingHoursOnly)
            Toggle(L("alerts.weekdaysOnly", comment: ""), isOn: $draft.weekdaysOnly)
            Text(L("alerts.advanced.hint", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func thresholdLabel(_ cond: AlertCondition) -> String {
        cond.isPercent ? L("alerts.thresholdPct", comment: "") : L("alerts.thresholdPrice", comment: "")
    }

    private func save() {
        do {
            guard let container else { throw EditorError("editor.unavailable") }
            try draft.save(to: container.alertsRepo, symbols: symbols)
            draft.error = nil
            onSaved()
        } catch {
            draft.error = error.localizedDescription
        }
    }
}
