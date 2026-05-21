import Foundation
import AppKit
import UniformTypeIdentifiers

/// 备份文件载荷:包含所有持仓 / 自选 / 预警 / 设置。
struct BackupBundle: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let appVersion: String
    let holdings: [Holding]
    let watchlist: [WatchItem]
    let alerts: [Alert]
    /// 全量 appSetting 表(包含语言、主题、配色、Provider Key、Hotkey 等所有 key-value)。
    let settings: [String: String]

    static let currentSchemaVersion: Int = 1
}

struct ImportSummary {
    let holdingsCount: Int
    let watchlistCount: Int
    let alertsCount: Int
    let settingsCount: Int
}

@MainActor
final class BackupService {
    private let container: DependencyContainer

    init(container: DependencyContainer) {
        self.container = container
    }

    // MARK: 导出

    func makeBundle() throws -> BackupBundle {
        let holdings = (try? container.holdingsRepo.all()) ?? []
        let watchlist = (try? container.watchlistRepo.all()) ?? []
        let alerts = (try? container.alertsRepo.all()) ?? []
        let settings = (try? container.settingsRepo.allEntries()) ?? [:]
        let version = AppVersion.short
        return BackupBundle(
            schemaVersion: BackupBundle.currentSchemaVersion,
            exportedAt: Date(),
            appVersion: version,
            holdings: holdings,
            watchlist: watchlist,
            alerts: alerts,
            settings: settings
        )
    }

    func encode(_ bundle: BackupBundle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(bundle)
    }

    // MARK: 导入

    func decode(_ data: Data) throws -> BackupBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupBundle.self, from: data)
    }

    /// 全量替换式导入。会清空当前 holdings / watchlist / alerts / settings 再写入。
    /// 调用方需先用 UI 弹窗确认。
    @discardableResult
    func applyReplace(_ bundle: BackupBundle) throws -> ImportSummary {
        guard bundle.schemaVersion <= BackupBundle.currentSchemaVersion else {
            throw BackupError.unsupportedSchema(bundle.schemaVersion)
        }

        try container.holdingsRepo.deleteAll()
        try container.watchlistRepo.deleteAll()
        try container.alertsRepo.deleteAll()
        try container.settingsRepo.replaceAll(bundle.settings)

        for h in bundle.holdings { try container.holdingsRepo.upsert(h) }
        for w in bundle.watchlist { try container.watchlistRepo.upsert(w) }
        for a in bundle.alerts { try container.alertsRepo.upsert(a) }

        return ImportSummary(
            holdingsCount: bundle.holdings.count,
            watchlistCount: bundle.watchlist.count,
            alertsCount: bundle.alerts.count,
            settingsCount: bundle.settings.count
        )
    }

    // MARK: NSPanel 工具

    func presentExportPanel() {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmm"
        let suggested = "panbar-backup-\(fmt.string(from: Date())).json"
        let panel = NSSavePanel()
        panel.title = L("backup.exportTitle", comment: "")
        panel.nameFieldStringValue = suggested
        if let json = UTType(filenameExtension: "json") {
            panel.allowedContentTypes = [json]
        }
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let bundle = try makeBundle()
                let data = try encode(bundle)
                try data.write(to: url)
                showExportDoneAlert(bundle: bundle, fileURL: url)
            } catch {
                showError(error)
            }
        }
    }

    private func showExportDoneAlert(bundle: BackupBundle, fileURL: URL) {
        let alert = NSAlert()
        alert.messageText = L("backup.exported.title", comment: "")
        alert.informativeText = String(
            format: L("backup.exported.body", comment: ""),
            bundle.holdings.count,
            bundle.watchlist.count,
            bundle.alerts.count,
            bundle.settings.count
        ) + "\n\n" + fileURL.path
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("action.ok", comment: ""))
        alert.addButton(withTitle: L("backup.revealInFinder", comment: ""))
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        }
    }

    func presentImportPanel(onSuccess: @escaping (ImportSummary) -> Void) {
        let panel = NSOpenPanel()
        panel.title = L("backup.importTitle", comment: "")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let json = UTType(filenameExtension: "json") {
            panel.allowedContentTypes = [json]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let bundle = try decode(data)
            // 二次确认
            let confirm = NSAlert()
            confirm.messageText = L("backup.confirmReplace.title", comment: "")
            confirm.informativeText = String(
                format: L("backup.confirmReplace.body", comment: ""),
                bundle.holdings.count, bundle.watchlist.count, bundle.alerts.count, bundle.settings.count
            )
            confirm.alertStyle = .warning
            confirm.addButton(withTitle: L("backup.confirmReplace.yes", comment: ""))
            confirm.addButton(withTitle: L("action.cancel", comment: ""))
            guard confirm.runModal() == .alertFirstButtonReturn else { return }
            let summary = try applyReplace(bundle)
            onSuccess(summary)
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L("backup.error.title", comment: "")
        alert.informativeText = "\(error)"
        alert.alertStyle = .critical
        alert.addButton(withTitle: L("action.ok", comment: ""))
        alert.runModal()
    }
}

enum BackupError: Error, LocalizedError {
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let v):
            return "Unsupported backup schema version: \(v)"
        }
    }
}
