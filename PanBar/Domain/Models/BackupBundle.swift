import Foundation

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

    let groups: [PortfolioGroup]?

    static let currentSchemaVersion: Int = 2

    func validate() throws {
        guard schemaVersion <= BackupBundle.currentSchemaVersion else {
            throw BackupError.unsupportedSchema(schemaVersion)
        }

        // 在清空旧数据前检查组合引用，损坏的备份不能造成部分恢复。
        let groups = self.groups ?? []
        let groupIDs = Set(groups.map(\.id))
        guard groupIDs.count == groups.count,
              Set(groups.map { "\($0.kind.rawValue):\($0.name)" }).count == groups.count,
              holdings.allSatisfy({ h in h.groupID == nil || groups.contains { $0.id == h.groupID && $0.kind == .holdings } }),
              watchlist.allSatisfy({ w in w.groupID == nil || groups.contains { $0.id == w.groupID && $0.kind == .watchlist } }) else {
            throw BackupError.invalidGroups
        }
    }
}

enum BackupError: Error, LocalizedError {
    case unsupportedSchema(Int)
    case invalidGroups

    var errorDescription: String? {
        switch self {
        case .invalidGroups:
            return L("groups.invalidBackup")
        case .unsupportedSchema(let v):
            return "Unsupported backup schema version: \(v)"
        }
    }
}
