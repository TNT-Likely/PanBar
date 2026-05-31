import AppKit

/// 「固定」模式:今日 / 累计 / 总市值 三个简写数字横向排列,不滚不切。
/// 每个 slot 自带极小的 label(今 / 累 / 总)+ 简写数字(K/M)。
final class CompactTickerView: NSView {
    struct Slots {
        let todayPnL: Decimal?
        let allTimePnL: Decimal?
        let totalAssets: Decimal?
        let baseCurrency: Currency
    }

    private var slots: Slots = Slots(todayPnL: nil, allTimePnL: nil, totalAssets: nil, baseCurrency: .cny)
    var scheme: TickerColorScheme = .east
    var privacyHidden: Bool = false
    var showsIcon: Bool = true
    var showsDirectionArrow: Bool = false
    var preferredTotalWidth: CGFloat?
    /// hover 状态(放着满足协议,固定模式实际用不到)
    var hovered: Bool = false
    var onContentChanged: (() -> Void)?

    let iconWidth: CGFloat = 18
    private let slotSpacing: CGFloat = 10
    private let labelFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
    private let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    /// 没有任何可见内容时仍保留一点点击区域,但不显示占位文字。
    private let emptyHitTargetWidth: CGFloat = 24

    /// 估算的最长行宽,根据当前 slots 算出来。
    private var contentWidth: CGFloat {
        var w: CGFloat = 0
        var first = true
        for piece in renderPieces() {
            if !first { w += slotSpacing }
            w += piece.size().width
            first = false
        }
        return w
    }

    var totalWidth: CGFloat {
        if let preferredTotalWidth {
            return max(40, preferredTotalWidth)
        }
        let width = contentWidth
        guard width > 0 else { return max(emptyHitTargetWidth, leadingTextX + 4) }
        return leadingTextX + width + 4
    }

    private var leadingTextX: CGFloat {
        showsIcon ? iconWidth + 6 : 2
    }

    override var isFlipped: Bool { false }
    override var allowsVibrancy: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = .clear
        appearance = NSAppearance(named: .darkAqua)
    }

    func update(slots: Slots) {
        self.slots = slots
        needsDisplay = true
        onContentChanged?()
    }

    override func draw(_ dirtyRect: NSRect) {
        if showsIcon {
            drawIcon(in: NSRect(x: 2, y: (bounds.height - iconWidth) / 2, width: iconWidth, height: iconWidth))
        }

        let textRect = NSRect(
            x: leadingTextX,
            y: 0,
            width: max(20, totalWidth - leadingTextX - 4),
            height: bounds.height
        )

        if privacyHidden {
            let dots = NSAttributedString(string: "•••", attributes: [
                .font: valueFont,
                .foregroundColor: NSColor.secondaryLabelColor
            ])
            dots.draw(at: NSPoint(x: textRect.minX + 4, y: bounds.midY - dots.size().height / 2))
            return
        }

        let ctx = NSGraphicsContext.current?.cgContext
        ctx?.saveGState()
        NSBezierPath(rect: textRect).addClip()
        var x: CGFloat = textRect.minX
        for (i, piece) in renderPieces().enumerated() {
            if i > 0 { x += slotSpacing }
            let size = piece.size()
            let y = (bounds.height - size.height) / 2
            piece.draw(at: NSPoint(x: x, y: y))
            x += size.width
        }
        ctx?.restoreGState()
    }

    /// 当前要展示的三个简写片段(组合 label + 数字 + 颜色,返回 AttributedString)。
    /// nil 的字段跳过(比如汇率还没来时 totalAssets=nil)。
    private func renderPieces() -> [NSAttributedString] {
        var out: [NSAttributedString] = []

        if let pnl = slots.todayPnL {
            out.append(piece(label: L("compact.label.today", comment: ""), value: pnl, direction: directionOf(pnl)))
        }
        if let pnl = slots.allTimePnL {
            out.append(piece(label: L("compact.label.allTime", comment: ""), value: pnl, direction: directionOf(pnl)))
        }
        if let v = slots.totalAssets {
            out.append(piece(label: L("compact.label.total", comment: ""), value: v, direction: .neutral))
        }
        return out
    }

    private func piece(label: String, value: Decimal, direction: TickerDirection) -> NSAttributedString {
        let labelAttr: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor.white.withAlphaComponent(0.55),
            .kern: 0.3
        ]
        let color: NSColor = {
            switch direction {
            case .up:      return SemanticColors.upNS(scheme: scheme)
            case .down:    return SemanticColors.downNS(scheme: scheme)
            case .neutral: return NSColor.white.withAlphaComponent(0.92)
            }
        }()
        let valueAttr: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: color
        ]
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: label + " ", attributes: labelAttr))
        let text: String
        if direction == .neutral {
            text = NumberAbbreviation.formatCurrency(value, currency: slots.baseCurrency)
        } else {
            let arrow: String
            if showsDirectionArrow {
                arrow = direction == .up ? "↑ " : "↓ "
            } else {
                arrow = ""
            }
            let sign = value < 0 ? "-" : "+"
            text = arrow + sign + slots.baseCurrency.symbol + NumberAbbreviation.format(value, currency: slots.baseCurrency)
        }
        s.append(NSAttributedString(string: text, attributes: valueAttr))
        return s
    }

    private func directionOf(_ v: Decimal) -> TickerDirection {
        if v > 0 { return .up }
        if v < 0 { return .down }
        return .neutral
    }

    private func drawIcon(in rect: NSRect) {
        MenuBarIcon.draw(in: rect)
    }
}
