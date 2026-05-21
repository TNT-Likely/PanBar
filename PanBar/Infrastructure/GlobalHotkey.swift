import Foundation
import Carbon
import AppKit

/// 极简全局快捷键封装。注册多个固定组合,用 Carbon RegisterEventHotKey。
///
/// 内置组合:
///   - ⌘⇧P   : 切换 Popover(togglePopover)
///   - ⌘⇧⌥P : 切换隐私模式(togglePrivacy)
@MainActor
final class GlobalHotkey {
    static let shared = GlobalHotkey()

    private var registrations: [HotkeyID: Registration] = [:]
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = OSType(0x504e4252) // 'PNBR'

    private init() {}

    enum HotkeyID: UInt32, CaseIterable, Codable {
        case togglePopover = 1
        case togglePrivacy = 2

        var displayName: String {
            switch self {
            case .togglePopover: return L("hotkey.togglePopover", comment: "")
            case .togglePrivacy: return L("hotkey.togglePrivacy", comment: "")
            }
        }

        var settingsKey: String { "hotkey_\(rawValue)" }

        var defaultBinding: HotkeyBinding {
            switch self {
            case .togglePopover: return .defaultTogglePopover
            case .togglePrivacy: return .defaultTogglePrivacy
            }
        }
    }

    private struct Registration {
        let ref: EventHotKeyRef
        let action: () -> Void
    }

    /// 一次性注册全部快捷键。
    /// `bindings` 是用户自定义的组合(可空 = 不注册该项)。
    func register(bindings: [HotkeyID: HotkeyBinding?], actions: [HotkeyID: () -> Void]) {
        unregister()
        installHandlerIfNeeded()

        for id in HotkeyID.allCases {
            guard let binding = bindings[id] ?? nil, binding.isValid else { continue }
            guard let action = actions[id] else { continue }
            let hotKeyID = EventHotKeyID(signature: signature, id: id.rawValue)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(binding.keyCode),
                binding.carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref = ref {
                registrations[id] = Registration(ref: ref, action: action)
            }
        }
    }

    func unregister() {
        for (_, reg) in registrations {
            UnregisterEventHotKey(reg.ref)
        }
        registrations.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData in
            guard let userData = userData, let eventRef = eventRef else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let me = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                if let id = HotkeyID(rawValue: hotKeyID.id) {
                    me.registrations[id]?.action()
                }
            }
            return noErr
        }, 1, &eventType, opaqueSelf, &eventHandler)
    }
}
