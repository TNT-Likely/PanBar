#if DEBUG
import SwiftUI
import AppKit

/// 仅 Debug 构建出现的工具页:清数据 / 灌示例数据 / 打开 DB 目录。
/// Release 包不会编译进去(整文件被 #if DEBUG 包住)。
struct DebugPane: View {
    @Environment(\.container) private var container
    @State private var lastMessage: String = ""

    var body: some View {
        if let container = container {
            content(container: container)
        } else {
            Text(L("loading", comment: ""))
        }
    }

    @ViewBuilder
    private func content(container: DependencyContainer) -> some View {
        Form {
            Section(header: Text("Debug 工具").font(.title3)) {
                Text("仅 dev 构建可见,用于快速重置 / 造数据。Release 包没有这页。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("数据").font(.headline)) {
                Button("生成示例数据(9 只持仓 · 覆盖各市场+ETF/LOF + 3 只自选 + 2 条预警)") {
                    seedSampleData(container: container)
                }
                Button("清空持仓") { clear(container: container, kinds: [.holdings]) }
                Button("清空自选") { clear(container: container, kinds: [.watchlist]) }
                Button("清空预警") { clear(container: container, kinds: [.alerts]) }
                Button(role: .destructive) {
                    clear(container: container, kinds: [.holdings, .watchlist, .alerts, .quoteCache, .fxCache])
                } label: {
                    Text("全部清空(持仓 + 自选 + 预警 + 行情缓存 + 汇率缓存)")
                }
            }

            Section(header: Text("文件").font(.headline)) {
                Button("在 Finder 打开数据目录") {
                    openDataFolderInFinder()
                }
                Button("打开 updater.log") {
                    openLogFile(name: "updater.log")
                }
            }

            if !lastMessage.isEmpty {
                Section {
                    Text(lastMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    // MARK: - Actions

    private enum ClearKind { case holdings, watchlist, alerts, quoteCache, fxCache }

    private func clear(container: DependencyContainer, kinds: Set<ClearKind>) {
        var done: [String] = []
        if kinds.contains(.holdings) {
            try? container.holdingsRepo.deleteAll()
            done.append("持仓")
        }
        if kinds.contains(.watchlist) {
            try? container.watchlistRepo.deleteAll()
            done.append("自选")
        }
        if kinds.contains(.alerts) {
            try? container.alertsRepo.deleteAll()
            done.append("预警")
        }
        if kinds.contains(.quoteCache) {
            try? container.database.dbPool.write { db in
                try db.execute(sql: "DELETE FROM quoteCache")
            }
            done.append("行情缓存")
        }
        if kinds.contains(.fxCache) {
            try? container.database.dbPool.write { db in
                try db.execute(sql: "DELETE FROM fxCache")
            }
            done.append("汇率缓存")
        }
        container.refresher.refreshNow()
        lastMessage = "✓ 已清空:\(done.joined(separator: " / "))"
    }

    private func seedSampleData(container: DependencyContainer) {
        // 先清旧的避免重复
        try? container.holdingsRepo.deleteAll()
        try? container.watchlistRepo.deleteAll()
        try? container.alertsRepo.deleteAll()

        // 持仓:务必覆盖「每一个市场 / A 股每个板块 / 主要品种」,验证多市场 /
        // 多币种 / 行情路由(沪 60·68·51 → sh,深 00·30·16 → sz)/ 搜索分类 / 排序。
        // 沪主板 60 + 深主板 00 + 创业板 30 + 科创板 68 + 沪ETF 51 + 深LOF 16 + 港股 + 美股。
        // (北交所 43/83/87/88/92:SymbolEncoder 明确不支持,不 seed;
        //  可转债:代码随赎回频繁退市、smartbox 也搜不到稳定个券,不适合写死。)
        let holdings: [Holding] = [
            Holding(symbol: SymbolID(code: "600519", market: .a),  name: "贵州茅台",     quantity: 100,  costPrice: 1300, currency: .cny, sortOrder: 0),  // 沪市主板
            Holding(symbol: SymbolID(code: "000001", market: .a),  name: "平安银行",     quantity: 2000, costPrice: 11,   currency: .cny, sortOrder: 1),  // 深市主板
            Holding(symbol: SymbolID(code: "300750", market: .a),  name: "宁德时代",     quantity: 200,  costPrice: 180,  currency: .cny, sortOrder: 2),  // 创业板
            Holding(symbol: SymbolID(code: "688256", market: .a),  name: "寒武纪",       quantity: 50,   costPrice: 600,  currency: .cny, sortOrder: 3),  // 科创板
            Holding(symbol: SymbolID(code: "510300", market: .a),  name: "沪深300ETF",  quantity: 5000, costPrice: 3.8,  currency: .cny, sortOrder: 4),  // ETF(沪市 51→sh)
            Holding(symbol: SymbolID(code: "161725", market: .a),  name: "白酒基金LOF", quantity: 3000, costPrice: 1.0,  currency: .cny, sortOrder: 5),  // LOF(深市基金 16→sz)
            Holding(symbol: SymbolID(code: "09988",  market: .hk), name: "阿里巴巴-W",   quantity: 1000, costPrice: 150,  currency: .hkd, sortOrder: 6),  // 港股
            Holding(symbol: SymbolID(code: "LI",     market: .us), name: "理想汽车",     quantity: 1000, costPrice: 5,    currency: .usd, sortOrder: 7),  // 美股
            Holding(symbol: SymbolID(code: "NVDA",   market: .us), name: "英伟达",       quantity: 200,  costPrice: 200,  currency: .usd, sortOrder: 8)   // 美股
        ]
        for h in holdings { try? container.holdingsRepo.upsert(h) }

        // 自选:覆盖未在持仓里的市场组合(美股 / 港股 / 科创板),便于一并验证。
        let watches: [WatchItem] = [
            WatchItem(symbol: SymbolID(code: "AAPL",   market: .us), name: "苹果",     order: 0),  // 美股
            WatchItem(symbol: SymbolID(code: "00700",  market: .hk), name: "腾讯控股", order: 1),  // 港股
            WatchItem(symbol: SymbolID(code: "688981", market: .a),  name: "中芯国际", order: 2)   // 科创板
        ]
        for w in watches { try? container.watchlistRepo.upsert(w) }

        // 预警:一个价格告警 + 一个跌幅告警(都指向已持仓的标的)
        let alerts: [Alert] = [
            Alert(symbol: SymbolID(code: "688256", market: .a),  name: "寒武纪", condition: .priceBelow, threshold: 500),
            Alert(symbol: SymbolID(code: "NVDA",   market: .us), name: "英伟达", condition: .changePctBelow, threshold: -0.03)
        ]
        for a in alerts { try? container.alertsRepo.upsert(a) }

        container.refresher.refreshNow()
        lastMessage = "✓ 已生成示例:9 只持仓(沪/深主板·创业板·科创板·ETF·LOF·港股·美股)+ 3 只自选 + 2 条预警"
    }

    private func openDataFolderInFinder() {
        guard let url = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }
        let folderName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "PanBar"
        let appFolder = url.appendingPathComponent(folderName, isDirectory: true)
        NSWorkspace.shared.open(appFolder)
        lastMessage = "✓ 已打开 \(appFolder.path)"
    }

    private func openLogFile(name: String) {
        guard let url = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }
        let folderName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "PanBar"
        let logURL = url.appendingPathComponent(folderName, isDirectory: true).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: logURL.path) {
            NSWorkspace.shared.open(logURL)
            lastMessage = "✓ 已打开 \(name)"
        } else {
            lastMessage = "× \(name) 不存在,等 Sparkle/Updater 跑一次再看"
        }
    }
}
#endif
