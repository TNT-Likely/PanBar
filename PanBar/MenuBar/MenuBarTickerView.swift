import AppKit

/// 所有菜单栏 ticker 视图的公共接口。
///
/// 关键设计:view 不挂到 NSStatusBarButton 的 subview 树里,而是单纯做「渲染器」。
/// Controller 调 `renderImage()` 拿到 NSImage(isTemplate=false),设给
/// `button.image`。这么做是为了绕开 macOS 在菜单栏对「非活跃 app 的 subview」
/// 自动加 vibrancy 降饱和度滤镜 —— NSImage 走另一条渲染管线,不被这个滤镜影响。
protocol MenuBarTickerView: NSView {
    var totalWidth: CGFloat { get }
    var privacyHidden: Bool { get set }
    var showsIcon: Bool { get set }
    var preferredTotalWidth: CGFloat? { get set }
    /// 鼠标 hover 状态;由 controller 监听 button 的 tracking area 同步过来
    var hovered: Bool { get set }
    /// 内容变化通知(动画帧 / 数据更新),controller 重新捕图。
    var onContentChanged: (() -> Void)? { get set }
    /// 暂停动画(全市场休市 / 用户开关)
    func setPaused(_ paused: Bool)
    /// view 被替换前停止内部动画源,避免旧 display link 的异步回调撞到新模式。
    func invalidateAnimation()
    /// 把当前状态画进 NSImage。size 跟 totalWidth × 22 一致。
    func renderImage() -> NSImage
}

/// 共用的渲染实现:cacheDisplay 强制 view 重画到 bitmap,封装成 NSImage 设 isTemplate=false。
extension MenuBarTickerView {
    func defaultRenderImage() -> NSImage {
        let size = NSSize(width: totalWidth, height: 22)
        let rect = NSRect(origin: .zero, size: size)
        // 改 frame 让 view bounds 跟 totalWidth 一致(否则 cacheDisplay 的范围不对)
        if frame.size != size {
            frame = rect
        }
        guard let rep = bitmapImageRepForCachingDisplay(in: rect) else {
            return NSImage(size: size)
        }
        cacheDisplay(in: rect, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        image.isTemplate = false
        return image
    }
}

extension TickerView: MenuBarTickerView {
    func renderImage() -> NSImage { defaultRenderImage() }
}

extension CarouselTickerView: MenuBarTickerView {
    func renderImage() -> NSImage { defaultRenderImage() }
    func setPaused(_ paused: Bool) { /* hover 状态间接控制 */ }
}

extension CompactTickerView: MenuBarTickerView {
    func renderImage() -> NSImage { defaultRenderImage() }
    func setPaused(_ paused: Bool) {}   // 无动画
    func invalidateAnimation() {}
}

extension MinimalTickerView: MenuBarTickerView {
    func renderImage() -> NSImage { defaultRenderImage() }
    func setPaused(_ paused: Bool) {}   // 无动画
    func invalidateAnimation() {}
}
