import AppKit

/// 「上下滚动」/「轮播」模式:每 N 秒切换显示下一条 item,带 300ms 垂直滑入 + 淡入。
/// 比真正的连续滚动眼花少很多,菜单栏空间合适。
final class CarouselTickerView: NSView {
    /// 单条 item 的渲染结果。
    private var items: [NSAttributedString] = []
    private var currentIndex: Int = 0
    /// 当前 transition 进度,0..1,1 表示完全到达 currentIndex,0 表示从上一条刚开始切。
    private var transition: CGFloat = 1
    private var transitionStart: CFTimeInterval = 0
    private let transitionDuration: CFTimeInterval = 0.35
    /// 每条停留 4s 后切下一条
    private let dwell: CFTimeInterval = 4
    private var lastSwitch: CFTimeInterval = 0
    private var displayLink: CVDisplayLink?
    private var hovered: Bool = false
    var pauseOnHover: Bool = true

    let iconWidth: CGFloat = 18
    var visibleTextWidth: CGFloat = 200
    var privacyHidden: Bool = false

    var totalWidth: CGFloat {
        iconWidth + 6 + visibleTextWidth + 4
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
        layer?.shouldRasterize = true
        layer?.rasterizationScale = NSScreen.main?.backingScaleFactor ?? 2.0
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        startAnimation()
    }

    deinit {
        stopAnimation()
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    func update(items: [NSAttributedString]) {
        self.items = items
        if currentIndex >= items.count { currentIndex = 0 }
        // 计算最长一条的宽度,统一让 visibleTextWidth 容得下,避免切换时宽度跳
        let maxW = items.map { $0.size().width }.max() ?? 0
        visibleTextWidth = max(80, min(400, maxW + 8))
        needsDisplay = true
    }

    private func startAnimation() {
        var dl: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&dl)
        guard let dl = dl else { return }
        displayLink = dl
        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(dl, { _, inNow, _, _, _, ctx in
            guard let ctx = ctx else { return kCVReturnSuccess }
            let view = Unmanaged<CarouselTickerView>.fromOpaque(ctx).takeUnretainedValue()
            let now = inNow.pointee
            let t = CFTimeInterval(now.hostTime) / CFTimeInterval(CVGetHostClockFrequency())
            DispatchQueue.main.async { view.step(now: t) }
            return kCVReturnSuccess
        }, opaqueSelf)
        CVDisplayLinkStart(dl)
    }

    private func stopAnimation() {
        if let dl = displayLink { CVDisplayLinkStop(dl) }
        displayLink = nil
    }

    private func step(now: CFTimeInterval) {
        if items.count <= 1 {
            return  // 只有一条不切
        }
        if pauseOnHover && hovered { return }
        if lastSwitch == 0 { lastSwitch = now }

        if transition < 1 {
            // 正在过渡
            let p = min(1, (now - transitionStart) / transitionDuration)
            transition = CGFloat(easeOut(p))
            needsDisplay = true
            return
        }

        if now - lastSwitch >= dwell {
            // 切到下一条
            currentIndex = (currentIndex + 1) % items.count
            transitionStart = now
            transition = 0
            lastSwitch = now
            needsDisplay = true
        }
    }

    private func easeOut(_ t: CFTimeInterval) -> CFTimeInterval {
        // 三次缓出,过渡末段更平
        let u = 1 - t
        return 1 - u * u * u
    }

    override func draw(_ dirtyRect: NSRect) {
        drawIcon(in: NSRect(x: 2, y: (bounds.height - iconWidth) / 2, width: iconWidth, height: iconWidth))

        let textRect = NSRect(
            x: iconWidth + 6,
            y: 0,
            width: visibleTextWidth,
            height: bounds.height
        )

        if privacyHidden {
            let dots = NSAttributedString(string: "•••", attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ])
            let p = NSPoint(x: textRect.minX + 4, y: textRect.midY - dots.size().height / 2)
            dots.draw(at: p)
            return
        }

        guard !items.isEmpty else { return }

        let current = items[currentIndex]
        // transition: 0 → 1.从上往下滑入(从 y=-6 到 y=0),配 alpha 0..1
        let slideY: CGFloat = (1 - transition) * -6
        let alpha = transition

        let ctx = NSGraphicsContext.current?.cgContext
        ctx?.saveGState()
        NSBezierPath(rect: textRect).addClip()

        // 重绘 alpha
        ctx?.setAlpha(alpha)
        let textY = (bounds.height - current.size().height) / 2 + slideY
        current.draw(at: NSPoint(x: textRect.minX, y: textY))
        ctx?.restoreGState()
    }

    private func drawIcon(in rect: NSRect) {
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor
        ]
        let str = NSAttributedString(string: "P", attributes: attr)
        let size = str.size()
        let p = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        str.draw(at: p)
    }
}
