import Foundation

struct PopoverDragItem: Equatable {
    enum Kind: String {
        case holdingGroup, watchGroup, holding, watch, index
    }

    let kind: Kind
    let id: String

    var value: String { "panbar:\(kind.rawValue):\(id)" }

    init(kind: Kind, id: String) {
        self.kind = kind
        self.id = id
    }

    init?(value: String) {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "panbar",
              let kind = Kind(rawValue: String(parts[1])), !parts[2].isEmpty else { return nil }
        self.init(kind: kind, id: String(parts[2]))
    }

    static func group(_ id: UUID?, kind: PortfolioGroupKind) -> Self {
        Self(kind: kind == .holdings ? .holdingGroup : .watchGroup, id: id?.uuidString ?? "ungrouped")
    }
}

enum PopoverOrder {
    static func moving<ID: Equatable>(_ source: ID, to target: ID, after: Bool, in ids: [ID]) -> [ID]? {
        guard source != target,
              let sourceIndex = ids.firstIndex(of: source),
              let targetIndex = ids.firstIndex(of: target) else { return nil }
        var result = ids
        result.remove(at: sourceIndex)
        let insertion = targetIndex + (after ? 1 : 0) - (sourceIndex < targetIndex ? 1 : 0)
        result.insert(source, at: insertion)
        return result == ids ? nil : result
    }

    static func movingItem<Item: Identifiable>(
        _ source: Item.ID, to target: Item.ID, after: Bool,
        in items: [Item], groupID: KeyPath<Item, UUID?>
    ) -> [Item.ID]? {
        guard let sourceItem = items.first(where: { $0.id == source }),
              let targetItem = items.first(where: { $0.id == target }),
              sourceItem[keyPath: groupID] == targetItem[keyPath: groupID] else { return nil }
        let group = sourceItem[keyPath: groupID]
        let ids = items.filter { $0[keyPath: groupID] == group }.map(\.id)
        guard let reordered = moving(source, to: target, after: after, in: ids) else { return nil }
        var iterator = reordered.makeIterator()
        // 仓储保存的是完整序列；只替换本组占据的位置，避免打乱其他分组。
        return items.map { $0[keyPath: groupID] == group ? iterator.next()! : $0.id }
    }

    static func groupIDs(_ groups: [PortfolioGroup], kind: PortfolioGroupKind,
                         hasUngrouped: Bool, ungroupedPosition: Int?) -> [UUID?] {
        var ids = groups.filter { $0.kind == kind }.map { Optional($0.id) }
        if hasUngrouped {
            ids.insert(nil, at: min(max(ungroupedPosition ?? ids.count, 0), ids.count))
        }
        return ids
    }

    static func indexIDs(stored: [String]) -> [String] {
        let catalog = IndexCatalog.all.map(\.id)
        let known = Set(catalog)
        var seen = Set<String>()
        return (stored + catalog).filter { known.contains($0) && seen.insert($0).inserted }
    }
}
