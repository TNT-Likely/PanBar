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

    @Published var currentTab: Tab = .holdings
    @Published var holdings: [Holding] = []
    @Published var watchlist: [WatchItem] = []

    @Published var groups: [PortfolioGroup] = []
    @Published var reorderError: String?
    @Published private var expandedGroups: Set<String> = []
    @Published private var ungroupedPositions: [String: Int] = [:]
    @Published private var indexOrder: [String] = []

    let groupsRepo: PortfolioGroupsRepository
    let refresher: QuoteRefresher
    let holdingsRepo: HoldingsRepository
    let watchlistRepo: WatchlistRepository
    let settingsRepo: SettingsRepository

    private var observationTasks: [Task<Void, Never>] = []

    init(
        refresher: QuoteRefresher,
        holdingsRepo: HoldingsRepository,
        watchlistRepo: WatchlistRepository,
        settingsRepo: SettingsRepository,
        groupsRepo: PortfolioGroupsRepository
    ) {
        self.refresher = refresher
        self.holdingsRepo = holdingsRepo
        self.watchlistRepo = watchlistRepo
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
        for kind in [PortfolioGroupKind.holdings, .watchlist] {
            ungroupedPositions[kind.rawValue] = settingsRepo.string(SettingsRepository.Keys.ungroupedPosition(kind)).flatMap(Int.init)
        }
        let stored = (settingsRepo.string(SettingsRepository.Keys.popoverIndexOrder) ?? "").split(separator: ",").map(String.init)
        indexOrder = PopoverOrder.indexIDs(stored: stored)
    }

    func groupIDs(for kind: PortfolioGroupKind) -> [UUID?] {
        let hasUngrouped = kind == .holdings
            ? holdings.contains { $0.groupID == nil }
            : watchlist.contains { $0.groupID == nil }
        return PopoverOrder.groupIDs(groups, kind: kind, hasUngrouped: hasUngrouped,
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
        guard source.kind == .holding, let id = UUID(uuidString: source.id),
              let ids = PopoverOrder.movingItem(id, to: target, after: after, in: holdings, groupID: \.groupID) else { return false }
        return saveOrder {
            try holdingsRepo.reorder(ids: ids)
            let byID = Dictionary(uniqueKeysWithValues: holdings.map { ($0.id, $0) })
            holdings = ids.enumerated().compactMap { order, id in
                guard var holding = byID[id] else { return nil }
                holding.sortOrder = order
                return holding
            }
        }
    }

    func moveWatchItem(_ source: PopoverDragItem, to target: UUID, after: Bool) -> Bool {
        guard source.kind == .watch, let id = UUID(uuidString: source.id),
              let ids = PopoverOrder.movingItem(id, to: target, after: after, in: watchlist, groupID: \.groupID) else { return false }
        return saveOrder {
            try watchlistRepo.reorder(ids: ids)
            let byID = Dictionary(uniqueKeysWithValues: watchlist.map { ($0.id, $0) })
            watchlist = ids.enumerated().compactMap { order, id in
                guard var item = byID[id] else { return nil }
                item.order = order
                return item
            }
        }
    }

    func orderedIndexQuotes(_ quotes: [IndexQuote]) -> [IndexQuote] {
        let byID = Dictionary(uniqueKeysWithValues: quotes.map { ($0.id, $0) })
        return indexOrder.compactMap { byID[$0] }
    }

    func moveIndex(_ source: PopoverDragItem, to target: String, after: Bool) -> Bool {
        guard source.kind == .index,
              let ids = PopoverOrder.moving(source.id, to: target, after: after, in: indexOrder) else { return false }
        return saveOrder {
            try settingsRepo.set(SettingsRepository.Keys.popoverIndexOrder, ids.joined(separator: ","))
            indexOrder = ids
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
        observationTasks = [h, w, g]
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
