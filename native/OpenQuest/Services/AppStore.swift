import Foundation

/// 全局状态：智能体、会话。落盘到 Documents 的 JSON，杀进程不丢。
/// 初始为空——团队和群都由用户自己建，什么都不预置。
@MainActor
final class AppStore: ObservableObject {
    @Published var agents: [Agent] = []
    @Published var conversations: [Conversation] = []
    @Published var providers: [ModelProvider] = []
    @Published var modelGroups: [ModelGroup] = []
    @Published var envVars: [EnvVar] = []
    @Published var soulText: String = ""      // 用户自己写的 Soul（最高优先级指令，见 SoulView）
    @Published var globalMemory: String = ""  // 全局记忆 GLOBAL.md 式正文（用户自己维护）
    @Published var dailyLogs: [DailyMemoryLog] = []  // 每日记忆日志
    @Published var server: ServerConfig = ServerConfig()
    @Published var connectors: [Connector] = builtinConnectors
    @Published var skills: [Skill] = []
    @Published var plugins: [Plugin] = []
    @Published var dnsMode: String = DNSSettings.mode
    @Published var dnsCustom: String = DNSSettings.custom
    @Published var scheduledTasks: [ScheduledTask] = []
    @Published var customMCPs: [CustomMCP] = []
    @Published var miniApps: [MiniApp] = []
    @Published var deviceCapabilities: [DeviceCapability] = builtinDeviceCapabilities
    @Published var pluginStoreIndex: String = ""   // 插件商店当前用的索引源（""=没开）
    @Published var language: String = "zh-Hans"    // 界面语言（多语言设置）
    @Published var autoReplyTick: Int = 0           // 定时任务到点时 +1，聊天页监听后开工
    /// 锁屏审批 deep link 回来后要打开的会话（ChatListView 监听，跳过去）。
    @Published var openConversationId: UUID?
    /// 锁屏审批 deep link 回来后的作答（ChatView 监听，是自己的会话就按卡片作答）。
    @Published var deepLinkApproval: DeepLinkApproval?

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
        // 仅供模拟器真聊验收：-PreviewLiveChat 时备好一个走实测中继的供应商，
        // 不进仓库、不落盘到正式数据（中继只在验收期间开着，平时不存在）。
        if ProcessInfo.processInfo.arguments.contains("-PreviewLiveChat") {
            seedLiveChat()
        }
        // 仅模拟器验收：-PreviewProviders 时走通用手动添加路径加一个供应商
        // （名字/地址/模型都由种子直填，不走任何预设），截图落在供应商页，
        // 验“用户自己加供应商”这条真路径（用户 2026-11-20：添加由助手测）。
        if ProcessInfo.processInfo.arguments.contains("-PreviewProviders") {
            addProvider(name: "演示供应商", baseURL: "https://api.example.com/v1", apiKey: "")
            if let p = providers.first(where: { $0.baseURL == "https://api.example.com/v1" }) {
                addModel(providerId: p.id, modelId: "demo-chat")
            }
        }
    }

    private func seedPreview() {
        let a1 = Agent(name: "小策", tintHue: 0.52)
        let a2 = Agent(name: "小评", tintHue: 0.09)
        let a3 = Agent(name: "翻译官", tintHue: 0.58)
        agents = [a1, a2, a3]
        var team = Conversation(title: "我的团队", memberIds: [a1.id, a2.id])
        // 验收种子：这条回复带用量快照（与真聊回包一致：输入 2,855 · 输出 14，
        // 供应商“实测中继”/模型 agnes-2.5-flash），用量页截图单次启动就能看到非零。
        var seedReply = Message(senderId: a1.id.uuidString, text: "我去服务器浏览器上查一下，马上回你。",
                                reasoning: "先确认是哪个版本，再去电商页面比价……")
        seedReply.usagePrompt = 2855
        seedReply.usageCompletion = 14
        seedReply.usageProvider = "实测中继"
        seedReply.usageModel = "agnes-2.5-flash"
        team.messages = [
            Message(senderId: "user", text: "帮我查下这个产品在国内卖多少钱"),
            seedReply,
            // 验收种子：一条含 LaTeX 公式、一条含 Mermaid 流程图的消息，
            // 让 preview-chat.png 能同时验 LaTeX 渲染与图表卡片点开。
            Message(senderId: a2.id.uuidString,
                    text: "公式是这样的：$E=mc^2$，其中 $m$ 是质量，$c$ 是光速。"),
            Message(senderId: a1.id.uuidString,
                    text: "流程图如下：\n```mermaid\ngraph TD\n    A[开始] --> B[查价格]\n    B --> C[比价]\n    C --> D[出报告]\n```"),
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

    private func seedLiveChat() {
        var p = ModelProvider(name: "实测中继",
                              baseURL: "http://47.238.160.204:8080/liveproof/v1",
                              models: [AIModel(id: "agnes-2.5-flash")])
        providers = [p]
        let status = KeychainHelper.setKey("oq-liveproof-2026", ref: p.keyRef)
        let roundTrip = KeychainHelper.key(ref: p.keyRef) == "oq-liveproof-2026"
        print("[LiveChat] seed keychain status=\(status) roundTrip=\(roundTrip)")
        var a = Agent(name: "助手", tintHue: 0.62)
        a.providerKey = p.id.uuidString
        a.modelId = "agnes-2.5-flash"
        agents = [a]
        conversations = [Conversation(title: "直接聊", memberIds: [a.id])]
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
        agents[i].modelGroupId = ""   // 选了单个模型，组的绑定就清掉
        save()
    }

    /// 智能体绑一个模型组：模型先切到组的首选成员，组 id 留在智能体身上，
    /// 主模型失败时按组顺序兜底（见 fallbackCandidates）。
    func setAgentModelGroup(agentId: UUID, group: ModelGroup) {
        guard let i = agents.firstIndex(where: { $0.id == agentId }),
              let first = group.firstMember(providers: providers)
        else { return }
        agents[i].modelGroupId = group.id.uuidString
        agents[i].providerKey = first.provider.id.uuidString
        agents[i].modelId = first.model.id
        save()
    }

    /// 智能体当前绑的模型组（没绑返回 nil）。
    func modelGroup(for agent: Agent?) -> ModelGroup? {
        guard let agent, !agent.modelGroupId.isEmpty else { return nil }
        return modelGroups.first { $0.id.uuidString == agent.modelGroupId }
    }

    /// 兜底候选顺序：绑了组 = 组成员按顺序；没绑 = 当前单个模型。
    /// Minis AIChatViewModel+Fallback.swift 的 streamWithGroupFallback 同款语义，
    /// 实际逐个重试由 AgentRunner 接这个列表（见汇报遗留项）。
    func fallbackCandidates(for agent: Agent?) -> [(provider: ModelProvider, model: AIModel)] {
        guard let agent else { return [] }
        if let g = modelGroup(for: agent) {
            let ms = g.members(providers: providers)
            if !ms.isEmpty { return ms }
        }
        guard let p = providers.first(where: { $0.id.uuidString == agent.providerKey }),
              let m = p.models.first(where: { $0.id == agent.modelId })
        else { return [] }
        return [(p, m)]
    }

    /// 生效的思考档位：智能体自己的 > 模型配置的 > 组默认 > 跟模型默认（""）。
    func effectiveEffort(for agent: Agent?) -> String {
        guard let agent else { return "" }
        if !agent.effort.isEmpty { return agent.effort }
        if let m = modelForAgent(agent), !m.effort.isEmpty { return m.effort }
        if let g = modelGroup(for: agent), !g.defaultThinkingLevel.isEmpty {
            return g.defaultThinkingLevel
        }
        return ""
    }

    func setAgentEffort(agentId: UUID, effort: String) {
        guard let i = agents.firstIndex(where: { $0.id == agentId }) else { return }
        agents[i].effort = effort
        save()
    }

    /// 已开启的本机能力 id 集合（进 AgentRunner 的工具表）。
    var enabledDeviceCaps: Set<String> {
        Set(deviceCapabilities.filter { $0.enabled }.map { $0.id })
    }

    /// 已开启且已填 Key 的连接器 id 集合（进 AgentRunner 的工具表）：
    /// 开了但没填 Key 的不进，模型看不到也调不到。
    var enabledConnectorIds: Set<String> {
        Set(connectors.filter { $0.enabled
            && !(KeychainHelper.key(ref: "connector-\($0.id)") ?? "").isEmpty
        }.map { $0.id })
    }

    /// 已开启的自定义 MCP 服务器（进 AgentRunner 的工具表）。
    var enabledMCPs: [CustomMCP] { customMCPs.filter { $0.enabled } }

    /// 已开启的脚本类插件（进 AgentRunner 的 run_plugin_script 工具表）。
    var enabledScriptPlugins: [Plugin] {
        plugins.filter { $0.enabled && $0.type == "script" && !$0.content.isEmpty }
    }

    func setDeviceCapability(id: String, on: Bool) {
        guard let i = deviceCapabilities.firstIndex(where: { $0.id == id }) else { return }
        deviceCapabilities[i].enabled = on
        save()
    }

    func createAgent(name: String) {
        agents.append(Agent(name: name))
        save()
    }

    /// 一句话创建智能体（DDchat）：本地按规则从一句话里提名字和人设，
    /// 不调模型、不用 Key，离线也能用。返回新智能体 id，界面跳进编辑页让用户接着调。
    func createAgentFromSentence(_ sentence: String) -> UUID {
        let s = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        var core = s
        // 先去前后缀：帮我做一个/一个/一名……一个会写诗的助手 → 会写诗的助手。
        for prefix in ["帮我做一个", "帮我创建一个", "请帮我做一个", "做一个", "创建一个",
                       "一个", "一名", "一位", "帮我", "请"] {
            if core.hasPrefix(prefix) { core = String(core.dropFirst(prefix.count)); break }
        }
        for suffix in ["的助手", "的智能体", "助手", "智能体"] {
            if core.hasSuffix(suffix) { core = String(core.dropLast(suffix.count)); break }
        }
        core = core.trimmingCharacters(in: .whitespacesAndNewlines)
        if core.hasPrefix("帮我") { core = String(core.dropFirst(2)) }
        if core.hasPrefix("会") || core.hasPrefix("能") { core = String(core.dropFirst()) }
        core = core.trimmingCharacters(in: .whitespacesAndNewlines)
        // 名字：核心描述 ≤6 字直接用，太长只取前 4 字；已有助手/官/师等结尾就不再加“助手”。
        var nameCore = core
        if nameCore.count > 6 { nameCore = String(nameCore.prefix(4)) }
        let keepEndings = ["助手", "官", "师", "员", "手", "生", "家", "者"]
        let name: String
        if nameCore.isEmpty {
            name = "新智能体"
        } else if keepEndings.contains(where: { nameCore.hasSuffix($0) }) {
            name = nameCore
        } else {
            name = nameCore + "助手"
        }
        // 人设就是这句话本身（DDchat 的一句话创建），头像底色按句子稳定取一个。
        var agent = Agent(name: name, tintHue: 0.6)
        agent.soul = "你的身份和任务：\(s)\n\n始终按以上身份和要求行事。"
        let hue = Double(s.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 100 }) / 100.0
        agent.tintHue = hue
        agents.append(agent)
        save()
        return agent.id
    }

    func deleteAgent(id: UUID) {
        agents.removeAll { $0.id == id }
        for i in conversations.indices {
            conversations[i].memberIds.removeAll { $0 == id }
        }
        save()
    }

    /// 建会话：群最多 12 人（FishPocket 房间上限）；私有智能体不进群聊
    /// （只在自己的文件夹里工作），多人里混了私有的一律剔掉；公告超 2000 字截断。
    /// 界面层（新建/群设置）也拦，这里是最后一道防线。
    func createConversation(title: String, memberIds: [UUID],
                            adminId: UUID? = nil, speakMode: String = "everyone",
                            notice: String = "") {
        var ids = memberIds
        if ids.count > 1 {
            ids = ids.filter { agent(id: $0)?.isPrivate != true }
            if ids.count > 12 { ids = Array(ids.prefix(12)) }
        }
        guard !ids.isEmpty else { return }
        var conv = Conversation(title: title, memberIds: ids)
        conv.adminId = ids.contains(adminId ?? UUID()) ? adminId : nil
        conv.speakMode = speakMode
        conv.notice = String(notice.prefix(2000))
        conversations.insert(conv, at: 0)
        save()
    }

    /// 某个智能体的单聊会话（定时任务到点时用，没有就建一个）。
    func directConversation(for agentId: UUID) -> UUID {
        if let c = conversations.first(where: { $0.memberIds == [agentId] }) {
            return c.id
        }
        let title = agent(id: agentId)?.name ?? "智能体"
        createConversation(title: title, memberIds: [agentId])
        return conversations[0].id
    }

    /// 分支切换：某组重新生成的回复显示第几个版本。
    func setVariant(conversationId: UUID, groupId: UUID, index: Int) {
        guard let i = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[i].variantSelection[groupId.uuidString] = index
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

    /// 用户自己添加供应商（名字、接口地址、Key 存 Keychain）。
    /// 不预置任何供应商和模型（用户 2026-11-20 撤了免费源预设）。
    /// 类型只定接口格式：OpenAI 兼容的地址缺 /v1 时保存时自动补上。
    func addProvider(name: String, baseURL: String, apiKey: String,
                     kind: ProviderKind = .openai) {
        var p = ModelProvider(name: name, baseURL: baseURL, kind: kind)
        p.baseURL = p.apiBaseURL
        providers.append(p)
        if !apiKey.isEmpty { KeychainHelper.setKey(apiKey, ref: p.keyRef) }
        save()
    }

    /// 从供应商接口自动拉模型列表（GET /models），本地没有的补进来；
    /// 拉到的每个模型都跑一次能力自动检测（DDchat），写进模型的能力 flag。
    func fetchModels(providerId: UUID) async -> String {
        guard let p = providers.first(where: { $0.id == providerId }) else { return "供应商不见了" }
        guard let key = KeychainHelper.key(ref: p.keyRef), !key.isEmpty else { return "先填 Key 才能拉" }
        let base = p.apiBaseURL
        guard let url = URL(string: base + "/models") else { return "接口地址不对" }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        for (k, v) in p.parsedCustomHeaders {
            let lower = k.lowercased()
            guard lower != "authorization", lower != "content-type" else { continue }
            req.setValue(v, forHTTPHeaderField: k)
        }
        do {
            let (data, resp) = try await Net.session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { return "服务返回 \(code)" }
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = root["data"] as? [[String: Any]] else { return "列表格式看不懂" }
            let ids = list.compactMap { $0["id"] as? String }
            guard let i = providers.firstIndex(where: { $0.id == providerId }) else { return "供应商不见了" }
            var added = 0
            for id in ids {
                let detected = ModelCapabilities.applying(to: AIModel(id: id))
                if let j = providers[i].models.firstIndex(where: { $0.id == id }) {
                    providers[i].models[j].supportsReasoning = detected.supportsReasoning
                    providers[i].models[j].supportsVision = detected.supportsVision
                } else {
                    providers[i].models.append(detected)
                    added += 1
                }
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

    /// 自定义请求头（DDchat）：每行一个 "Key: Value"，存进供应商快照。
    func setProviderHeaders(id: UUID, headers: String) {
        guard let i = providers.firstIndex(where: { $0.id == id }) else { return }
        providers[i].customHeaders = headers
        save()
    }

    /// 某个智能体当前用的模型（没选就是 nil）。
    func modelForAgent(_ agent: Agent?) -> AIModel? {
        guard let agent else { return nil }
        return providers.first { $0.id.uuidString == agent.providerKey }?
            .models.first { $0.id == agent.modelId }
    }

    /// 能力 flag 是提示：没检测出（nil）按支持处理，控件照常显示；只有明确标 false 才收起来。
    func agentSupportsReasoning(_ agent: Agent?) -> Bool {
        modelForAgent(agent)?.supportsReasoning ?? true
    }

    func agentSupportsVision(_ agent: Agent?) -> Bool {
        modelForAgent(agent)?.supportsVision ?? true
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
        providers[i].models.append(
            ModelCapabilities.applying(to: AIModel(id: modelId, displayName: displayName)))
        save()
    }

    func deleteModel(providerId: UUID, modelId: String) {
        guard let i = providers.firstIndex(where: { $0.id == providerId }) else { return }
        providers[i].models.removeAll { $0.id == modelId }
        save()
    }

    /// 改供应商的名字/接口地址/类型（Key 不动，仍在 Keychain 里）。
    /// 地址按新类型重新归一化（OpenAI 兼容缺 /v1 就补）。
    func updateProvider(id: UUID, name: String, baseURL: String, kind: ProviderKind) {
        guard let i = providers.firstIndex(where: { $0.id == id }) else { return }
        providers[i].name = name
        providers[i].kind = kind
        providers[i].baseURL = ModelProvider(name: name, baseURL: baseURL, kind: kind).apiBaseURL
        save()
    }

    /// 改模型：显示名 + 每模型的思考档位（存进模型配置）。
    func updateModel(providerId: UUID, modelId: String, displayName: String, effort: String) {
        guard let i = providers.firstIndex(where: { $0.id == providerId }),
              let j = providers[i].models.firstIndex(where: { $0.id == modelId })
        else { return }
        providers[i].models[j].displayName = displayName
        providers[i].models[j].effort = effort
        save()
    }

    // MARK: 模型组（Minis Model Groups 兜底）

    func addModelGroup(name: String, memberRefs: [String]) {
        modelGroups.append(ModelGroup(name: name, memberRefs: memberRefs))
        save()
    }

    func updateModelGroup(_ group: ModelGroup) {
        guard let i = modelGroups.firstIndex(where: { $0.id == group.id }) else { return }
        modelGroups[i] = group
        save()
    }

    func deleteModelGroup(id: UUID) {
        modelGroups.removeAll { $0.id == id }
        // 绑了这个组的智能体解绑，回落到当前单个模型。
        for i in agents.indices where agents[i].modelGroupId == id.uuidString {
            agents[i].modelGroupId = ""
        }
        save()
    }

    // MARK: 环境变量（Minis EnvVarStore：值存 Keychain，key/note/开关进快照）

    func addEnvVar(key: String, note: String, value: String) {
        let v = EnvVar(key: key, note: note)
        envVars.append(v)
        if !value.isEmpty { KeychainHelper.setKey(value, ref: v.valueRef) }
        save()
    }

    func updateEnvVar(id: UUID, key: String, note: String) {
        guard let i = envVars.firstIndex(where: { $0.id == id }) else { return }
        envVars[i].key = key
        envVars[i].note = note
        save()
    }

    func setEnvVarValue(id: UUID, value: String) {
        guard let v = envVars.first(where: { $0.id == id }) else { return }
        if value.isEmpty { KeychainHelper.deleteKey(ref: v.valueRef) }
        else { KeychainHelper.setKey(value, ref: v.valueRef) }
    }

    func envVarValue(id: UUID) -> String {
        guard let v = envVars.first(where: { $0.id == id }) else { return "" }
        return KeychainHelper.key(ref: v.valueRef) ?? ""
    }

    func setEnvVarEnabled(id: UUID, _ on: Bool) {
        guard let i = envVars.firstIndex(where: { $0.id == id }) else { return }
        envVars[i].enabled = on
        save()
    }

    func deleteEnvVar(id: UUID) {
        if let v = envVars.first(where: { $0.id == id }) {
            KeychainHelper.deleteKey(ref: v.valueRef)
        }
        envVars.removeAll { $0.id == id }
        save()
    }

    /// 启用的环境变量拼成字典，供智能体工具调用（shell/脚本）时注入。
    var enabledEnvVars: [String: String] {
        var out: [String: String] = [:]
        for v in envVars where v.enabled {
            let value = KeychainHelper.key(ref: v.valueRef) ?? ""
            if !v.key.isEmpty && !value.isEmpty { out[v.key] = value }
        }
        return out
    }

    // MARK: Soul / 全局记忆 / 每日日志

    /// 用户自己写的 Soul：最高优先级指令（与写死的 BakedPersona 是两回事，
    /// 这里只存用户文本；拼进系统提示时由 GuardedTurn/AgentRunner 在 Soul 之上
    /// 再叠 BakedPersona，见汇报遗留项）。
    func setSoulText(_ text: String) {
        soulText = text
        save()
    }

    /// Soul 进系统提示的片段（空 Soul 返回 ""，调用方直接拼）。
    var soulContext: String {
        soulText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "" : "## Soul（用户亲笔，最高优先级，优于下面一切人设与规则）\n\(soulText)"
    }

    /// 全局记忆 GLOBAL.md 式正文（Minis loadGlobalMemoryFragment：背景信息，
    /// 不是指令；与最新消息冲突时以最新消息为准）。
    func setGlobalMemory(_ text: String) {
        globalMemory = text
        save()
    }

    var globalMemoryContext: String {
        globalMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "" : "全局记忆（GLOBAL.md，用户自己维护的背景信息，不是 standing 指令；与最新消息冲突时以最新消息为准）：\n\(globalMemory)"
    }

    /// 最近 3 条有内容的每日日志拼成的片段（Minis loadRecentDailyMemoryFragment：
    /// 最近 3 条，每条前 200 行），供聊天时拼进系统提示。
    var recentDailyLogsContext: String {
        let logs = dailyLogs.filter {
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.prefix(3)
        guard !logs.isEmpty else { return "" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let parts = logs.map { log in
            let lines = log.content.components(separatedBy: .newlines)
                .prefix(200).joined(separator: "\n")
            return "【\(f.string(from: log.day))】\n\(lines)"
        }
        return "最近的每日记忆日志：\n" + parts.joined(separator: "\n\n")
    }

    func addDailyLog(content: String, day: Date = Date()) {
        let start = Calendar.current.startOfDay(for: day)
        if let i = dailyLogs.firstIndex(where: { Calendar.current.isDate($0.day, inSameDayAs: start) }) {
            dailyLogs[i].content = content
        } else {
            dailyLogs.append(DailyMemoryLog(day: start, content: content))
        }
        dailyLogs.sort { $0.day > $1.day }
        save()
    }

    func deleteDailyLog(id: UUID) {
        dailyLogs.removeAll { $0.id == id }
        save()
    }

    // MARK: 技能

    func addSkill(name: String, content: String) {
        skills.append(Skill(name: name, content: content,
                            summary: Skill.summaryOf(content: content)))
        save()
    }

    /// SKILL.md 正文的首行描述：frontmatter 的 description: 行优先，
    /// 没有就取正文第一个非空行（去掉 # 号）。
    static func skillSummaryFor(content: String) -> String {
        Skill.summaryOf(content: content)
    }

    func setSkillEnabled(id: UUID, _ on: Bool) {
        guard let i = skills.firstIndex(where: { $0.id == id }) else { return }
        skills[i].enabled = on
        save()
    }

    func setSkillSummary(id: UUID, summary: String) {
        guard let i = skills.firstIndex(where: { $0.id == id }) else { return }
        skills[i].summary = summary
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
    /// 总开关关掉的技能不拼（Minis SkillStore 的启用状态同款语义）。
    func skillsContext(for agentId: UUID) -> String {
        let active = skills.filter { $0.enabled && $0.agentIds.contains(agentId) }
        guard !active.isEmpty else { return "" }
        return active.map { "## 技能：\($0.name)\n\($0.content)" }.joined(separator: "\n\n")
    }

    // MARK: DNS（写穿到 DNSSettings，Net.session 立刻按新设置走）

    func setDNS(mode: String, custom: String = "") {
        dnsMode = mode
        if !custom.isEmpty { dnsCustom = custom }
        DNSSettings.mode = mode
        DNSSettings.custom = dnsCustom
        save()
    }

    // MARK: 插件（DSH 风格单文件包）

    func addPlugin(_ plugin: Plugin) {
        plugins.append(plugin)
        save()
    }

    func deletePlugin(id: UUID) {
        plugins.removeAll { $0.id == id }
        save()
    }

    func setPluginEnabled(id: UUID, _ on: Bool) {
        guard let i = plugins.firstIndex(where: { $0.id == id }) else { return }
        plugins[i].enabled = on
        save()
    }

    /// 启用的指令类插件拼成的上下文，聊天时和技能一起进系统指令。
    func pluginsContext() -> String {
        let active = plugins.filter { $0.enabled && $0.type == "instruction" && !$0.content.isEmpty }
        guard !active.isEmpty else { return "" }
        return active.map { "## 插件：\($0.name)\n\($0.content)" }.joined(separator: "\n\n")
    }

    /// 插件名/说明是英文时，用用户自己配的第一个可用模型译成中文（免费、国内源）。
    /// 没配模型或翻译失败就原样返回，不拦安装。
    func translatePluginText(name: String, summary: String) async -> (String, String) {
        func looksEnglish(_ t: String) -> Bool {
            !t.isEmpty && t.allSatisfy { $0.isASCII || $0.isWhitespace } && t.contains(where: { $0.isLetter })
        }
        guard looksEnglish(name) || looksEnglish(summary),
              let p = providers.first(where: { providerHasKey($0) && !$0.models.isEmpty }),
              let key = KeychainHelper.key(ref: p.keyRef),
              let model = p.models.first?.id
        else { return (name, summary) }
        let base = p.apiBaseURL
        guard let url = URL(string: base + "/chat/completions") else { return (name, summary) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in p.parsedCustomHeaders {
            let lower = k.lowercased()
            guard lower != "authorization", lower != "content-type" else { continue }
            req.setValue(v, forHTTPHeaderField: k)
        }
        let prompt = "把下面这个软件插件的名字和说明译成简体中文，只输出两行：第一行译名，第二行译后的说明，不要任何多余文字。\n名字：\(name)\n说明：\(summary)"
        let payload: [String: Any] = ["model": model,
                                      "messages": [["role": "user", "content": prompt]],
                                      "stream": false]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        guard let (data, _) = try? await Net.session.data(for: req),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let text = msg["content"] as? String
        else { return (name, summary) }
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.count >= 1, !lines[0].isEmpty else { return (name, summary) }
        return (lines[0], lines.count > 1 ? lines[1] : summary)
    }

    // MARK: 定时任务

    func addScheduledTask(_ t: ScheduledTask) {
        scheduledTasks.append(t)
        save()
        NotificationHelper.schedule(task: t)
    }

    func deleteScheduledTask(id: UUID) {
        scheduledTasks.removeAll { $0.id == id }
        save()
        NotificationHelper.cancel(taskId: id)
    }

    func setScheduledTaskEnabled(id: UUID, _ on: Bool) {
        guard let i = scheduledTasks.firstIndex(where: { $0.id == id }) else { return }
        scheduledTasks[i].enabled = on
        save()
        if on { NotificationHelper.schedule(task: scheduledTasks[i]) }
        else { NotificationHelper.cancel(taskId: id) }
    }

    /// App 回到前台时执行到期的任务：把指令作为用户消息投进目标会话，
    /// 标记 autoReplyPending，聊天页看到就开工（人设+拒绝拦截照常走 send 那套）。
    /// 一次性的做完就关；重复的按下一次算好下次时间并重新排通知。
    func fireDueTasks() {
        let now = Date()
        var changed = false
        for i in scheduledTasks.indices {
            var t = scheduledTasks[i]
            guard t.enabled, t.nextFire <= now else { continue }
            let convId: UUID
            if t.targetKind == "room" {
                convId = t.targetId
            } else {
                convId = directConversation(for: t.targetId)
            }
            guard let ci = conversations.firstIndex(where: { $0.id == convId }) else { continue }
            conversations[ci].messages.append(
                Message(senderId: "user", text: "【定时任务：\(t.title)】\(t.prompt)"))
            conversations[ci].autoReplyPending = true
            conversations[ci].lastActivity = now
            autoReplyTick += 1
            changed = true
            if t.repeatKind == "once" {
                t.enabled = false
            } else {
                // 重复任务：下次时间从上次往后推到现在之后（App 关了几天再开，
                // 只补发一次，不把欠的次数全补成一堆消息），再重新排通知。
                var next = Self.nextFire(after: t.nextFire, task: t)
                var guardCount = 0
                while next <= now && guardCount < 10000 {
                    next = Self.nextFire(after: next, task: t)
                    guardCount += 1
                }
                t.nextFire = next
                NotificationHelper.schedule(task: t)
            }
            scheduledTasks[i] = t
        }
        if changed { save() }
    }

    /// 按重复规则算下一次触发时间（从上一次触发时间往后推，不是现在）。
    static func nextFire(after date: Date, task: ScheduledTask) -> Date {
        let cal = Calendar.current
        switch task.repeatKind {
        case "daily":
            let parts = task.time.split(separator: ":").compactMap { Int($0) }
            let h = parts.count > 0 ? parts[0] : 9, m = parts.count > 1 ? parts[1] : 0
            var next = cal.date(bySettingHour: h, minute: m, second: 0, of: date) ?? date
            if next <= date { next = cal.date(byAdding: .day, value: 1, to: next) ?? next }
            return next
        case "weekly":
            let parts = task.time.split(separator: ":").compactMap { Int($0) }
            let h = parts.count > 0 ? parts[0] : 9, m = parts.count > 1 ? parts[1] : 0
            var next = date
            for _ in 0..<8 {
                next = cal.date(byAdding: .day, value: 1, to: next) ?? next
                // Calendar 的 weekday：周日=1，周一=2；任务里周一=1。
                let wd = (cal.component(.weekday, from: next) + 5) % 7 + 1
                if task.weekdays.contains(wd) {
                    next = cal.date(bySettingHour: h, minute: m, second: 0, of: next) ?? next
                    if next > date { return next }
                }
            }
            return cal.date(byAdding: .day, value: 7, to: date) ?? date
        case "every":
            return cal.date(byAdding: .minute,
                            value: max(task.everyMinutes, 1), to: date) ?? date
        default:
            return date
        }
    }

    /// 新建任务的首次触发时间（一次=选的日期时间；每天/每周=最近一次；每 N 分钟=现在+N 分钟）。
    static func firstFire(repeatKind: String, time: String, weekdays: [Int],
                          everyMinutes: Int, at: Date) -> Date {
        let cal = Calendar.current
        switch repeatKind {
        case "once":
            return at
        case "every":
            return cal.date(byAdding: .minute, value: max(everyMinutes, 1), to: Date()) ?? Date()
        default:
            let probe = ScheduledTask(repeatKind: repeatKind, time: time,
                                      weekdays: weekdays, everyMinutes: everyMinutes)
            return nextFire(after: Date().addingTimeInterval(-60), task: probe)
        }
    }

    // MARK: 自定义 MCP / 小工具

    func addCustomMCP(name: String, url: String) {
        customMCPs.append(CustomMCP(name: name, url: url))
        save()
    }

    func deleteCustomMCP(id: UUID) {
        customMCPs.removeAll { $0.id == id }
        save()
    }

    func setCustomMCPEnabled(id: UUID, _ on: Bool) {
        guard let i = customMCPs.firstIndex(where: { $0.id == id }) else { return }
        customMCPs[i].enabled = on
        save()
    }

    func addMiniApp(name: String, files: [String: String]) {
        miniApps.append(MiniApp(name: name, files: files))
        save()
    }

    func deleteMiniApp(id: UUID) {
        miniApps.removeAll { $0.id == id }
        save()
    }

    /// 改小工具里一个文件的内容（MiniApps 文件编辑用；不存在就新建）。
    func updateMiniAppFile(id: UUID, file: String, content: String) {
        guard let i = miniApps.firstIndex(where: { $0.id == id }) else { return }
        miniApps[i].files[file] = content
        save()
    }

    /// 小工具里删一个文件（index.html 和 app.json 删了会跑不起来，界面层会拦）。
    func deleteMiniAppFile(id: UUID, file: String) {
        guard let i = miniApps.firstIndex(where: { $0.id == id }) else { return }
        miniApps[i].files.removeValue(forKey: file)
        save()
    }

    /// 全部会话的用量合计（每条回复尾部的用量胶囊加起来）。
    var totalUsage: (prompt: Int, completion: Int) {
        var p = 0, c = 0
        for conv in conversations {
            for m in conv.messages {
                p += m.usagePrompt ?? 0
                c += m.usageCompletion ?? 0
            }
        }
        return (p, c)
    }

    /// 每个智能体的用量（按回复的发送者分）。
    func usageByAgent() -> [(name: String, prompt: Int, completion: Int)] {
        var map: [String: (Int, Int)] = [:]
        for conv in conversations {
            for m in conv.messages {
                guard let p = m.usagePrompt, let c = m.usageCompletion else { continue }
                let name = agent(id: UUID(uuidString: m.senderId) ?? UUID())?.name ?? "其他"
                let cur = map[name] ?? (0, 0)
                map[name] = (cur.0 + p, cur.1 + c)
            }
        }
        return map.map { (name: $0.key, prompt: $0.value.0, completion: $0.value.1) }
            .sorted { ($0.prompt + $0.completion) > ($1.prompt + $1.completion) }
    }

    /// 一条带用量回复的归属：快照优先（准确）；没快照按发送智能体当前用的
    /// 供应商/模型估算（Minis ChatStore+UsageStats.swift 的 fallback 行语义）。
    private func usageAttribution(for m: Message) -> (provider: String, model: String, estimated: Bool) {
        if let p = m.usageProvider, let mo = m.usageModel {
            return (p, mo, false)
        }
        if let a = agent(id: UUID(uuidString: m.senderId) ?? UUID()),
           let p = providers.first(where: { $0.id.uuidString == a.providerKey }) {
            return (p.name, a.modelId.isEmpty ? "未选模型" : a.modelId, true)
        }
        return ("其他", m.usageModel ?? "未知模型", true)
    }

    /// 按供应商汇总用量（Minis Usage 页按 provider 分组的同款口径）。
    func usageByProvider() -> [(name: String, prompt: Int, completion: Int, estimated: Bool)] {
        var map: [String: (Int, Int, Bool)] = [:]
        for conv in conversations {
            for m in conv.messages {
                guard let p = m.usagePrompt, let c = m.usageCompletion else { continue }
                let attr = usageAttribution(for: m)
                let cur = map[attr.provider] ?? (0, 0, false)
                map[attr.provider] = (cur.0 + p, cur.1 + c, cur.2 || attr.estimated)
            }
        }
        return map.map { (name: $0.key, prompt: $0.value.0, completion: $0.value.1, estimated: $0.value.2) }
            .sorted { ($0.prompt + $0.completion) > ($1.prompt + $1.completion) }
    }

    /// 按模型汇总用量。
    func usageByModel() -> [(name: String, prompt: Int, completion: Int, estimated: Bool)] {
        var map: [String: (Int, Int, Bool)] = [:]
        for conv in conversations {
            for m in conv.messages {
                guard let p = m.usagePrompt, let c = m.usageCompletion else { continue }
                let attr = usageAttribution(for: m)
                let cur = map[attr.model] ?? (0, 0, false)
                map[attr.model] = (cur.0 + p, cur.1 + c, cur.2 || attr.estimated)
            }
        }
        return map.map { (name: $0.key, prompt: $0.value.0, completion: $0.value.1, estimated: $0.value.2) }
            .sorted { ($0.prompt + $0.completion) > ($1.prompt + $1.completion) }
    }

    /// 按日汇总用量（最近 30 天，按天倒序）。
    func usageByDay() -> [(day: Date, prompt: Int, completion: Int)] {
        var map: [Date: (Int, Int)] = [:]
        let cal = Calendar.current
        for conv in conversations {
            for m in conv.messages {
                guard let p = m.usagePrompt, let c = m.usageCompletion else { continue }
                let day = cal.startOfDay(for: m.date)
                let cur = map[day] ?? (0, 0)
                map[day] = (cur.0 + p, cur.1 + c)
            }
        }
        return map.map { (day: $0.key, prompt: $0.value.0, completion: $0.value.1) }
            .sorted { $0.day > $1.day }
            .prefix(30).map { $0 }
    }

    /// 给一条回复记用量（含供应商/模型快照，供上面三个汇总用）。
    /// 聊天方在写 usagePrompt/usageCompletion 的同时调这个（ChatView 接线，见汇报）。
    func setMessageUsage(conversationId: UUID, messageId: UUID,
                         providerName: String, modelId: String,
                         prompt: Int, completion: Int) {
        guard let ci = conversations.firstIndex(where: { $0.id == conversationId }),
              let mi = conversations[ci].messages.firstIndex(where: { $0.id == messageId })
        else { return }
        conversations[ci].messages[mi].usagePrompt = prompt
        conversations[ci].messages[mi].usageCompletion = completion
        conversations[ci].messages[mi].usageProvider = providerName
        conversations[ci].messages[mi].usageModel = modelId
        save()
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
        var modelGroups: [ModelGroup] = []
        var envVars: [EnvVar] = []
        var soulText: String = ""
        var globalMemory: String = ""
        var dailyLogs: [DailyMemoryLog] = []
        var server: ServerConfig = ServerConfig()
        var connectors: [Connector] = builtinConnectors
        var skills: [Skill] = []
        var plugins: [Plugin] = []
        var scheduledTasks: [ScheduledTask] = []
        var customMCPs: [CustomMCP] = []
        var miniApps: [MiniApp] = []
        var deviceCapabilities: [DeviceCapability] = builtinDeviceCapabilities
        var pluginStoreIndex: String = ""
        var language: String = "zh-Hans"
    }

    func save() {
        let snap = Snapshot(agents: agents, conversations: conversations,
                            providers: providers, modelGroups: modelGroups,
                            envVars: envVars, soulText: soulText,
                            globalMemory: globalMemory, dailyLogs: dailyLogs,
                            server: server, connectors: connectors,
                            skills: skills, plugins: plugins,
                            scheduledTasks: scheduledTasks, customMCPs: customMCPs,
                            miniApps: miniApps, deviceCapabilities: deviceCapabilities,
                            pluginStoreIndex: pluginStoreIndex, language: language)
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
        modelGroups = snap.modelGroups
        envVars = snap.envVars
        soulText = snap.soulText
        globalMemory = snap.globalMemory
        dailyLogs = snap.dailyLogs
        server = snap.server
        if !snap.connectors.isEmpty { connectors = snap.connectors }
        skills = snap.skills
        plugins = snap.plugins
        scheduledTasks = snap.scheduledTasks
        customMCPs = snap.customMCPs
        miniApps = snap.miniApps
        if !snap.deviceCapabilities.isEmpty { deviceCapabilities = snap.deviceCapabilities }
        pluginStoreIndex = snap.pluginStoreIndex
        if !snap.language.isEmpty { language = snap.language }
    }
}
