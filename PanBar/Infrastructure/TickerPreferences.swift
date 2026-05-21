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

    private let repo: SettingsRepository

    init(repo: SettingsRepository) {
        self.repo = repo
        self.colorScheme = repo.colorScheme
        self.scrollSpeed = ScrollSpeed(rawValue: repo.string(SettingsRepository.Keys.tickerSpeed) ?? "") ?? .medium
        self.pauseOnHover = repo.string(SettingsRepository.Keys.pauseOnHover) != "0"
        self.pauseWhenClosed = repo.string(SettingsRepository.Keys.pauseWhenClosed) != "0"
        self.maxItems = Int(repo.string(SettingsRepository.Keys.maxTickerItems) ?? "10") ?? 10
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
