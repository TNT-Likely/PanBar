import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let container = DependencyContainer.shared else { return }
        let view = SettingsRootView()
            .environmentObject(container.refresher)
            .environment(\.container, container)
            .frame(width: 640, height: 480)

        let hosting = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: hosting)
        w.title = L("settings.title", comment: "")
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.setContentSize(NSSize(width: 640, height: 480))
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
        case general, ticker, portfolio, watchlist, alerts, dataSources, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general:     return L("settings.general", comment: "")
            case .ticker:      return L("settings.ticker", comment: "")
            case .portfolio:   return L("settings.portfolio", comment: "")
            case .watchlist:   return L("settings.watchlist", comment: "")
            case .alerts:      return L("settings.alerts", comment: "")
            case .dataSources: return L("settings.dataSources", comment: "")
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
            case .about:       return "info.circle"
            }
        }
    }

    @State private var selected: Pane = .general

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
            case .about:       AboutPane()
            }
        }
    }
}
