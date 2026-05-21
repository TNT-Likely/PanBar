import SwiftUI

struct TickerPane: View {
    @Environment(\.container) private var container

    var body: some View {
        if let prefs = container?.tickerPrefs {
            TickerPaneContent(prefs: prefs)
        } else {
            Text("Loading…")
        }
    }
}

private struct TickerPaneContent: View {
    @ObservedObject var prefs: TickerPreferences

    var body: some View {
        Form {
            Section(header: Text(L("settings.ticker", comment: "")).font(.title3)) {
                Picker(L("settings.colorScheme", comment: ""), selection: $prefs.colorScheme) {
                    Text(L("scheme.east", comment: "")).tag(TickerColorScheme.east)
                    Text(L("scheme.west", comment: "")).tag(TickerColorScheme.west)
                    Text(L("scheme.mono", comment: "")).tag(TickerColorScheme.mono)
                }
                Picker(L("settings.scrollSpeed", comment: ""), selection: $prefs.scrollSpeed) {
                    ForEach(ScrollSpeed.allCases) { s in
                        Text(s.displayName).tag(s)
                    }
                }
                Toggle(L("settings.pauseOnHover", comment: ""), isOn: $prefs.pauseOnHover)
                Toggle(L("settings.pauseWhenClosed", comment: ""), isOn: $prefs.pauseWhenClosed)
                Stepper(value: $prefs.maxItems, in: 1...50) {
                    Text(String(format: L("settings.maxItems", comment: ""), prefs.maxItems))
                }
            }

            Section(header: Text(L("ticker.summarySection", comment: "")).font(.headline)) {
                Toggle(L("ticker.showTodayPnL", comment: ""), isOn: $prefs.showTodayPnL)
                Toggle(L("ticker.showTotalAssets", comment: ""), isOn: $prefs.showTotalAssets)
                Toggle(L("ticker.showAllTimePnL", comment: ""), isOn: $prefs.showAllTimePnL)
                Text(L("ticker.summaryHint", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text(L("ticker.itemsHint.title", comment: "")).font(.headline)) {
                Text(L("ticker.itemsHint.body", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
