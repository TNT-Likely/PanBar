import SwiftUI

struct PopoverRoot: View {
    @EnvironmentObject var vm: PopoverViewModel
    @EnvironmentObject var refresher: QuoteRefresher

    var body: some View {
        VStack(spacing: 0) {
            header
            SummaryCards(snapshot: refresher.snapshot)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            tabs
            Divider()
            content
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)
                Text("P")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("PanBar")
                        .font(.system(size: 14, weight: .semibold))
                    if let updated = refresher.lastUpdated, Date().timeIntervalSince(updated) < 15 {
                        Text("Live")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.85))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: openSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help(L("menu.settings", comment: ""))
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var subtitle: String {
        let m = String(format: L("popover.subtitle.markets", comment: "%d markets"), 3)
        let h = String(format: L("popover.subtitle.holdings", comment: "%d holdings"), vm.holdings.count)
        return "\(m) · \(h)"
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(PopoverViewModel.Tab.allCases) { tab in
                Button(action: { vm.currentTab = tab }) {
                    Text(tab.title)
                        .font(.system(size: 11, weight: vm.currentTab == tab ? .semibold : .regular))
                        .foregroundColor(vm.currentTab == tab ? .primary : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(vm.currentTab == tab ? Color.primary.opacity(0.08) : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch vm.currentTab {
        case .holdings:  HoldingsTab()
        case .watchlist: WatchlistTab()
        case .indices:   IndicesTab()
        case .alerts:    AlertsTab()
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(action: { refresher.refreshNow() }) {
                HStack(spacing: 5) {
                    if refresher.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.55)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(footerStatus)
                }
                .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(footerStatusColor)
            .disabled(refresher.isRefreshing)

            Spacer()
            Text(AppVersion.displayShort)
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))
            Button(action: { NSApp.terminate(nil) }) {
                Text(L("menu.quit", comment: ""))
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var footerStatus: String {
        if let err = refresher.lastError, !err.isEmpty {
            return L("footer.offline", comment: "")
        }
        // 还没拿到任何 fresh 数据,但有磁盘 seed 进来的旧数据
        if refresher.snapshotIsFromCache {
            return L("footer.cached", comment: "")
        }
        if refresher.isRefreshing && refresher.lastUpdated == nil {
            return L("footer.refreshing", comment: "")
        }
        if let t = refresher.lastUpdated {
            let interval = Int(Date().timeIntervalSince(t))
            return String(format: L("footer.updated", comment: ""), interval)
        }
        return L("footer.loading", comment: "")
    }

    private var footerStatusColor: Color {
        // cached 时给点黄色作弱提示,让用户知道这不是最新值
        if refresher.snapshotIsFromCache { return .orange.opacity(0.85) }
        return .secondary
    }

    private func openSettings() {
        SettingsWindowController.shared.show()
    }
}
