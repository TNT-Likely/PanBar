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

    let refresher: QuoteRefresher
    let holdingsRepo: HoldingsRepository
    let watchlistRepo: WatchlistRepository
    let settingsRepo: SettingsRepository

    private var observationTasks: [Task<Void, Never>] = []

    init(
        refresher: QuoteRefresher,
        holdingsRepo: HoldingsRepository,
        watchlistRepo: WatchlistRepository,
        settingsRepo: SettingsRepository
    ) {
        self.refresher = refresher
        self.holdingsRepo = holdingsRepo
        self.watchlistRepo = watchlistRepo
        self.settingsRepo = settingsRepo
        reload()
        startObserving()
    }

    func reload() {
        holdings = (try? holdingsRepo.all()) ?? []
        watchlist = (try? watchlistRepo.all()) ?? []
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
        observationTasks = [h, w]
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
