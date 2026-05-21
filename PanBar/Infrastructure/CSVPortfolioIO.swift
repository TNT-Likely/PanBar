import Foundation
import AppKit
import UniformTypeIdentifiers

/// 持仓 & 自选股的 CSV 导入导出。
///
/// 持仓 CSV 格式(header 行 + 数据):
///   symbol,market,name,quantity,cost_price,currency,note
///
/// 自选 CSV 格式:
///   symbol,market,name,order
enum CSVPortfolioIO {
    // MARK: Export

    static func exportHoldings(_ holdings: [Holding]) -> String {
        var lines = ["symbol,market,name,quantity,cost_price,currency,note"]
        for h in holdings {
            let row: [String] = [
                h.symbol.code,
                h.symbol.market.rawValue,
                csvField(h.name),
                "\(h.quantity)",
                "\(h.costPrice)",
                h.currency.rawValue,
                csvField(h.note ?? "")
            ]
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    static func exportWatchlist(_ items: [WatchItem]) -> String {
        var lines = ["symbol,market,name,order"]
        for w in items {
            let row: [String] = [
                w.symbol.code,
                w.symbol.market.rawValue,
                csvField(w.name),
                "\(w.order)"
            ]
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Import

    static func importHoldings(_ text: String) -> [Holding] {
        var out: [Holding] = []
        let rows = parseRows(text)
        for row in rows.dropFirst() {  // skip header
            guard row.count >= 5 else { continue }
            guard let market = Market(rawValue: row[1]) else { continue }
            guard let qty = Decimal(string: row[3]) else { continue }
            guard let cost = Decimal(string: row[4]) else { continue }
            let currency: Currency = {
                if row.count > 5, let c = Currency(rawValue: row[5]) { return c }
                return market.defaultCurrency
            }()
            let note = row.count > 6 ? row[6] : nil
            out.append(Holding(
                symbol: SymbolID(code: row[0], market: market),
                name: row[2],
                quantity: qty,
                costPrice: cost,
                currency: currency,
                note: note?.isEmpty == true ? nil : note
            ))
        }
        return out
    }

    static func importWatchlist(_ text: String) -> [WatchItem] {
        var out: [WatchItem] = []
        let rows = parseRows(text)
        for row in rows.dropFirst() {
            guard row.count >= 3 else { continue }
            guard let market = Market(rawValue: row[1]) else { continue }
            let order = row.count > 3 ? Int(row[3]) ?? 0 : 0
            out.append(WatchItem(
                symbol: SymbolID(code: row[0], market: market),
                name: row[2],
                order: order
            ))
        }
        return out
    }

    // MARK: File panels (NSOpenPanel / NSSavePanel)

    @MainActor
    static func presentExportPanel(suggestedName: String, content: String) {
        let panel = NSSavePanel()
        panel.title = L("csv.exportTitle", comment: "")
        panel.nameFieldStringValue = suggestedName
        if let csv = UTType(filenameExtension: "csv") {
            panel.allowedContentTypes = [csv]
        }
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                Log.app.error("CSV write failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    @MainActor
    static func presentImportPanel(completion: @escaping (String?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = L("csv.importTitle", comment: "")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let csv = UTType(filenameExtension: "csv") {
            panel.allowedContentTypes = [csv]
        }
        if panel.runModal() == .OK, let url = panel.url {
            let text = (try? String(contentsOf: url, encoding: .utf8))
                ?? (try? String(contentsOf: url, encoding: .ascii))
            completion(text)
        } else {
            completion(nil)
        }
    }

    // MARK: helpers

    private static func parseRows(_ text: String) -> [[String]] {
        text.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }).map { line in
            parseLine(String(line))
        }
    }

    /// 处理引号包裹与逗号的 CSV 行解析(简化版)。
    private static func parseLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
                continue
            }
            if ch == "," && !inQuotes {
                fields.append(current)
                current = ""
                continue
            }
            current.append(ch)
        }
        fields.append(current)
        return fields
    }

    private static func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
