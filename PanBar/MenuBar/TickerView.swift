import AppKit

/// 自绘的滚动 ticker 视图。绘制一个 P 图标 + 不停向左滚动的 NSAttributedString。
final class TickerView: NSView {
    /// ticker 内容(纯文本部分,不含图标)。
    private var attributed: NSAttributedString = NSAttributedString()
    /// 当前滚动偏移量(像素,>=0)。
    private var offset: CGFloat = 0
    /// 滚动速度(像素 / 秒)。
    var pixelsPerSecond: CGFloat = 30
    /// 是否在 hover 时暂停。
    var pauseOnHover: Bool = true
    /// 由 controller 同步过来的 hover 状态(view 不在 window 里,自己监听不到)
    var hovered: Bool = false
    private var paused: Bool = false
    /// 动画帧或数据更新后,通知 controller 重新捕图。
    var onContentChanged: (() -> Void)?
    private var displayLink: CVDisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    /// 文字与图标之间的间距。
    let iconWidth: CGFloat = 18
    var showsIcon: Bool = true
    var preferredTotalWidth: CGFloat?
    /// 滚动文字可视区宽度(超出会被裁剪)。
    var visibleTextWidth: CGFloat = 280
    /// 隐私模式:屏幕共享或用户手动开启时,只显示图标和 "•••",不绘制具体行情。
    var privacyHidden: Bool = false
    /// 没有任何可见内容时仍保留一点点击区域,但不显示占位文字。
    private let emptyHitTargetWidth: CGFloat = 24

    /// 文字宽度(单条 attributed 的渲染宽度)。
    private var attributedWidth: CGFloat = 0
    /// 在滚动循环中,接缝间隔(单条结尾与下一次开头之间的空白)。
    private let loopGap: CGFloat = 24

    override var isFlipped: Bool { false }

    /// 关键:关掉 vibrancy。
    /// NSStatusBarButton 默认会把其子 view 的绘制结果套上 vibrancy 滤镜,
    /// 导致红色文字在滚动到不同壁纸区域时被混色成橙色 / 粉色。
    /// 这里强制返回 false,确保我们设定的 NSColor 1:1 渲染。
    override var allowsVibrancy: Bool { false }

    var totalWidth: CGFloat {
        if let preferredTotalWidth {
            return max(40, preferredTotalWidth)
        }
        if attributed.length == 0 {
            return max(emptyHitTargetWidth, leadingTextX + 4)
        }
        return leadingTextX + visibleTextWidth + 4
    }

    private var leadingTextX: CGFloat {
        showsIcon ? iconWidth + 6 : 2
    }

    // MARK: lifecycle

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
        startAnimation()
    }

    deinit {
        stopAnimation()
    }

    // MARK: data

    func update(attributed: NSAttributedString) {
        self.attributed = attributed
        self.attributedWidth = attributed.size().width
        if attributedWidth > 0 {
            visibleTextWidth = min(520, max(20, attributedWidth + 8))
        } else {
            visibleTextWidth = 0
        }
        if attributedWidth + loopGap > 0 {
            offset = offset.truncatingRemainder(dividingBy: attributedWidth + loopGap)
            if offset < 0 { offset += attributedWidth + loopGap }
        }
        needsDisplay = true
        onContentChanged?()
    }

    func setPaused(_ value: Bool) {
        paused = value
    }

    // MARK: animation

    private func startAnimation() {
        var dl: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&dl)
        guard let dl = dl else { return }
        displayLink = dl
        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(dl, { _, inNow, _, _, _, displayLinkContext in
            guard let context = displayLinkContext else { return kCVReturnSuccess }
            let view = Unmanaged<TickerView>.fromOpaque(context).takeUnretainedValue()
            let now = inNow.pointee
            let timestamp = CFTimeInterval(now.hostTime) / CFTimeInterval(CVGetHostClockFrequency())
            DispatchQueue.main.async {
                view.step(timestamp: timestamp)
            }
            return kCVReturnSuccess
        }, opaqueSelf)
        CVDisplayLinkStart(dl)
    }

    private func stopAnimation() {
        if let dl = displayLink { CVDisplayLinkStop(dl) }
        displayLink = nil
    }

    func invalidateAnimation() {
        stopAnimation()
    }

    private func step(timestamp: CFTimeInterval) {
        defer { lastTimestamp = timestamp }
        if lastTimestamp == 0 { return }
        let dt = timestamp - lastTimestamp
        if dt <= 0 || dt > 0.2 { return }
        if paused || (pauseOnHover && hovered) { return }
        if attributedWidth <= 0 { return }

        offset += CGFloat(dt) * pixelsPerSecond
        let cycle = attributedWidth + loopGap
        if offset > cycle { offset -= cycle }
        needsDisplay = true
        onContentChanged?()
    }

    // MARK: draw

    override func draw(_ dirtyRect: NSRect) {
        let ctx = NSGraphicsContext.current?.cgContext

        if showsIcon {
            drawIcon(in: NSRect(x: 2, y: (bounds.height - iconWidth) / 2, width: iconWidth, height: iconWidth))
        }

        let textRect = NSRect(
            x: leadingTextX,
            y: 0,
            width: max(20, totalWidth - leadingTextX - 4),
            height: bounds.height
        )

        // 隐私模式:不渲染数字,只展示一串占位符
        if privacyHidden {
            let dots = NSAttributedString(string: "•••", attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ])
            let size = dots.size()
            let p = NSPoint(
                x: textRect.minX + 4,
                y: textRect.midY - size.height / 2
            )
            dots.draw(at: p)
            return
        }

        ctx?.saveGState()
        NSBezierPath(rect: textRect).addClip()
        let textY = (bounds.height - attributed.size().height) / 2

        // 主串
        let drawX = textRect.minX - offset
        attributed.draw(at: NSPoint(x: drawX, y: textY))
        // 接缝:再绘一份在右边
        let next = drawX + attributedWidth + loopGap
        attributed.draw(at: NSPoint(x: next, y: textY))
        ctx?.restoreGState()
    }

    private func drawIcon(in rect: NSRect) {
        MenuBarIcon.draw(in: rect)
    }
}
