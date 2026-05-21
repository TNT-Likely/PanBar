import Foundation

/// 全局网络配置。所有 HTTPClient 默认走这里拿 URLSession,这样改了代理设置
/// 就能在不重启 app 的情况下让所有数据源(腾讯/东方财富/Yahoo/Finnhub/GitHub)
/// 立即切到新通道。
enum NetworkConfig {
    enum ProxyMode: String, CaseIterable {
        case off       // 显式关闭代理(忽略系统设置)
        case system    // 跟随 macOS 系统代理(默认)
        case manual    // 用户填的 host:port

        var displayName: String {
            switch self {
            case .off:    return L("proxy.mode.off", comment: "")
            case .system: return L("proxy.mode.system", comment: "")
            case .manual: return L("proxy.mode.manual", comment: "")
            }
        }
    }

    /// 当前共享的 session。HTTPClient 默认用它。改完代理设置后 apply() 替换。
    static private(set) var sharedSession: URLSession = .shared

    /// 根据 mode / host / port 重建 sharedSession。改完立即生效,后续 HTTPClient
    /// 实例(默认懒读 sharedSession)就走新代理。
    static func apply(mode: ProxyMode, host: String?, port: Int?) {
        let config = URLSessionConfiguration.default
        switch mode {
        case .off:
            // 显式空字典:绕开 macOS 系统代理(给「我在公司挂了代理但想直连 GitHub」的场景)
            config.connectionProxyDictionary = [:]
        case .system:
            // 默认就走系统配置,什么都不动
            break
        case .manual:
            guard let host = host, !host.isEmpty, let port = port, port > 0 else {
                // 配置不全时回退到系统
                break
            }
            // HTTP + HTTPS 都走同一个代理,常见用法
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: 1,
                kCFNetworkProxiesHTTPProxy as String: host,
                kCFNetworkProxiesHTTPPort as String: port,
                "HTTPSEnable": 1,
                "HTTPSProxy": host,
                "HTTPSPort": port
            ]
        }
        sharedSession = URLSession(configuration: config)
    }
}
