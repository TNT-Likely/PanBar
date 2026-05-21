import Foundation
import AppKit

/// 把一组 Quote 渲染为单条 NSAttributedString。
/// 调用方在拼接前/后会自行加分隔符。
struct TickerRenderer {
    var scheme: TickerColorScheme = .east
    var font: NSFont = NSFont.menuBarFont(ofSize: 0)

    /// 涨/跌色。
    private var upColor: NSColor {
        switch scheme {
        case .east: return NSColor.systemRed
        case .west: return NSColor.systemGreen
        case .mono: return NSColor.labelColor
        }
    }

    private var downColor: NSColor {
        switch scheme {
        case .east: return NSColor.systemGreen
        case .west: return NSColor.systemRed
        case .mono: return NSColor.labelColor
        }
    }

    /// 拼成 ticker 串。format 暂支持固定模板:`SYMBOL PRICE ±PCT%`
    /// 多只之间用 "  ·  " 分隔。
    func render(quotes orderedQuotes: [Quote]) -> NSAttributedString {
        guard !orderedQuotes.isEmpty else {
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

        for (i, q) in orderedQuotes.enumerated() {
            if i > 0 { out.append(separatorAttr) }
            out.append(piece(for: q))
        }
        return out
    }

    private func piece(for q: Quote) -> NSAttributedString {
        let baseAttr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
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

        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: display + " ", attributes: baseAttr))
        s.append(NSAttributedString(string: formatPrice(q.price) + " ", attributes: valueAttr))
        s.append(NSAttributedString(string: pctText, attributes: pctAttr))
        return s
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
