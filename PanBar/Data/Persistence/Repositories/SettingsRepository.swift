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

    /// 导出/备份用:返回所有 key-value。
    func allEntries() throws -> [String: String] {
        try dbPool.read { db in
            try SettingRecord.fetchAll(db).reduce(into: [String: String]()) { acc, r in
                acc[r.key] = r.value
            }
        }
    }

    /// 批量写入(导入用)。
    func replaceAll(_ entries: [String: String]) throws {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM appSetting")
            for (k, v) in entries {
                try SettingRecord(key: k, value: v).insert(db)
            }
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
        static let fxRefreshInterval = "fx_refresh_interval"   // seconds; 0 = off
        static let quoteRefreshInterval = "quote_refresh_interval"  // seconds during open hours
        static let marketOverrideA = "market_override_a"
        static let marketOverrideHK = "market_override_hk"
        static let marketOverrideUS = "market_override_us"
        static let pauseRefreshWhenClosed = "pause_refresh_when_closed"
        static let tickerDisplayMode = "ticker_display_mode"
        static let tickerMinimalMetric = "ticker_minimal_metric"
        static let tickerCarouselDwell = "ticker_carousel_dwell"
        static let proxyMode = "proxy_mode"            // off / system / manual
        static let proxyHost = "proxy_host"
        static let proxyPort = "proxy_port"

        /// 拼出市场对应的 override key,避免外部各自拼字符串
        static func marketOverride(_ market: Market) -> String {
            switch market {
            case .a:  return marketOverrideA
            case .hk: return marketOverrideHK
            case .us: return marketOverrideUS
            }
        }
    }

    /// FX 自动刷新间隔(秒)。0 = 关闭自动刷新。
    var fxRefreshInterval: Int {
        if let s = string(Keys.fxRefreshInterval), let v = Int(s), v >= 0 { return v }
        return FXService.defaultInterval
    }

    func setFXRefreshInterval(_ seconds: Int) throws {
        try set(Keys.fxRefreshInterval, "\(max(0, seconds))")
    }

    /// 开盘期间行情刷新间隔(秒)。popover 打开时无视此值固定 3s。
    var quoteRefreshInterval: Int {
        if let s = string(Keys.quoteRefreshInterval), let v = Int(s), v >= 3 { return v }
        return 5
    }

    func setQuoteRefreshInterval(_ seconds: Int) throws {
        try set(Keys.quoteRefreshInterval, "\(max(3, seconds))")
    }

    /// 代理模式。默认 system(跟随 macOS 系统代理)。
    var proxyMode: NetworkConfig.ProxyMode {
        if let s = string(Keys.proxyMode), let m = NetworkConfig.ProxyMode(rawValue: s) { return m }
        return .system
    }

    func setProxyMode(_ mode: NetworkConfig.ProxyMode) throws {
        try set(Keys.proxyMode, mode.rawValue)
    }

    var proxyHost: String { string(Keys.proxyHost) ?? "" }
    func setProxyHost(_ host: String) throws { try set(Keys.proxyHost, host) }

    var proxyPort: Int { Int(string(Keys.proxyPort) ?? "") ?? 7890 }
    func setProxyPort(_ port: Int) throws { try set(Keys.proxyPort, "\(max(1, port))") }

    /// 三个市场都休市时是否完全暂停自动刷新。默认 true(开)。
    var pauseRefreshWhenClosed: Bool {
        // 缺省 / 非法值都视为 true(默认开)
        let v = string(Keys.pauseRefreshWhenClosed)
        return v != "0"
    }

    func setPauseRefreshWhenClosed(_ enabled: Bool) throws {
        try set(Keys.pauseRefreshWhenClosed, enabled ? "1" : "0")
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
