import AppKit
import SwiftUI

@MainActor
final class PopoverController {
    private let popover: NSPopover
    private let refresher: QuoteRefresher
    private let viewModel: PopoverViewModel
    /// 监听 popover 之外的点击,关 popover。`.transient` 行为对菜单栏 popover 有时漏
    /// (尤其是点系统菜单栏 / 通知 / 其它 app 时),这里多加一层保险。
    private var eventMonitor: Any?
    private var didCloseObserver: NSObjectProtocol?
    var onClose: (() -> Void)?

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

        // popover 通过 .transient 行为自己关时,也要更新 refresher 状态
        // (否则 pace 会一直停在 .popoverOpen,后台多耗一点请求)
        didCloseObserver = NotificationCenter.default.addObserver(
            forName: NSPopover.didCloseNotification,
            object: popover,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handlePopoverClosed()
            }
        }
    }

    deinit {
        if let m = eventMonitor { NSEvent.removeMonitor(m) }
        if let observer = didCloseObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func handlePopoverClosed() {
        stopOutsideClickMonitor()
        refresher.setPopoverOpen(false)
        onClose?()
    }

    func show(relativeTo view: NSView, anchorWidth: CGFloat? = nil) {
        refresher.setPopoverOpen(true)
        refresher.refreshNow()
        popover.show(relativeTo: positioningRect(relativeTo: view, anchorWidth: anchorWidth), of: view, preferredEdge: .minY)
        startOutsideClickMonitor()
    }

    private func positioningRect(relativeTo view: NSView, anchorWidth: CGFloat?) -> NSRect {
        let rect: NSRect
        if let anchorWidth {
            let width = max(view.bounds.width, anchorWidth)
            rect = NSRect(
                x: view.bounds.maxX - width,
                y: view.bounds.minY,
                width: width,
                height: view.bounds.height
            )
        } else {
            rect = view.bounds
        }
        return rect
    }

    func close() {
        stopOutsideClickMonitor()
        popover.performClose(nil)
        refresher.setPopoverOpen(false)
    }

    /// 全局监听点击事件,任何 popover 之外的点都关掉它。
    /// 不用 local monitor 是因为 local 只捕获本 app 内,系统菜单栏 / 通知中心捕不到。
    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            // 全局监听拿到事件 = 用户点了别处(popover 是 app 内的,本 app 内点击不会进 global monitor)
            DispatchQueue.main.async {
                guard let self = self, self.popover.isShown else { return }
                self.close()
            }
        }
    }

    private func stopOutsideClickMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
