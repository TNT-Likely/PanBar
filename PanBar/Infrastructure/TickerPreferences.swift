import Foundation
import Combine

/// 用户可配置的滚动相关偏好。读取自 SettingsRepository,变更时同步落库,并通过 @Published 通知视图。
@MainActor
final class TickerPreferences: ObservableObject {
    @Published var colorScheme: TickerColorScheme {
        didSet {
            if oldValue != colorScheme {
                try? repo.setColorScheme(colorScheme)
            }
        }
    }
    @Published var scrollSpeed: ScrollSpeed {
        didSet { if oldValue != scrollSpeed { try? repo.set(SettingsRepository.Keys.tickerSpeed, scrollSpeed.rawValue) } }
    }
    @Published var pauseOnHover: Bool {
        didSet { try? repo.set(SettingsRepository.Keys.pauseOnHover, pauseOnHover ? "1" : "0") }
    }
    @Published var pauseWhenClosed: Bool {
        didSet { try? repo.set(SettingsRepository.Keys.pauseWhenClosed, pauseWhenClosed ? "1" : "0") }
    }
    @Published var maxItems: Int {
        didSet { try? repo.set(SettingsRepository.Keys.maxTickerItems, "\(maxItems)") }
    }
    @Published var showTotalAssets: Bool {
        didSet { try? repo.set(SettingsRepository.Keys.tickerShowTotalAssets, showTotalAssets ? "1" : "0") }
    }
    @Published var showTodayPnL: Bool {
        didSet { try? repo.set(SettingsRepository.Keys.tickerShowTodayPnL, showTodayPnL ? "1" : "0") }
    }
    @Published var showAllTimePnL: Bool {
        didSet { try? repo.set(SettingsRepository.Keys.tickerShowAllTimePnL, showAllTimePnL ? "1" : "0") }
    }
    /// 哪些大盘指数显示在滚动条中(存 IndexDescriptor.id 集合)。
    @Published var tickerIndexIDs: Set<String> {
        didSet {
            if let data = try? JSONEncoder().encode(Array(tickerIndexIDs).sorted()),
               let json = String(data: data, encoding: .utf8) {
                try? repo.set(SettingsRepository.Keys.tickerIndexIDs, json)
            }
        }
    }

    private let repo: SettingsRepository

    init(repo: SettingsRepository) {
        self.repo = repo
        self.colorScheme = repo.colorScheme
        self.scrollSpeed = ScrollSpeed(rawValue: repo.string(SettingsRepository.Keys.tickerSpeed) ?? "") ?? .medium
        self.pauseOnHover = repo.string(SettingsRepository.Keys.pauseOnHover) != "0"
        self.pauseWhenClosed = repo.string(SettingsRepository.Keys.pauseWhenClosed) != "0"
        self.maxItems = Int(repo.string(SettingsRepository.Keys.maxTickerItems) ?? "10") ?? 10
        // Summary 三项默认不显示(避免菜单栏一启动就长),用户主动开启
        self.showTotalAssets = repo.string(SettingsRepository.Keys.tickerShowTotalAssets) == "1"
        self.showTodayPnL = repo.string(SettingsRepository.Keys.tickerShowTodayPnL) == "1"
        self.showAllTimePnL = repo.string(SettingsRepository.Keys.tickerShowAllTimePnL) == "1"
        if let json = repo.string(SettingsRepository.Keys.tickerIndexIDs),
           let data = json.data(using: .utf8),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            self.tickerIndexIDs = Set(arr)
        } else {
            self.tickerIndexIDs = []
        }
    }
}

enum ScrollSpeed: String, CaseIterable, Codable, Identifiable {
    case slow, medium, fast
    var id: String { rawValue }
    var pixelsPerSecond: CGFloat {
        switch self {
        case .slow:   return 18
        case .medium: return 30
        case .fast:   return 48
        }
    }
    var displayName: String {
        switch self {
        case .slow:   return L("speed.slow", comment: "")
        case .medium: return L("speed.medium", comment: "")
        case .fast:   return L("speed.fast", comment: "")
        }
    }
}
