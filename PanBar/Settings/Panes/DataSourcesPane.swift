import SwiftUI

struct DataSourcesPane: View {
    @Environment(\.container) private var container

    var body: some View {
        if let prefs = container?.dataSourcePrefs {
            DataSourcesPaneContent(prefs: prefs)
        } else {
            Text("Loading…")
        }
    }
}

private struct DataSourcesPaneContent: View {
    @ObservedObject var prefs: DataSourcePreferences

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L("settings.dataSources", comment: ""))
                    .font(.title3)
                    .padding(.bottom, 4)

                ForEach(Market.allCases, id: \.self) { market in
                    MarketProvidersSection(prefs: prefs, market: market)
                }

                Divider().padding(.vertical, 8)

                FinnhubKeySection(prefs: prefs)
            }
            .padding(20)
        }
    }
}

private struct MarketProvidersSection: View {
    @ObservedObject var prefs: DataSourcePreferences
    let market: Market

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(market.displayName)
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(currentOrder, id: \.self) { pid in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(.secondary)
                        Toggle("", isOn: enabledBinding(pid))
                            .labelsHidden()
                        Text(pid.displayName)
                            .font(.system(size: 13))
                            .foregroundColor(enabledFor(pid) ? .primary : .secondary)
                        if pid == .finnhub && market != .us {
                            Text(L("dataSource.usOnly", comment: ""))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        Spacer()
                        Button { moveUp(pid) } label: {
                            Image(systemName: "arrow.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(isFirst(pid))
                        Button { moveDown(pid) } label: {
                            Image(systemName: "arrow.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(isLast(pid))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.04))
                    if pid != currentOrder.last { Divider().opacity(0.4) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var currentOrder: [ProviderID] {
        prefs.preferences[market]?.order ?? ProviderPreference.defaults[market]?.order ?? ProviderID.allCases
    }

    private func enabledFor(_ pid: ProviderID) -> Bool {
        prefs.preferences[market]?.enabled[pid] ?? false
    }

    private func enabledBinding(_ pid: ProviderID) -> Binding<Bool> {
        Binding(
            get: { enabledFor(pid) },
            set: { newValue in
                var pref = prefs.preferences[market] ?? ProviderPreference.defaults[market]!
                pref.enabled[pid] = newValue
                update(pref: pref)
            }
        )
    }

    private func isFirst(_ pid: ProviderID) -> Bool { currentOrder.first == pid }
    private func isLast(_ pid: ProviderID) -> Bool { currentOrder.last == pid }

    private func moveUp(_ pid: ProviderID) {
        var pref = prefs.preferences[market] ?? ProviderPreference.defaults[market]!
        guard let idx = pref.order.firstIndex(of: pid), idx > 0 else { return }
        pref.order.swapAt(idx, idx - 1)
        update(pref: pref)
    }

    private func moveDown(_ pid: ProviderID) {
        var pref = prefs.preferences[market] ?? ProviderPreference.defaults[market]!
        guard let idx = pref.order.firstIndex(of: pid), idx < pref.order.count - 1 else { return }
        pref.order.swapAt(idx, idx + 1)
        update(pref: pref)
    }

    private func update(pref: ProviderPreference) {
        var all = prefs.preferences
        all[market] = pref
        prefs.updatePreferences(all)
    }
}

private struct FinnhubKeySection: View {
    @ObservedObject var prefs: DataSourcePreferences
    @State private var revealed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Finnhub")
                .font(.headline)
            Text(L("dataSource.finnhub.help", comment: ""))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            HStack {
                if revealed {
                    TextField(L("dataSource.finnhub.keyPlaceholder", comment: ""), text: $prefs.finnhubKey)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField(L("dataSource.finnhub.keyPlaceholder", comment: ""), text: $prefs.finnhubKey)
                        .textFieldStyle(.roundedBorder)
                }
                Button(action: { revealed.toggle() }) {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                Link(L("dataSource.finnhub.signup", comment: ""), destination: URL(string: "https://finnhub.io/dashboard")!)
                    .font(.system(size: 11))
            }
        }
    }
}
