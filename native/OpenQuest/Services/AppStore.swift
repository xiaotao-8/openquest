import Foundation

/// 全局状态：智能体、会话。落盘到 Documents 的 JSON，杀进程不丢。
/// 初始为空——团队和群都由用户自己建，什么都不预置。
@MainActor
final class AppStore: ObservableObject {
    @Published var agents: [Agent] = []
    @Published var conversations: [Conversation] = []
    @Published var providers: [ModelProvider] = []
    @Published var server: ServerConfig = ServerConfig()
    @Published var connectors: [Connector] = builtinConnectors
    @Published var skills: [Skill] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("openquest-store.json")
    }()

    init() {
        load()
        // 仅供模拟器截图预览：启动参数带 -PreviewSeed 时临时填演示数据（不落盘，
        // 正常启动永远是空的——什么都不预置）。
        if ProcessInfo.processInfo.arguments.contains("-PreviewSeed") {
            seedPreview()
        }
    }

    private func seedPreview() {
        let a1 = Agent(name: "小策", tintHue: 0.52)
        let a2 = Agent(name: "小评", tintHue: 0.09)
        let a3 = Agent(name: "翻译官", tintHue: 0.58)
        agents = [a1, a2, a3]
        var team = Conversation(title: "我的团队", memberIds: [a1.id, a2.id])
        team.messages = [
            Message(senderId: "user", text: "帮我查下这个产品在国内卖多少钱"),
            Message(senderId: a1.id.uuidString, text: "我去服务器浏览器上查一下，马上回你。",
                    reasoning: "先确认是哪个版本，再去电商页面比价……"),
        ]
        team.workingNote = "小评 正在调用服务器浏览器…"
        var c1 = Conversation(title: "小策", memberIds: [a1.id])
        c1.messages = [Message(senderId: a1.id.uuidString, text: "数据在服务器上跑完了，结果发你")]
        var c2 = Conversation(title: "小评", memberIds: [a2.id])
        c2.messages = [Message(senderId: a2.id.uuidString, text: "这篇测评我看完了，优缺点列好了")]
        var c3 = Conversation(title: "翻译官", memberIds: [a3.id])
        c3.messages = [Message(senderId: a3.id.uuidString, text: "插件说明翻好了，是中文版")]
        conversations = [team, c1, c2, c3]
    }

    func agent(id: UUID) -> Agent? { agents.first { $0.id == id } }

    /// 直接聊：不用先建智能体。第一次点时自动备好一个「助手」，
    /// 自动挑第一个可用的供应商模型；用户随时能在聊天页右上角换模型。
    func ensureDirectChat() -> UUID {
        if let existing = conversations.first(where: { $0.title == "直接聊" }) {
            return existing.id
        }
        var a = Agent(name: "助手", tintHue: 0.62)
        let usable = providers.first(where: { providerHasKey($0) && !$0.models.isEmpty })
            ?? providers.first(where: { !$0.models.isEmpty })
        if let p = usable {
            a.providerKey = p.id.uuidString
            a.modelId = p.models[0].id
        }
        agents.append(a)
        let conv = Conversation(title: "直接聊", memberIds: [a.id])
        conversations.insert(conv, at: 0)
        save()
        return conv.id
    }

    func setAgentModel(agentId: UUID, provider: ModelProvider, modelId: String) {
        guard let i = agents.firstIndex(where: { $0.id == agentId }) else { return }
        agents[i].providerKey = provider.id.uuidString
        agents[i].modelId = modelId
        save()
    }

    func createAgent(name: String) {
        agents.append(Agent(name: name))
        save()
    }

    func deleteAgent(id: UUID) {
        agents.removeAll { $0.id == id }
        for i in conversations.indices {
            conversations[i].memberIds.removeAll { $0 == id }
        }
        save()
    }

    func createConversation(title: String, memberIds: [UUID]) {
        conversations.insert(
            Conversation(title: title, memberIds: memberIds),
            at: 0
        )
        save()
    }

    func deleteMessage(conversationId: UUID, messageId: UUID) {
        guard let i = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[i].messages.removeAll { $0.id == messageId }
        save()
    }

    func deleteConversation(id: UUID) {
        conversations.removeAll { $0.id == id }
        save()
    }

    // MARK: 供应商与模型（用户自己添加）

    func addProvider(name: String, baseURL: String, apiKey: String) {
        let p = ModelProvider(name: name, baseURL: baseURL)
        providers.append(p)
        if !apiKey.isEmpty { KeychainHelper.setKey(apiKey, ref: p.keyRef) }
        save()
    }

    /// 内置免费源：一键添加（地址和常用模型都预填好），用户只剩填 Key。
    func addPresetProvider(name: String, baseURL: String, modelIds: [String]) {
        guard !providers.contains(where: { $0.baseURL == baseURL }) else { return }
        var p = ModelProvider(name: name, baseURL: baseURL)
        p.models = modelIds.map { AIModel(id: $0) }
        providers.append(p)
        save()
    }

    /// 从供应商接口自动拉模型列表（GET /models），本地没有的补进来。
    func fetchModels(providerId: UUID) async -> String {
        guard let p = providers.first(where: { $0.id == providerId }) else { return "供应商不见了" }
        guard let key = KeychainHelper.key(ref: p.keyRef), !key.isEmpty else { return "先填 Key 才能拉" }
        let base = p.baseURL.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/models") else { return "接口地址不对" }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { return "服务返回 \(code)" }
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = root["data"] as? [[String: Any]] else { return "列表格式看不懂" }
            let ids = list.compactMap { $0["id"] as? String }
            guard let i = providers.firstIndex(where: { $0.id == providerId }) else { return "供应商不见了" }
            var added = 0
            for id in ids where !providers[i].models.contains(where: { $0.id == id }) {
                providers[i].models.append(AIModel(id: id))
                added += 1
            }
            save()
            return added > 0 ? "新拉到 \(added) 个" : "共 \(ids.count) 个，已都在"
        } catch {
            return "拉取失败"
        }
    }

    func setProviderKey(id: UUID, apiKey: String) {
        guard let p = providers.first(where: { $0.id == id }) else { return }
        if apiKey.isEmpty { KeychainHelper.deleteKey(ref: p.keyRef) }
        else { KeychainHelper.setKey(apiKey, ref: p.keyRef) }
    }

    func providerHasKey(_ p: ModelProvider) -> Bool {
        KeychainHelper.key(ref: p.keyRef) != nil
    }

    func deleteProvider(id: UUID) {
        if let p = providers.first(where: { $0.id == id }) {
            KeychainHelper.deleteKey(ref: p.keyRef)
        }
        providers.removeAll { $0.id == id }
        save()
    }

    func addModel(providerId: UUID, modelId: String, displayName: String = "") {
        guard let i = providers.firstIndex(where: { $0.id == providerId }) else { return }
        providers[i].models.append(AIModel(id: modelId, displayName: displayName))
        save()
    }

    func deleteModel(providerId: UUID, modelId: String) {
        guard let i = providers.firstIndex(where: { $0.id == providerId }) else { return }
        providers[i].models.removeAll { $0.id == modelId }
        save()
    }

    // MARK: 技能

    func addSkill(name: String, content: String) {
        skills.append(Skill(name: name, content: content))
        save()
    }

    func deleteSkill(id: UUID) {
        skills.removeAll { $0.id == id }
        save()
    }

    func setSkill(id: UUID, agentId: UUID, on: Bool) {
        guard let i = skills.firstIndex(where: { $0.id == id }) else { return }
        if on {
            if !skills[i].agentIds.contains(agentId) { skills[i].agentIds.append(agentId) }
        } else {
            skills[i].agentIds.removeAll { $0 == agentId }
        }
        save()
    }

    /// 某个智能体启用的技能拼成的上下文，聊天时进系统指令。
    func skillsContext(for agentId: UUID) -> String {
        let active = skills.filter { $0.agentIds.contains(agentId) }
        guard !active.isEmpty else { return "" }
        return active.map { "## 技能：\($0.name)\n\($0.content)" }.joined(separator: "\n\n")
    }

    func setConnectorEnabled(id: String, _ on: Bool) {
        guard let i = connectors.firstIndex(where: { $0.id == id }) else { return }
        connectors[i].enabled = on
        save()
    }

    private struct Snapshot: Codable {
        var agents: [Agent]
        var conversations: [Conversation]
        var providers: [ModelProvider] = []
        var server: ServerConfig = ServerConfig()
        var connectors: [Connector] = builtinConnectors
        var skills: [Skill] = []
    }

    func save() {
        let snap = Snapshot(agents: agents, conversations: conversations,
                            providers: providers, server: server, connectors: connectors,
                            skills: skills)
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }
        agents = snap.agents
        conversations = snap.conversations
        providers = snap.providers
        server = snap.server
        if !snap.connectors.isEmpty { connectors = snap.connectors }
        skills = snap.skills
    }
}
