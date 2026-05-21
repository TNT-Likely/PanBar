import Foundation
import Sparkle
import AppKit

/// Sparkle 自动更新封装。
///
/// - Feed URL 配置在 Info.plist 的 `SUFeedURL`
/// - 公钥 ED25519 在 `SUPublicEDKey`(私钥保管在签发机器,见 docs/RELEASING.md)
/// - DEBUG 构建关闭自动检查,避免开发期反复弹窗
@MainActor
final class Updater: NSObject {
    static let shared = Updater()

    private(set) var controller: SPUStandardUpdaterController!

    private override init() {
        super.init()
        let startsAutomatic: Bool
        #if DEBUG
        startsAutomatic = false
        #else
        startsAutomatic = true
        #endif
        controller = SPUStandardUpdaterController(
            startingUpdater: startsAutomatic,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    /// 用户手动触发"检查更新"。
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// 是否启用自动检查。
    var automaticChecksEnabled: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}

extension Updater: SPUUpdaterDelegate {
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        // 优先用 Info.plist 中的,如果以后要切换 channel 可以在这里覆盖。
        return nil
    }
}
