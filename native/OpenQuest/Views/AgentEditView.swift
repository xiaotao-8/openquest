import SwiftUI

/// 智能体管理：设置里列出所有智能体，点进去改名字、人设（Soul）、供应商和模型。
struct AgentsView: View {
    @EnvironmentObject var store: AppStore
    @State private var quickSentence = ""
    @State private var quickCreatedId: UUID?

    var body: some View {
        List {
            // 一句话创建（DDchat）：说清要什么样的智能体，本地按规则提名字和人设，
            // 不调模型、不用 Key，离线也能用；建好直接进编辑页接着调。
            Section {
                TextField("一句话说清，如：一个会写诗的助手", text: $quickSentence, axis: .vertical)
                    .lineLimit(1...3)
                Button("一句话创建") {
                    quickCreatedId = store.createAgentFromSentence(quickSentence)
                    quickSentence = ""
                }
                .disabled(quickSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("一句话创建")
            } footer: {
                Text("名字和人设按这句话本地生成，不联网；创建后进编辑页，模型和细节自己再调。")
            }
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
        .navigationDestination(item: $quickCreatedId) { id in
            AgentEditView(agentId: id)
        }
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
                Section("思考档位") {
                    if store.agentSupportsReasoning(a) {
                        Picker("思考档位", selection: binding(\.effort)) {
                            Text("跟模型默认").tag("")
                            Text("关").tag("off")
                            Text("低").tag("low")
                            Text("中").tag("medium")
                            Text("高").tag("high")
                        }
                        .pickerStyle(.segmented)
                        Text("档位越高想得越深、回得越慢；关就是不让模型做深度思考。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("这个模型未检测到深度思考能力，思考档位先收起来了（换个模型就有）。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("生成参数") {
                    TextField("前置词（每条用户消息前面加）", text: binding(\.prefix))
                    TextField("后置词（每条用户消息后面加）", text: binding(\.suffix))
                    HStack {
                        Text("Temperature")
                        Slider(value: binding(\.temperature), in: 0...2, step: 0.1)
                        Text(String(format: "%.1f", a.temperature))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Top-P")
                        Slider(value: binding(\.topP), in: 0...1, step: 0.05)
                        Text(String(format: "%.2f", a.topP))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Stepper("上下文：最多带 \(a.contextLength == 0 ? "不限" : "\(a.contextLength) 条")历史消息",
                            value: binding(\.contextLength), in: 0...100, step: 5)
                    Toggle("满了自动压缩（截掉最旧的并打标记）", isOn: binding(\.autoCompress))
                }
                Section("工作文件夹") {
                    TextField("文件夹，如：project-a（空=团队工作区）", text: binding(\.workDir))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Toggle("私有智能体（只在自己的文件夹里工作）", isOn: binding(\.isPrivate))
                    Text(a.isPrivate
                         ? "私有智能体必须另指一个不重叠的文件夹，不能是主智能体、不能进群聊；换文件夹后下一轮在新文件夹开新的一段对话。"
                         : "留空就是团队工作区，所有智能体共用。")
                        .font(.caption).foregroundStyle(.secondary)
                    if a.isPrivate && a.workDir.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("私有智能体要先填一个文件夹，不然还是落在团队工作区。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                Section {
                    NavigationLink {
                        MemoryView(agentId: a.id)
                    } label: {
                        Label("记忆", systemImage: "brain")
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
