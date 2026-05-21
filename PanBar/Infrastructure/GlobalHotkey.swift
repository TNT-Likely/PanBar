import Foundation
import Carbon
import AppKit

/// 极简全局快捷键封装。固定一组快捷键(默认 ⌘⇧P),用 Carbon RegisterEventHotKey 注册。
@MainActor
final class GlobalHotkey {
    static let shared = GlobalHotkey()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: (() -> Void)?

    private let signature: OSType = OSType(0x504e4252) // 'PNBR'

    private init() {}

    /// 注册默认 ⌘⇧P。重复调用会先注销旧的再注册。
    func registerDefault(action: @escaping () -> Void) {
        unregister()
        self.action = action

        let keyCode: UInt32 = UInt32(kVK_ANSI_P)
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData in
            guard let userData = userData else { return noErr }
            let me = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.action?() }
            return noErr
        }, 1, &eventType, opaqueSelf, &eventHandler)

        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
        action = nil
    }
}
