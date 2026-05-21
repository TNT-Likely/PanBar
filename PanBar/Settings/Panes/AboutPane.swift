import SwiftUI

struct AboutPane: View {
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
                Text("v0.1.0").foregroundColor(.secondary).font(.system(size: 12))
            }
            Text(L("about.tagline", comment: ""))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
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
