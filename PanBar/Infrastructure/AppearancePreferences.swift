import AppKit
import Combine
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case system, light, dark
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: return L("theme.system", comment: "")
        case .light:  return L("theme.light", comment: "")
        case .dark:   return L("theme.dark", comment: "")
        }
    }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}

enum PopoverDensity: String, CaseIterable, Identifiable, Codable {
    case compact, standard, spacious
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .compact:  return L("density.compact", comment: "")
        case .standard: return L("density.standard", comment: "")
        case .spacious: return L("density.spacious", comment: "")
        }
    }
    /// 行内垂直内边距倍数。
    var rowVerticalPadding: CGFloat {
        switch self {
        case .compact: return 6
        case .standard: return 9
        case .spacious: return 13
        }
    }
    var rowHorizontalPadding: CGFloat {
        switch self {
        case .compact: return 12
        case .standard: return 14
        case .spacious: return 16
        }
    }
}

@MainActor
final class AppearancePreferences: ObservableObject {
    @Published var theme: AppTheme {
        didSet {
            if oldValue != theme {
                try? repo.set(Keys.theme, theme.rawValue)
                applyTheme()
            }
        }
    }
    @Published var density: PopoverDensity {
        didSet {
            if oldValue != density {
                try? repo.set(Keys.density, density.rawValue)
            }
        }
    }

    private let repo: SettingsRepository

    enum Keys {
        static let theme = "app_theme"
        static let density = "popover_density"
    }

    init(repo: SettingsRepository) {
        self.repo = repo
        self.theme = AppTheme(rawValue: repo.string(Keys.theme) ?? "") ?? .system
        self.density = PopoverDensity(rawValue: repo.string(Keys.density) ?? "") ?? .standard
        applyTheme()
    }

    func applyTheme() {
        NSApp.appearance = theme.nsAppearance
    }
}
