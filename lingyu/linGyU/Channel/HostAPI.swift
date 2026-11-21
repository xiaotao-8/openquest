import Foundation

/// A bot create/update draft. Nil fields are omitted, except that an update
/// writes `model` / `mode` / `loginProfile` as explicit JSON null when nil
/// (§7.3) so a full-editor update clears a previous override.
struct BotDraft: Sendable {
    var id: String?
    var kind: String?
    var name: String?
    var description: String?
    var avatarColor: String?
    var avatarShape: String?
    var backend: String?
    var command: String?
    var loginProfile: String?
    var cwd: String?
    var permission: String?
    var mode: String?
    var model: String?
    var modelOptions: [String: String]?
    var fastMode: Bool?
    var fallbacks: [BotFallback]?
    var selfFallbacks: Bool?
    var pinned: Bool?
    var hidden: Bool?
    var notify: Bool?
    var connectors: [String]?
    var skills: [String]?
    var computer: Bool?
    var manageTeam: Bool?
    var offeredToNetwork: Bool?
    var reachableByAssistants: Bool?
    var sharedMemory: Bool?
    var harnessMemory: Bool?
    var compaction: JSONValue?
    var maxThreads: Int?
    var threadWorktrees: Bool?
    var members: [String]?
    var section: String?

    func jsonDictionary(forUpdate: Bool) -> [String: Any] {
        var dict: [String: Any] = [:]
        func set(_ key: String, _ value: Any?) {
            if let value { dict[key] = value }
        }
        set("id", id)
        set("kind", kind)
        set("name", name)
        set("description", description)
        set("avatarColor", avatarColor)
        set("avatarShape", avatarShape)
        set("backend", backend)
        set("command", command)
        set("cwd", cwd)
        set("permission", permission)
        set("modelOptions", modelOptions)
        set("fastMode", fastMode)
        set("pinned", pinned)
        set("hidden", hidden)
        set("notify", notify)
        set("connectors", connectors)
        set("skills", skills)
        set("computer", computer)
        set("manageTeam", manageTeam)
        set("offeredToNetwork", offeredToNetwork)
        set("reachableByAssistants", reachableByAssistants)
        set("sharedMemory", sharedMemory)
        set("harnessMemory", harnessMemory)
        set("members", members)
        set("section", section)
        // loginProfile / mode / model: omitted on create, explicit null on update.
        if forUpdate {
            dict["loginProfile"] = loginProfile ?? NSNull()
            dict["mode"] = mode ?? NSNull()
            dict["model"] = model ?? NSNull()
        } else {
            set("loginProfile", loginProfile)
            set("mode", mode)
            set("model", model)
        }
        if let fallbacks {
            if let data = try? JSONEncoder().encode(fallbacks),
               let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                dict["fallbacks"] = array
            }
        }
        if let selfFallbacks { dict["selfFallbacks"] = selfFallbacks }
        if let compaction {
            if let data = try? JSONEncoder().encode(compaction),
               let value = try? JSONSerialization.jsonObject(with: data) {
                dict["compaction"] = value
            }
        }
        // Dual-name sends (§10 D3): the live host 2.50.0 reads maxAgents /
        // taskWorktrees; 2.51.0-era reads maxThreads / threadWorktrees.
        if let maxThreads {
            dict["maxThreads"] = maxThreads
            dict["maxAgents"] = maxThreads
        }
        if let threadWorktrees {
            dict["threadWorktrees"] = threadWorktrees
            dict["taskWorktrees"] = threadWorktrees
        }
        return dict
    }

    static func from(bot: Bot) -> BotDraft {
        var draft = BotDraft()
        draft.id = bot.id
        draft.kind = bot.kind
        draft.name = bot.name
        draft.description = bot.description
        draft.avatarColor = bot.avatarColor
        draft.avatarShape = bot.avatarShape
        draft.backend = bot.backend
        draft.command = bot.command
        draft.loginProfile = bot.loginProfile
        draft.cwd = bot.managedWorkspace ? "" : bot.cwd
        draft.permission = bot.permission
        draft.mode = bot.mode
        draft.model = bot.model
        draft.modelOptions = bot.modelOptions
        draft.fastMode = bot.fastMode
        draft.fallbacks = bot.fallbacks
        draft.selfFallbacks = bot.selfFallbacks
        draft.pinned = bot.pinned
        draft.hidden = bot.hidden
        draft.notify = bot.notify
        draft.connectors = bot.connectors
        draft.skills = bot.skills
        draft.computer = bot.computer
        draft.manageTeam = bot.manageTeam
        draft.maxThreads = bot.maxThreads
        draft.threadWorktrees = bot.threadWorktrees
        draft.members = bot.members
        draft.section = bot.section
        return draft
    }
}

/// Typed wrappers over the channel's inner RPC — one function per method
/// (§7). No UI logic. Bodies are built as JSON dictionaries so explicit
/// nulls and dual-name fields are exact.
struct HostAPI: Sendable {
    let connection: ChannelConnection
    /// Set from the inner-`hello` reply; gates the task/thread naming (§10 D3).
    var speaksThreads = false

    private func body(_ dict: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: dict)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    private func okEntry(from data: Data) throws -> Entry {
        struct Wrapper: Decodable { var entry: Entry }
        return try decode(Wrapper.self, from: data).entry
    }

    private func okBot(from data: Data) throws -> Bot {
        struct Wrapper: Decodable { var bot: Bot }
        return try decode(Wrapper.self, from: data).bot
    }

    func history(botId: String, beforeSeq: Int64 = 0, limit: Int = 100) async throws -> [Entry] {
        var dict: [String: Any] = ["botId": botId, "limit": limit]
        if beforeSeq != 0 { dict["beforeSeq"] = beforeSeq }
        let data = try await connection.call(method: "history", body: try body(dict))
        struct Wrapper: Decodable { var entries: [Entry] }
        return try decode(Wrapper.self, from: data).entries
    }

    func send(botId: String, text: String, clientNonce: String, taskId: String? = nil,
              attachments: [String]? = nil, replyTo: String? = nil) async throws -> Entry {
        var dict: [String: Any] = ["botId": botId, "text": text, "clientNonce": clientNonce]
        if let taskId {
            // Dual-name (§10 D3): live host 2.50.0 reads `itemId`.
            dict["taskId"] = taskId
            dict["itemId"] = taskId
        }
        if let attachments { dict["attachments"] = attachments }
        if let replyTo { dict["replyTo"] = replyTo }
        let data = try await connection.call(method: "send", body: try body(dict))
        return try okEntry(from: data)
    }

    func stop(botId: String) async throws {
        _ = try await connection.call(method: "stop", body: try body(["botId": botId]))
    }

    /// Stops the bot's work: every live task, or just `taskId`.
    func stopWork(botId: String, taskId: String? = nil) async throws {
        var dict: [String: Any] = ["botId": botId]
        if let taskId { dict["taskId"] = taskId }
        _ = try await connection.call(method: "stopWork", body: try body(dict))
    }

    /// A work action: "workFirst", "dropWork" or "retryWork".
    func work(method: String, botId: String, taskId: String) async throws {
        _ = try await connection.call(method: method, body: try body(["botId": botId, "taskId": taskId]))
    }

    /// Cuts `taskId` in ahead of `insteadOf`'s task.
    func workCutIn(botId: String, taskId: String, insteadOf: String) async throws {
        _ = try await connection.call(method: "workCutIn", body: try body(["botId": botId, "taskId": taskId, "insteadOf": insteadOf]))
    }

    func markRead(botId: String) async throws {
        _ = try await connection.call(method: "markRead", body: try body(["botId": botId]))
    }

    func respondPermission(entryId: String, optionId: String?) async throws {
        var dict: [String: Any] = ["entryId": entryId]
        dict["optionId"] = optionId ?? NSNull()
        _ = try await connection.call(method: "respondPermission", body: try body(dict))
    }

    func respondDecision(entryId: String, option: String) async throws {
        _ = try await connection.call(method: "respondDecision", body: try body(["entryId": entryId, "option": option]))
    }

    func createBot(draft: BotDraft) async throws -> Bot {
        let data = try await connection.call(method: "createBot", body: try body(draft.jsonDictionary(forUpdate: false)))
        return try okBot(from: data)
    }

    func updateBot(draft: BotDraft) async throws -> Bot {
        let data = try await connection.call(method: "updateBot", body: try body(draft.jsonDictionary(forUpdate: true)))
        return try okBot(from: data)
    }

    func deleteBot(botId: String) async throws {
        _ = try await connection.call(method: "deleteBot", body: try body(["botId": botId]))
    }

    func setLead(botId: String) async throws {
        _ = try await connection.call(method: "setLead", body: try body(["botId": botId]))
    }

    func setSection(botId: String, section: String?) async throws {
        var dict: [String: Any] = ["botId": botId]
        dict["section"] = section ?? NSNull()
        _ = try await connection.call(method: "updateBot", body: try body(dict))
    }

    /// Uploads one file in 384 KiB chunks; `data` here is standard padded
    /// base64 (inner-RPC rule), unlike channel `d`. Returns the upload id.
    func upload(botId: String, name: String, data: Data) async throws -> String {
        let uploadId = UUID().uuidString
        let chunkSize = 384 * 1024
        var offset = 0
        repeat {
            let end = min(offset + chunkSize, data.count)
            let chunk = data[offset..<end]
            let done = end == data.count
            let dict: [String: Any] = [
                "botId": botId,
                "uploadId": uploadId,
                "name": name,
                "data": chunk.base64EncodedString(),
                "offset": offset,
                "done": done,
            ]
            _ = try await connection.call(method: "upload", body: try body(dict), timeout: 60)
            offset = end
        } while offset < data.count
        return uploadId
    }

    /// Pages a sent file back. Phase 1 uses it only to re-display sent files.
    func readUpload(botId: String, uploadId: String, offset: Int) async throws -> (data: Data, size: Int) {
        let data = try await connection.call(method: "readUpload", body: try body(["botId": botId, "uploadId": uploadId, "offset": offset]))
        struct Wrapper: Decodable { var data: String; var size: Int }
        let wrapper = try decode(Wrapper.self, from: data)
        return (Data(base64Encoded: wrapper.data) ?? Data(), wrapper.size)
    }

    /// The events subscription, mapped to decoded `HostEvent`s. One per
    /// connection; resubscribe from the persisted `rev` on every reconnect.
    func events(since: Int64) async -> AsyncThrowingStream<HostEvent, Error> {
        let raw = await connection.stream(.events(since: since, client: "ios"))
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await data in raw {
                        continuation.yield(HostEvent.parse(data))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
