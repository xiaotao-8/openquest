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
        return entries.compactMap { $0 }
    }

    // MARK: - Live driver

    /// Connects with the preview pairing blob, opens the preview bot chat,
    /// sends a Chinese intro message, then a file-listing message to trigger
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
        // 2. A file-listing request — the preview bot has permission "ask",
        // so the tool call surfaces a real approval card.
        try? await Task.sleep(nanoseconds: 20_000_000_000)
        let listNonce = UUID().uuidString
        let list = Entry(localText: "列出你工作区里的文件。", botId: parsed.botId, clientNonce: listNonce)
        connector.mirror.addLocalEntry(list)
        do {
            _ = try await api.send(botId: parsed.botId, text: "列出你工作区里的文件。", clientNonce: listNonce)
            store.liveDiag.record("list request sent")
        } catch {
            store.liveDiag.record("list send failed: \(error)")
        }
        recordRoster(store: store, tag: "after-list")
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
