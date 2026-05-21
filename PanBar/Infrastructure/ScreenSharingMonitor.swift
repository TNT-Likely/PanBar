import Foundation
import AppKit
import CoreGraphics

/// 监测屏幕是否正在被共享 / 录制。
///
/// 检测分两层(从精确到保守):
///   1. **窗口特征匹配** — 通过 CGWindowListCopyWindowInfo 扫描屏幕上的窗口,
///      如果发现 Zoom/Teams 等 app 拥有"分享时才会有"的小窗(layer>0 的悬浮控件、
///      或名称含 "Sharing/Share/分享/共享" 关键字),立即视为正在分享。
///   2. **进程兜底** — 如果上层没命中,但已知共享类 app 正在运行(无需 active),
///      也认为大概率在分享。会有少量误报(比如 Zoom 开着但不在会议),但代价是
///      ticker 短暂隐藏,可以右键手动恢复。
///
/// 日志:所有检测决策落 /tmp/panbar-sharing.log。
@MainActor
final class ScreenSharingMonitor {
    /// 已知和屏幕共享/录制相关的 bundle id。
    private static let knownSharingApps: Set<String> = [
        "us.zoom.xos",
        "us.zoom.ZoomChat",
        "us.zoom.ZoomClips",
        "us.zoom.videomeetings",
        "us.zoom.ZoomPresence",
        "com.tencent.meeting",
        "com.tencent.xinWeMeet",
        "com.tencent.WeMeet",
        "com.alibaba.DingTalkMac",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.tinyspeck.slackmacgap",
        "com.apple.screensharing",
        "com.apple.ScreenSharing",
        "com.apple.QuickTimePlayerX",
        "com.apple.screencaptureui",
        "com.apple.replayd",
        "com.cisco.webexmeetingsapp",
        "com.cisco.webex.meetings",
        "com.google.GoogleMeet",
        "com.lark.ipm",
        "com.bytedance.lark",
        "com.feishu.feishu",
        "com.tencent.kuihua",
        "com.discord",
        "com.hnc.Discord",
        "com.electron.discord"
    ]

    /// 在共享时常见的窗口名关键字(多语言)。
    private static let sharingKeywords: [String] = [
        "Sharing", "Share Screen", "Screen Share",
        "共享", "分享", "屏幕共享", "正在共享",
        "Stop Sharing", "停止共享"
    ]

    private(set) var isSharing: Bool = false
    var onChange: ((Bool) -> Void)?

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    func start() {
        diag("monitor start")
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        timer?.tolerance = 0.5
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
        let result = detectWithReason()
        if result.isSharing != isSharing {
            isSharing = result.isSharing
            diag("→ \(result.isSharing ? "HIDE" : "SHOW") reason=\(result.reason)")
            onChange?(result.isSharing)
        }
    }

    private struct Detection {
        let isSharing: Bool
        let reason: String
    }

    private func detectWithReason() -> Detection {
        let runningKnown = knownAppsRunning()

        // 层 1:窗口扫描
        if let (owner, windowName) = sharingWindow() {
            return Detection(isSharing: true, reason: "window owner=\(owner) name=\(windowName ?? "<nil>")")
        }

        // 层 2:进程兜底 — 已知 app 在跑就视为可能分享
        if let app = runningKnown.first {
            return Detection(isSharing: true,
                             reason: "process running bid=\(app.bundleIdentifier ?? "?") active=\(app.isActive)")
        }
        return Detection(isSharing: false, reason: "no signal")
    }

    private func knownAppsRunning() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            guard let bid = $0.bundleIdentifier else { return false }
            return Self.knownSharingApps.contains(bid)
        }
    }

    /// 扫描屏幕上的窗口,看有没有匹配"分享时才会出现的"窗口。
    /// 返回 (owner, name)。
    private func sharingWindow() -> (String, String?)? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let knownOwners: Set<String> = [
            "zoom.us", "zoom", "Microsoft Teams", "Microsoft Teams (work or school)",
            "腾讯会议", "WeMeet", "钉钉", "DingTalk", "飞书", "Lark",
            "Slack", "Webex", "Discord", "Google Meet", "QuickTime Player",
            "Screenshot", "screencapture", "screencaptureui"
        ]
        for info in infos {
            guard let owner = info[kCGWindowOwnerName as String] as? String else { continue }
            // 1) owner 是已知共享 app
            guard knownOwners.contains(owner) else { continue }
            let name = info[kCGWindowName as String] as? String
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            // 2a) 窗口名包含分享关键字
            if let n = name, !n.isEmpty {
                for kw in Self.sharingKeywords where n.localizedCaseInsensitiveContains(kw) {
                    return (owner, n)
                }
            }
            // 2b) 该 app 有窗口处于浮动层(layer > 0,通常是共享 floating bar)
            //     普通应用窗口 layer 是 0
            if layer > 0 {
                return (owner, name)
            }
        }
        return nil
    }

    // MARK: 诊断

    private func diag(_ msg: String) {
        let line = "[\(Date())] Sharing: \(msg)\n"
        // 同时三路输出:NSLog(走 Console.app)+ 文件(沙盒友好的 App Support 路径)
        NSLog("PanBar.Sharing: %@", msg)
        guard let url = Self.logURL else { return }
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

    /// 写到 App Support 目录(沙盒能写)。
    private static let logURL: URL? = {
        let fm = FileManager.default
        guard let base = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("PanBar", isDirectory: true) else { return nil }
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("sharing.log")
    }()
}
