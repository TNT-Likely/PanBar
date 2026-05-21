import Foundation
import Combine
import AppKit

/// 全局行情刷新泵。根据当前可见性 / 系统休眠 / 市场状态切换不同刷新频率。
@MainActor
final class QuoteRefresher: ObservableObject {
    enum Pace {
        case popoverOpen   // 3s
        case tickerOnly    // 5s
        case marketClosed  // 60s
        case sleeping      // 暂停

        var interval: TimeInterval {
            switch self {
            case .popoverOpen:  return 3
            case .tickerOnly:   return 5
            case .marketClosed: return 60
            case .sleeping:     return .infinity
            }
        }
    }

    @Published private(set) var snapshot: PortfolioSnapshot = .empty
    @Published private(set) var quotes: [SymbolID: Quote] = [:]
    @Published private(set) var lastError: String?
    @Published private(set) var lastUpdated: Date?

    private let service: PortfolioService
    private let clock: MarketClock
    private let alertEngine: AlertEngine?
    private var task: Task<Void, Never>?
    private var pace: Pace = .tickerOnly
    private var popoverOpen = false
    private var sleeping = false
    private var offline = false
    private var observers: [NSObjectProtocol] = []

    init(service: PortfolioService, clock: MarketClock, alertEngine: AlertEngine? = nil) {
        self.service = service
        self.clock = clock
        self.alertEngine = alertEngine
        observeSystem()
    }

    func setOffline(_ value: Bool) {
        offline = value
        recomputePace()
    }

    var isOffline: Bool { offline }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        task?.cancel()
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// 触发立即刷新一次(不影响调度)。
    func refreshNow() {
        Task { await tick() }
    }

    func setPopoverOpen(_ open: Bool) {
        popoverOpen = open
        recomputePace()
    }

    private func observeSystem() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.sleeping = true
                self?.recomputePace()
            }
        })
        observers.append(nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.sleeping = false
                self?.recomputePace()
            }
        })
    }

    private func recomputePace() {
        let next: Pace
        if sleeping || offline {
            next = .sleeping
        } else if popoverOpen {
            next = .popoverOpen
        } else if clock.anyOpen() {
            next = .tickerOnly
        } else {
            next = .marketClosed
        }
        pace = next
    }

    private func runLoop() async {
        await tick()
        while !Task.isCancelled {
            recomputePace()
            let interval = pace.interval
            if interval.isInfinite {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                continue
            }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            if Task.isCancelled { break }
            await tick()
        }
    }

    private func tick() async {
        do {
            let snap = try await service.computeSnapshot()
            let quoteMap = snap.positions.reduce(into: [SymbolID: Quote]()) { acc, pos in
                if let q = pos.quote { acc[pos.holding.symbol] = q }
            }
            await MainActor.run {
                self.snapshot = snap
                if !quoteMap.isEmpty {
                    self.quotes.merge(quoteMap) { _, new in new }
                }
                self.lastUpdated = Date()
                self.lastError = nil
                self.alertEngine?.evaluate(quotes: self.quotes)
            }
        } catch {
            await MainActor.run {
                self.lastError = String(describing: error)
            }
            Log.quote.error("refresh failed: \(String(describing: error), privacy: .public)")
        }
    }
}
