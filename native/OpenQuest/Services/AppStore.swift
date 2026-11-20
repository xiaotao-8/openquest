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
        // 仅模拟器验收：-PreviewProviders 时走一遍免费源“点一下添加”的真路径，
        // 把免费 Agnes 加进来，截图落在供应商页验添加本身（用户 2026-11-20：添加由助手测）。
        if ProcessInfo.processInfo.arguments.contains("-PreviewProviders") {
            addPresetProvider(name: "Agnes", baseURL: "https://api.agnes-ai.cn/v1",
                              modelIds: ["agnes-2.5-flash", "agnes-2.5-pro"])
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
        save()
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

    func setDeviceCapability(id: String, on: Bool) {
        guard let i = deviceCapabilities.firstIndex(where: { $0.id == id }) else { return }
        deviceCapabilities[i].enabled = on
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

    func createConversation(title: String, memberIds: [UUID],
                            adminId: UUID? = nil, speakMode: String = "everyone",
                            notice: String = "") {
        var conv = Conversation(title: title, memberIds: memberIds)
        conv.adminId = adminId
        conv.speakMode = speakMode
        conv.notice = notice
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
            let (data, resp) = try await Net.session.data(for: req)
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
        let base = p.baseURL.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/chat/completions") else { return (name, summary) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
                t.nextFire = Self.nextFire(after: t.nextFire, task: t)
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
                            providers: providers, server: server, connectors: connectors,
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
