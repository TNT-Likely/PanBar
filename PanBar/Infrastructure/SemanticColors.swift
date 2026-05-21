import AppKit
import SwiftUI

/// 全局涨跌配色。统一从这里取,确保:
///  - 菜单栏 ticker(深色背景)对比度足够
///  - Popover 半透明面板上文字仍清晰
///  - 三种 scheme(East / West / Mono)语义一致
enum SemanticColors {
    /// 涨色(NSColor 版,菜单栏用)
    static func upNS(scheme: TickerColorScheme) -> NSColor {
        switch scheme {
        case .east: return NSColor(red: 1.00, green: 0.42, blue: 0.42, alpha: 1) // #FF6B6B
        case .west: return NSColor(red: 0.32, green: 0.83, blue: 0.46, alpha: 1) // #52D375
        case .mono: return NSColor.labelColor
        }
    }
    /// 跌色(NSColor 版)
    static func downNS(scheme: TickerColorScheme) -> NSColor {
        switch scheme {
        case .east: return NSColor(red: 0.32, green: 0.83, blue: 0.46, alpha: 1) // #52D375
        case .west: return NSColor(red: 1.00, green: 0.42, blue: 0.42, alpha: 1)
        case .mono: return NSColor.labelColor
        }
    }

    // MARK: SwiftUI Color 版本(Popover / 设置面板用)

    /// 涨色(SwiftUI 版,定义同 NSColor 但走 sRGB)
    static func up(scheme: TickerColorScheme = .east) -> Color {
        switch scheme {
        case .east: return Color(red: 1.00, green: 0.30, blue: 0.30) // #FF4D4D
        case .west: return Color(red: 0.18, green: 0.76, blue: 0.36) // #2EC25C
        case .mono: return .primary
        }
    }
    static func down(scheme: TickerColorScheme = .east) -> Color {
        switch scheme {
        case .east: return Color(red: 0.18, green: 0.76, blue: 0.36)
        case .west: return Color(red: 1.00, green: 0.30, blue: 0.30)
        case .mono: return .primary
        }
    }

    /// 涨色填充背景(pct pill 等)
    static func upPillBg(scheme: TickerColorScheme = .east) -> Color {
        up(scheme: scheme).opacity(0.18)
    }
    static func downPillBg(scheme: TickerColorScheme = .east) -> Color {
        down(scheme: scheme).opacity(0.18)
    }

    /// 根据 Decimal 值方向取颜色。
    static func directional(_ value: Decimal, scheme: TickerColorScheme = .east) -> Color {
        if value > 0 { return up(scheme: scheme) }
        if value < 0 { return down(scheme: scheme) }
        return .primary
    }
    static func directional(_ value: Double, scheme: TickerColorScheme = .east) -> Color {
        if value > 0 { return up(scheme: scheme) }
        if value < 0 { return down(scheme: scheme) }
        return .primary
    }
}
