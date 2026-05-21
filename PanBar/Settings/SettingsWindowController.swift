import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    /// 由 popover 触发的"快速添加":打开设置 + 自动跳到目标 pane + 自动弹添加 sheet。
    /// PortfolioPane / WatchlistPane / AlertsPane 启动时会读这个标记并消费。
    enum PendingAction {
        case addHolding
        case addWatch
        case addAlert
    }
    static var pendingAction: PendingAction?

    /// SettingsRootView 启动时读这个并设置 initial selected pane。
    static var preferredPane: SettingsRootView.Pane?

    private init() {}

    func show(initialAction: PendingAction? = nil) {
        Self.pendingAction = initialAction
        Self.preferredPane = switch initialAction {
        case .addHolding: .portfolio
        case .addWatch:   .watchlist
        case .addAlert:   .alerts
        case nil:         nil
        }
        showWindow()
    }

    func show() {
        showWindow()
    }

    private func showWindow() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let container = DependencyContainer.shared else { return }
        let view = SettingsRootView()
            .environmentObject(container.refresher)
            .environment(\.container, container)
            .frame(minWidth: 600, minHeight: 480)

        let hosting = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: hosting)
        w.title = L("settings.title", comment: "")
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(NSSize(width: 720, height: 640))
        w.minSize = NSSize(width: 600, height: 480)
        w.center()
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}

private struct ContainerKey: EnvironmentKey {
    static let defaultValue: DependencyContainer? = nil
}

extension EnvironmentValues {
    var container: DependencyContainer? {
        get { self[ContainerKey.self] }
        set { self[ContainerKey.self] = newValue }
    }
}

struct SettingsRootView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general, ticker, portfolio, watchlist, alerts, dataSources, fx, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general:     return L("settings.general", comment: "")
            case .ticker:      return L("settings.ticker", comment: "")
            case .portfolio:   return L("settings.portfolio", comment: "")
            case .watchlist:   return L("settings.watchlist", comment: "")
            case .alerts:      return L("settings.alerts", comment: "")
            case .dataSources: return L("settings.dataSources", comment: "")
            case .fx:          return L("settings.fx", comment: "")
            case .about:       return L("settings.about", comment: "")
            }
        }
        var icon: String {
            switch self {
            case .general:     return "gear"
            case .ticker:      return "text.line.first.and.arrowtriangle.forward"
            case .portfolio:   return "briefcase"
            case .watchlist:   return "star"
            case .alerts:      return "bell"
            case .dataSources: return "antenna.radiowaves.left.and.right"
            case .fx:          return "dollarsign.arrow.circlepath"
            case .about:       return "info.circle"
            }
        }
    }

    @State private var selected: Pane = SettingsWindowController.preferredPane ?? .general

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $selected) { pane in
                Label(pane.title, systemImage: pane.icon).tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 200)
        } detail: {
            switch selected {
            case .general:     GeneralPane()
            case .ticker:      TickerPane()
            case .portfolio:   PortfolioPane()
            case .watchlist:   WatchlistPane()
            case .alerts:      AlertsPane()
            case .dataSources: DataSourcesPane()
            case .fx:          FXPane()
            case .about:       AboutPane()
            }
        }
        .onAppear {
            SettingsWindowController.preferredPane = nil
        }
    }
}
