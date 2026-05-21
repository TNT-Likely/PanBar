import AppKit
import SwiftUI

/// 全局涨跌配色。统一从这里取,确保:
///  - 菜单栏 ticker(深色背景)对比度足够
///  - Popover 半透明面板上文字在深色 / 浅色模式都清晰
///  - 三种 scheme(East / West / Mono)语义一致
enum SemanticColors {
    // MARK: 动态颜色(深色 / 浅色自适应)

    /// 红 — 深色模式上亮(#FF453A),浅色模式上深(#C0392B)。
    private static let dynamicRed = NSColor(name: "panbar.red") { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(srgbRed: 1.0,   green: 0.271, blue: 0.227, alpha: 1) // #FF453A
        }
        return NSColor(srgbRed: 0.753, green: 0.224, blue: 0.169, alpha: 1)     // #C0392B
    }

    /// 绿 — 深色模式上亮(#30D158),浅色模式上深(#15803D)。
    private static let dynamicGreen = NSColor(name: "panbar.green") { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(srgbRed: 0.188, green: 0.820, blue: 0.345, alpha: 1) // #30D158
        }
        return NSColor(srgbRed: 0.086, green: 0.502, blue: 0.239, alpha: 1)     // #15803D
    }

    // MARK: NSColor 版本(菜单栏 ticker)

    /// 菜单栏始终深底(背景由系统模糊产生 vibrancy),用偏亮的色保证对比度。
    static func upNS(scheme: TickerColorScheme) -> NSColor {
        switch scheme {
        case .east: return NSColor(srgbRed: 1.00, green: 0.271, blue: 0.227, alpha: 1) // #FF453A
        case .west: return NSColor(srgbRed: 0.188, green: 0.820, blue: 0.345, alpha: 1) // #30D158
        case .mono: return NSColor.labelColor
        }
    }
    static func downNS(scheme: TickerColorScheme) -> NSColor {
        switch scheme {
        case .east: return NSColor(srgbRed: 0.188, green: 0.820, blue: 0.345, alpha: 1)
        case .west: return NSColor(srgbRed: 1.00, green: 0.271, blue: 0.227, alpha: 1)
        case .mono: return NSColor.labelColor
        }
    }

    // MARK: SwiftUI 版本(Popover / 设置面板)— 动态适配

    static func up(scheme: TickerColorScheme = .east) -> Color {
        switch scheme {
        case .east: return Color(nsColor: dynamicRed)
        case .west: return Color(nsColor: dynamicGreen)
        case .mono: return .primary
        }
    }
    static func down(scheme: TickerColorScheme = .east) -> Color {
        switch scheme {
        case .east: return Color(nsColor: dynamicGreen)
        case .west: return Color(nsColor: dynamicRed)
        case .mono: return .primary
        }
    }

    /// 涨色填充背景(pct pill 等)— 不透明度提高到 0.25,深色背景下更醒目。
    static func upPillBg(scheme: TickerColorScheme = .east) -> Color {
        up(scheme: scheme).opacity(0.22)
    }
    static func downPillBg(scheme: TickerColorScheme = .east) -> Color {
        down(scheme: scheme).opacity(0.22)
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
