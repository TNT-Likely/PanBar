import AppKit
import SwiftUI

@MainActor
final class PopoverController {
    private let popover: NSPopover
    private let refresher: QuoteRefresher
    private let viewModel: PopoverViewModel

    var isShown: Bool { popover.isShown }

    init(
        refresher: QuoteRefresher,
        holdingsRepo: HoldingsRepository,
        watchlistRepo: WatchlistRepository,
        settingsRepo: SettingsRepository,
        appearancePrefs: AppearancePreferences,
        tickerPrefs: TickerPreferences,
        container: DependencyContainer
    ) {
        self.refresher = refresher
        self.viewModel = PopoverViewModel(
            refresher: refresher,
            holdingsRepo: holdingsRepo,
            watchlistRepo: watchlistRepo,
            settingsRepo: settingsRepo
        )

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 520)
        popover.contentViewController = NSHostingController(rootView:
            PopoverRoot()
                .environmentObject(viewModel)
                .environmentObject(refresher)
                .environmentObject(appearancePrefs)
                .environmentObject(tickerPrefs)
                .environment(\.container, container)  // 修复:之前没注入,导致 IndicesTab 拿不到 indexService
                .frame(width: 360, height: 520)
        )
        self.popover = popover
    }

    func show(relativeTo view: NSView) {
        refresher.setPopoverOpen(true)
        refresher.refreshNow()
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func close() {
        popover.performClose(nil)
        refresher.setPopoverOpen(false)
    }
}
