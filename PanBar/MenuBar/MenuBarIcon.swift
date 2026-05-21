import AppKit

/// 菜单栏 ticker 视图通用的「P」图标绘制。
///
/// 四种展现模式(Scroll/Carousel/Compact/Minimal)以前各自写一遍,样式还略有差异。
/// 抽出来:圆角紫色磁贴 + 白色 heavy 粗体 P,跟 popover 头部那个 logo 视觉一致。
enum MenuBarIcon {
    /// 固定的紫色,跟 Assets.xcassets/AccentColor.colorset 一致。
    /// 不用 NSColor.controlAccentColor —— 那是动态色,菜单栏未激活时会自动降饱和度,
    /// 用户切到别的 app 看就变成怪青蓝色。
    private static let accent = NSColor(named: "AccentColor")
        ?? NSColor(srgbRed: 0.486, green: 0.361, blue: 1.0, alpha: 1)
    private static let accentDark = NSColor(srgbRed: 0.486 * 0.75, green: 0.361 * 0.75, blue: 1.0 * 0.75, alpha: 1)

    static func draw(in rect: NSRect) {
        let cornerRadius: CGFloat = max(3, rect.width * 0.22)
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

        // 用固定 RGB 渐变,跟 popover 头部那个 logo 视觉一致;不受 app 激活状态影响
        let gradient = NSGradient(colors: [accent, accentDark])
        gradient?.draw(in: path, angle: 135)

        let fontSize = rect.height * 0.62
        // design: .rounded 在 NSFont 上没有直接 API,用 systemFont + heavy 重量近似
        let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
        let attr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: "P", attributes: attr)
        let size = str.size()
        // 中线对齐时,字形 baseline 偏下一点,微调让视觉居中
        let p = NSPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2 - 0.5
        )
        str.draw(at: p)
    }
}
