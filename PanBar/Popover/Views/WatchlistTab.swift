import SwiftUI

struct WatchlistTab: View {
    @EnvironmentObject var vm: PopoverViewModel
    @EnvironmentObject var refresher: QuoteRefresher
    @EnvironmentObject var appearance: AppearancePreferences
    @EnvironmentObject var prefs: TickerPreferences

    var body: some View {
        VStack(spacing: 0) {
            let groups = vm.groups.filter { $0.kind == .watchlist }
            if vm.watchlist.isEmpty && groups.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.groupIDs(for: .watchlist), id: \.self) { id in
                            groupSection(id, name: groups.first { $0.id == id }?.name ?? L("groups.ungrouped"))
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            ZStack(alignment: .trailing) {
                Button(action: openAddSheet) {
                    Label(L("watchlist.quickAdd"), systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                }
                Button {
                    SettingsWindowController.shared.show(initialAction: .manageWatchGroups)
                } label: {
                    Text(L("groups.manage"))
                        .padding(.horizontal, 8)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                }
            }
            .frame(height: 32)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.accentColor)
            .buttonStyle(.plain)
            .overlay(alignment: .top) {
                Divider().opacity(0.4)
            }
        }
    }

    @ViewBuilder
    private func groupSection(_ groupID: UUID?, name: String) -> some View {
        let items = vm.watchlist.filter { $0.groupID == groupID }
        let expanded = vm.isExpanded(groupID, kind: .watchlist)
        Button { vm.toggleGroup(groupID, kind: .watchlist) } label: {
            HStack(spacing: 8) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right").frame(width: 10)
                Text(name).fontWeight(.semibold).lineLimit(1)
                Text("(\(items.count))").foregroundColor(.secondary)
                Spacer()
            }
            .font(.system(size: 12))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(L(expanded ? "groups.expanded" : "groups.collapsed"))
        .modifier(PopoverReorder(item: .group(groupID, kind: .watchlist), title: name) { source, after in
            vm.moveGroup(source, to: groupID, kind: .watchlist, after: after)
        })
        if expanded {
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "star").font(.system(size: 24))
                    Text(L("groups.emptyItems")).font(.system(size: 12))
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 120)
            } else {
                ForEach(items) { item in
                    WatchRow(item: item, quote: refresher.quotes[item.symbol], density: appearance.density, scheme: prefs.colorScheme)
                        .modifier(PopoverReorder(item: .init(kind: .watch, id: item.id.uuidString), title: item.name) { source, after in
                            vm.moveWatchItem(source, to: item.id, after: after)
                        })
                        .contextMenu {
                            Button(L("action.openInBrowser")) { openInBrowser(item.symbol) }
                            Divider()
                            Button(L("action.delete"), role: .destructive) { vm.deleteWatchItem(item.id) }
                        }
                        .onTapGesture(count: 2) { openInBrowser(item.symbol) }
                    Divider().opacity(0.4)
                }
            }
        }
        Divider().opacity(0.4)
    }

    private func openAddSheet() {
        SettingsWindowController.shared.show(initialAction: .addWatch)
    }

    private func openInBrowser(_ symbol: SymbolID) {
        let template = vm.settingsRepo.string(BrowserURLBuilder.templateKey) ?? BrowserURLBuilder.Template.xueqiu.rawValue
        if let url = BrowserURLBuilder.url(template: template, symbol: symbol) {
            NSWorkspace.shared.open(url)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "star")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text(L("watchlist.empty", comment: ""))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Button(L("watchlist.quickAdd", comment: "")) {
                openAddSheet()
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WatchRow: View {
    let item: WatchItem
    let quote: Quote?
    let density: PopoverDensity
    let scheme: TickerColorScheme

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.symbol.market == .us ? item.symbol.code.uppercased() : item.symbol.code)
                    .font(.system(size: 13, weight: .semibold))
                Text(item.name)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let q = quote {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.symbol.market.defaultCurrency.format(q.price))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                    Text(String(format: "%+.2f%%", q.changePct * 100))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(q.change >= 0 ? SemanticColors.up(scheme: scheme) : SemanticColors.down(scheme: scheme))
                        .monospacedDigit()
                }
            } else {
                Text("--")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, density.rowHorizontalPadding)
        .padding(.vertical, max(density.rowVerticalPadding - 1, 4))
    }
}
