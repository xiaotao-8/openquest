import Foundation

/// Preview modes driven by launch arguments (Codemagic simulator runs).
/// Seeded mode renders demo data with no host; live mode connects with the
/// preview pairing blob (`-PreviewPairing <base64 of preview-pairing.json>`)
/// and drives a real conversation against the ECS host.
enum PreviewMode: Equatable {
    case none
    case seeded(SeedOptions)
    case live

    struct SeedOptions: Equatable {
        var openChat = false
        var approval = false
        var ask = false
        var settings = false
        var page: String?
        /// Show the pairing flow instead of the tabs: "install" or "scan".
        var pairingPage: String?
        /// Show the computer-management sheet instead of the tabs.
        var computers = false
        /// Seed Phase 2 demo data (Feed / Ideas / Goals / Spaces / audit)
        /// and demo Soul / Memory / Identity files.
        var phase2 = false
        /// Open the corresponding sheet on the Settings tab.
        var soul = false
        var memory = false
        var identity = false
        var vault = false
        var network = false
        var dataControls = false
        /// Open the audit log sheet on the State tab.
        var audit = false
        /// Scroll the State tab to the lower sections (Activity /
        /// Approvals / Upcoming / audit) for the screenshot.
        var stateLower = false
        /// Seed demo routines for the State-lower screenshot.
        var routines = false
        /// Open the Voice service sheet on the Settings tab.
        var voice = false
        /// Open the lead bot's chat, then the call screen over it.
        var call = false
        /// Show the Extensions page instead of the tabs.
        var extensions = false
        /// Show the host Network page instead of the tabs.
        var hostNetwork = false
        /// Show the Usage page (true data) instead of the tabs.
        var usage = false
        /// Open the Upcoming sheet on the State tab.
        var upcoming = false
        /// Open the lead bot's chat with "@" already typed, so the candidate
        /// panel shows above the composer.
        var candidates = false
        /// Seed one agent message carrying a ```schemaJson block, so the
        /// read-only GenUI rendering shows in the chat.
        var genUI = false
        /// Seed a demo view card (FishPocket show_view) in the lead bot's chat.
        var viewCard = false
        /// Seed a demo learning proposal in the lead bot's chat.
        var learning = false
        /// Show the Cordis panel sheet over the Extensions page.
        var cordis = false
        /// Open the first demo market connector's detail sheet over the Extensions page.
        var connectorDetail = false
        /// Show the IM bridge page instead of the tabs.
        var imBridge = false
        /// Show the phone-control (iCTRL) page instead of the tabs.
        var phoneControl = false
        /// Show the bot-import page instead of the tabs.
        var botImport = false
        /// Show the computer-use page instead of the tabs.
        var computerUse = false
    }

    static func fromLaunchArguments() -> PreviewMode {
        let args = ProcessInfo.processInfo.arguments
        if value(for: "-PreviewPairing", in: args) != nil {
            return .live
        }
        guard args.contains("-PreviewSeed") else { return .none }
        var options = SeedOptions()
        options.openChat = args.contains("-PreviewChat")
        options.approval = args.contains("-PreviewApproval")
        options.ask = args.contains("-PreviewAsk")
        options.settings = args.contains("-PreviewSettings")
        options.page = value(for: "-PreviewPage", in: args)
        options.pairingPage = value(for: "-PreviewPairingPage", in: args)
        options.computers = args.contains("-PreviewComputers")
        options.phase2 = args.contains("-PreviewPhase2")
        options.soul = args.contains("-PreviewSoul")
        options.memory = args.contains("-PreviewMemory")
        options.identity = args.contains("-PreviewIdentity")
        options.vault = args.contains("-PreviewVault")
        options.network = args.contains("-PreviewNetwork")
        options.dataControls = args.contains("-PreviewDataControls")
        options.audit = args.contains("-PreviewAudit")
        options.stateLower = args.contains("-PreviewStateLower")
        options.routines = args.contains("-PreviewRoutines")
        options.voice = args.contains("-PreviewVoice")
        options.call = args.contains("-PreviewCall")
        options.extensions = args.contains("-PreviewExtensions")
        options.hostNetwork = args.contains("-PreviewHostNetwork")
        options.usage = args.contains("-PreviewUsage")
        options.upcoming = args.contains("-PreviewUpcoming")
        options.candidates = args.contains("-PreviewCandidates")
        options.genUI = args.contains("-PreviewGenUI")
        options.viewCard = args.contains("-PreviewViewCard")
        options.learning = args.contains("-PreviewLearning")
        options.cordis = args.contains("-PreviewCordis")
        options.connectorDetail = args.contains("-PreviewConnectorDetail")
        options.imBridge = args.contains("-PreviewIMBridge")
        options.phoneControl = args.contains("-PreviewPhoneControl")
        options.botImport = args.contains("-PreviewBotImport")
        options.computerUse = args.contains("-PreviewComputerUse")
        return .seeded(options)
    }

    /// Reads a launch-argument value in either form: two separate arguments
    /// (`-PreviewPage discover`) or one `=`-joined argument
    /// (`-PreviewPage=discover`, as codemagic.yaml passes it).
    static func value(for flag: String, in args: [String]) -> String? {
        if let index = args.firstIndex(of: flag), index + 1 < args.count {
            return args[index + 1]
        }
        let prefix = flag + "="
        for arg in args where arg.hasPrefix(prefix) {
            return String(arg.dropFirst(prefix.count))
        }
        return nil
    }

    static func pairingBlob() -> Data? {
        let args = ProcessInfo.processInfo.arguments
        guard let raw = value(for: "-PreviewPairing", in: args)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty else {
            return nil
        }
        return Data(base64Encoded: raw)
    }
}

/// Seeded demo data + the live preview driver.
enum PreviewRunner {
    // MARK: - Seeded demo data

    @MainActor
    static func seed(store: AppStore, options: PreviewMode.SeedOptions) {
        let mirror = store.connector.mirror
        mirror.reset()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let bots = demoBots(now: now)
        for bot in bots {
            mirror.apply(.bot(bot))
        }
        for entry in demoEntries(bots: bots, now: now, approval: options.approval, ask: options.ask, genUI: options.genUI, viewCard: options.viewCard, learning: options.learning) {
            mirror.apply(.entry(entry))
        }
        if options.computers, let computer = demoComputer(), let hello = demoHello() {
            store.connector.seedPreview(computer: computer, hello: hello)
        }
        if options.phase2 {
            seedPhase2(store: store)
        }
        if options.routines {
            seedRoutinesDemo(store: store)
        }
        if options.soul || options.memory || options.identity || options.vault || options.network || options.dataControls || options.voice {
            store.selectedTab = 3
        } else if options.audit || options.upcoming {
            store.selectedTab = 2
        } else if options.settings {
            store.selectedTab = 3
        } else if let page = options.page {
            store.selectedTab = page == "state" ? 2 : 1
        } else if options.openChat || options.approval || options.ask || options.call || options.candidates || options.genUI || options.viewCard || options.learning {
            store.selectedTab = 0
            if let lead = bots.first {
                store.navigationPath.append(lead.id)
                store.openBotId = lead.id
            }
        }
    }

    /// Phase 2 demo data (seeded mode only): one Feed post, one Idea, one
    /// Goal with a progress entry, one Space request, two audit records,
    /// and demo Soul / Memory / Identity files — so the new tabs can be
    /// screenshotted with real-looking rows. Demo rows only; a real user
    /// starts with all of these empty. Idempotent: the captures run
    /// several phase2 launches in one simulator, and the rows must not
    /// duplicate.
    @MainActor
    private static func seedPhase2(store: AppStore) {
        if store.feed.posts.isEmpty {
            store.feed.add(title: "本周值得看的几件事", body: "演示简报：登录测试已修复，文档已更新，本周聚焦在新功能的收尾上。", category: "工作", source: "generated")
        }
        if store.ideas.ideas.isEmpty {
            store.ideas.add(title: "把每周简报固定在周一早上发", category: "工作", source: "typed")
        }
        if store.goals.goals.isEmpty {
            store.goals.add(title: "每周读完一本书", type: GoalCategory.health.rawValue)
            if let goal = store.goals.goals.first {
                store.goals.addProgress(goalId: goal.id, text: "读完了第一章，做了三页笔记。")
            }
        }
        if store.spaces.spaces.isEmpty {
            store.spaces.add(title: "倒数日", description: "一个显示重要日子倒计时的桌面小工具。")
        }
        if store.audit.records.isEmpty {
            store.audit.record(botId: "demo-lead", botName: "阿文", kind: .approval,
                               title: "rm -rf /root/demo/node_modules/.cache", detail: "删除缓存目录", status: .allowed)
            store.audit.record(botId: "demo-north", botName: "小北", kind: .decision,
                               title: "登录测试修好后，要不要顺手把注册测试也跑一遍？", detail: "跑一遍", status: .done)
        }
        store.identity.saveSoul("演示 Soul：你是 linGyU 的智能体，中文回复，简洁直接。")
        store.identity.saveMemory("演示记忆：用户喜欢简洁直接的回答。")
        store.identity.saveIdentity(name: "阿文", vibe: "冷静、直接", tagline: "写代码、修 bug、跑测试。", body: "演示身份。")
    }

    /// Seeded demo routines (seeded mode only): one enabled daily routine
    /// with a next run, one disabled weekly routine, one done run, one
    /// failed run (retryable), and one waiting follow-up — so the State
    /// lower sections and Upcoming can be screenshotted with real rows.
    @MainActor
    private static func seedRoutinesDemo(store: AppStore) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let hour: Int64 = 3600_000
        let listing = RoutineListing(
            routines: [
                Routine(id: "demo-routine-morning", botId: "demo-lead", name: "早上简报",
                        instruction: "每天早上整理一份简报发给我。",
                        triggers: [RoutineTrigger(type: "cron", expression: "0 8 * * *", timeZone: TimeZone.current.identifier)],
                        enabled: true, createdAt: now - 7 * 24 * hour, updatedAt: now - 7 * 24 * hour,
                        triggerDescriptions: ["每天 08:00"], nextRunAt: now + hour, timeoutSeconds: 3600),
                Routine(id: "demo-routine-weekly", botId: "demo-lead", name: "每周回顾",
                        instruction: "每周五晚上总结这周完成的事。",
                        triggers: [RoutineTrigger(type: "cron", expression: "0 18 * * 5", timeZone: TimeZone.current.identifier)],
                        enabled: false, createdAt: now - 7 * 24 * hour, updatedAt: now - 7 * 24 * hour,
                        triggerDescriptions: ["每周五 18:00"], nextRunAt: nil, timeoutSeconds: 3600),
            ],
            runs: [
                RoutineRun(id: "demo-run-1", routineId: "demo-routine-morning", botId: "demo-lead",
                           status: "done", createdAt: now - hour, finishedAt: now - hour + 60_000, detail: "简报已发。"),
                RoutineRun(id: "demo-run-2", routineId: "demo-routine-morning", botId: "demo-lead",
                           status: "failed", createdAt: now - 25 * hour, finishedAt: now - 25 * hour + 30_000, detail: "电脑端返回错误。"),
            ],
            followUps: [
                FollowUp(id: "demo-followup-1", botId: "demo-lead", at: now + 2 * hour,
                         note: "下午三点前提醒我看一眼简报。", createdAt: now - hour),
            ])
        store.routines.seedDemo(botId: "demo-lead", listing: listing)
    }

    private static func demoBots(now: Int64) -> [Bot] {
        func botJSON(_ json: String) -> Bot? {
            try? JSONDecoder().decode(Bot.self, from: Data(json.utf8))
        }
        return [
            botJSON("""
            {"id":"demo-lead","kind":"agent","members":[],"name":"阿文","description":"写代码、修 bug、跑测试。","avatarColor":"blue","avatarShape":"blob","backend":"opencode","cwd":"/root/demo","managedWorkspace":true,"permission":"ask","mode":"auto","model":null,"modelOptions":{},"rev":1,"status":"working","activity":"正在修登录测试","unread":2,"waiting":1,"lastMessage":"搞定了，登录测试已修复，跑了三遍都通过。","lastAt":\(now),"createdAt":\(now)}
            """),
            botJSON("""
            {"id":"demo-north","kind":"agent","members":[],"name":"小北","description":"查资料、写文档。","avatarColor":"orange","avatarShape":"squircle","backend":"opencode","cwd":"/root/demo","managedWorkspace":true,"permission":"ask","mode":"auto","model":null,"modelOptions":{},"rev":1,"status":"idle","activity":"","unread":0,"waiting":0,"lastMessage":"文档已按你的要求改好。","lastAt":\(now - 3600_000),"createdAt":\(now)}
            """),
            botJSON("""
            {"id":"demo-group","kind":"group","members":["demo-lead","demo-north"],"name":"工作组","description":"","avatarColor":"violet","avatarShape":"teardrop","backend":"","cwd":"","managedWorkspace":false,"permission":"ask","model":null,"modelOptions":{},"rev":1,"status":"idle","activity":"","unread":1,"waiting":0,"lastMessage":"小北：文档已按你的要求改好。","lastAt":\(now - 7200_000),"createdAt":\(now)}
            """),
        ].compactMap { $0 }
    }

    /// One demo computer + hello with the ECS host's real values, for the
    /// computer-management sheet preview (in-memory only, never persisted).
    /// The hello reports an update (2.51.0) so the version row's update
    /// state is visible too.
    private static func demoComputer() -> Computer? {
        try? JSONDecoder().decode(Computer.self, from: Data("""
        {"id":"demo-computer","name":"ECS","signKey":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","boxKey":null,"urls":["http://47.238.160.204:19222"],"cloud":null,"device":"linux","color":null,"route":"direct","notifications":null}
        """.utf8))
    }

    private static func demoHello() -> HelloReply? {
        try? JSONDecoder().decode(HelloReply.self, from: Data("""
        {"hostId":"demo-host","computerId":"demo-computer","name":"ECS","version":"2.50.0","schema":8,"canUpdate":true,"latestVersion":"2.51.0","autoOrder":false,"urls":["http://47.238.160.204:19222"],"rev":1}
        """.utf8))
    }

    private static func demoEntries(bots: [Bot], now: Int64, approval: Bool, ask: Bool, genUI: Bool = false, viewCard: Bool = false, learning: Bool = false) -> [Entry] {
        func entryJSON(_ json: String) -> Entry? {
            try? JSONDecoder().decode(Entry.self, from: Data(json.utf8))
        }
        let lead = bots[0].id
        var entries: [Entry] = [
            entryJSON("""
            {"id":"demo-e1","seq":1,"botId":"\(lead)","rev":1,"kind":"user","turn":1,"data":{"text":"修好那个不稳定的登录测试","clientNonce":"demo-nonce-1","status":"sent"},"createdAt":\(now - 120_000),"updatedAt":\(now - 120_000)}
            """),
            entryJSON("""
            {"id":"demo-e2","seq":2,"botId":"\(lead)","rev":2,"kind":"agent","turn":1,"data":{"text":"搞定了，登录测试已修复，跑了三遍都通过。","final":true,"author":"\(lead)"},"createdAt":\(now - 60_000),"updatedAt":\(now - 60_000)}
            """),
        ].compactMap { $0 }
        if approval {
            if let entry = entryJSON("""
            {"id":"demo-e3","seq":3,"botId":"\(lead)","rev":3,"kind":"permission","turn":2,"data":{"title":"rm -rf /root/demo/node_modules/.cache","toolKind":"execute","command":"rm -rf /root/demo/node_modules/.cache","cwd":"/root/demo","status":"pending","options":[{"optionId":"allow_once","name":"仅允许一次","kind":"allow_once"},{"optionId":"allow_always","name":"始终允许","kind":"allow_always"},{"optionId":"deny","name":"拒绝","kind":"reject_once"}]},"createdAt":\(now - 30_000),"updatedAt":\(now - 30_000)}
            """) { entries.append(entry) }
        }
        if ask {
            if let entry = entryJSON("""
            {"id":"demo-e4","seq":4,"botId":"\(lead)","rev":4,"kind":"permission","turn":2,"data":{"question":"登录测试修好后，要不要顺手把注册测试也跑一遍？","choices":["跑一遍","只跑登录测试","先不跑"],"recommended":0,"status":"pending"},"createdAt":\(now - 10_000),"updatedAt":\(now - 10_000)}
            """) { entries.append(entry) }
        }
        if genUI {
            let schema = """
            {"componentName":"Page","children":[{"componentName":"TinyCard","props":{"title":"本周进度"},"children":[{"componentName":"Text","props":{"text":"登录测试已修复，跑了三遍都通过。"}}]},{"componentName":"TinyGrid","props":{"columns":[{"title":"任务","field":"task"},{"title":"状态","field":"status"}],"data":[{"task":"登录测试","status":"已完成"},{"task":"注册测试","status":"进行中"}]}}]}
            """
            let text = "这是本周的进度汇总：\n\n```schemaJson\n\(schema)\n```\n"
            let dict: [String: Any] = [
                "id": "demo-e5", "seq": 5, "botId": lead, "rev": 5, "kind": "agent", "turn": 3,
                "data": ["text": text, "final": true, "author": lead],
                "createdAt": now - 5_000, "updatedAt": now - 5_000,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: dict),
               let entry = try? JSONDecoder().decode(Entry.self, from: data) {
                entries.append(entry)
            }
        }
        if viewCard {
            if let entry = entryJSON("""
            {"id":"demo-e7","seq":7,"botId":"\(lead)","rev":7,"kind":"view","turn":2,"data":{"title":"本周花费汇总","status":"pending","view":{"id":"demo-view-1","title":"本周花费汇总","view":{"type":"stack","children":[{"type":"text","text":"本周三项开销合计 1,240 元，预算还剩 260 元。"},{"type":"metric","label":"合计","value":1240,"unit":"元"},{"type":"table","label":"花费明细","columns":["项目","金额"],"rows":[["餐饮",520],["交通",310],["日用",410]]},{"type":"chart","kind":"bar","label":"按项目","labels":["餐饮","交通","日用"],"series":[{"label":"金额","values":[520,310,410]}]},{"type":"metric","label":"预算结余","value":{"=":"budget - 1240"},"unit":"元"},{"type":"form","fields":[{"id":"budget","type":"number","label":"本周预算","value":1500},{"id":"food","type":"slider","label":"餐饮预算","value":520,"min":0,"max":1000,"step":10},{"id":"save","type":"options","label":"省钱方式","options":[{"label":"自己做饭","description":"每周约省 200 元","selected":true},{"label":"公交出行","description":"每周约省 80 元"}]},{"id":"note","type":"text","label":"备注","value":"","multiline":true},{"id":"lastweek","type":"text","label":"上周结余","value":"上周结余 120 元","readonly":true}]},{"type":"confirm","text":"确认按这份预算执行吗？"},{"type":"submit","label":"提交预算"}]}}},"createdAt":\(now - 5_000),"updatedAt":\(now - 5_000)}
            """) { entries.append(entry) }
        }
        if learning {
            if let entry = entryJSON("""
            {"id":"demo-e8","seq":8,"botId":"\(lead)","rev":8,"kind":"learning","turn":2,"data":{"status":"pending","learning":{"id":"demo-learning-1","kind":"skill","title":"学到一个新技能：整理周报","summary":"本周的三次周报请求都用了同一套步骤，可以存成一个技能，下次直接调用。","target":"skills/weekly-report","preview":"# 整理周报\\n\\n1. 汇总本周已完成的事\\n2. 列出进行中的事\\n3. 写出下周计划"}},"createdAt":\(now - 2_000),"updatedAt":\(now - 2_000)}
            """) { entries.append(entry) }
        }
        return entries.compactMap { $0 }
    }

    // MARK: - Live driver

    /// Connects with the preview pairing blob, opens the preview bot chat,
    /// sends a Chinese intro message, then a file-write message to trigger
    /// a real approval card. When a pending card appears, it is answered
    /// "Allow once" at ~+120 s so the ~150 s screenshot shows it answered.
    @MainActor
    static func runLive(store: AppStore) async {
        store.liveDiag.record("runLive started")
        store.connector.mirror.reset()
        store.liveDiag.record("mirror reset")
        recordRoster(store: store, tag: "after-reset")
        guard let blob = PreviewMode.pairingBlob(),
              let parsed = try? JSONDecoder().decode(PreviewPairing.self, from: blob),
              let seed = Base64URL.decode(parsed.deviceKey), seed.count == 32,
              let signKey = Base64URL.decode(parsed.signKey), signKey.count == 32,
              let boxKey = Base64URL.decode(parsed.boxKey), boxKey.count == 32 else {
            store.liveDiag.record("live preview: bad pairing blob")
            return
        }
        store.liveDiag.record("blob ok bytes=\(blob.count) urls=\(parsed.urls.count) bot=\(parsed.botName ?? "?")")
        let identity: PreviewIdentity
        do {
            identity = try DeviceIdentity.preview(deviceSeed: seed)
        } catch {
            store.liveDiag.record("live preview: bad device seed")
            return
        }
        store.liveDiag.record("identity ok")
        // Build the Computer through the pairing-link path so the record is
        // exactly what a real pairing would store.
        let link = PairingLink(
            name: "ECS", computerId: parsed.computerId, signKey: signKey,
            boxKey: boxKey, code: Data(), codeBase64URL: "",
            urls: parsed.urls, cloud: nil, offerId: ""
        )
        let paired = Computer(from: link)
        let connector = store.connector
        // Dial instrumentation: every WS attempt is logged to the diag card.
        store.connector.setDialReporter { [weak store] line in
            Task { @MainActor in store?.liveDiag.record(line) }
        }
        await preflightHealth(store: store, urls: parsed.urls)
        store.liveDiag.record("connect() called")
        await connector.connect(computer: paired, identity: identity)
        // Wait for the channel + hello (bounded). 60 s, not 20 s: a cold
        // simulator reaching a cross-region host can need several race +
        // backoff cycles before the first hello lands, and the 60 s
        // screenshot only needs the chat to be open by then.
        for _ in 0..<300 {
            if connector.hello != nil { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard let hello = connector.hello else {
            store.liveDiag.record("live preview: hello timed out after 60s state=\(connector.state)")
            return
        }
        store.liveDiag.record("hello ok host v\(hello.version) schema=\(hello.schema)")
        recordRoster(store: store, tag: "after-hello")
        // The 150 s budget below measures the conversation, not the
        // connection: start the clock once the chat is open.
        let start = Date()
        store.selectedTab = 0
        store.navigationPath.append(parsed.botId)
        store.openBotId = parsed.botId
        guard let api = connector.api else {
            store.liveDiag.record("api nil after hello — abort")
            return
        }
        store.liveDiag.record("chat opened")
        // 1. Intro message in Chinese.
        let introNonce = UUID().uuidString
        let intro = Entry(localText: "你好，请用中文介绍一下你自己。", botId: parsed.botId, clientNonce: introNonce)
        connector.mirror.addLocalEntry(intro)
        do {
            _ = try await api.send(botId: parsed.botId, text: "你好，请用中文介绍一下你自己。", clientNonce: introNonce)
            store.liveDiag.record("intro sent")
        } catch {
            store.liveDiag.record("intro send failed: \(error)")
        }
        // 2. A file-write request — the preview bot has permission "ask",
        // so the write surfaces a real approval card (a read-only file
        // listing never would: nothing there needs approving).
        try? await Task.sleep(nanoseconds: 20_000_000_000)
        let writeNonce = UUID().uuidString
        let write = Entry(localText: "在工作区新建文件 linGyU-live-test.txt，写一行 hello。", botId: parsed.botId, clientNonce: writeNonce)
        connector.mirror.addLocalEntry(write)
        do {
            _ = try await api.send(botId: parsed.botId, text: "在工作区新建文件 linGyU-live-test.txt，写一行 hello。", clientNonce: writeNonce)
            store.liveDiag.record("write request sent")
        } catch {
            store.liveDiag.record("write send failed: \(error)")
        }
        recordRoster(store: store, tag: "after-write")
        // 3. Watch for a pending card; answer "Allow once" at ~+120 s.
        var cardSeen = false
        while Date().timeIntervalSince(start) < 150 {
            let pending = connector.mirror.entries(for: parsed.botId).first { $0.isWaitingCard }
            if let pending {
                if !cardSeen {
                    cardSeen = true
                    store.liveDiag.record("approval card seen")
                }
                if Date().timeIntervalSince(start) >= 120 {
                    if let option = pending.data.options?.first(where: { $0.kind == "allow_once" }) {
                        do {
                            try await api.respondPermission(entryId: pending.id, optionId: option.optionId)
                            store.liveDiag.record("live preview: answered approval once")
                        } catch {
                            store.liveDiag.record("approval answer failed: \(error)")
                        }
                        return
                    }
                }
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        store.liveDiag.record("window ended without approval answer")
    }

    /// Roster truth for the verification question "did the seeded bots
    /// leave and the real bot arrive": bot count + first few names.
    /// Names are not secrets.
    @MainActor
    private static func recordRoster(store: AppStore, tag: String) {
        let bots = store.connector.mirror.bots
        let names = Array(bots.prefix(5)).map(\.name).joined(separator: ",")
        store.liveDiag.record("roster \(tag) bots=\(bots.count) [\(names)]")
    }

    /// In-app reachability check before the WS dial: a plain HTTP GET to
    /// the first blob URL's /health, logged with the code or the error.
    /// Distinguishes "this process cannot reach the host at all" from
    /// "reached but the WebSocket handshake failed". Best effort and
    /// bounded (5 s) — the WS dial always runs afterwards regardless.
    @MainActor
    private static func preflightHealth(store: AppStore, urls: [String]) async {
        guard let first = urls.first, var parts = URLComponents(string: first) else {
            store.liveDiag.record("preflight: no url")
            return
        }
        parts.path = "/health"
        parts.query = nil
        guard let url = parts.url else {
            store.liveDiag.record("preflight: bad url")
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            store.liveDiag.record("preflight \(parts.host ?? "?") http=\(code)")
        } catch {
            let ns = error as NSError
            store.liveDiag.record("preflight failed (\(ns.domain) \(ns.code))")
        }
    }

    private struct PreviewPairing: Decodable {
        var deviceKey: String
        var signKey: String
        var boxKey: String
        var computerId: String
        var urls: [String]
        var botId: String
        var botName: String?
    }
}
