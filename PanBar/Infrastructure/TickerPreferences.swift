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
    @Published var showAppIcon: Bool {
        didSet { try? repo.set(SettingsRepository.Keys.tickerShowAppIcon, showAppIcon ? "1" : "0") }
    }
    @Published var showQuoteCode: Bool {
        didSet { try? repo.set(SettingsRepository.Keys.tickerShowQuoteCode, showQuoteCode ? "1" : "0") }
    }
    @Published var showQuoteName: Bool {
        didSet { try? repo.set(SettingsRepository.Keys.tickerShowQuoteName, showQuoteName ? "1" : "0") }
    }
    @Published var menuBarWidth: Int {
        didSet {
            let clamped = min(520, max(80, menuBarWidth))
            if clamped != menuBarWidth {
                menuBarWidth = clamped
            } else {
                try? repo.set(SettingsRepository.Keys.tickerMenuBarWidth, "\(menuBarWidth)")
            }
        }
    }
    @Published var scrollMenuBarWidth: Int {
        didSet {
            let clamped = min(720, max(160, scrollMenuBarWidth))
            if clamped != scrollMenuBarWidth {
                scrollMenuBarWidth = clamped
            } else {
                try? repo.set(SettingsRepository.Keys.tickerScrollMenuBarWidth, "\(scrollMenuBarWidth)")
            }
        }
    }
    @Published var carouselMenuBarWidth: Int {
        didSet {
            let clamped = min(360, max(100, carouselMenuBarWidth))
            if clamped != carouselMenuBarWidth {
                carouselMenuBarWidth = clamped
            } else {
                try? repo.set(SettingsRepository.Keys.tickerCarouselMenuBarWidth, "\(carouselMenuBarWidth)")
            }
        }
    }
    @Published var compactMenuBarWidth: Int {
        didSet {
            let clamped = min(360, max(60, compactMenuBarWidth))
            if clamped != compactMenuBarWidth {
                compactMenuBarWidth = clamped
            } else {
                try? repo.set(SettingsRepository.Keys.tickerCompactMenuBarWidth, "\(compactMenuBarWidth)")
            }
        }
    }
    @Published var scrollAutoWidth: Bool {
        didSet { try? repo.set(SettingsRepository.Keys.tickerScrollAutoWidth, scrollAutoWidth ? "1" : "0") }
    }
    @Published var carouselAutoWidth: Bool {
        didSet { try? repo.set(SettingsRepository.Keys.tickerCarouselAutoWidth, carouselAutoWidth ? "1" : "0") }
    }
    @Published var compactAutoWidth: Bool {
        didSet { try? repo.set(SettingsRepository.Keys.tickerCompactAutoWidth, compactAutoWidth ? "1" : "0") }
    }
    @Published var showDirectionArrow: Bool {
        didSet { try? repo.set(SettingsRepository.Keys.tickerShowDirectionArrow, showDirectionArrow ? "1" : "0") }
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
    /// 菜单栏展现形式。
    @Published var displayMode: TickerDisplayMode {
        didSet { try? repo.set(SettingsRepository.Keys.tickerDisplayMode, displayMode.rawValue) }
    }
    /// 极简模式下显示哪个汇总指标(today / total / allTime)。
    @Published var minimalMetric: MinimalMetric {
        didSet { try? repo.set(SettingsRepository.Keys.tickerMinimalMetric, minimalMetric.rawValue) }
    }
    /// 轮播每条停留秒数(2/3/4/6/10),只对 carousel 模式生效。
    @Published var carouselDwell: Int {
        didSet { try? repo.set(SettingsRepository.Keys.tickerCarouselDwell, "\(carouselDwell)") }
    }

    private let repo: SettingsRepository

    init(repo: SettingsRepository) {
        self.repo = repo
        self.colorScheme = repo.colorScheme
        self.scrollSpeed = ScrollSpeed(rawValue: repo.string(SettingsRepository.Keys.tickerSpeed) ?? "") ?? .medium
        self.pauseOnHover = repo.string(SettingsRepository.Keys.pauseOnHover) != "0"
        self.pauseWhenClosed = repo.string(SettingsRepository.Keys.pauseWhenClosed) != "0"
        self.maxItems = Int(repo.string(SettingsRepository.Keys.maxTickerItems) ?? "10") ?? 10
        let storedDisplayMode = TickerDisplayMode(rawValue: repo.string(SettingsRepository.Keys.tickerDisplayMode) ?? "") ?? .scroll
        let storedMinimalMetric = MinimalMetric(rawValue: repo.string(SettingsRepository.Keys.tickerMinimalMetric) ?? "") ?? .todayPnL
        let migratesMinimal = storedDisplayMode == .minimal
        // Summary 三项默认不显示(避免菜单栏一启动就长),用户主动开启。
        // 旧版「极简」迁移为「固定」:只保留原来极简选择的那个指标。
        if migratesMinimal {
            let migratedShowTotalAssets = storedMinimalMetric == .totalAssets
            let migratedShowTodayPnL = storedMinimalMetric == .todayPnL
            let migratedShowAllTimePnL = storedMinimalMetric == .allTimePnL
            self.showTotalAssets = migratedShowTotalAssets
            self.showTodayPnL = migratedShowTodayPnL
            self.showAllTimePnL = migratedShowAllTimePnL
            try? repo.set(SettingsRepository.Keys.tickerShowTotalAssets, migratedShowTotalAssets ? "1" : "0")
            try? repo.set(SettingsRepository.Keys.tickerShowTodayPnL, migratedShowTodayPnL ? "1" : "0")
            try? repo.set(SettingsRepository.Keys.tickerShowAllTimePnL, migratedShowAllTimePnL ? "1" : "0")
        } else {
            self.showTotalAssets = repo.string(SettingsRepository.Keys.tickerShowTotalAssets) == "1"
            self.showTodayPnL = repo.string(SettingsRepository.Keys.tickerShowTodayPnL) == "1"
            self.showAllTimePnL = repo.string(SettingsRepository.Keys.tickerShowAllTimePnL) == "1"
        }
        if let json = repo.string(SettingsRepository.Keys.tickerIndexIDs),
           let data = json.data(using: .utf8),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            self.tickerIndexIDs = Set(arr)
        } else {
            self.tickerIndexIDs = []
        }
        self.displayMode = storedDisplayMode == .scrollNoCode ? .scroll : (migratesMinimal ? .compact : storedDisplayMode)
        if migratesMinimal {
            try? repo.set(SettingsRepository.Keys.tickerDisplayMode, TickerDisplayMode.compact.rawValue)
        }
        self.minimalMetric = storedMinimalMetric
        self.carouselDwell = Int(repo.string(SettingsRepository.Keys.tickerCarouselDwell) ?? "") ?? 4
        self.showAppIcon = repo.string(SettingsRepository.Keys.tickerShowAppIcon) != "0"
        if storedDisplayMode == .scrollNoCode {
            self.showQuoteCode = false
        } else {
            self.showQuoteCode = repo.string(SettingsRepository.Keys.tickerShowQuoteCode) != "0"
        }
        self.showQuoteName = repo.string(SettingsRepository.Keys.tickerShowQuoteName) != "0"
        let legacyWidth = Int(repo.string(SettingsRepository.Keys.tickerMenuBarWidth) ?? "") ?? 280
        self.menuBarWidth = legacyWidth
        self.scrollMenuBarWidth = Int(repo.string(SettingsRepository.Keys.tickerScrollMenuBarWidth) ?? "") ?? max(160, legacyWidth)
        self.carouselMenuBarWidth = Int(repo.string(SettingsRepository.Keys.tickerCarouselMenuBarWidth) ?? "") ?? min(360, max(160, legacyWidth))
        self.compactMenuBarWidth = Int(repo.string(SettingsRepository.Keys.tickerCompactMenuBarWidth) ?? "") ?? 160
        self.scrollAutoWidth = repo.string(SettingsRepository.Keys.tickerScrollAutoWidth) == "1"
        self.carouselAutoWidth = repo.string(SettingsRepository.Keys.tickerCarouselAutoWidth) == "1"
        self.compactAutoWidth = repo.string(SettingsRepository.Keys.tickerCompactAutoWidth) != "0"
        self.showDirectionArrow = migratesMinimal || repo.string(SettingsRepository.Keys.tickerShowDirectionArrow) == "1"
        if migratesMinimal {
            try? repo.set(SettingsRepository.Keys.tickerShowDirectionArrow, "1")
        }
    }

}

/// 菜单栏 ticker 的展现形式。
enum TickerDisplayMode: String, CaseIterable, Identifiable, Codable {
    case scroll    // 经典左右滚动(默认)
    case scrollNoCode // 旧版本兼容:现在用 showQuoteCode 控制
    case carousel  // 一条一条上下淡入轮播
    case compact   // 三个简写卡片(今日 / 总盈亏 / 总市值)
    case minimal   // 只显示一个用户选定的数字

    static let allCases: [TickerDisplayMode] = [.scroll, .carousel, .compact]

    var id: String { rawValue }

    var usesScrollingView: Bool {
        switch self {
        case .scroll, .scrollNoCode: return true
        case .carousel, .compact, .minimal: return false
        }
    }

    var displayName: String {
        switch self {
        case .scroll:   return L("displayMode.scroll", comment: "")
        case .scrollNoCode: return L("displayMode.scroll", comment: "")
        case .carousel: return L("displayMode.carousel", comment: "")
        case .compact:  return L("displayMode.compact", comment: "")
        case .minimal:  return L("displayMode.minimal", comment: "")
        }
    }
}

/// 极简模式下显示哪个汇总指标。
enum MinimalMetric: String, CaseIterable, Identifiable, Codable {
    case todayPnL
    case allTimePnL
    case totalAssets

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .todayPnL:    return L("summary.today", comment: "")
        case .allTimePnL:  return L("summary.allTime", comment: "")
        case .totalAssets: return L("summary.totalAssets", comment: "")
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
