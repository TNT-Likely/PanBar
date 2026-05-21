import Foundation
import AppKit

/// 应用层语言覆盖。
///
/// macOS 的 NSBundle 在加载时根据 `UserDefaults.AppleLanguages` 决定用哪份 .lproj。
/// 一旦 Bundle 决定了语言,运行期切换是不可靠的(必须重启)。
///
/// 这里做两件事:
///   1. 启动时(在任何 L(...) 调用之前)读取用户设置,把 AppleLanguages 写入 UserDefaults。
///   2. 用户在设置里换语言 → 持久化新值 + 弹窗提示重启。
enum LanguageManager {
    enum Choice: String, CaseIterable, Identifiable {
        case auto
        case zhHans = "zh-Hans"
        case en

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .auto:   return L("language.auto", comment: "")
            case .zhHans: return "简体中文"
            case .en:     return "English"
            }
        }
    }

    /// 启动时调用 — 必须在创建任何 UI / 调 L() 之前。
    static func applyOnLaunch(_ choice: Choice) {
        switch choice {
        case .auto:
            // 让系统决定(不动 AppleLanguages)
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .zhHans:
            UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        case .en:
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        }
    }

    /// 用户切了语言后调用 — 弹窗问是否立即重启。
    @MainActor
    static func promptRestart() {
        let alert = NSAlert()
        alert.messageText = L("language.restart.title", comment: "")
        alert.informativeText = L("language.restart.body", comment: "")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("language.restart.now", comment: ""))
        alert.addButton(withTitle: L("action.later", comment: ""))
        if alert.runModal() == .alertFirstButtonReturn {
            relaunch()
        }
    }

    @MainActor
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", path]
        do {
            try task.run()
        } catch {
            Log.app.error("relaunch failed: \(String(describing: error), privacy: .public)")
        }
        // 留一点点时间让 open 命令真正起来
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }
}
