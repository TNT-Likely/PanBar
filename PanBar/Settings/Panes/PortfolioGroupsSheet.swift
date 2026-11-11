import SwiftUI

struct PortfolioGroupsSheet: View {
    @Environment(\.container) private var container
    @Environment(\.dismiss) private var dismiss
    let kind: PortfolioGroupKind
    @State private var groups: [PortfolioGroup] = []
    @State private var editing: PortfolioGroup?
    @State private var deleting: PortfolioGroup?
    @State private var showEditor = false
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("groups.manage")).font(.title3)
                Spacer()
                Button(L("groups.create")) {
                    editing = nil
                    name = ""
                    error = nil
                    showEditor = true
                }
            }
            if groups.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder").font(.system(size: 28))
                    Text(L("groups.empty")).font(.system(size: 12))
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 120)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(groups) { group in
                            HStack {
                                Text(group.name).lineLimit(1)
                                Spacer()
                                Button {
                                    editing = group
                                    name = group.name
                                    error = nil
                                    showEditor = true
                                } label: { Image(systemName: "pencil") }
                                .help(L("groups.rename"))
                                Button(role: .destructive) { deleting = group } label: { Image(systemName: "trash") }
                                .help(L("action.delete"))
                            }
                            .frame(height: 24)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // 按行数限制滚动区域，避免 ScrollView 把弹窗撑高。
                .frame(height: min(CGFloat(groups.count) * 36 - 12, 180))
            }
            Text(L("groups.deleteHint")).font(.caption).foregroundColor(.secondary)
            if let error = error { Text(error).foregroundColor(.red).font(.caption) }
            HStack {
                Spacer()
                Button(L("action.close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear(perform: reload)
        .sheet(isPresented: $showEditor) { editor }
        .alert(L("groups.deleteTitle"), isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        )) {
            Button(L("action.cancel"), role: .cancel) { deleting = nil }
            Button(L("action.delete"), role: .destructive) { deleteGroup() }
        } message: {
            Text(L("groups.deleteHint"))
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L(editing == nil ? "groups.create" : "groups.rename")).font(.title3)
            TextField(L("groups.name"), text: $name).textFieldStyle(.roundedBorder)
            if let error = error { Text(error).foregroundColor(.red).font(.caption) }
            HStack {
                Spacer()
                Button(L("action.cancel")) { showEditor = false }.keyboardShortcut(.cancelAction)
                Button(L("action.save"), action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func reload() {
        groups = ((try? container?.groupsRepo.all()) ?? []).filter { $0.kind == kind }
    }

    private func save() {
        guard let repo = container?.groupsRepo else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { error = L("groups.nameRequired"); return }
        guard !groups.contains(where: { $0.id != editing?.id && $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) else {
            error = L("groups.duplicateName")
            return
        }
        var group = editing ?? PortfolioGroup(name: trimmed, kind: kind, sortOrder: (groups.map(\.sortOrder).max() ?? -1) + 1)
        group.name = trimmed
        do {
            try repo.upsert(group)
            error = nil
            showEditor = false
            reload()
        } catch { self.error = error.localizedDescription }
    }

    private func deleteGroup() {
        guard let group = deleting, let repo = container?.groupsRepo else { return }
        do {
            try repo.delete(id: group.id)
            deleting = nil
            error = nil
            reload()
            container?.refresher.refreshNow()
        } catch { self.error = error.localizedDescription }
    }
}
