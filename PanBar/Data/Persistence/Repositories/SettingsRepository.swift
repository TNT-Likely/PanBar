import Foundation
import GRDB

private struct SettingRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "appSetting"
    var key: String
    var value: String
}

/// 简易 key-value 设置 + 类型化访问器。
struct SettingsRepository {
    let dbPool: DatabasePool

    func string(_ key: String) -> String? {
        try? dbPool.read { db in
            try SettingRecord.fetchOne(db, key: key)?.value
        }
    }

    func set(_ key: String, _ value: String) throws {
        try dbPool.write { db in
            try SettingRecord(key: key, value: value).save(db)
        }
    }

    // MARK: 类型化访问器

    enum Keys {
        static let baseCurrency = "base_currency"
        static let colorScheme = "color_scheme"   // east / west / mono
        static let tickerSpeed = "ticker_speed"   // slow / medium / fast
        static let language = "language"          // auto / zh-Hans / en
        static let tickerTemplate = "ticker_template"
        static let pauseOnHover = "pause_on_hover"
        static let pauseWhenClosed = "pause_when_closed"
        static let maxTickerItems = "max_ticker_items"
        static let globalHotkeyEnabled = "global_hotkey_enabled"
        static let tickerShowTotalAssets = "ticker_show_total_assets"
        static let tickerShowTodayPnL = "ticker_show_today_pnl"
        static let tickerShowAllTimePnL = "ticker_show_alltime_pnl"
        static let hideOnScreenShare = "hide_on_screen_share"
        static let privacyManualHide = "privacy_manual_hide"
        static let tickerIndexIDs = "ticker_index_ids"
    }

    var baseCurrency: Currency {
        get {
            if let s = string(Keys.baseCurrency), let c = Currency(rawValue: s) { return c }
            return Currency(rawValue: Locale.current.currency?.identifier ?? "CNY") ?? .cny
        }
    }

    func setBaseCurrency(_ c: Currency) throws {
        try set(Keys.baseCurrency, c.rawValue)
    }

    var colorScheme: TickerColorScheme {
        if let s = string(Keys.colorScheme), let v = TickerColorScheme(rawValue: s) { return v }
        return .east
    }

    func setColorScheme(_ v: TickerColorScheme) throws {
        try set(Keys.colorScheme, v.rawValue)
    }
}

enum TickerColorScheme: String, Codable, CaseIterable {
    case east   // 涨红 跌绿
    case west   // 涨绿 跌红
    case mono   // 黑白
}
