import SwiftUI

struct AlertsTab: View {
    @EnvironmentObject private var vm: PopoverViewModel
    @EnvironmentObject private var refresher: QuoteRefresher

    var body: some View {
        VStack(spacing: 0) {
            PopoverReorderList(drag: vm.itemDrag, kind: .alert, items: vm.orderedAlerts, groupID: nil,
                               groups: [nil], onDrop: { source, target in
                vm.moveAlert(source, before: target.beforeID)
            }) { _ in
                VStack(spacing: 0) {
                    AlertPermissionBanner().padding(.horizontal, 14)
                    if vm.alerts.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(vm.orderedAlerts) { alert in
                                PopoverDropPlaceholder(groupID: nil, beforeID: alert.id.uuidString)
                                VStack(spacing: 0) {
                                    alertRow(alert)
                                    Divider().opacity(0.4)
                                }
                                .modifier(PopoverItemReorder(id: alert.id.uuidString, groupID: nil))
                            }
                            PopoverDropPlaceholder(groupID: nil, beforeID: nil)
                        }
                    }
                }
            } preview: { alert in
                alertRow(alert)
            }
            .frame(maxHeight: .infinity)
            Button { vm.openAlertEditor() } label: {
                Label(L("alerts.addTitle"), systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .contentShape(Rectangle())
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.accentColor)
            .buttonStyle(.plain)
            .overlay(alignment: .top) { Divider().opacity(0.4) }
        }
    }

    private func alertRow(_ alert: Alert) -> some View {
        AlertRow(alert: alert, quote: refresher.quotes[alert.symbol],
                 onEdit: { vm.openAlertEditor(alert) },
                 onToggle: { toggle(alert) },
                 onDelete: { delete(alert) })
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell.slash")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text(L("alerts.empty", comment: ""))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Button(L("alerts.addFirst", comment: "")) {
                vm.openAlertEditor()
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func toggle(_ alert: Alert) {
        var updated = alert
        updated.isActive.toggle()
        try? vm.alertsRepo.upsert(updated)
    }

    private func delete(_ alert: Alert) {
        try? vm.alertsRepo.delete(id: alert.id)
    }
}

private struct AlertRow: View {
    let alert: Alert
    let quote: Quote?
    let onEdit: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: triggeredRecently ? "bell.badge.fill" : "bell")
                        .foregroundColor(triggeredRecently ? .orange : .secondary)
                        .font(.system(size: 11))
                    Text(alert.name.isEmpty ? alert.symbol.code : alert.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(alert.isActive ? .primary : .secondary)
                        .lineLimit(1)
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help(L("action.edit"))
                    .opacity(isHovered ? 1 : 0)
                    .disabled(!isHovered)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
                    .accessibilityLabel(L("action.edit"))
                    .accessibilityHidden(!isHovered)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                Button(action: onToggle) {
                    Image(systemName: alert.isActive ? "pause.circle" : "play.circle")
                }
                .buttonStyle(.plain)
                .frame(width: 16, height: 16)
                .help(alert.isActive ? L("alert.pause", comment: "") : L("alert.resume", comment: ""))
            }
            HStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(displayCode(alert.symbol))
                        .fixedSize(horizontal: true, vertical: false)
                    Text("·")
                    Text("\(L("alerts.currentPrice")) \(quote.map { $0.currency.format($0.price) } ?? "--")")
                        .fixedSize(horizontal: true, vertical: false)
                        .help(quote.map { String(format: L("alerts.priceUpdated"), $0.timestamp.formatted(date: .abbreviated, time: .standard)) } ?? L("alerts.noQuote"))
                    Text("·")
                    Text(alert.conditionText)
                        .truncationMode(.tail)
                        .help(alert.conditionText)
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .frame(width: 16, height: 16)
            }
            if let last = alert.lastTriggeredAt {
                Text(String(format: L("alert.lastTriggered", comment: ""), relative(last)))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .opacity(alert.isActive ? 1 : 0.55)
    }

    private var triggeredRecently: Bool {
        guard let last = alert.lastTriggeredAt else { return false }
        return Date().timeIntervalSince(last) < 600   // 10 min
    }

    private func displayCode(_ s: SymbolID) -> String {
        s.market == .us ? s.code.uppercased() : s.code
    }

    private func relative(_ date: Date) -> String {
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 60 { return "\(secs)s" }
        if secs < 3600 { return "\(secs / 60)m" }
        if secs < 86400 { return "\(secs / 3600)h" }
        return "\(secs / 86400)d"
    }
}
