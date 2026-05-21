import SwiftUI

struct GeneralPane: View {
    @Environment(\.container) private var container

    var body: some View {
        if let container = container {
            GeneralPaneContent(
                container: container,
                appearance: container.appearancePrefs,
                prefs: container.tickerPrefs
            )
        } else {
            Text(L("loading", comment: ""))
        }
    }
}

private struct GeneralPaneContent: View {
    let container: DependencyContainer
    @ObservedObject var appearance: AppearancePreferences
    @ObservedObject var prefs: TickerPreferences

    @State private var launchAtLogin: Bool = LaunchAtLoginService.isEnabled
    @State private var baseCurrency: Currency = .cny
    @State private var browserTemplate: String = BrowserURLBuilder.Template.xueqiu.rawValue
    @State private var hideOnScreenShare: Bool = true

    /// 语言:不走 @State,直接读写 storage,避免 .onAppear 触发 .onChange
    private var languageBinding: Binding<LanguageManager.Choice> {
        Binding(
            get: {
                let raw = container.settingsRepo.string(SettingsRepository.Keys.language) ?? "auto"
                return LanguageManager.Choice(rawValue: raw) ?? .auto
            },
            set: { newValue in
                try? container.settingsRepo.set(SettingsRepository.Keys.language, newValue.rawValue)
                UserDefaults.standard.set(newValue.rawValue, forKey: "panbar.\(SettingsRepository.Keys.language)")
                LanguageManager.applyOnLaunch(newValue)
                UserDefaults.standard.synchronize()
                LanguageManager.promptRestart()
            }
        )
    }

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

                Picker(L("settings.language", comment: ""), selection: languageBinding) {
                    ForEach(LanguageManager.Choice.allCases) { c in
                        Text(c.displayName).tag(c)
                    }
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

                Picker(L("settings.colorScheme", comment: ""), selection: $prefs.colorScheme) {
                    Text(L("scheme.east", comment: "")).tag(TickerColorScheme.east)
                    Text(L("scheme.west", comment: "")).tag(TickerColorScheme.west)
                    Text(L("scheme.mono", comment: "")).tag(TickerColorScheme.mono)
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

            Section(header: Text(L("settings.hotkeysSection", comment: "")).font(.headline)) {
                ForEach(GlobalHotkey.HotkeyID.allCases, id: \.self) { hotkeyID in
                    HotkeyRow(container: container, hotkeyID: hotkeyID)
                }
                Text(L("settings.hotkeys.hint", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text(L("settings.backupSection", comment: "")).font(.headline)) {
                HStack {
                    Button {
                        BackupService(container: container).presentExportPanel()
                    } label: {
                        Label(L("backup.exportAll", comment: ""), systemImage: "square.and.arrow.up")
                    }
                    Button {
                        let svc = BackupService(container: container)
                        svc.presentImportPanel { summary in
                            // 重新 register hotkey,因为 settings 全替换了
                            if let delegate = NSApp.delegate as? AppDelegate {
                                delegate.applyHotkeys(container: container)
                            }
                            container.refresher.refreshNow()
                            showImportDoneAlert(summary)
                        }
                    } label: {
                        Label(L("backup.importAll", comment: ""), systemImage: "square.and.arrow.down")
                    }
                    Spacer()
                }
                Text(L("settings.backup.hint", comment: ""))
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

@MainActor
private func showImportDoneAlert(_ summary: ImportSummary) {
    let alert = NSAlert()
    alert.messageText = L("backup.imported.title", comment: "")
    alert.informativeText = String(
        format: L("backup.imported.body", comment: ""),
        summary.holdingsCount, summary.watchlistCount, summary.alertsCount, summary.settingsCount
    )
    alert.alertStyle = .informational
    alert.addButton(withTitle: L("action.ok", comment: ""))
    alert.runModal()
}

/// 单行快捷键编辑器:左侧标签 + 中间录入器 + 右侧"重置默认"按钮。
private struct HotkeyRow: View {
    let container: DependencyContainer
    let hotkeyID: GlobalHotkey.HotkeyID
    @State private var binding: HotkeyBinding?

    var body: some View {
        HStack {
            Text(hotkeyID.displayName)
            Spacer()
            HotkeyRecorderField(binding: $binding) { newValue in
                try? HotkeyStore.save(id: hotkeyID, newValue, to: container.settingsRepo)
                applyToApp()
            }
            Button(action: resetToDefault) {
                Image(systemName: "arrow.uturn.backward.circle")
            }
            .buttonStyle(.borderless)
            .help(L("hotkey.resetDefault", comment: ""))
        }
        .onAppear {
            binding = HotkeyStore.load(id: hotkeyID, from: container.settingsRepo) ?? hotkeyID.defaultBinding
        }
    }

    private func resetToDefault() {
        binding = hotkeyID.defaultBinding
        try? HotkeyStore.save(id: hotkeyID, binding, to: container.settingsRepo)
        applyToApp()
    }

    private func applyToApp() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.applyHotkeys(container: container)
        }
    }
}
