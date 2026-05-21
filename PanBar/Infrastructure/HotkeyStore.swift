import Foundation

/// 把 HotkeyBinding 序列化进 SettingsRepository。
enum HotkeyStore {
    static func load(id: GlobalHotkey.HotkeyID, from repo: SettingsRepository) -> HotkeyBinding? {
        guard let raw = repo.string(id.settingsKey),
              let data = raw.data(using: .utf8),
              let binding = try? JSONDecoder().decode(HotkeyBinding.self, from: data) else {
            return nil
        }
        return binding
    }

    /// `nil` = 清除该项(全局注销)。
    static func save(id: GlobalHotkey.HotkeyID, _ binding: HotkeyBinding?, to repo: SettingsRepository) throws {
        if let binding = binding,
           let data = try? JSONEncoder().encode(binding),
           let json = String(data: data, encoding: .utf8) {
            try repo.set(id.settingsKey, json)
        } else {
            try repo.set(id.settingsKey, "")
        }
    }
}
