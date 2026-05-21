import SwiftUI

struct FXPane: View {
    @Environment(\.container) private var container

    var body: some View {
        if let container = container {
            FXPaneContent(container: container)
        } else {
            Text(L("loading", comment: ""))
        }
    }
}

/// 自动刷新间隔的预设档位。0 = 关闭。
private enum FXRefreshChoice: Int, CaseIterable, Identifiable {
    case off = 0
    case fiveMin = 300
    case fifteenMin = 900
    case oneHour = 3600
    case sixHours = 21600
    case oneDay = 86400

    var id: Int { rawValue }
    var displayName: String {
        switch self {
        case .off:        return L("fx.interval.off", comment: "")
        case .fiveMin:    return L("fx.interval.5min", comment: "")
        case .fifteenMin: return L("fx.interval.15min", comment: "")
        case .oneHour:    return L("fx.interval.1h", comment: "")
        case .sixHours:   return L("fx.interval.6h", comment: "")
        case .oneDay:     return L("fx.interval.1d", comment: "")
        }
    }

    /// 把任意秒数对齐到最近的预设(用户在配置文件里塞了奇怪值时也能渲染)
    static func nearest(to seconds: Int) -> FXRefreshChoice {
        allCases.min(by: { abs($0.rawValue - seconds) < abs($1.rawValue - seconds) }) ?? .oneHour
    }
}

/// 内存里展示一行汇率用的轻量模型。来自 FXService.snapshot()。
private struct FXRow: Identifiable {
    let id: String     // pair key e.g. "USDCNY"
    let from: Currency
    let to: Currency
    let rate: Decimal
    let asOf: Date
}

private struct FXPaneContent: View {
    let container: DependencyContainer

    @State private var rows: [FXRow] = []
    @State private var lastFetch: Date? = nil
    @State private var isRefreshing: Bool = false
    @State private var refreshChoice: FXRefreshChoice = .oneDay
    @State private var tickTrigger: Date = Date()
    @State private var refreshMessage: RefreshMessage? = nil

    private enum RefreshMessage: Equatable {
        case success(Int)   // 更新了几对
        case failed         // 网络挂了或空响应
    }

    private let refreshTicker = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section(header: Text(L("settings.fx", comment: "")).font(.title3)) {
                if rows.isEmpty {
                    Text(L("fx.empty", comment: ""))
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                } else {
                    ForEach(rows) { row in
                        FXRowView(row: row, now: tickTrigger)
                    }
                }
            }

            Section {
                HStack {
                    Button(action: refresh) {
                        HStack(spacing: 6) {
                            if isRefreshing {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(L("fx.refreshNow", comment: ""))
                        }
                    }
                    .disabled(isRefreshing)
                    Spacer()
                    Text(lastFetchText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let msg = refreshMessage {
                    HStack(spacing: 6) {
                        switch msg {
                        case .success(let n):
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text(String(format: L("fx.refresh.success", comment: ""), n))
                        case .failed:
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                            Text(L("fx.refresh.failed", comment: ""))
                        }
                    }
                    .font(.caption)
                    .transition(.opacity)
                }
            }

            Section(header: Text(L("fx.autoRefresh", comment: "")).font(.headline)) {
                Picker(L("fx.autoRefresh.interval", comment: ""), selection: $refreshChoice) {
                    ForEach(FXRefreshChoice.allCases) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                .onChange(of: refreshChoice) { newValue in
                    try? container.settingsRepo.setFXRefreshInterval(newValue.rawValue)
                    Task { await container.fx.setAutoRefreshInterval(newValue.rawValue) }
                }
                Text(L("fx.autoRefresh.hint", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text(L("fx.source", comment: "")).font(.headline)) {
                Text(L("fx.source.eastmoney", comment: ""))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear {
            refreshChoice = FXRefreshChoice.nearest(to: container.settingsRepo.fxRefreshInterval)
            Task { await reloadSnapshot() }
        }
        .onReceive(refreshTicker) { now in
            // 每 5 秒重画一次 "Updated Xs ago" 的相对时间
            tickTrigger = now
        }
    }

    private var lastFetchText: String {
        guard let t = lastFetch else { return L("fx.neverFetched", comment: "") }
        let interval = Int(tickTrigger.timeIntervalSince(t))
        return String(format: L("fx.lastFetched", comment: ""), formatInterval(interval))
    }

    private func formatInterval(_ seconds: Int) -> String {
        if seconds < 60 { return String(format: L("fx.time.seconds", comment: ""), seconds) }
        if seconds < 3600 { return String(format: L("fx.time.minutes", comment: ""), seconds / 60) }
        if seconds < 86400 { return String(format: L("fx.time.hours", comment: ""), seconds / 3600) }
        return String(format: L("fx.time.days", comment: ""), seconds / 86400)
    }

    private func refresh() {
        isRefreshing = true
        refreshMessage = nil
        Task {
            let ok = await container.fx.forceRefresh()
            await reloadSnapshot()
            await MainActor.run {
                isRefreshing = false
                refreshMessage = ok ? .success(rows.count) : .failed
                if ok { container.refresher.refreshNow() }
            }
            // 3 秒后自动隐藏提示
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                if refreshMessage != nil { refreshMessage = nil }
            }
        }
    }

    private func reloadSnapshot() async {
        let snap = await container.fx.snapshot()
        let mapped: [FXRow] = snap.rates
            .sorted(by: { $0.key < $1.key })
            .map { (pair, rate) in
                FXRow(id: pair, from: rate.from, to: rate.to, rate: rate.rate, asOf: rate.asOf)
            }
        await MainActor.run {
            self.rows = mapped
            self.lastFetch = snap.lastFetch == .distantPast ? nil : snap.lastFetch
        }
    }
}

private struct FXRowView: View {
    let row: FXRow
    let now: Date

    var body: some View {
        HStack {
            Text("\(row.from.rawValue) → \(row.to.rawValue)")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 90, alignment: .leading)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatRate(row.rate))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                Text(relativeTime(row.asOf))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func formatRate(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 4
        formatter.maximumFractionDigits = 4
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        formatter.numberStyle = .decimal
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return String(format: L("fx.time.seconds", comment: ""), seconds) }
        if seconds < 3600 { return String(format: L("fx.time.minutes", comment: ""), seconds / 60) }
        if seconds < 86400 { return String(format: L("fx.time.hours", comment: ""), seconds / 3600) }
        return String(format: L("fx.time.days", comment: ""), seconds / 86400)
    }
}
