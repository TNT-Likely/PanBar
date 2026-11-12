import Foundation

struct PopoverDragItem: Equatable {
    enum Kind: String {
        case holdingGroup, watchGroup, holding, watch, index, alert
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
    static func moving<ID: Equatable>(_ source: ID, before target: ID?, in ids: [ID]) -> [ID]? {
        if let target { return moving(source, to: target, after: false, in: ids) }
        guard let last = ids.last else { return nil }
        return moving(source, to: last, after: true, in: ids)
    }

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
        guard source != target, let targetItem = items.first(where: { $0.id == target }) else { return nil }
        let group = targetItem[keyPath: groupID]
        let peers = items.filter { $0[keyPath: groupID] == group && $0.id != source }.map(\.id)
        guard let index = peers.firstIndex(of: target) else { return nil }
        let before = after ? peers.dropFirst(index + 1).first : target
        return movingItem(source, toGroup: group, before: before, in: items, groupID: groupID)
    }

    static func movingItem<Item: Identifiable>(
        _ source: Item.ID, toGroup group: UUID?, before target: Item.ID?,
        in items: [Item], groupID: KeyPath<Item, UUID?>
    ) -> [Item.ID]? {
        guard let sourceItem = items.first(where: { $0.id == source }) else { return nil }
        let original = items.map(\.id)
        if target == source { return nil }
        let peers = items.filter { $0[keyPath: groupID] == group && $0.id != source }.map(\.id)
        let insertion: Int
        if let target {
            guard let index = peers.firstIndex(of: target) else { return nil }
            insertion = index
        } else {
            insertion = peers.count
        }
        var reordered = peers
        reordered.insert(source, at: insertion)
        // 同组排序只替换本组的位置；跨组移动只移走源项，不重排其他组。
        if sourceItem[keyPath: groupID] == group {
            var iterator = reordered.makeIterator()
            let ids = items.map { $0[keyPath: groupID] == group ? iterator.next()! : $0.id }
            return ids == original ? nil : ids
        }
        var ids = original.filter { $0 != source }
        if let target, let index = ids.firstIndex(of: target) {
            ids.insert(source, at: index)
        } else if let last = peers.last, let index = ids.firstIndex(of: last) {
            ids.insert(source, at: index + 1)
        } else {
            ids.append(source)
        }
        return ids
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
        orderedIDs(stored: stored, available: IndexCatalog.all.map(\.id))
    }

    static func orderedIDs(stored: [String], available: [String]) -> [String] {
        let known = Set(available)
        var seen = Set<String>()
        return (stored + available).filter { known.contains($0) && seen.insert($0).inserted }
    }
}
