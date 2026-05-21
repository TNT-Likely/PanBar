import Foundation
import AppKit

/// 简易更新检查:对比本地版本 vs GitHub Releases latest,弹窗让用户去下载页。
///
/// 之前用 Sparkle 想要自动下载+替换的丝滑体验,但代价太大:
///   - 必须关沙盒(✓ 已做)
///   - 必须配 EdDSA 密钥对 + CI 签名(没做,Sparkle 因此整个拒绝工作)
///   - appcast.xml 维护
///
/// 对小型开源 menubar app,这点收益不值得。直接比 GitHub Release tag,
/// 用户点「下载」浏览器打开 release 页,自己拖一下就完事。
@MainActor
final class Updater: NSObject {
    static let shared = Updater()

    private let owner = "TNT-Likely"
    private let repo = "PanBar"

    private override init() {
        super.init()
    }

    /// 用户点「检查更新」时调。带 UI:成功显示「有更新可用」或「已是最新」,
    /// 失败显示错误。
    func checkForUpdates() {
        checkForUpdates(silent: false)
    }

    /// app 启动后台静默检查。有更新才弹窗,没更新或失败都安静。
    func checkInBackground() {
        checkForUpdates(silent: true)
    }

    private func checkForUpdates(silent: Bool) {
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let release = try await self.fetchLatestRelease()
                await self.handleResult(release: release, silent: silent)
            } catch {
                Log.app.warning("update check failed: \(String(describing: error), privacy: .public)")
                if !silent {
                    await self.showError(error)
                }
            }
        }
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlUrl: String
        let body: String?
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
            case body
        }
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // 加 timeout,避免用户网络挂时一直转圈
        req.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "Updater", code: code, userInfo: [
                NSLocalizedDescriptionKey: "GitHub API returned \(code)"
            ])
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    @MainActor
    private func handleResult(release: GitHubRelease, silent: Bool) {
        let latest = release.tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = AppVersion.short
        if compareSemver(current, latest) >= 0 {
            // 已是最新或更新(开发版可能比 release 高),静默检查不打扰
            if !silent {
                showAlreadyLatest(current: current)
            }
            return
        }
        showUpdateAvailable(current: current, latest: latest, release: release)
    }

    @MainActor
    private func showUpdateAvailable(current: String, latest: String, release: GitHubRelease) {
        let alert = NSAlert()
        alert.messageText = String(format: L("update.available.title", comment: ""), latest)
        var body = String(format: L("update.available.body", comment: ""), current, latest)
        if let notes = release.body, !notes.isEmpty {
            // 取前几行作为预览,完整 release notes 在网页
            let lines = notes.split(separator: "\n").prefix(8).joined(separator: "\n")
            body += "\n\n" + lines
        }
        alert.informativeText = body
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("update.action.download", comment: ""))
        alert.addButton(withTitle: L("update.action.later", comment: ""))
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: release.htmlUrl) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @MainActor
    private func showAlreadyLatest(current: String) {
        let alert = NSAlert()
        alert.messageText = L("update.uptodate.title", comment: "")
        alert.informativeText = String(format: L("update.uptodate.body", comment: ""), current)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("action.ok", comment: ""))
        alert.runModal()
    }

    @MainActor
    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L("update.error.title", comment: "")
        alert.informativeText = L("update.error.body", comment: "") + "\n\n" + error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("action.ok", comment: ""))
        alert.runModal()
    }

    /// 比较 semver 风格的版本号。返回 -1 / 0 / 1。
    /// 非数字部分(如 "0.2.1-beta")按字符串排序兜底。
    private func compareSemver(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { String($0) }
        let pb = b.split(separator: ".").map { String($0) }
        let n = max(pa.count, pb.count)
        for i in 0..<n {
            let av = i < pa.count ? pa[i] : "0"
            let bv = i < pb.count ? pb[i] : "0"
            if let ai = Int(av), let bi = Int(bv) {
                if ai < bi { return -1 }
                if ai > bi { return 1 }
            } else {
                if av < bv { return -1 }
                if av > bv { return 1 }
            }
        }
        return 0
    }
}
