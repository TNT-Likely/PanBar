import Foundation
import Combine

struct EditorError: LocalizedError {
    let key: String
    init(_ key: String) { self.key = key }
    var errorDescription: String? { L(key) }
}

@MainActor
final class WatchEditorDraft: ObservableObject {
    let id: UUID?
    let searchVM = SymbolSearchViewModel()
    @Published var market: Market
    @Published var code: String
    @Published var name: String
    @Published var groupID: UUID?
    @Published var error: String?

    init(initial: WatchItem? = nil) {
        id = initial?.id
        market = initial?.symbol.market ?? .a
        code = initial?.symbol.code ?? ""
        name = initial?.name ?? ""
        groupID = initial?.groupID
    }

    func pick(_ result: SymbolSearchResult) {
        market = result.symbol.market
        code = result.symbol.code
        name = result.name
    }

    func save(to repo: WatchlistRepository, groups: PortfolioGroupsRepository) throws {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EditorError("error.codeRequired") }
        if let groupID, try !groups.all().contains(where: { $0.id == groupID && $0.kind == .watchlist }) {
            throw EditorError("editor.groupDeleted")
        }
        let symbol = SymbolID(code: trimmed, market: market)
        if let id {
            guard try repo.update(id: id, { item in
                item.symbol = symbol
                item.name = name.isEmpty ? trimmed : name
                item.groupID = groupID
            }) else { throw EditorError("editor.recordDeleted") }
        } else {
            try repo.upsert(WatchItem(symbol: symbol, name: name.isEmpty ? trimmed : name, groupID: groupID))
        }
    }
}

@MainActor
final class HoldingEditorDraft: ObservableObject {
    let id: UUID?
    let searchVM = SymbolSearchViewModel()
    @Published var market: Market
    @Published var code: String
    @Published var name: String
    @Published var groupID: UUID?
    @Published var quantity: String
    @Published var costPrice: String
    @Published var error: String?

    init(initial: Holding? = nil) {
        id = initial?.id
        market = initial?.symbol.market ?? .a
        code = initial?.symbol.code ?? ""
        name = initial?.name ?? ""
        groupID = initial?.groupID
        quantity = initial.map { "\($0.quantity)" } ?? ""
        costPrice = initial.map { "\($0.costPrice)" } ?? ""
    }

    func pick(_ result: SymbolSearchResult) {
        market = result.symbol.market
        code = result.symbol.code
        name = result.name
    }

    func save(to repo: HoldingsRepository, groups: PortfolioGroupsRepository) throws {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EditorError("error.codeRequired") }
        guard let qty = Decimal(string: quantity.trimmingCharacters(in: .whitespaces)), qty > 0 else {
            throw EditorError("error.qtyInvalid")
        }
        guard let cost = Decimal(string: costPrice.trimmingCharacters(in: .whitespaces)), cost > 0 else {
            throw EditorError("error.costInvalid")
        }
        if let groupID, try !groups.all().contains(where: { $0.id == groupID && $0.kind == .holdings }) {
            throw EditorError("editor.groupDeleted")
        }
        let symbol = SymbolID(code: trimmed, market: market)
        if let id {
            guard try repo.update(id: id, { holding in
                holding.symbol = symbol
                holding.name = name.isEmpty ? trimmed : name
                holding.groupID = groupID
                holding.quantity = qty
                holding.costPrice = cost
                holding.currency = symbol.market.defaultCurrency
            }) else { throw EditorError("editor.recordDeleted") }
        } else {
            try repo.upsert(Holding(symbol: symbol, name: name.isEmpty ? trimmed : name,
                                   quantity: qty, costPrice: cost, groupID: groupID))
        }
    }
}

@MainActor
final class AlertEditorDraft: ObservableObject {
    let id: UUID?
    let searchVM = SymbolSearchViewModel()
    let usesPortfolioSymbols: Bool
    @Published private(set) var selectedSymbolKey: String?
    @Published var market: Market
    @Published var code: String
    @Published var name: String
    @Published var condition: AlertCondition
    @Published var thresholdText: String
    @Published var hasSecondary: Bool
    @Published var secondaryCondition: AlertCondition
    @Published var secondaryThresholdText: String
    @Published var conditionLogic: ConditionLogic
    @Published var cooldownText: String
    @Published var hasDailyCap: Bool
    @Published var dailyCapText: String
    @Published var tradingHoursOnly: Bool
    @Published var weekdaysOnly: Bool
    @Published var showAdvanced = false
    @Published var error: String?

    init(initial: Alert? = nil, symbol: SymbolSearchResult? = nil, usesPortfolioSymbols: Bool = false) {
        id = initial?.id
        self.usesPortfolioSymbols = usesPortfolioSymbols && initial == nil && symbol == nil
        market = initial?.symbol.market ?? symbol?.symbol.market ?? .a
        code = initial?.symbol.code ?? symbol?.symbol.code ?? ""
        name = initial?.name ?? symbol?.name ?? ""
        condition = initial?.condition ?? .priceAbove
        thresholdText = initial.map { Self.text($0.threshold, condition: $0.condition) } ?? ""
        hasSecondary = initial?.secondaryCondition != nil && initial?.secondaryThreshold != nil
        secondaryCondition = initial?.secondaryCondition ?? .changePctAbove
        if let condition = initial?.secondaryCondition, let threshold = initial?.secondaryThreshold {
            secondaryThresholdText = Self.text(threshold, condition: condition)
        } else {
            secondaryThresholdText = ""
        }
        conditionLogic = initial?.conditionLogic ?? .and
        cooldownText = "\(initial?.cooldownSeconds ?? 300)"
        hasDailyCap = initial?.maxTriggersPerDay != nil
        dailyCapText = "\(initial?.maxTriggersPerDay ?? 3)"
        tradingHoursOnly = initial?.tradingHoursOnly ?? false
        weekdaysOnly = initial?.weekdaysOnly ?? false
    }

    func pick(_ result: SymbolSearchResult) {
        market = result.symbol.market
        code = result.symbol.code
        name = result.name
    }

    var hasSymbol: Bool {
        !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!usesPortfolioSymbols || selectedSymbolKey == SymbolID(code: code, market: market).storageKey)
    }

    func canSave(symbols: [SymbolSearchResult]) -> Bool {
        hasSymbol && (!usesPortfolioSymbols || symbols.contains { $0.symbol.storageKey == selectedSymbolKey })
    }

    func selectSymbol(_ result: SymbolSearchResult?) {
        selectedSymbolKey = result?.symbol.storageKey
        if let result {
            pick(result)
        } else {
            code = ""
            name = ""
        }
        error = nil
    }

    private static func text(_ value: Decimal, condition: AlertCondition) -> String {
        "\(condition.isPercent ? value * 100 : value)"
    }

    private func threshold(_ text: String, condition: AlertCondition) throws -> Decimal {
        guard let value = Decimal(string: text.trimmingCharacters(in: .whitespaces)) else {
            throw EditorError("error.thresholdInvalid")
        }
        return condition.isPercent ? value / 100 : value
    }

    func save(to repo: AlertsRepository, symbols: [SymbolSearchResult] = []) throws {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSave(symbols: symbols) else { throw EditorError("error.codeRequired") }
        let primary = try threshold(thresholdText, condition: condition)
        let secondary = hasSecondary ? try threshold(secondaryThresholdText, condition: secondaryCondition) : nil
        let symbol = SymbolID(code: trimmed, market: market)
        let cooldown = Int(cooldownText) ?? 300
        let cap = hasDailyCap ? Int(dailyCapText) : nil
        if let id {
            guard try repo.update(id: id, { alert in
                alert.symbol = symbol
                alert.name = name.isEmpty ? trimmed : name
                alert.condition = condition
                alert.threshold = primary
                alert.secondaryCondition = hasSecondary ? secondaryCondition : nil
                alert.secondaryThreshold = secondary
                alert.conditionLogic = conditionLogic
                alert.cooldownSeconds = cooldown
                alert.maxTriggersPerDay = cap
                alert.tradingHoursOnly = tradingHoursOnly
                alert.weekdaysOnly = weekdaysOnly
            }) else { throw EditorError("editor.recordDeleted") }
        } else {
            try repo.upsert(Alert(symbol: symbol, name: name.isEmpty ? trimmed : name,
                                  condition: condition, threshold: primary,
                                  secondaryCondition: hasSecondary ? secondaryCondition : nil,
                                  secondaryThreshold: secondary, conditionLogic: conditionLogic,
                                  cooldownSeconds: cooldown, maxTriggersPerDay: cap,
                                  tradingHoursOnly: tradingHoursOnly, weekdaysOnly: weekdaysOnly))
        }
    }
}
