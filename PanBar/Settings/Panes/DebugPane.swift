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
                Button("生成示例数据(5 只持仓 + 3 只自选 + 2 条预警)") {
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

        // 持仓:A 股 + 港股 + 美股 混合,验证多市场 / 多币种 / 排序
        let holdings: [Holding] = [
            Holding(symbol: SymbolID(code: "600519", market: .a),  name: "贵州茅台", quantity: 100,  costPrice: 1300, currency: .cny, sortOrder: 0),
            Holding(symbol: SymbolID(code: "601127", market: .a),  name: "赛力斯",   quantity: 100,  costPrice: 2000, currency: .cny, sortOrder: 1),
            Holding(symbol: SymbolID(code: "LI",     market: .us), name: "理想汽车", quantity: 1000, costPrice: 5,    currency: .usd, sortOrder: 2),
            Holding(symbol: SymbolID(code: "09988",  market: .hk), name: "阿里巴巴-W", quantity: 1000, costPrice: 150, currency: .hkd, sortOrder: 3),
            Holding(symbol: SymbolID(code: "NVDA",   market: .us), name: "英伟达",   quantity: 200,  costPrice: 200,  currency: .usd, sortOrder: 4)
        ]
        for h in holdings { try? container.holdingsRepo.upsert(h) }

        // 自选:看几只不在持仓里的
        let watches: [WatchItem] = [
            WatchItem(symbol: SymbolID(code: "AAPL",  market: .us), name: "苹果",     order: 0),
            WatchItem(symbol: SymbolID(code: "TSLA",  market: .us), name: "特斯拉",   order: 1),
            WatchItem(symbol: SymbolID(code: "00700", market: .hk), name: "腾讯控股", order: 2)
        ]
        for w in watches { try? container.watchlistRepo.upsert(w) }

        // 预警:一个价格告警 + 一个跌幅告警
        let alerts: [Alert] = [
            Alert(symbol: SymbolID(code: "601127", market: .a),  name: "赛力斯",   condition: .priceBelow, threshold: 90),
            Alert(symbol: SymbolID(code: "NVDA",   market: .us), name: "英伟达",   condition: .changePctBelow, threshold: -0.03)
        ]
        for a in alerts { try? container.alertsRepo.upsert(a) }

        container.refresher.refreshNow()
        lastMessage = "✓ 已生成示例:5 只持仓 + 3 只自选 + 2 条预警"
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
