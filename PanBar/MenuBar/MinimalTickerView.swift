import AppKit

/// 「极简」模式:只显示一个用户选定的汇总数字 + ↑↓ 箭头。
/// 适合屏幕窄、菜单栏挤的场景,可能只占 60-80pt 宽。
final class MinimalTickerView: NSView {
    struct Content {
        let label: String   // 「今」「累」「总」之类的单字提示
        let value: Decimal
        let direction: TickerDirection
        let currency: Currency
    }

    private var content: Content?
    var scheme: TickerColorScheme = .east
    var privacyHidden: Bool = false
    var hovered: Bool = false
    var onContentChanged: (() -> Void)?

    let iconWidth: CGFloat = 18
    private let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)

    var totalWidth: CGFloat {
        guard let _ = content else { return iconWidth + 40 }
        return iconWidth + 6 + max(56, renderedString().size().width) + 6
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

    func update(content: Content?) {
        self.content = content
        needsDisplay = true
        onContentChanged?()
    }

    override func draw(_ dirtyRect: NSRect) {
        drawIcon(in: NSRect(x: 2, y: (bounds.height - iconWidth) / 2, width: iconWidth, height: iconWidth))

        if privacyHidden {
            let dots = NSAttributedString(string: "•••", attributes: [
                .font: valueFont,
                .foregroundColor: NSColor.secondaryLabelColor
            ])
            dots.draw(at: NSPoint(x: iconWidth + 8, y: bounds.midY - dots.size().height / 2))
            return
        }

        let str = renderedString()
        let size = str.size()
        let p = NSPoint(x: iconWidth + 6, y: (bounds.height - size.height) / 2)
        str.draw(at: p)
    }

    private func renderedString() -> NSAttributedString {
        guard let c = content else {
            return NSAttributedString(string: "—", attributes: [
                .font: valueFont,
                .foregroundColor: NSColor.secondaryLabelColor
            ])
        }
        let color: NSColor = {
            switch c.direction {
            case .up:      return SemanticColors.upNS(scheme: scheme)
            case .down:    return SemanticColors.downNS(scheme: scheme)
            case .neutral: return NSColor.white.withAlphaComponent(0.92)
            }
        }()
        let labelAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.55)
        ]
        let valueAttr: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: color
        ]
        // 箭头放在数字前面更直观,中性时省略
        let arrow: String = {
            switch c.direction {
            case .up: return "↑ "
            case .down: return "↓ "
            case .neutral: return ""
            }
        }()
        let sign: String
        if c.direction == .neutral {
            sign = ""
        } else {
            sign = c.value < 0 ? "-" : "+"
        }
        let text = arrow + sign + c.currency.symbol + NumberAbbreviation.format(c.value, currency: c.currency)
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: c.label + " ", attributes: labelAttr))
        s.append(NSAttributedString(string: text, attributes: valueAttr))
        return s
    }

    private func drawIcon(in rect: NSRect) {
        MenuBarIcon.draw(in: rect)
    }
}
