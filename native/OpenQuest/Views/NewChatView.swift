import SwiftUI

/// 新建：先建智能体（名字、人设、选模型），再勾选成员建群或单聊。
/// 什么都不预置，全由用户建。
struct NewChatView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var newAgentName = ""
    @State private var selected: Set<UUID> = []
    @State private var groupTitle = ""
    @State private var showingProviders = false
    @State private var groupAdmin: UUID?
    @State private var speakMode = "everyone"
    @State private var groupNotice = ""

    var body: some View {
        NavigationStack {
            List {
                Section("新建智能体") {
                    HStack {
                        TextField("智能体名字", text: $newAgentName)
                        Button("建") {
                            let n = newAgentName.trimmingCharacters(in: .whitespaces)
                            guard !n.isEmpty else { return }
                            store.createAgent(name: n)
                            newAgentName = ""
                        }
                        .disabled(newAgentName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if store.providers.isEmpty {
                        Button {
                            showingProviders = true
                        } label: {
                            Label("先添加供应商和模型", systemImage: "cube")
                        }
                    }
                }
                Section("选成员开聊（选一个是单聊，选多个是群聊）") {
                    ForEach(store.agents) { a in
                        Button {
                            if selected.contains(a.id) { selected.remove(a.id) }
                            else { selected.insert(a.id) }
                        } label: {
                            HStack {
                                AvatarDisc(text: a.initial, hue: a.tintHue, size: 34)
                                Text(a.name).foregroundStyle(.primary)
                                Spacer()
                                if selected.contains(a.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                        }
                    }
                }
                if selected.count > 1 {
                    Section("群名") {
                        TextField("给群起个名字", text: $groupTitle)
                    }
                    Section("群设置") {
                        Picker("发言模式", selection: $speakMode) {
                            Text("全员轮流").tag("everyone")
                            Text("群主先接，再点名").tag("admin")
                        }
                        .pickerStyle(.segmented)
                        Picker("群主", selection: $groupAdmin) {
                            Text("不设群主").tag(nil as UUID?)
                            ForEach(store.agents.filter { selected.contains($0.id) }) { a in
                                Text(a.name).tag(a.id as UUID?)
                            }
                        }
                        TextField("群公告（每个成员发言前先读，可空）", text: $groupNotice)
                    }
                }
            }
            .navigationTitle("新建")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始") {
                        let members = store.agents.filter { selected.contains($0.id) }
                        let title: String
                        if members.count == 1 { title = members[0].name }
                        else {
                            let t = groupTitle.trimmingCharacters(in: .whitespaces)
                            title = t.isEmpty ? members.map(\.name).joined(separator: "、") : t
                        }
                        store.createConversation(
                            title: title, memberIds: members.map(\.id),
                            adminId: members.count > 1 ? groupAdmin : nil,
                            speakMode: members.count > 1 ? speakMode : "everyone",
                            notice: members.count > 1
                                ? groupNotice.trimmingCharacters(in: .whitespaces) : "")
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showingProviders) {
            NavigationStack { ProvidersView() }
        }
    }
}
