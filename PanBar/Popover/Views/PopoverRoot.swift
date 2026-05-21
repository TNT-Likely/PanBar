import SwiftUI

struct PopoverRoot: View {
    @EnvironmentObject var vm: PopoverViewModel
    @EnvironmentObject var refresher: QuoteRefresher
    @Environment(\.container) private var container

    /// 每 30 秒强制重算市场状态(开市/午休/休市切换);用 timer trigger 让 @State 变化触发重渲染
    @State private var statusTick: Date = Date()
    private let statusTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

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
        .onReceive(statusTimer) { statusTick = $0 }
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
            VStack(alignment: .leading, spacing: 2) {
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
                marketStatusRow
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

    /// 三个市场的实时状态:绿点=开盘 / 黄=午休 / 灰=休市
    @ViewBuilder
    private var marketStatusRow: some View {
        if let clock = container?.clock {
            HStack(spacing: 8) {
                ForEach(Market.allCases, id: \.self) { market in
                    let status = clock.status(market, at: statusTick)
                    HStack(spacing: 3) {
                        Circle()
                            .fill(statusColor(status))
                            .frame(width: 5, height: 5)
                        Text(marketShortName(market))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(statusLabel(status))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
            }
        }
    }

    private func marketShortName(_ m: Market) -> String {
        switch m {
        case .a: return "A"
        case .hk: return "HK"
        case .us: return "US"
        }
    }

    private func statusColor(_ s: MarketStatus) -> Color {
        switch s {
        case .open: return .green
        case .lunchBreak: return .yellow
        case .closed: return .secondary.opacity(0.5)
        }
    }

    private func statusLabel(_ s: MarketStatus) -> String {
        switch s {
        case .open:       return L("market.status.open", comment: "")
        case .lunchBreak: return L("market.status.lunch", comment: "")
        case .closed:     return L("market.status.closed", comment: "")
        }
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
                        Image(systemName: footerIcon)
                            .foregroundColor(footerIconColor)
                    }
                    Text(footerStatus)
                        .foregroundColor(.secondary)
                }
                .font(.system(size: 11))
            }
            .buttonStyle(.plain)
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

    /// 文字统一用 .secondary 灰色保证两个模式下都清晰可读,状态用图标颜色区分:
    ///   - 离线:橙色 wifi.slash
    ///   - cached:橙色 clock(让用户知道在看的不是最新值,但不刺眼)
    ///   - 正常:灰色刷新箭头
    private var footerIcon: String {
        if refresher.lastError != nil { return "wifi.slash" }
        if refresher.snapshotIsFromCache { return "clock.arrow.circlepath" }
        return "arrow.clockwise"
    }

    private var footerIconColor: Color {
        if refresher.lastError != nil { return .orange }
        if refresher.snapshotIsFromCache { return .orange }
        return .secondary
    }

    private func openSettings() {
        SettingsWindowController.shared.show()
    }
}
