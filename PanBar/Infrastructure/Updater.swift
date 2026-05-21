import Foundation
import Sparkle
import AppKit

/// Sparkle 自动更新封装,带详细诊断日志(写到 ~/Library/Application Support/PanBar/updater.log)。
@MainActor
final class Updater: NSObject {
    static let shared = Updater()

    private(set) var controller: SPUStandardUpdaterController!

    private override init() {
        super.init()
        Self.diag("init: feedURL=\(Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") ?? "nil")")
        Self.diag("init: bundleID=\(Bundle.main.bundleIdentifier ?? "?") sandbox=\(Self.isSandboxed)")

        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        Self.diag("init: controller created, automaticChecks=\(controller.updater.automaticallyChecksForUpdates)")
        #if DEBUG
        controller.updater.automaticallyChecksForUpdates = false
        #endif
    }

    func checkForUpdates() {
        Self.diag("checkForUpdates() invoked")
        Self.diag("  canCheckForUpdates=\(controller.updater.canCheckForUpdates)")
        Self.diag("  sessionInProgress=\(controller.updater.sessionInProgress)")
        controller.checkForUpdates(nil)
    }

    var automaticChecksEnabled: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    // MARK: 诊断

    private static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    private static let logURL: URL? = {
        let fm = FileManager.default
        guard let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                      appropriateFor: nil, create: true)
            .appendingPathComponent("PanBar", isDirectory: true) else { return nil }
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("updater.log")
    }()

    nonisolated static func diag(_ msg: String) {
        let line = "[\(Date())] Updater: \(msg)\n"
        NSLog("PanBar.Updater: %@", msg)
        guard let url = logURL else { return }
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

extension Updater: SPUUpdaterDelegate {
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        Updater.diag("delegate feedURLString called → nil (use Info.plist)")
        return nil
    }

    nonisolated func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        Updater.diag("delegate mayPerform updateCheck=\(updateCheck.rawValue)")
    }

    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error = error {
            Updater.diag("delegate didFinishUpdateCycle error: \(error)")
        } else {
            Updater.diag("delegate didFinishUpdateCycle ok")
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        Updater.diag("delegate didAbortWithError: \(error)")
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Updater.diag("delegate updaterDidNotFindUpdate (up to date)")
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Updater.diag("delegate didFindValidUpdate version=\(item.versionString)")
    }
}
