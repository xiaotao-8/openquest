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
    }

    static func fromLaunchArguments() -> PreviewMode {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-PreviewPairing"), index + 1 < args.count {
            return .live
        }
        guard args.contains("-PreviewSeed") else { return .none }
        var options = SeedOptions()
        options.openChat = args.contains("-PreviewChat")
        options.approval = args.contains("-PreviewApproval")
        options.ask = args.contains("-PreviewAsk")
        options.settings = args.contains("-PreviewSettings")
        if let index = args.firstIndex(of: "-PreviewPage"), index + 1 < args.count {
            options.page = args[index + 1]
        }
        return .seeded(options)
    }

    static func pairingBlob() -> Data? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-PreviewPairing"), index + 1 < args.count else {
            return nil
        }
        return Data(base64Encoded: args[index + 1])
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
        for entry in demoEntries(bots: bots, now: now, approval: options.approval, ask: options.ask) {
            mirror.apply(.entry(entry))
        }
        if options.settings {
            store.selectedTab = 3
        } else if let page = options.page {
            store.selectedTab = page == "state" ? 2 : 1
        } else if options.openChat || options.approval || options.ask {
            store.selectedTab = 0
            if let lead = bots.first {
                store.navigationPath.append(lead.id)
                store.openBotId = lead.id
            }
        }
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

    private static func demoEntries(bots: [Bot], now: Int64, approval: Bool, ask: Bool) -> [Entry] {
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
        ]
        if approval {
            entries.append(entryJSON("""
            {"id":"demo-e3","seq":3,"botId":"\(lead)","rev":3,"kind":"permission","turn":2,"data":{"title":"rm -rf /root/demo/node_modules/.cache","toolKind":"execute","command":"rm -rf /root/demo/node_modules/.cache","cwd":"/root/demo","status":"pending","options":[{"optionId":"allow_once","name":"仅允许一次","kind":"allow_once"},{"optionId":"allow_always","name":"始终允许","kind":"allow_always"},{"optionId":"deny","name":"拒绝","kind":"reject_once"}]},"createdAt":\(now - 30_000),"updatedAt":\(now - 30_000)}
            """))
        }
        if ask {
            entries.append(entryJSON("""
            {"id":"demo-e4","seq":4,"botId":"\(lead)","rev":4,"kind":"permission","turn":2,"data":{"question":"登录测试修好后，要不要顺手把注册测试也跑一遍？","choices":["跑一遍","只跑登录测试","先不跑"],"recommended":0,"status":"pending"},"createdAt":\(now - 10_000),"updatedAt":\(now - 10_000)}
            """))
        }
        return entries.compactMap { $0 }
    }

    // MARK: - Live driver

    /// Connects with the preview pairing blob, opens the preview bot chat,
    /// sends a Chinese intro message, then a file-listing message to trigger
    /// a real approval card. When a pending card appears, it is answered
    /// "Allow once" at ~+120 s so the ~150 s screenshot shows it answered.
    @MainActor
    static func runLive(store: AppStore) async {
        store.connector.mirror.reset()
        guard let blob = PreviewMode.pairingBlob(),
              let parsed = try? JSONDecoder().decode(PreviewPairing.self, from: blob),
              let seed = Base64URL.decode(parsed.deviceKey), seed.count == 32,
              let signKey = Base64URL.decode(parsed.signKey), signKey.count == 32,
              let boxKey = Base64URL.decode(parsed.boxKey), boxKey.count == 32 else {
            LogStore.record("live preview: bad pairing blob")
            return
        }
        let identity: PreviewIdentity
        do {
            identity = try DeviceIdentity.preview(deviceSeed: seed)
        } catch {
            LogStore.record("live preview: bad device seed")
            return
        }
        // Build the Computer through the pairing-link path so the record is
        // exactly what a real pairing would store.
        let link = PairingLink(
            name: "ECS", computerId: parsed.computerId, signKey: signKey,
            boxKey: boxKey, code: Data(), codeBase64URL: "",
            urls: parsed.urls, cloud: nil, offerId: ""
        )
        let paired = Computer(from: link)
        let connector = store.connector
        connector.connect(computer: paired, identity: identity)
        let start = Date()
        // Wait for the channel + hello (bounded).
        for _ in 0..<100 {
            if connector.hello != nil { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard connector.hello != nil else {
            LogStore.record("live preview: hello timed out")
            return
        }
        store.selectedTab = 0
        store.navigationPath.append(parsed.botId)
        store.openBotId = parsed.botId
        guard let api = connector.api else { return }
        // 1. Intro message in Chinese.
        let introNonce = UUID().uuidString
        let intro = Entry(localText: "你好，请用中文介绍一下你自己。", botId: parsed.botId, clientNonce: introNonce)
        connector.mirror.addLocalEntry(intro)
        _ = try? await api.send(botId: parsed.botId, text: "你好，请用中文介绍一下你自己。", clientNonce: introNonce)
        // 2. A file-listing request — the preview bot has permission "ask",
        // so the tool call surfaces a real approval card.
        try? await Task.sleep(nanoseconds: 20_000_000_000)
        let listNonce = UUID().uuidString
        let list = Entry(localText: "列出你工作区里的文件。", botId: parsed.botId, clientNonce: listNonce)
        connector.mirror.addLocalEntry(list)
        _ = try? await api.send(botId: parsed.botId, text: "列出你工作区里的文件。", clientNonce: listNonce)
        // 3. Watch for a pending card; answer "Allow once" at ~+120 s.
        while Date().timeIntervalSince(start) < 150 {
            let pending = connector.mirror.entries(for: parsed.botId).first { $0.isWaitingCard }
            if let pending, Date().timeIntervalSince(start) >= 120 {
                if let option = pending.data.options?.first(where: { $0.kind == "allow_once" }) {
                    try? await api.respondPermission(entryId: pending.id, optionId: option.optionId)
                    LogStore.record("live preview: answered approval once")
                    return
                }
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
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
