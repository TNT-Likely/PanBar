import SwiftUI

struct AboutPane: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(colors: [.accentColor, .accentColor.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 84, height: 84)
                Text("P")
                    .font(.system(size: 50, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            }
            VStack(spacing: 4) {
                Text("PanBar").font(.system(size: 22, weight: .bold))
                Text(AppVersion.displayShort).foregroundColor(.secondary).font(.system(size: 12))
            }
            Text(L("about.tagline", comment: ""))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            Button(action: { updater.checkForUpdates() }) {
                HStack(spacing: 6) {
                    if updater.isChecking {
                        ProgressView().controlSize(.small)
                        Text(L("update.checking", comment: ""))
                    } else {
                        Text(L("menu.checkForUpdates", comment: ""))
                    }
                }
            }
            .disabled(updater.isChecking)
            .padding(.top, 6)
            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/TNT-Likely/PanBar")!)
                Link(L("about.reportIssue", comment: ""), destination: URL(string: "https://github.com/TNT-Likely/PanBar/issues")!)
            }
            .font(.system(size: 11))
            Spacer()
            Text("© 2026 PanBar contributors · MIT")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }
}
