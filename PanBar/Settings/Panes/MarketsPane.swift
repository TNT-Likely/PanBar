import SwiftUI

struct MarketsPane: View {
    @Environment(\.container) private var container

    var body: some View {
        if let container = container {
            MarketsPaneContent(container: container)
        } else {
            Text(L("loading", comment: ""))
        }
    }
}

/// 开盘期间刷新间隔预设
private enum QuoteRefreshChoice: Int, CaseIterable, Identifiable {
    case fast = 3, normal = 5, relaxed = 10, slow = 30, lazy = 60
    var id: Int { rawValue }
    var displayName: String {
        switch self {
        case .fast:    return L("market.quoteInterval.3s", comment: "")
        case .normal:  return L("market.quoteInterval.5s", comment: "")
        case .relaxed: return L("market.quoteInterval.10s", comment: "")
        case .slow:    return L("market.quoteInterval.30s", comment: "")
        case .lazy:    return L("market.quoteInterval.60s", comment: "")
        }
    }

    static func nearest(to seconds: Int) -> QuoteRefreshChoice {
        allCases.min(by: { abs($0.rawValue - seconds) < abs($1.rawValue - seconds) }) ?? .normal
    }
}

/// 节假日 override 用户选项
private enum OverrideChoice: String, CaseIterable, Identifiable {
    case auto        // 跟着 MarketClock 默认规则
    case forceOpen   // 今天强制开盘
    case forceClosed // 今天强制休市

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .auto:        return L("market.override.auto", comment: "")
        case .forceOpen:   return L("market.override.forceOpen", comment: "")
        case .forceClosed: return L("market.override.forceClosed", comment: "")
        }
    }
}

private struct MarketsPaneContent: View {
    let container: DependencyContainer

    @State private var quoteRefreshChoice: QuoteRefreshChoice = .normal
    @State private var pauseWhenClosed: Bool = true
    @State private var statusTick: Date = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section(header: Text(L("market.refreshSection", comment: "")).font(.title3)) {
                Picker(L("market.quoteInterval", comment: ""), selection: $quoteRefreshChoice) {
                    ForEach(QuoteRefreshChoice.allCases) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                .onChange(of: quoteRefreshChoice) { v in
                    try? container.settingsRepo.setQuoteRefreshInterval(v.rawValue)
                    container.refresher.tickerInterval = TimeInterval(v.rawValue)
                }
                Toggle(L("market.pauseWhenClosed", comment: ""), isOn: $pauseWhenClosed)
                    .onChange(of: pauseWhenClosed) { v in
                        try? container.settingsRepo.setPauseRefreshWhenClosed(v)
                        container.refresher.pauseWhenClosed = v
                    }
                Text(L("market.quoteInterval.hint", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text(L("market.hoursSection", comment: "")).font(.headline)) {
                ForEach(Market.allCases, id: \.self) { market in
                    MarketRow(
                        container: container,
                        market: market,
                        statusTick: statusTick
                    )
                }
                Text(L("market.hours.hint", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear {
            quoteRefreshChoice = QuoteRefreshChoice.nearest(to: container.settingsRepo.quoteRefreshInterval)
            pauseWhenClosed = container.settingsRepo.pauseRefreshWhenClosed
        }
        .onReceive(timer) { statusTick = $0 }
    }
}

private struct MarketRow: View {
    let container: DependencyContainer
    let market: Market
    let statusTick: Date

    @State private var override: OverrideChoice = .auto

    private var status: MarketStatus { container.clock.status(market, at: statusTick) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor(status))
                    .frame(width: 8, height: 8)
                Text(market.displayName)
                    .font(.system(size: 13, weight: .semibold))
                Text(statusLabel(status))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Text(localTimeLabel)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            Text(hoursDescription)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            HStack {
                Picker(L("market.override.label", comment: ""), selection: $override) {
                    ForEach(OverrideChoice.allCases) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                .frame(maxWidth: 280)
                .onChange(of: override) { v in
                    persistOverride(v)
                    // 改完让 refresher 重算 pace,休市/开盘状态立即生效
                    container.refresher.refreshNow()
                }
                Spacer()
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            override = loadOverride()
        }
    }

    private var localTimeLabel: String {
        let f = DateFormatter()
        f.timeZone = market.timeZone
        f.dateFormat = "HH:mm"
        let timeStr = f.string(from: statusTick)
        let tz = market.timeZone.abbreviation(for: statusTick) ?? market.timeZone.identifier
        return "\(timeStr) \(tz)"
    }

    private var hoursDescription: String {
        switch market {
        case .a:  return L("market.hours.a", comment: "")
        case .hk: return L("market.hours.hk", comment: "")
        case .us: return L("market.hours.us", comment: "")
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

    private func loadOverride() -> OverrideChoice {
        guard let raw = container.settingsRepo.string(SettingsRepository.Keys.marketOverride(market)) else {
            return .auto
        }
        let parts = raw.split(separator: ":")
        guard parts.count == 2 else { return .auto }
        let savedDate = String(parts[0])
        let todayInMarketTZ = MarketClock.dateString(Date(), tz: market.timeZone)
        guard savedDate == todayInMarketTZ else { return .auto }
        switch String(parts[1]) {
        case "open":   return .forceOpen
        case "closed": return .forceClosed
        default:       return .auto
        }
    }

    private func persistOverride(_ choice: OverrideChoice) {
        let key = SettingsRepository.Keys.marketOverride(market)
        switch choice {
        case .auto:
            // 清空 = 写空字符串(也可以删 row,简单起见写 "" 占位)
            try? container.settingsRepo.set(key, "")
        case .forceOpen:
            let today = MarketClock.dateString(Date(), tz: market.timeZone)
            try? container.settingsRepo.set(key, "\(today):open")
        case .forceClosed:
            let today = MarketClock.dateString(Date(), tz: market.timeZone)
            try? container.settingsRepo.set(key, "\(today):closed")
        }
    }
}

