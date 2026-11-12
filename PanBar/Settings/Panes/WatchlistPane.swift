import SwiftUI

struct WatchlistPane: View {
    @Environment(\.container) private var container
    @State private var items: [WatchItem] = []
    @EnvironmentObject private var navigation: SettingsNavigation
    @State private var groups: [PortfolioGroup] = []
    @State private var showGroups = false
    @State private var showAdd: Bool = false
    @State private var editing: WatchItem?
    @State private var deleting: WatchItem?
    @State private var selectedID: UUID?
    @State private var dropTargetID: UUID?

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
            Button(L("groups.manage")) { showGroups = true }
            watchlistList
            if items.isEmpty {
                Text(L("watchlist.empty", comment: ""))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
            }
        }
        .padding(20)
        .onAppear { reload(); handlePendingAction() }
        .onChange(of: navigation.pendingAction) { _ in handlePendingAction() }
        .sheet(isPresented: $showGroups, onDismiss: reload) {
            PortfolioGroupsSheet(kind: .watchlist)
        }
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
        .alert(
            String(format: L("delete.confirm.title", comment: ""), deleting?.name ?? ""),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button(L("action.cancel", comment: ""), role: .cancel) { deleting = nil }
            Button(L("action.delete", comment: ""), role: .destructive) {
                if let w = deleting {
                    try? container?.watchlistRepo.delete(id: w.id)
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
        case .addWatch: showAdd = true
        case .manageWatchGroups: showGroups = true
        default: return
        }
        navigation.pendingAction = nil
    }

    private func reload() {
        groups = ((try? container?.groupsRepo.all()) ?? []).filter { $0.kind == .watchlist }
        items = (try? container?.watchlistRepo.all()) ?? []
    }

    /// 同 PortfolioPane:抛弃 List(macOS 上选中态 + onMove 互相打架),改用
    /// ScrollView + LazyVStack 手撸 + .draggable/.dropDestination。
    private var watchlistList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("").frame(width: 18)
                Text(L("col.symbol", comment: "")).frame(width: 80, alignment: .leading)
                Text(L("col.name", comment: "")).frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                Text(L("col.market", comment: "")).frame(width: 56, alignment: .leading)
                Spacer().frame(width: 56)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.08))

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, w in
                        watchRow(w, index: index, isAlternate: index.isMultiple(of: 2))
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func watchRow(_ w: WatchItem, index: Int, isAlternate: Bool) -> some View {
        let isSelected = selectedID == w.id
        let isDropTarget = dropTargetID == w.id

        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.55))
                .frame(width: 18)
                .help(L("action.dragToReorder", comment: ""))
            Text(w.symbol.market == .us ? w.symbol.code.uppercased() : w.symbol.code)
                .frame(width: 80, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(w.name).lineLimit(1).truncationMode(.tail)
                Text(groups.first { $0.id == w.groupID }?.name ?? L("groups.ungrouped"))
                    .font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
            Text(w.symbol.market.displayName)
                .frame(width: 56, alignment: .leading)
                .foregroundColor(.secondary)
            HStack(spacing: 4) {
                Button { editing = w } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help(L("action.edit", comment: ""))
                Button(role: .destructive) {
                    deleting = w
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            .frame(width: 56)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(rowBackground(isSelected: isSelected, isAlternate: isAlternate))
        .overlay(alignment: .top) {
            if isDropTarget {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editing = w }
        .onTapGesture { selectedID = w.id }
        .draggable(w.id.uuidString) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal")
                Text(w.name).bold()
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        .dropDestination(for: String.self) { droppedIDs, _ in
            handleDrop(droppedIDs: droppedIDs, ontoIndex: index)
        } isTargeted: { hovering in
            dropTargetID = hovering ? w.id : (dropTargetID == w.id ? nil : dropTargetID)
        }
    }

    private func rowBackground(isSelected: Bool, isAlternate: Bool) -> Color {
        if isSelected { return Color.accentColor.opacity(0.20) }
        return isAlternate ? Color.secondary.opacity(0.05) : Color.clear
    }

    private func handleDrop(droppedIDs: [String], ontoIndex target: Int) -> Bool {
        guard let firstStr = droppedIDs.first,
              let firstID = UUID(uuidString: firstStr),
              let sourceIndex = items.firstIndex(where: { $0.id == firstID }),
              sourceIndex != target else { return false }
        let item = items.remove(at: sourceIndex)
        let insertAt = sourceIndex < target ? target - 1 : target
        items.insert(item, at: insertAt)
        let ids = items.map { $0.id }
        try? container?.watchlistRepo.reorder(ids: ids)
        return true
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

@MainActor
struct WatchEditorSheet: View {
    @Environment(\.container) private var container
    @StateObject private var draft: WatchEditorDraft
    @State private var groups: [PortfolioGroup] = []
    private let embedded: Bool
    var onSaved: () -> Void
    var onCancel: () -> Void

    init(initial: WatchItem? = nil, draft: WatchEditorDraft? = nil, embedded: Bool = false,
         onSaved: @escaping () -> Void, onCancel: @escaping () -> Void) {
        _draft = StateObject(wrappedValue: draft ?? WatchEditorDraft(initial: initial))
        self.embedded = embedded
        self.onSaved = onSaved
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L(draft.id == nil ? "watchlist.addTitle" : "watchlist.editTitle"))
                .font(.title3)
                .padding(.horizontal, 14)
                .padding(.top, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SymbolSearchField(vm: draft.searchVM, onPick: draft.pick)
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
        .frame(width: embedded ? nil : 460, height: embedded ? nil : 370)
        .onAppear {
            groups = ((try? container?.groupsRepo.all()) ?? []).filter { $0.kind == .watchlist }
            draft.searchVM.bind(container?.symbolSearch)
        }
    }

    private func save() {
        do {
            guard let container else { throw EditorError("editor.unavailable") }
            try draft.save(to: container.watchlistRepo, groups: container.groupsRepo)
            draft.error = nil
            onSaved()
        } catch {
            draft.error = error.localizedDescription
        }
    }
}
