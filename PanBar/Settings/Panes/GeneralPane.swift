import SwiftUI

struct GeneralPane: View {
    @Environment(\.container) private var container

    var body: some View {
        if let container = container {
            GeneralPaneContent(
                container: container,
                appearance: container.appearancePrefs
            )
        } else {
            Text("Loading…")
        }
    }
}

private struct GeneralPaneContent: View {
    let container: DependencyContainer
    @ObservedObject var appearance: AppearancePreferences

    @State private var launchAtLogin: Bool = LaunchAtLoginService.isEnabled
    @State private var baseCurrency: Currency = .cny
    @State private var browserTemplate: String = BrowserURLBuilder.Template.xueqiu.rawValue
    @State private var hideOnScreenShare: Bool = true

    var body: some View {
        Form {
            Section(header: Text(L("settings.general", comment: "")).font(.title3)) {
                Toggle(isOn: $launchAtLogin) {
                    Text(L("settings.launchAtLogin", comment: ""))
                }
                .onChange(of: launchAtLogin) { value in
                    try? LaunchAtLoginService.setEnabled(value)
                }

                Picker(L("settings.baseCurrency", comment: ""), selection: $baseCurrency) {
                    ForEach(Currency.allCases, id: \.self) { c in
                        Text("\(c.rawValue) (\(c.symbol))").tag(c)
                    }
                }
                .onChange(of: baseCurrency) { value in
                    try? container.settingsRepo.setBaseCurrency(value)
                    container.refresher.refreshNow()
                }

                Picker(L("settings.theme", comment: ""), selection: $appearance.theme) {
                    ForEach(AppTheme.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }

                Picker(L("settings.density", comment: ""), selection: $appearance.density) {
                    ForEach(PopoverDensity.allCases) { d in
                        Text(d.displayName).tag(d)
                    }
                }

                Picker(L("settings.browser", comment: ""), selection: $browserTemplate) {
                    ForEach(BrowserURLBuilder.Template.allCases) { t in
                        Text(t.displayName).tag(t.rawValue)
                    }
                }
                .onChange(of: browserTemplate) { value in
                    try? container.settingsRepo.set(BrowserURLBuilder.templateKey, value)
                }
            }

            Section(header: Text(L("settings.privacySection", comment: "")).font(.headline)) {
                Toggle(L("settings.hideOnScreenShare", comment: ""), isOn: $hideOnScreenShare)
                    .onChange(of: hideOnScreenShare) { value in
                        try? container.settingsRepo.set(SettingsRepository.Keys.hideOnScreenShare, value ? "1" : "0")
                    }
                Text(L("settings.hideOnScreenShare.hint", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear {
            baseCurrency = container.settingsRepo.baseCurrency
            browserTemplate = container.settingsRepo.string(BrowserURLBuilder.templateKey) ?? BrowserURLBuilder.Template.xueqiu.rawValue
            hideOnScreenShare = container.settingsRepo.string(SettingsRepository.Keys.hideOnScreenShare) != "0"
        }
    }
}
