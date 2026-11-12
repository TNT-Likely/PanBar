import SwiftUI

private struct PortfolioColumnWidths {
    let horizontalPadding: CGFloat = 10
    let spacing: CGFloat = 8
    let drag: CGFloat = 18
    let symbol: CGFloat = 62
    let market: CGFloat = 34
    let actions: CGFloat = 44
    let name: CGFloat
    let quantity: CGFloat
    let cost: CGFloat
    let contentWidth: CGFloat

    init(totalWidth: CGFloat, holdings: [Holding], nameHeader: String) {
        let quantityBase: CGFloat = 48
        let costBase: CGFloat = 76
        let measuredName = ([nameHeader] + holdings.map(\.name))
            .map(Self.measuredNameWidth)
            .max() ?? Self.measuredNameWidth(nameHeader)
        let nameCap = max(88, min(180, totalWidth * 0.32))
        name = min(max(88, measuredName), nameCap)

        let fixedWidth = horizontalPadding * 2
            + spacing * 6
            + drag
            + symbol
            + name
            + market
            + actions
        let flexibleBase = quantityBase + costBase
        let extraWidth = max(0, totalWidth - fixedWidth - flexibleBase)

        quantity = quantityBase + extraWidth / 2
        cost = costBase + extraWidth / 2
        contentWidth = fixedWidth + flexibleBase + extraWidth
    }

    private static func measuredNameWidth(_ value: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13)
        let width = (value as NSString).size(withAttributes: [.font: font]).width
        return ceil(width) + 8
    }
}

struct PortfolioPane: View {
    @Environment(\.container) private var container
    @State private var holdings: [Holding] = []
    @EnvironmentObject private var navigation: SettingsNavigation
    @State private var groups: [PortfolioGroup] = []
    @State private var showGroups = false
    @State private var showAdd: Bool = false
    @State private var editing: Holding?
    @State private var deleting: Holding?
    @State private var selectedID: UUID?
    @State private var dropTargetID: UUID?    // 当前正在被拖入的行 id,用于画 drop indicator

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

            Button(L("groups.manage")) { showGroups = true }
            holdingsList

            if holdings.isEmpty {
                Text(L("holdings.empty", comment: ""))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
            }
        }
        .padding(20)
        .onAppear { reload(); handlePendingAction() }
        .onChange(of: navigation.pendingAction) { _ in handlePendingAction() }
        .sheet(isPresented: $showGroups, onDismiss: reload) {
            PortfolioGroupsSheet(kind: .holdings)
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

    private func handlePendingAction() {
        switch navigation.pendingAction {
        case .addHolding:
            showAdd = true
        case .editHolding(let id):
            editing = holdings.first { $0.id == id }
        case .manageHoldingGroups:
            showGroups = true
        default:
            return
        }
        navigation.pendingAction = nil
    }

    private func reload() {
        groups = ((try? container?.groupsRepo.all()) ?? []).filter { $0.kind == .holdings }
        holdings = (try? container?.holdingsRepo.all()) ?? []
    }

    /// 之前用 SwiftUI List + .onMove + selection 在 macOS 反复踩 bug(选中不高亮、
    /// 第二次拖不动)。改成 ScrollView + LazyVStack 手撸,行为完全自己控制。
    /// 拖拽:.draggable(行 ID)+ .dropDestination(整行作为放置目标)。
    /// 选中:单击置 selectedID,改背景色。
    private var holdingsList: some View {
        GeometryReader { proxy in
            let nameHeader = L("col.name", comment: "")
            let columns = PortfolioColumnWidths(totalWidth: proxy.size.width, holdings: holdings, nameHeader: nameHeader)

            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: columns.spacing) {
                        Text("").frame(width: columns.drag)
                        Text(L("col.symbol", comment: "")).frame(width: columns.symbol, alignment: .leading)
                        Text(nameHeader).frame(width: columns.name, alignment: .leading)
                        Text(L("col.market", comment: "")).frame(width: columns.market, alignment: .leading)
                        Text(L("col.qty", comment: "")).frame(width: columns.quantity, alignment: .center)
                        Text(L("col.cost", comment: "")).frame(width: columns.cost, alignment: .center)
                        Text("").frame(width: columns.actions)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, columns.horizontalPadding)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.08))

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(holdings.enumerated()), id: \.element.id) { index, h in
                                holdingRow(h, index: index, isAlternate: index.isMultiple(of: 2), columns: columns)
                            }
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                }
                .frame(width: columns.contentWidth, height: proxy.size.height, alignment: .topLeading)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
        }
        .frame(minHeight: 260)
    }

    @ViewBuilder
    private func holdingRow(_ h: Holding, index: Int, isAlternate: Bool, columns: PortfolioColumnWidths) -> some View {
        let isSelected = selectedID == h.id
        let isDropTarget = dropTargetID == h.id

        HStack(spacing: columns.spacing) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.55))
                .frame(width: columns.drag)
                .help(L("action.dragToReorder", comment: ""))
            Text(h.symbol.market == .us ? h.symbol.code.uppercased() : h.symbol.code)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: columns.symbol, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(h.name).lineLimit(1).truncationMode(.tail)
                Text(groups.first { $0.id == h.groupID }?.name ?? L("groups.ungrouped"))
                    .font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            .frame(width: columns.name, alignment: .leading)
            Text(h.symbol.market.displayName)
                .lineLimit(1)
                .frame(width: columns.market, alignment: .leading)
                .foregroundColor(.secondary)
            Text(quantityText(h.quantity))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: columns.quantity, alignment: .center)
            Text(h.currency.format(h.costPrice, fractionDigits: 3))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: columns.cost, alignment: .center)
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
            .frame(width: columns.actions)
        }
        .padding(.horizontal, columns.horizontalPadding)
        .padding(.vertical, 6)
        .background(rowBackground(isSelected: isSelected, isAlternate: isAlternate))
        .overlay(alignment: .top) {
            if isDropTarget {
                // 拖拽时在目标行顶部画一条蓝色横线作 drop indicator
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editing = h }
        .onTapGesture { selectedID = h.id }
        .draggable(h.id.uuidString) {
            // 拖拽时的预览(浮起来的那个小卡片)
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal")
                Text(h.name).bold()
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        .dropDestination(for: String.self) { droppedIDs, _ in
            handleDrop(droppedIDs: droppedIDs, ontoIndex: index)
        } isTargeted: { hovering in
            dropTargetID = hovering ? h.id : (dropTargetID == h.id ? nil : dropTargetID)
        }
    }

    private func rowBackground(isSelected: Bool, isAlternate: Bool) -> Color {
        if isSelected { return Color.accentColor.opacity(0.20) }
        return isAlternate ? Color.secondary.opacity(0.05) : Color.clear
    }

    private func quantityText(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? NSDecimalNumber(decimal: value).stringValue
    }

    /// 把 droppedIDs(UUID string)对应的行移到 ontoIndex 位置,持久化新 sortOrder。
    private func handleDrop(droppedIDs: [String], ontoIndex target: Int) -> Bool {
        guard let firstStr = droppedIDs.first,
              let firstID = UUID(uuidString: firstStr),
              let sourceIndex = holdings.firstIndex(where: { $0.id == firstID }),
              sourceIndex != target else { return false }
        let item = holdings.remove(at: sourceIndex)
        // 移除后,target 索引可能因为前面少了一个元素需要回退一位
        let insertAt = sourceIndex < target ? target - 1 : target
        holdings.insert(item, at: insertAt)
        let ids = holdings.map { $0.id }
        try? container?.holdingsRepo.reorder(ids: ids)
        return true
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

@MainActor
struct HoldingEditorSheet: View {
    @Environment(\.container) private var container
    @StateObject private var draft: HoldingEditorDraft
    @State private var groups: [PortfolioGroup] = []
    private let embedded: Bool
    var onSaved: () -> Void
    var onCancel: () -> Void

    init(initial: Holding? = nil, draft: HoldingEditorDraft? = nil, embedded: Bool = false,
         onSaved: @escaping () -> Void, onCancel: @escaping () -> Void) {
        _draft = StateObject(wrappedValue: draft ?? HoldingEditorDraft(initial: initial))
        self.embedded = embedded
        self.onSaved = onSaved
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L(draft.id == nil ? "holdings.addTitle" : "holdings.editTitle"))
                .font(.title3)
                .padding(.horizontal, 14)
                .padding(.top, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !embedded || draft.id == nil {
                        SymbolSearchField(vm: draft.searchVM, onPick: draft.pick)
                    }
                    Form {
                        Picker(L("groups.group"), selection: $draft.groupID) {
                            Text(L("groups.ungrouped")).tag(nil as UUID?)
                            ForEach(groups) { group in Text(group.name).tag(Optional(group.id)) }
                        }
                        Picker(L("col.market"), selection: $draft.market) {
                            ForEach(Market.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        TextField(L("col.symbol"), text: $draft.code).textFieldStyle(.roundedBorder)
                        TextField(L("col.name"), text: $draft.name).textFieldStyle(.roundedBorder)
                        TextField(L("col.qty"), text: $draft.quantity).textFieldStyle(.roundedBorder)
                        TextField(L("col.cost"), text: $draft.costPrice).textFieldStyle(.roundedBorder)
                    }
                }
                .padding(14)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let error = draft.error {
                    Text(error).foregroundColor(.red).font(.caption).lineLimit(3).help(error)
                }
                HStack {
                    Spacer()
                    Button(L("action.cancel"), action: onCancel)
                    Button(L("action.save"), action: save).keyboardShortcut(.defaultAction)
                }
            }
            .padding(12)
        }
        .frame(width: embedded ? nil : 460, height: embedded ? nil : 430)
        .onAppear {
            groups = ((try? container?.groupsRepo.all()) ?? []).filter { $0.kind == .holdings }
            draft.searchVM.bind(container?.symbolSearch)
        }
    }

    private func save() {
        do {
            guard let container else { throw EditorError("editor.unavailable") }
            try draft.save(to: container.holdingsRepo, groups: container.groupsRepo)
            draft.error = nil
            onSaved()
        } catch {
            draft.error = error.localizedDescription
        }
    }
}
