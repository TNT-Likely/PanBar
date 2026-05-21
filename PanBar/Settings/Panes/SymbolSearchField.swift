import SwiftUI
import Combine

@MainActor
final class SymbolSearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [SymbolSearchResult] = []
    @Published var loading: Bool = false

    private var service: SymbolSearch?
    private var task: Task<Void, Never>?

    func bind(_ service: SymbolSearch?) {
        self.service = service
    }

    func updateQuery(_ q: String) {
        query = q
        task?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            results = []
            loading = false
            return
        }
        loading = true
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)  // 300ms debounce
            guard let self = self, !Task.isCancelled else { return }
            guard let service = self.service else { self.loading = false; return }
            do {
                let hits = try await service.search(trimmed)
                await MainActor.run {
                    self.results = hits
                    self.loading = false
                }
            } catch {
                await MainActor.run {
                    self.results = []
                    self.loading = false
                }
            }
        }
    }
}

struct SymbolSearchField: View {
    @ObservedObject var vm: SymbolSearchViewModel
    var onPick: (SymbolSearchResult) -> Void

    @State private var localQuery: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(L("search.placeholder", comment: ""), text: $localQuery)
                    .textFieldStyle(.plain)
                    .onChange(of: localQuery) { value in
                        vm.updateQuery(value)
                    }
                if vm.loading {
                    ProgressView()
                        .controlSize(.small)
                } else if !localQuery.isEmpty {
                    Button {
                        localQuery = ""
                        vm.updateQuery("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if !vm.results.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.results) { result in
                            Button {
                                onPick(result)
                                localQuery = ""
                                vm.updateQuery("")
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.name)
                                            .font(.system(size: 12, weight: .medium))
                                        Text(displayCode(result.symbol))
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(marketBadge(result.symbol.market))
                                        .font(.system(size: 9, weight: .semibold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(badgeColor(result.symbol.market).opacity(0.18))
                                        .foregroundColor(badgeColor(result.symbol.market))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().opacity(0.4)
                        }
                    }
                }
                .frame(maxHeight: 180)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if !localQuery.isEmpty && !vm.loading {
                Text(L("search.noResults", comment: ""))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
            }
        }
    }

    private func displayCode(_ s: SymbolID) -> String {
        s.market == .us ? s.code.uppercased() : s.code
    }

    private func marketBadge(_ m: Market) -> String {
        switch m {
        case .a:  return "A"
        case .hk: return "HK"
        case .us: return "US"
        }
    }

    private func badgeColor(_ m: Market) -> Color {
        switch m {
        case .a:  return .red
        case .hk: return .purple
        case .us: return .blue
        }
    }
}
