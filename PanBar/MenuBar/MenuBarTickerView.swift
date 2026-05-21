import AppKit

/// 所有菜单栏 ticker 视图的公共接口,StatusItemController 用它跨四种模式
/// (TickerView / CarouselTickerView / CompactTickerView / MinimalTickerView)无差别操作。
protocol MenuBarTickerView: NSView {
    var totalWidth: CGFloat { get }
    var privacyHidden: Bool { get set }
    /// 仅 scroll / carousel 模式有实际动作;其它模式空实现即可。
    func setPaused(_ paused: Bool)
}

extension TickerView: MenuBarTickerView {}

extension CarouselTickerView: MenuBarTickerView {
    func setPaused(_ paused: Bool) { /* 通过 hovered 状态间接控制;暂不暴露 */ }
}

extension CompactTickerView: MenuBarTickerView {
    func setPaused(_ paused: Bool) {}   // 无动画
}

extension MinimalTickerView: MenuBarTickerView {
    func setPaused(_ paused: Bool) {}   // 无动画
}
