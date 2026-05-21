import AppKit
import SwiftUI

/// 设置窗口的导航状态。用 ObservableObject 而不是 @State,是为了让 popover
/// 后续多次发起「跳到某 pane」请求时,已存在的窗口能正确切过去 —— @State 初值
/// 只算一次,旧 bug 就是这个。
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var selectedPane: SettingsRootView.Pane = .general
    @Published var pendingAction: SettingsWindowController.PendingAction?
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    let navigation = SettingsNavigation()
    private var window: NSWindow?

    /// 由 popover 触发的"快速添加 / 编辑":打开设置 + 自动跳到目标 pane + 自动弹对应 sheet。
    /// PortfolioPane / WatchlistPane / AlertsPane 启动时会读这个标记并消费。
    enum PendingAction: Equatable {
        case addHolding
        case addWatch
        case addAlert
        case editHolding(UUID)
    }

    /// 兼容旧 API:目标 pane 想用静态属性时仍可写,但 navigation.selectedPane 是真相源。
    static var preferredPane: SettingsRootView.Pane? {
        get { nil }
        set {
            if let pane = newValue {
                shared.navigation.selectedPane = pane
            }
        }
    }

    /// 兼容旧 API:Pane 启动时读 pendingAction 并清空。
    static var pendingAction: PendingAction? {
        get { shared.navigation.pendingAction }
        set { shared.navigation.pendingAction = newValue }
    }

    private init() {}

    func show(initialAction: PendingAction? = nil) {
        navigation.pendingAction = initialAction
        if let initialAction = initialAction {
            navigation.selectedPane = pane(for: initialAction)
        }
        showWindow()
    }

    func show() {
        showWindow()
    }

    func show(pane: SettingsRootView.Pane) {
        navigation.selectedPane = pane
        showWindow()
    }

    private func pane(for action: PendingAction) -> SettingsRootView.Pane {
        switch action {
        case .addHolding, .editHolding: return .portfolio
        case .addWatch:                 return .watchlist
        case .addAlert:                 return .alerts
        }
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
            .environmentObject(navigation)
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
        case general, ticker, portfolio, watchlist, alerts, dataSources, fx, markets, about
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
            case .markets:     return L("settings.markets", comment: "")
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
            case .markets:     return "clock"
            case .about:       return "info.circle"
            }
        }
    }

    @EnvironmentObject private var navigation: SettingsNavigation

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $navigation.selectedPane) { pane in
                Label(pane.title, systemImage: pane.icon).tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 200)
        } detail: {
            switch navigation.selectedPane {
            case .general:     GeneralPane()
            case .ticker:      TickerPane()
            case .portfolio:   PortfolioPane()
            case .watchlist:   WatchlistPane()
            case .alerts:      AlertsPane()
            case .dataSources: DataSourcesPane()
            case .fx:          FXPane()
            case .markets:     MarketsPane()
            case .about:       AboutPane()
            }
        }
    }
}
