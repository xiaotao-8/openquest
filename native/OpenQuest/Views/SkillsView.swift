import SwiftUI
import UniformTypeIdentifiers

/// 技能：用户自己写、或从文件导入的一段指令。挂到哪个智能体身上，
/// 哪个智能体聊天时就带着它——保存后立刻生效，不是展示用的开关。
struct SkillsView: View {
    @EnvironmentObject var store: AppStore
    @State private var showingAdd = false
    @State private var showingImport = false
    @State private var showingFolderImport = false

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
                        HStack(spacing: 6) {
                            Text(s.name)
                            if !s.enabled {
                                Text("已停用").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        if !s.summary.isEmpty {
                            Text(s.summary).font(.caption).foregroundStyle(.secondary)
                        }
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
                    Button { showingFolderImport = true } label: { Label("导入技能文件夹", systemImage: "folder") }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .fileImporter(isPresented: $showingFolderImport, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            importSkillFolder(url)
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

    /// 导入技能文件夹：SKILL.md 是入口，其余 .md 文件附在后面；名字取文件夹名。
    private func importSkillFolder(_ url: URL) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return }
        let mdFiles = items.filter { $0.pathExtension.lowercased() == "md" }
        guard !mdFiles.isEmpty else { return }
        let entry = mdFiles.first { $0.lastPathComponent == "SKILL.md" } ?? mdFiles[0]
        var parts: [String] = []
        if let text = try? String(contentsOf: entry, encoding: .utf8), !text.isEmpty {
            parts.append(String(text.prefix(20000)))
        }
        for f in mdFiles where f != entry {
            if let text = try? String(contentsOf: f, encoding: .utf8), !text.isEmpty {
                parts.append("## 附加文件：\(f.lastPathComponent)\n\(String(text.prefix(8000)))")
            }
        }
        guard !parts.isEmpty else { return }
        store.addSkill(name: url.lastPathComponent, content: parts.joined(separator: "\n\n"))
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
                Section("开关") {
                    Toggle("启用这个技能", isOn: Binding(
                        get: { s.enabled },
                        set: { store.setSkillEnabled(id: s.id, $0) }
                    ))
                    Text("关掉后不拼进任何智能体的系统指令，内容留着，下次打开接着用。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("描述（一行）") {
                    TextField("一句话说明这个技能是干什么的", text: Binding(
                        get: { s.summary },
                        set: { store.setSkillSummary(id: s.id, summary: $0) }
                    ))
                }
                Section("内容（SKILL.md 正文）") {
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
