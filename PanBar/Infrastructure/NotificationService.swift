import Foundation
import UserNotifications

/// 极简通知封装。第一次启动时申请权限,后续按需发送。
@MainActor
final class NotificationService: NSObject {
    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()
    private var requested = false

    private override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorizationIfNeeded() {
        guard !requested else { return }
        requested = true
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                Log.app.warning("notification auth error: \(String(describing: error), privacy: .public)")
            } else {
                Log.app.info("notification auth granted=\(granted, privacy: .public)")
            }
        }
    }

    /// 发送本地通知。`identifier` 相同会替换前一条(避免堆叠)。
    func send(identifier: String, title: String, body: String, sound: Bool = true) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error = error {
                Log.app.error("send notification failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    // 即使前台也展示横幅
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
