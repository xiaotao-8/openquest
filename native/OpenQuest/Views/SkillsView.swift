import SwiftUI
import UniformTypeIdentifiers

/// 技能：用户自己写、或从文件导入的一段指令。挂到哪个智能体身上，
/// 哪个智能体聊天时就带着它——保存后立刻生效，不是展示用的开关。
struct SkillsView: View {
    @EnvironmentObject var store: AppStore
    @State private var showingAdd = false
    @State private var showingImport = false

    var body: some View {
        List {
            if store.skills.isEmpty {
                Text("还没有技能。点右上角加一个：写一段指令（比如翻译规范、代码风格），挂到智能体身上就会生效；也可以导入现成的 .md 技能文件。")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.skills) { s in
                NavigationLink {
                    SkillDetailView(skillId: s.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.name)
                        Text(s.agentIds.isEmpty ? "还没挂到任何智能体" : "已挂 \(s.agentIds.count) 个智能体")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { idx in
                idx.map { store.skills[$0].id }.forEach(store.deleteSkill)
            }
        }
        .navigationTitle("技能")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingAdd = true } label: { Label("新建技能", systemImage: "plus") }
                    Button { showingImport = true } label: { Label("导入 .md 文件", systemImage: "square.and.arrow.down") }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) { AddSkillView() }
        .fileImporter(isPresented: $showingImport, allowedContentTypes: [.text, .plainText, .data]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
            store.addSkill(name: url.deletingPathExtension().lastPathComponent,
                           content: String(text.prefix(20000)))
        }
    }
}

private struct AddSkillView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var content = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("技能名字，如：翻译规范", text: $name)
                Section("技能内容（指令）") {
                    TextEditor(text: $content)
                        .frame(minHeight: 160)
                }
            }
            .navigationTitle("新建技能")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.addSkill(name: name.trimmingCharacters(in: .whitespaces),
                                       content: content)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                              || content.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

private struct SkillDetailView: View {
    @EnvironmentObject var store: AppStore
    let skillId: UUID

    private var skill: Skill? { store.skills.first { $0.id == skillId } }

    var body: some View {
        List {
            if let s = skill {
                Section("内容") {
                    Text(s.content).font(.footnote).foregroundStyle(.secondary)
                }
                Section("挂到哪些智能体") {
                    if store.agents.isEmpty {
                        Text("还没有智能体，先建一个。").foregroundStyle(.secondary)
                    }
                    ForEach(store.agents) { a in
                        Toggle(isOn: Binding(
                            get: { s.agentIds.contains(a.id) },
                            set: { store.setSkill(id: s.id, agentId: a.id, on: $0) }
                        )) {
                            HStack {
                                AvatarDisc(text: a.initial, hue: a.tintHue, size: 28)
                                Text(a.name)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(skill?.name ?? "技能")
    }
}
