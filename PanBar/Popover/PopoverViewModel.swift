import Foundation
import Combine

@MainActor
final class PopoverViewModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case holdings, watchlist, indices, alerts
        var id: String { rawValue }
        var title: String {
            switch self {
            case .holdings:  return L("tab.holdings", comment: "")
            case .watchlist: return L("tab.watchlist", comment: "")
            case .indices:   return L("tab.indices", comment: "")
            case .alerts:    return L("tab.alerts", comment: "")
            }
        }
    }

    enum Editor {
        case watch(WatchEditorDraft)
        case holding(HoldingEditorDraft)
        case alert(AlertEditorDraft)
    }

    @Published var currentTab: Tab = .holdings {
        didSet { if currentTab != oldValue { itemDrag.cancel() } }
    }
    let itemDrag = PopoverItemDrag()
    // 面板每次打开都会重建 SwiftUI 根视图，草稿由长期存在的 view model 持有。
    @Published private(set) var editors: [Tab: Editor] = [:]
    @Published var holdings: [Holding] = []
    @Published var watchlist: [WatchItem] = []
    @Published var alerts: [Alert] = []

    @Published var groups: [PortfolioGroup] = []
    @Published var reorderError: String?
    @Published private var expandedGroups: Set<String> = []
    @Published private var ungroupedPositions: [String: Int] = [:]
    @Published private var indexOrder: [String] = []
    @Published private var alertOrder: [String] = []

    let groupsRepo: PortfolioGroupsRepository
    let refresher: QuoteRefresher
    let holdingsRepo: HoldingsRepository
    let watchlistRepo: WatchlistRepository
    let alertsRepo: AlertsRepository
    let settingsRepo: SettingsRepository

    private var observationTasks: [Task<Void, Never>] = []

    init(
        refresher: QuoteRefresher,
        holdingsRepo: HoldingsRepository,
        watchlistRepo: WatchlistRepository,
        alertsRepo: AlertsRepository,
        settingsRepo: SettingsRepository,
        groupsRepo: PortfolioGroupsRepository
    ) {
        self.refresher = refresher
        self.holdingsRepo = holdingsRepo
        self.watchlistRepo = watchlistRepo
        self.alertsRepo = alertsRepo
        self.settingsRepo = settingsRepo
        self.groupsRepo = groupsRepo
        expandedGroups = Set((settingsRepo.string("expanded_portfolio_groups") ?? "").split(separator: ",").map(String.init))
        reload()
        startObserving()
    }

    func reload() {
        groups = (try? groupsRepo.all()) ?? []
        holdings = (try? holdingsRepo.all()) ?? []
        watchlist = (try? watchlistRepo.all()) ?? []
        alerts = (try? alertsRepo.all()) ?? []
        for kind in [PortfolioGroupKind.holdings, .watchlist] {
            ungroupedPositions[kind.rawValue] = settingsRepo.string(SettingsRepository.Keys.ungroupedPosition(kind)).flatMap(Int.init)
        }
        let stored = (settingsRepo.string(SettingsRepository.Keys.popoverIndexOrder) ?? "").split(separator: ",").map(String.init)
        indexOrder = PopoverOrder.indexIDs(stored: stored)
        alertOrder = (settingsRepo.string(SettingsRepository.Keys.popoverAlertOrder) ?? "").split(separator: ",").map(String.init)
    }

    func openWatchEditor() {
        guard editors[.watchlist] == nil else { return }
        editors[.watchlist] = .watch(WatchEditorDraft())
    }

    func openHoldingEditor(_ holding: Holding? = nil) {
        guard editors[.holdings] == nil else { return }
        editors[.holdings] = .holding(HoldingEditorDraft(initial: holding))
    }

    func openAlertEditor(_ alert: Alert? = nil, symbol: SymbolSearchResult? = nil) {
        guard currentTab != .indices, editors[currentTab] == nil else { return }
        editors[currentTab] = .alert(AlertEditorDraft(initial: alert, symbol: symbol,
                                                    usesPortfolioSymbols: currentTab == .alerts))
    }

    var alertSymbols: [SymbolSearchResult] {
        let held = groupIDs(for: .holdings).flatMap { groupID in
            holdings.filter { $0.groupID == groupID }
                .map { SymbolSearchResult(symbol: $0.symbol, name: $0.name) }
        }
        let watched = groupIDs(for: .watchlist).flatMap { groupID in
            watchlist.filter { $0.groupID == groupID }
                .map { SymbolSearchResult(symbol: $0.symbol, name: $0.name) }
        }
        var seen = Set<String>()
        return (held + watched).filter { seen.insert($0.symbol.storageKey).inserted }
    }

    func cancelEditor(in tab: Tab) {
        editors[tab] = nil
    }

    func finishEditor(in tab: Tab) {
        guard let editor = editors[tab] else { return }
        switch editor {
        case .watch(let draft):
            if !isExpanded(draft.groupID, kind: .watchlist) { toggleGroup(draft.groupID, kind: .watchlist) }
        case .holding(let draft):
            if !isExpanded(draft.groupID, kind: .holdings) { toggleGroup(draft.groupID, kind: .holdings) }
        case .alert:
            break
        }
        reload()
        editors[tab] = nil
        refresher.refreshNow()
    }

    func groupIDs(for kind: PortfolioGroupKind, includingEmptyUngrouped: Bool = false) -> [UUID?] {
        let hasUngrouped = kind == .holdings
            ? holdings.contains { $0.groupID == nil }
            : watchlist.contains { $0.groupID == nil }
        return PopoverOrder.groupIDs(groups, kind: kind, hasUngrouped: hasUngrouped || includingEmptyUngrouped,
                                     ungroupedPosition: ungroupedPositions[kind.rawValue])
    }

    func moveGroup(_ source: PopoverDragItem, to target: UUID?, kind: PortfolioGroupKind, after: Bool) -> Bool {
        let ids = groupIDs(for: kind)
        guard source.kind == PopoverDragItem.group(target, kind: kind).kind,
              let sourceIndex = ids.firstIndex(where: { PopoverDragItem.group($0, kind: kind) == source }),
              let reordered = PopoverOrder.moving(ids[sourceIndex], to: target, after: after, in: ids) else { return false }
        return saveOrder {
            try groupsRepo.reorder(ids: reordered, kind: kind)
            let byID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
            let updated = reordered.compactMap { $0 }.enumerated().compactMap { order, id -> PortfolioGroup? in
                guard var group = byID[id] else { return nil }
                group.sortOrder = order
                return group
            }
            groups = groups.filter { $0.kind != kind } + updated
            if let position = reordered.firstIndex(where: { $0 == nil }) {
                ungroupedPositions[kind.rawValue] = position
            }
        }
    }

    func moveHolding(_ source: PopoverDragItem, to target: UUID, after: Bool) -> Bool {
        guard source.id != target.uuidString, let row = holdings.first(where: { $0.id == target }) else { return false }
        let peers = holdings.filter { $0.groupID == row.groupID && $0.id.uuidString != source.id }
        guard let index = peers.firstIndex(where: { $0.id == target }) else { return false }
        return moveHolding(source, toGroup: row.groupID, before: after ? peers.dropFirst(index + 1).first?.id : target)
    }

    func moveHolding(_ source: PopoverDragItem, toGroup groupID: UUID?, before target: UUID?) -> Bool {
        guard source.kind == .holding, let id = UUID(uuidString: source.id) else { return false }
        var moved = false
        let saved = saveOrder {
            guard let updated = try holdingsRepo.move(id: id, toGroup: groupID, before: target) else { return }
            holdings = updated
            if !isExpanded(groupID, kind: .holdings) { toggleGroup(groupID, kind: .holdings) }
            moved = true
        }
        return saved && moved
    }

    func moveWatchItem(_ source: PopoverDragItem, to target: UUID, after: Bool) -> Bool {
        guard source.id != target.uuidString, let row = watchlist.first(where: { $0.id == target }) else { return false }
        let peers = watchlist.filter { $0.groupID == row.groupID && $0.id.uuidString != source.id }
        guard let index = peers.firstIndex(where: { $0.id == target }) else { return false }
        return moveWatchItem(source, toGroup: row.groupID, before: after ? peers.dropFirst(index + 1).first?.id : target)
    }

    func moveWatchItem(_ source: PopoverDragItem, toGroup groupID: UUID?, before target: UUID?) -> Bool {
        guard source.kind == .watch, let id = UUID(uuidString: source.id) else { return false }
        var moved = false
        let saved = saveOrder {
            guard let updated = try watchlistRepo.move(id: id, toGroup: groupID, before: target) else { return }
            watchlist = updated
            if !isExpanded(groupID, kind: .watchlist) { toggleGroup(groupID, kind: .watchlist) }
            moved = true
        }
        return saved && moved
    }

    func orderedIndexQuotes(_ quotes: [IndexQuote]) -> [IndexQuote] {
        let byID = Dictionary(uniqueKeysWithValues: quotes.map { ($0.id, $0) })
        return indexOrder.compactMap { byID[$0] }
    }

    func moveIndex(_ source: PopoverDragItem, to target: String, after: Bool) -> Bool {
        guard let index = indexOrder.firstIndex(of: target) else { return false }
        let before = after ? indexOrder.dropFirst(index + 1).first : target
        return moveIndex(source, before: before)
    }

    func moveIndex(_ source: PopoverDragItem, before target: String?) -> Bool {
        guard source.kind == .index,
              let ids = PopoverOrder.moving(source.id, before: target, in: indexOrder) else { return false }
        return saveOrder {
            try settingsRepo.set(SettingsRepository.Keys.popoverIndexOrder, ids.joined(separator: ","))
            indexOrder = ids
        }
    }

    var orderedAlerts: [Alert] {
        let byID = Dictionary(uniqueKeysWithValues: alerts.map { ($0.id.uuidString, $0) })
        return PopoverOrder.orderedIDs(stored: alertOrder, available: alerts.map { $0.id.uuidString }).compactMap { byID[$0] }
    }

    func moveAlert(_ source: PopoverDragItem, before target: String?) -> Bool {
        guard source.kind == .alert,
              let ids = PopoverOrder.moving(source.id, before: target, in: orderedAlerts.map({ $0.id.uuidString })) else { return false }
        return saveOrder {
            try settingsRepo.set(SettingsRepository.Keys.popoverAlertOrder, ids.joined(separator: ","))
            alertOrder = ids
        }
    }

    private func saveOrder(_ save: () throws -> Void) -> Bool {
        do {
            try save()
            return true
        } catch {
            Log.ui.error("save order failed: \(String(describing: error), privacy: .public)")
            reorderError = L("reorder.errorMessage")
            return false
        }
    }

    private func startObserving() {
        let h = Task { [weak self] in
            guard let stream = self?.holdingsRepo.observeAll() else { return }
            for await items in stream {
                await MainActor.run { self?.holdings = items }
            }
        }
        let w = Task { [weak self] in
            guard let stream = self?.watchlistRepo.observeAll() else { return }
            for await items in stream {
                await MainActor.run { self?.watchlist = items }
            }
        }
        let g = Task { [weak self] in
            guard let stream = self?.groupsRepo.observeAll() else { return }
            for await groups in stream {
                self?.groups = groups
            }
        }
        let a = Task { [weak self] in
            guard let stream = self?.alertsRepo.observeAll() else { return }
            for await items in stream {
                self?.alerts = items
            }
        }
        observationTasks = [h, w, g, a]
    }

    func isExpanded(_ groupID: UUID?, kind: PortfolioGroupKind) -> Bool {
        expandedGroups.contains(expansionKey(groupID, kind: kind))
    }

    func toggleGroup(_ groupID: UUID?, kind: PortfolioGroupKind) {
        let key = expansionKey(groupID, kind: kind)
        if !expandedGroups.insert(key).inserted { expandedGroups.remove(key) }
        try? settingsRepo.set("expanded_portfolio_groups", expandedGroups.sorted().joined(separator: ","))
    }

    private func expansionKey(_ groupID: UUID?, kind: PortfolioGroupKind) -> String {
        "\(kind.rawValue):\(groupID?.uuidString ?? "ungrouped")"
    }

    func deleteHolding(_ id: UUID) {
        try? holdingsRepo.delete(id: id)
        refresher.refreshNow()
    }

    func deleteWatchItem(_ id: UUID) {
        try? watchlistRepo.delete(id: id)
        refresher.refreshNow()
    }

    deinit {
        observationTasks.forEach { $0.cancel() }
    }
}
