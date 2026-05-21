import SwiftUI

struct AlertsTab: View {
    @Environment(\.container) private var container
    @State private var alerts: [Alert] = []
    @State private var observationTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if alerts.isEmpty {
                    emptyState
                } else {
                    ForEach(alerts) { alert in
                        AlertRow(alert: alert,
                                 onToggle: { toggle(alert) },
                                 onDelete: { delete(alert) })
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .frame(maxHeight: 320)
        .onAppear { observe() }
        .onDisappear { observationTask?.cancel() }
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
                SettingsWindowController.shared.show()
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func observe() {
        observationTask?.cancel()
        observationTask = Task {
            await reload()
            guard let stream = container?.alertsRepo.observeAll() else { return }
            for await items in stream {
                await MainActor.run {
                    self.alerts = items
                }
            }
        }
    }

    private func reload() async {
        let items = (try? container?.alertsRepo.all()) ?? []
        await MainActor.run { self.alerts = items }
    }

    private func toggle(_ alert: Alert) {
        var updated = alert
        updated.isActive.toggle()
        try? container?.alertsRepo.upsert(updated)
    }

    private func delete(_ alert: Alert) {
        try? container?.alertsRepo.delete(id: alert.id)
    }
}

private struct AlertRow: View {
    let alert: Alert
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: triggeredRecently ? "bell.badge.fill" : "bell")
                        .foregroundColor(triggeredRecently ? .orange : .secondary)
                        .font(.system(size: 11))
                    Text(alert.name.isEmpty ? alert.symbol.code : alert.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(alert.isActive ? .primary : .secondary)
                }
                Text(conditionText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                if let last = alert.lastTriggeredAt {
                    Text(String(format: L("alert.lastTriggered", comment: ""), relative(last)))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            Spacer()
            VStack(alignment: .trailing) {
                Button(action: onToggle) {
                    Image(systemName: alert.isActive ? "pause.circle" : "play.circle")
                }
                .buttonStyle(.plain)
                .help(alert.isActive ? L("alert.pause", comment: "") : L("alert.resume", comment: ""))
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .opacity(alert.isActive ? 1 : 0.55)
    }

    private var triggeredRecently: Bool {
        guard let last = alert.lastTriggeredAt else { return false }
        return Date().timeIntervalSince(last) < 600   // 10 min
    }

    private var conditionText: String {
        let display = displayCode(alert.symbol)
        let value = alert.condition.isPercent
            ? String(format: "%+.2f%%", (alert.threshold as NSDecimalNumber).doubleValue * 100)
            : alert.symbol.market.defaultCurrency.format(alert.threshold)
        return "\(display) · \(alert.condition.displayName) \(value)"
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
