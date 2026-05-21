import Foundation
import UserNotifications
import AppKit

/// 极简通知封装。第一次启动时申请权限,后续按需发送。
/// 对开发期 ad-hoc 签名的 app,如果系统不接受通知,会回退到一个简单的 NSAlert,确保用户看到。
@MainActor
final class NotificationService: NSObject {
    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()
    private var requested = false
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private override init() {
        super.init()
        center.delegate = self
        refreshAuthorizationStatus()
    }

    func requestAuthorizationIfNeeded() {
        guard !requested else { return }
        requested = true
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            if let error = error {
                Log.app.warning("notification auth error: \(String(describing: error), privacy: .public)")
            } else {
                Log.app.info("notification auth granted=\(granted, privacy: .public)")
            }
            DispatchQueue.main.async {
                self?.refreshAuthorizationStatus()
            }
        }
    }

    func refreshAuthorizationStatus() {
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.authorizationStatus = settings.authorizationStatus
            }
        }
    }

    /// 发送本地通知。`identifier` 相同会替换前一条。
    /// 如果权限被拒,会落回弹窗,确保用户能看到事件。
    func send(identifier: String, title: String, body: String, sound: Bool = true) {
        diag("send id=\(identifier) title=\(title)")

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        center.add(request) { [weak self] error in
            if let error = error {
                Log.app.error("notification add failed: \(String(describing: error), privacy: .public)")
                self?.diag("add failed: \(error)")
            } else {
                self?.diag("add ok id=\(identifier)")
            }
        }

        // 同步检查权限,如果是 denied 就走弹窗 fallback
        center.getNotificationSettings { [weak self] settings in
            if settings.authorizationStatus == .denied {
                DispatchQueue.main.async {
                    self?.showFallbackAlert(title: title, body: body)
                }
            }
        }
    }

    private func showFallbackAlert(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = "PanBar · \(title)"
        alert.informativeText = body + "\n\n" + L("notification.fallbackHint", comment: "")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("action.ok", comment: ""))
        alert.addButton(withTitle: L("notification.openSettings", comment: ""))
        if alert.runModal() == .alertSecondButtonReturn {
            // 跳到系统通知设置
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// 手动测试用 — 立即发一条 "Hello" 通知。
    func sendTest() {
        send(
            identifier: "panbar.test.\(UUID().uuidString)",
            title: L("notification.test.title", comment: ""),
            body: L("notification.test.body", comment: "")
        )
    }

    private func diag(_ msg: String) {
        let line = "[\(Date())] Notification: \(msg)\n"
        let url = URL(fileURLWithPath: "/tmp/panbar-alerts.log")
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
