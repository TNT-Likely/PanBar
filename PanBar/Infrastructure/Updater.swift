import Foundation
import Sparkle
import AppKit

/// Sparkle 自动更新封装。
///
/// - Feed URL 配置在 Info.plist 的 `SUFeedURL`(指向 GitHub Pages 上的 appcast.xml)
/// - 公钥 ED25519 在 `SUPublicEDKey`(私钥保管在签发机器,见 docs/RELEASING.md)
/// - 永远启动 updater,DEBUG 仅关闭定时检查(用户手动点"检查更新"始终生效)
@MainActor
final class Updater: NSObject {
    static let shared = Updater()

    private(set) var controller: SPUStandardUpdaterController!

    private override init() {
        super.init()
        // ⚠ 必须 startingUpdater: true,否则后续 checkForUpdates() 完全 no-op。
        // DEBUG 关掉的是"自动定时检查",不是 updater 本身。
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        #if DEBUG
        controller.updater.automaticallyChecksForUpdates = false
        #endif
    }

    /// 用户手动触发"检查更新"。Sparkle 会弹出自己的进度 / 结果对话框。
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    var automaticChecksEnabled: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}

extension Updater: SPUUpdaterDelegate {
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        // 走 Info.plist SUFeedURL
        return nil
    }
}
