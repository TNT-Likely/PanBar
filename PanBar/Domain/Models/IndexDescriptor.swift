import Foundation

/// 大盘指数描述符。每个指数自带本地化名 + EM secid + 货币。
/// 不复用 SymbolID,因为指数代码空间和股票冲突(000001 既可以是平安银行也可以是上证指数)。
struct IndexDescriptor: Identifiable, Hashable, Sendable {
    let id: String              // "SH000001"
    let nameZh: String
    let nameEn: String
    let market: Market
    let emSecid: String         // "1.000001"
    let currency: Currency

    var displayName: String {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true ? nameZh : nameEn
    }
}

enum IndexCatalog {
    static let all: [IndexDescriptor] = [
        IndexDescriptor(id: "SH000001", nameZh: "上证指数",   nameEn: "SSE Composite",  market: .a,  emSecid: "1.000001", currency: .cny),
        IndexDescriptor(id: "SZ399001", nameZh: "深证成指",   nameEn: "SZSE Component", market: .a,  emSecid: "0.399001", currency: .cny),
        IndexDescriptor(id: "SZ399006", nameZh: "创业板指",   nameEn: "ChiNext",        market: .a,  emSecid: "0.399006", currency: .cny),
        IndexDescriptor(id: "SH000300", nameZh: "沪深300",    nameEn: "CSI 300",        market: .a,  emSecid: "1.000300", currency: .cny),
        IndexDescriptor(id: "HSI",      nameZh: "恒生指数",   nameEn: "Hang Seng",      market: .hk, emSecid: "100.HSI",  currency: .hkd),
        IndexDescriptor(id: "DJIA",     nameZh: "道琼斯",     nameEn: "Dow Jones",      market: .us, emSecid: "100.DJIA", currency: .usd),
        IndexDescriptor(id: "NDX",      nameZh: "纳斯达克100", nameEn: "NASDAQ 100",    market: .us, emSecid: "100.NDX",  currency: .usd),
        IndexDescriptor(id: "SPX",      nameZh: "标普500",    nameEn: "S&P 500",        market: .us, emSecid: "100.SPX",  currency: .usd)
    ]
}

struct IndexQuote: Identifiable, Equatable, Sendable {
    var id: String { descriptor.id }
    let descriptor: IndexDescriptor
    let price: Decimal
    let prevClose: Decimal
    let change: Decimal
    let changePct: Double
}
