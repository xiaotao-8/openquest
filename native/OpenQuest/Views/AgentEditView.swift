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

    @State private var optimizeSentence = ""
    @State private var optimizeProposal: AgentOptimizer.Proposal?
    @State private var optimizeNote: String?

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
                Section("复制 / 导入 / 分享") {
                    AgentShareButtons(agentId: a.id)
                } footer: {
                    Text("复制是改名另存一份；导出/分享是 JSON（不含 Key）；导入从剪贴板或文件读助手 JSON 新建一个。")
                }
                Section {
                    TextField("一句话说清想改的方向，如：回答再简洁一点", text: $optimizeSentence, axis: .vertical)
                        .lineLimit(1...3)
                    Button("生成优化方案") {
                        optimizeProposal = AgentOptimizer.propose(for: a, sentence: optimizeSentence)
                        optimizeNote = nil
                    }
                    .disabled(optimizeSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let p = optimizeProposal {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(p.summary, id: \.self) { line in
                                Text("· \(line)").font(.subheadline)
                            }
                        }
                        .padding(.vertical, 2)
                        Button("应用优化") {
                            AgentOptimizer.apply(store: store, agentId: a.id, proposal: p)
                            optimizeProposal = nil
                            optimizeSentence = ""
                            optimizeNote = "已按这句话优化好，人设和参数都改了，不满意再改回来就行。"
                        }
                    }
                    if let optimizeNote {
                        Text(optimizeNote).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("一句话优化")
                } footer: {
                    Text("本地按规则改写人设和参数，不调模型、不用 Key，离线也能用；先出方案给你看，点了“应用优化”才改。")
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

/// 一句话优化助手（DDchat 补 3 的优化一半；创建已做过，见 AgentsView 的“一句话创建”）。
/// 商店原文：「效果不满意时，再用一句话优化现有助手的提示词及相关配置。」
/// 本地规则生成，离线可用，不调模型：按句子里的方向词改人设、Temperature、思考档位；
/// 先出方案给用户看，点了“应用优化”才改，不直接覆盖。
enum AgentOptimizer {
    struct Proposal {
        var soul: String
        var temperature: Double
        var effort: String
        var contextLength: Int
        var summary: [String]
    }

    static func propose(for agent: Agent, sentence: String) -> Proposal {
        let s = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        var soul = agent.soul
        var temperature = agent.temperature
        var effort = agent.effort
        var contextLength = agent.contextLength
        var summary: [String] = []

        func addSoul(_ line: String, note: String) {
            if !soul.isEmpty && !soul.hasSuffix("\n") { soul += "\n" }
            soul += line
            summary.append(note)
        }

        if s.contains("简洁") || s.contains("简短") || s.contains("精简") || s.contains("言简意赅") {
            addSoul("回答要简洁，每次不超过三句话，只说重点。",
                    "人设：回答改简洁（不超过三句话）")
            temperature = max(0, temperature - 0.2)
            summary.append("Temperature 调到 \(String(format: "%.1f", temperature))（更收敛）")
        }
        if s.contains("详细") || s.contains("深入") || s.contains("展开") || s.contains("全面") {
            addSoul("回答要详细全面，分点讲清楚来龙去脉。",
                    "人设：回答改详细全面")
            temperature = min(2, temperature + 0.1)
            summary.append("Temperature 调到 \(String(format: "%.1f", temperature))（更发散）")
        }
        if s.contains("幽默") || s.contains("风趣") || s.contains("好玩") || s.contains("有趣") {
            addSoul("说话风趣幽默，偶尔讲个冷笑话，但不跑题。",
                    "人设：说话改风趣幽默")
        }
        if s.contains("严谨") || s.contains("专业") || s.contains("准确") || s.contains("靠谱") {
            addSoul("回答要严谨准确，不确定的就说不确定，不要编造。",
                    "人设：回答改严谨准确，不编造")
            temperature = max(0, temperature - 0.1)
        }
        if s.contains("温柔") || s.contains("耐心") || s.contains("亲切") || s.contains("友好") {
            addSoul("语气温柔耐心，像朋友一样慢慢讲。",
                    "人设：语气改温柔耐心")
        }
        if s.contains("代码") || s.contains("编程") || s.contains("写程序") {
            addSoul("写代码先给思路再给完整可跑的代码，标出关键步骤。",
                    "人设：写代码先给思路再给完整代码")
            if effort.isEmpty {
                effort = "medium"
                summary.append("思考档位改成“中”（代码想深一点）")
            }
        }
        if s.contains("翻译") {
            addSoul("翻译要信达雅，保留原文语气，难译的地方加一句说明。",
                    "人设：翻译改信达雅")
        }
        if s.contains("诗") || s.contains("文艺") || s.contains("浪漫") {
            addSoul("语言要有文采和画面感。",
                    "人设：语言改有文采")
        }
        if s.contains("记住") || s.contains("上下文") || s.contains("多轮") {
            if contextLength != 0, contextLength < 40 {
                contextLength = 40
                summary.append("上下文改成最多带 40 条历史消息（记得住多轮）")
            } else {
                summary.append("上下文已是不限，不用改")
            }
        }
        if summary.isEmpty {
            // 没命中任何方向词：把这句话本身记进人设，让智能体按这句话的方向行事。
            addSoul("优化方向：\(s)", note: "已把“\(s)”记进人设，按这句话的方向调整")
        }
        return Proposal(soul: soul, temperature: temperature, effort: effort,
                        contextLength: contextLength, summary: summary)
    }

    static func apply(store: AppStore, agentId: UUID, proposal: Proposal) {
        guard let i = store.agents.firstIndex(where: { $0.id == agentId }) else { return }
        store.agents[i].soul = proposal.soul
        store.agents[i].temperature = proposal.temperature
        store.agents[i].effort = proposal.effort
        store.agents[i].contextLength = proposal.contextLength
        store.save()
    }
}
