import SwiftUI

/// 智能体管理：设置里列出所有智能体，点进去改名字、人设（Soul）、供应商和模型。
struct AgentsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        List {
            if store.agents.isEmpty {
                Text("还没有智能体。在聊天列表右上角新建里建。")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.agents) { a in
                NavigationLink {
                    AgentEditView(agentId: a.id)
                } label: {
                    HStack(spacing: 10) {
                        AvatarDisc(text: a.initial, hue: a.tintHue, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.name)
                            Text(modelSummary(a))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { idx in
                for i in idx { store.deleteAgent(id: store.agents[i].id) }
            }
        }
        .navigationTitle("智能体")
    }

    private func modelSummary(_ a: Agent) -> String {
        if a.modelId.isEmpty { return "还没选模型" }
        let p = store.providers.first { $0.id.uuidString == a.providerKey }?.name ?? ""
        return p.isEmpty ? a.modelId : "\(p) · \(a.modelId)"
    }
}

/// 智能体编辑：名字、人设（最高优先级，完全服从）、供应商、模型、头像底色。
struct AgentEditView: View {
    @EnvironmentObject var store: AppStore
    let agentId: UUID

    private var agent: Agent? { store.agent(id: agentId) }

    var body: some View {
        Form {
            if let a = agent {
                Section("名字") {
                    TextField("名字", text: binding(\.name))
                }
                Section {
                    TextEditor(text: binding(\.soul))
                        .frame(minHeight: 120)
                } header: {
                    Text("人设（Soul）")
                } footer: {
                    Text("你写什么它完全服从，优先级最高于一切默认行为。")
                }
                Section("模型") {
                    Picker("供应商", selection: binding(\.providerKey)) {
                        Text("未选").tag("")
                        ForEach(store.providers) { p in
                            Text(p.name).tag(p.id.uuidString)
                        }
                    }
                    Picker("模型", selection: binding(\.modelId)) {
                        Text("未选").tag("")
                        ForEach(modelsOfSelectedProvider) { m in
                            Text(m.name).tag(m.id)
                        }
                    }
                    if store.providers.isEmpty {
                        Text("先去「供应商与模型」加供应商，这里才能选。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("头像底色") {
                    Slider(value: binding(\.tintHue), in: 0...1) {
                        Text("色调")
                    }
                    HStack {
                        Text("预览")
                        AvatarDisc(text: a.initial, hue: a.tintHue, size: 34)
                    }
                }
            } else {
                Text("这个智能体不存在了")
            }
        }
        .navigationTitle(agent?.name ?? "智能体")
    }

    private var modelsOfSelectedProvider: [AIModel] {
        guard let a = agent else { return [] }
        return store.providers.first { $0.id.uuidString == a.providerKey }?.models ?? []
    }

    /// 把 Agent 的某个字段绑成可写 Binding，写回 store 并落盘。
    private func binding<T>(_ keyPath: WritableKeyPath<Agent, T>) -> Binding<T> {
        Binding(
            get: { store.agent(id: agentId)?[keyPath: keyPath] ?? Agent(name: "")[keyPath: keyPath] },
            set: { newValue in
                guard let i = store.agents.firstIndex(where: { $0.id == agentId }) else { return }
                store.agents[i][keyPath: keyPath] = newValue
                store.save()
            }
        )
    }
}
