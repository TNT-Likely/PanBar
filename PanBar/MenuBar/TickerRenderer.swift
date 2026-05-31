import Foundation
import AppKit

/// 菜单栏滚动条上一格内容。可以是一只股票行情、一个大盘指数、或者汇总指标。
enum TickerItem {
    case quote(Quote)
    case index(IndexQuote)
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
    var showsQuoteCode: Bool = true
    var showsQuoteName: Bool = true

    /// 涨色 / 跌色:走 SemanticColors,与 Popover 保持一致 + 菜单栏对比度优化。
    private var upColor: NSColor { SemanticColors.upNS(scheme: scheme) }
    private var downColor: NSColor { SemanticColors.downNS(scheme: scheme) }

    /// 渲染 ticker 串。
    /// 多项之间用 "  ·  " 分隔。
    func render(items: [TickerItem]) -> NSAttributedString {
        guard !items.isEmpty else {
            return NSAttributedString()
        }

        let out = NSMutableAttributedString()
        let separatorAttr = NSAttributedString(string: "  ·  ", attributes: [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.45)
        ])

        for (i, item) in items.enumerated() {
            if i > 0 { out.append(separatorAttr) }
            switch item {
            case .quote(let q):
                out.append(piece(for: q))
            case .index(let iq):
                out.append(indexPiece(for: iq))
            case .summary(let label, let value, let dir):
                out.append(summaryPiece(label: label, value: value, direction: dir))
            }
        }
        return out
    }

    private func indexPiece(for q: IndexQuote) -> NSAttributedString {
        let nameAttr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.92)
        ]
        let valueAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.75)
        ]
        let pctColor = q.change >= 0 ? upColor : downColor
        let pctAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .semibold),
            .foregroundColor: pctColor
        ]
        let pctSign = q.change >= 0 ? "+" : ""
        let pctText = String(format: "%@%.2f%%", pctSign, q.changePct * 100)

        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: q.descriptor.displayName + " ", attributes: nameAttr))
        s.append(NSAttributedString(string: formatPrice(q.price) + " ", attributes: valueAttr))
        s.append(NSAttributedString(string: pctText, attributes: pctAttr))
        return s
    }

    private func summaryPiece(label: String, value: String, direction: TickerDirection) -> NSAttributedString {
        // label 部分:小一号、白色 + 50% 透明,加底色块区分,避免和股票名混淆。
        // 由于 NSAttributedString 不支持背景圆角,改用更明显的字体处理:粗体 + 字距 + 后缀冒号。
        let labelAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: font.pointSize - 1, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.55),
            .kern: 0.6
        ]
        let valueColor: NSColor
        switch direction {
        case .up:      valueColor = upColor
        case .down:    valueColor = downColor
        case .neutral: valueColor = NSColor.white.withAlphaComponent(0.95)
        }
        let valueAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .semibold),
            .foregroundColor: valueColor
        ]
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: label.uppercased() + " ", attributes: labelAttr))
        s.append(NSAttributedString(string: value, attributes: valueAttr))
        return s
    }

    private func piece(for q: Quote) -> NSAttributedString {
        // 关掉 vibrancy 之后,系统 secondaryLabelColor 会被原色渲染,在菜单栏深底上显得太灰。
        // 改用固定白色不同 alpha,确保层级清晰:
        //   - 代码:100% 白(主信息)
        //   - 名称:80% 白(辅助识别)
        //   - 价格:80% 白 + 等宽数字
        //   - 涨跌:语义红/绿
        let symbolAttr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let nameAttr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.80)
        ]
        let valueAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.80)
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
        if showsQuoteCode {
            s.append(NSAttributedString(string: display + " ", attributes: symbolAttr))
        }
        if showsQuoteName && !name.isEmpty {
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
