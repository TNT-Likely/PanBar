import SwiftUI

struct OnboardingView: View {
    let container: DependencyContainer
    let onComplete: () -> Void

    @State private var step: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(width: 520, height: 400)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: WelcomeStep()
        case 1: AddStockStep(container: container)
        case 2: ColorSchemeStep(prefs: container.tickerPrefs)
        default: EmptyView()
        }
    }

    private var footer: some View {
        HStack {
            // 步骤指示器
            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            Spacer()
            if step == 0 {
                Button(L("onboarding.skip", comment: ""), action: onComplete)
            }
            if step > 0 {
                Button(L("onboarding.back", comment: "")) { step -= 1 }
            }
            Button(step == 2 ? L("onboarding.finish", comment: "") : L("onboarding.next", comment: "")) {
                if step == 2 { onComplete() } else { step += 1 }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color.primary.opacity(0.04))
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(LinearGradient(colors: [.accentColor, .accentColor.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 100, height: 100)
                Text("P")
                    .font(.system(size: 60, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            }
            Text(L("onboarding.welcome.title", comment: ""))
                .font(.system(size: 22, weight: .bold))
            Text(L("onboarding.welcome.subtitle", comment: ""))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }
}

private struct AddStockStep: View {
    let container: DependencyContainer

    @State private var market: Market = .a
    @State private var code: String = ""
    @State private var name: String = ""
    @State private var addedSomething = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("onboarding.add.title", comment: ""))
                .font(.system(size: 18, weight: .semibold))
            Text(L("onboarding.add.hint", comment: ""))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Form {
                Picker(L("col.market", comment: ""), selection: $market) {
                    ForEach(Market.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                TextField(L("col.symbol", comment: ""), text: $code)
                    .textFieldStyle(.roundedBorder)
                TextField(L("col.name", comment: ""), text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Button(L("onboarding.add.toWatchlist", comment: "")) {
                    addToWatchlist()
                }
                .disabled(code.isEmpty)
                Spacer()
                if addedSomething {
                    Label(L("onboarding.add.added", comment: ""), systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 11))
                }
            }
            Spacer()
        }
        .padding(24)
    }

    private func addToWatchlist() {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        let item = WatchItem(
            symbol: SymbolID(code: trimmed, market: market),
            name: name.isEmpty ? trimmed : name
        )
        try? container.watchlistRepo.upsert(item)
        addedSomething = true
        code = ""
        name = ""
        container.refresher.refreshNow()
    }
}

private struct ColorSchemeStep: View {
    @ObservedObject var prefs: TickerPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("onboarding.color.title", comment: ""))
                .font(.system(size: 18, weight: .semibold))
            Text(L("onboarding.color.hint", comment: ""))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            HStack(spacing: 14) {
                schemeCard(.east)
                schemeCard(.west)
                schemeCard(.mono)
            }
            .padding(.top, 8)
            Spacer()
        }
        .padding(24)
    }

    private func schemeCard(_ scheme: TickerColorScheme) -> some View {
        Button(action: { prefs.colorScheme = scheme }) {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text("+0.62%")
                        .foregroundColor(upColor(scheme))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                    Text("-1.45%")
                        .foregroundColor(downColor(scheme))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                }
                Text(label(scheme))
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(prefs.colorScheme == scheme ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(prefs.colorScheme == scheme ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: prefs.colorScheme == scheme ? 1.5 : 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func upColor(_ s: TickerColorScheme) -> Color {
        switch s {
        case .east: return .red
        case .west: return .green
        case .mono: return .primary
        }
    }

    private func downColor(_ s: TickerColorScheme) -> Color {
        switch s {
        case .east: return .green
        case .west: return .red
        case .mono: return .primary
        }
    }

    private func label(_ s: TickerColorScheme) -> String {
        switch s {
        case .east: return L("scheme.east.short", comment: "")
        case .west: return L("scheme.west.short", comment: "")
        case .mono: return L("scheme.mono.short", comment: "")
        }
    }
}
