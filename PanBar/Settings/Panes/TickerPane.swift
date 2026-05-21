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
                Stepper(value: $prefs.maxItems, in: 1...30) {
                    Text(String(format: L("settings.maxItems", comment: ""), prefs.maxItems))
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
