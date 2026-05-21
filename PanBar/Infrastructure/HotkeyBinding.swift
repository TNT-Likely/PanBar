import Foundation
import Carbon
import AppKit

/// 一组键码 + 修饰键的组合。可序列化、可在 UI 里展示为 "⌃⌥H"。
struct HotkeyBinding: Codable, Equatable, Sendable {
    /// 虚拟键码,与 Carbon kVK_* / NSEvent.keyCode 一致。
    var keyCode: UInt16
    /// Carbon 修饰位(cmdKey / shiftKey / optionKey / controlKey 的或)。
    var carbonModifiers: UInt32

    var isEmpty: Bool { keyCode == 0 && carbonModifiers == 0 }

    /// 必须至少一个修饰键 + 一个普通键,否则全局快捷键太容易和打字冲突。
    var isValid: Bool {
        keyCode != 0 && carbonModifiers != 0
    }

    var displayString: String {
        guard isValid else { return "—" }
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0  { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0   { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0     { s += "⌘" }
        s += HotkeyBinding.character(for: keyCode)
        return s
    }

    static func from(event: NSEvent) -> HotkeyBinding? {
        let cocoaMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if cocoaMods.contains(.command) { carbon |= UInt32(cmdKey) }
        if cocoaMods.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if cocoaMods.contains(.option)  { carbon |= UInt32(optionKey) }
        if cocoaMods.contains(.control) { carbon |= UInt32(controlKey) }
        let kc = event.keyCode
        let b = HotkeyBinding(keyCode: kc, carbonModifiers: carbon)
        return b.isValid ? b : nil
    }

    // MARK: 默认值

    static let defaultTogglePopover = HotkeyBinding(
        keyCode: UInt16(kVK_ANSI_P),
        carbonModifiers: UInt32(cmdKey | shiftKey)
    )
    static let defaultTogglePrivacy = HotkeyBinding(
        keyCode: UInt16(kVK_ANSI_M),
        carbonModifiers: UInt32(cmdKey | shiftKey)
    )

    // MARK: keyCode → 字符

    private static let nameTable: [UInt16: String] = [
        UInt16(kVK_Return): "↵",
        UInt16(kVK_Tab): "⇥",
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Delete): "⌫",
        UInt16(kVK_ForwardDelete): "⌦",
        UInt16(kVK_Escape): "⎋",
        UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_PageUp): "⇞",
        UInt16(kVK_PageDown): "⇟",
        UInt16(kVK_Home): "↖",
        UInt16(kVK_End): "↘",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12"
    ]

    static func character(for keyCode: UInt16) -> String {
        if let s = nameTable[keyCode] { return s }
        // 通过当前键盘布局把 keyCode 翻译成字符
        if let s = translateKeyCode(keyCode) { return s.uppercased() }
        return "Key\(keyCode)"
    }

    private static func translateKeyCode(_ keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let dataRef = unsafeBitCast(layoutData, to: CFData.self)
        let layoutPtr = CFDataGetBytePtr(dataRef)!
        let keyLayout = unsafeBitCast(layoutPtr, to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        var actualLength = 0
        var chars: [UniChar] = Array(repeating: 0, count: 4)
        let status = UCKeyTranslate(
            keyLayout,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &actualLength,
            &chars
        )
        guard status == noErr, actualLength > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: actualLength)
    }
}
