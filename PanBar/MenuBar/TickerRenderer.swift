import Foundation
import AppKit

/// 菜单栏滚动条上一格内容。可以是一只股票行情,也可以是汇总指标(今日盈亏 / 总资产 / 累计盈亏)。
enum TickerItem {
    case quote(Quote)
    /// 汇总项,自带方向(用于配色):.up / .down / .neutral
    case summary(label: String, value: String, direction: TickerDirection)
}

enum TickerDirection {
    case up
    case down
    case neutral
}

/// 把一组 TickerItem 渲染为单条 NSAttributedString。
/// 调用方在拼接前/后会自行加分隔符。
struct TickerRenderer {
    var scheme: TickerColorScheme = .east
    var font: NSFont = NSFont.menuBarFont(ofSize: 0)

    /// 涨色 / 跌色:走 SemanticColors,与 Popover 保持一致 + 菜单栏对比度优化。
    private var upColor: NSColor { SemanticColors.upNS(scheme: scheme) }
    private var downColor: NSColor { SemanticColors.downNS(scheme: scheme) }

    /// 渲染 ticker 串。
    /// 多项之间用 "  ·  " 分隔。
    func render(items: [TickerItem]) -> NSAttributedString {
        guard !items.isEmpty else {
            return NSAttributedString(
                string: L("ticker.empty", comment: "no quotes"),
                attributes: [
                    .font: font,
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
        }

        let out = NSMutableAttributedString()
        let separatorAttr = NSAttributedString(string: "  ·  ", attributes: [
            .font: font,
            .foregroundColor: NSColor.tertiaryLabelColor
        ])

        for (i, item) in items.enumerated() {
            if i > 0 { out.append(separatorAttr) }
            switch item {
            case .quote(let q):
                out.append(piece(for: q))
            case .summary(let label, let value, let dir):
                out.append(summaryPiece(label: label, value: value, direction: dir))
            }
        }
        return out
    }

    private func summaryPiece(label: String, value: String, direction: TickerDirection) -> NSAttributedString {
        let labelAttr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let valueColor: NSColor
        switch direction {
        case .up:      valueColor = upColor
        case .down:    valueColor = downColor
        case .neutral: valueColor = NSColor.labelColor
        }
        let valueAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .semibold),
            .foregroundColor: valueColor
        ]
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: label + " ", attributes: labelAttr))
        s.append(NSAttributedString(string: value, attributes: valueAttr))
        return s
    }

    private func piece(for q: Quote) -> NSAttributedString {
        let symbolAttr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let nameAttr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let valueAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let pctColor = q.change >= 0 ? upColor : downColor
        let pctAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .semibold),
            .foregroundColor: pctColor
        ]
        let pctSign = q.change >= 0 ? "+" : ""
        let pctText = String(format: "%@%.2f%%", pctSign, q.changePct * 100)

        let display = displayCode(for: q.symbol)
        let name = shortenedName(q.name, market: q.symbol.market)

        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: display + " ", attributes: symbolAttr))
        if !name.isEmpty {
            s.append(NSAttributedString(string: name + " ", attributes: nameAttr))
        }
        s.append(NSAttributedString(string: formatPrice(q.price) + " ", attributes: valueAttr))
        s.append(NSAttributedString(string: pctText, attributes: pctAttr))
        return s
    }

    /// 截断超长名称,英文名 12 字符内,中文名 6 字内,避免单只票占太长。
    private func shortenedName(_ name: String, market: Market) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let isChinese = trimmed.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        let limit = isChinese ? 6 : 12
        if trimmed.count <= limit { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }

    private func displayCode(for symbol: SymbolID) -> String {
        switch symbol.market {
        case .us:  return symbol.code.uppercased()
        case .hk:  return symbol.code
        case .a:   return symbol.code
        }
    }

    private func formatPrice(_ price: Decimal) -> String {
        let fmt = NumberFormatter()
        fmt.minimumFractionDigits = 2
        fmt.maximumFractionDigits = 2
        return fmt.string(from: NSDecimalNumber(decimal: price)) ?? "\(price)"
    }
}
