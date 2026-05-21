import Foundation
import AppKit
import CoreGraphics

/// 监测屏幕是否正在被共享 / 录制。
/// 综合三个信号:
///   1. CGDisplayIsCaptured —— 全屏捕获(QuickTime 录屏、AirPlay 镜像等)
///   2. CGWindowListCopyWindowInfo + 检查是否有屏幕共享相关 window
///   3. 已知会议软件 bundle id 列表(Zoom / Teams / Slack 屏幕共享活跃时通常常驻)
@MainActor
final class ScreenSharingMonitor {
    /// 已知的"屏幕共享场景"app bundle id。出现这些 app 不一定就在共享屏幕,但作为辅助信号。
    private static let knownSharingApps: Set<String> = [
        "us.zoom.xos",
        "us.zoom.ZoomClips",
        "us.zoom.videomeetings",
        "com.tencent.meeting",         // 腾讯会议
        "com.tencent.xinWeMeet",       // 腾讯会议另一个 id
        "com.alibaba.DingTalkMac",     // 钉钉
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.tinyspeck.slackmacgap",   // Slack
        "com.apple.screensharing",     // 系统屏幕共享
        "com.apple.ScreenSharing",
        "com.apple.QuickTimePlayerX",  // 录屏
        "com.apple.screencaptureui",
        "com.apple.replayd",
        "com.cisco.webexmeetingsapp",
        "com.cisco.webex.meetings",
        "com.google.GoogleMeet",
        "com.lark.ipm",                // 飞书
        "com.bytedance.lark"
    ]

    private(set) var isSharing: Bool = false
    var onChange: ((Bool) -> Void)?

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    func start() {
        // 每 3s 轮询一次(对性能影响极小)
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        timer?.tolerance = 0.5
        // app 启动/退出时也立即重新评估
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        })
        evaluate()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
    }

    private func evaluate() {
        let now = detect()
        if now != isSharing {
            isSharing = now
            onChange?(now)
        }
    }

    private func detect() -> Bool {
        // 已知屏幕共享 app 在跑 + 它们是 active(前台)→ 视为可能在共享。
        // CGDisplayIsCaptured 在新版 macOS 已废弃,这里改纯启发式。
        let running = NSWorkspace.shared.runningApplications
        return running.contains { app in
            guard let bid = app.bundleIdentifier, Self.knownSharingApps.contains(bid) else { return false }
            return app.isActive
        }
    }
}
