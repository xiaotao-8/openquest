import CryptoKit
import Foundation

// MARK: - Lenient decoding

/// A JSON value stored opaquely (custom icons, agent steps, unmodelled blobs).
enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Int64.self) { self = .int(value); return }
        if let value = try? container.decode(Double.self) { self = .double(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([JSONValue].self) { self = .array(value); return }
        if let value = try? container.decode([String: JSONValue].self) { self = .object(value); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

extension KeyedDecodingContainer {
    /// Decodes a field leniently: absent, null, or wrong-typed all yield nil
    /// instead of failing the whole object.
    func lenient<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)).flatMap { $0 }
    }
}

// MARK: - Computer

struct Computer: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var signKey: String
    var boxKey: String?
    var urls: [String]
    var cloud: String?
    var device: String?
    var color: String?
    var route: String?
    var notifications: Bool?

    var signKeyData: Data { Base64URL.decode(signKey) ?? Data() }
    var boxKeyData: Data? { boxKey.flatMap(Base64URL.decode) }

    /// computerId is b64url(SHA-256(signKey)[0..16]) — 22 chars (§8.2).
    static func computerId(forSignKey signKey: Data) -> String {
        ChannelCrypto.computerId(hostSignPub: signKey)
    }

    init(from link: PairingLink) {
        id = link.computerId
        name = link.name
        signKey = Base64URL.encode(link.signKey)
        boxKey = Base64URL.encode(link.boxKey)
        urls = link.urls
        cloud = link.cloud
        device = nil
        color = nil
        route = nil
        notifications = nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, forKey: .id) ?? ""
        name = container.lenient(String.self, forKey: .name) ?? L("我的电脑")
        signKey = container.lenient(String.self, forKey: .signKey) ?? ""
        boxKey = container.lenient(String.self, forKey: .boxKey)
        urls = container.lenient([String].self, forKey: .urls) ?? []
        cloud = container.lenient(String.self, forKey: .cloud)
        device = container.lenient(String.self, forKey: .device)
        color = container.lenient(String.self, forKey: .color)
        route = container.lenient(String.self, forKey: .route)
        notifications = container.lenient(Bool.self, forKey: .notifications)
    }
}

// MARK: - Cloud computer
//
// A computer rented from the account's cloud service (as opposed to a
// computer the user paired themselves). It is listed, never paired with a
// code: connecting one needs the account sign-in, which is a later phase.
// The record is display-only data — no live state is invented for it.

struct CloudComputer: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var region: String
    var botCount: Int

    /// The account allows at most this many cloud computers.
    static let accountLimit = 3
}

// MARK: - HelloReply

struct HelloReply: Codable, Sendable {
    var hostId: String
    var computerId: String?
    var signKey: String?
    var boxKey: String?
    var cloud: String?
    var name: String
    var version: String
    var minApp: String?
    var schema: Int
    var os: String?
    var device: String?
    var home: String?
    var rev: Int64
    var urls: [String]
    var canUpdate: Bool
    var latestVersion: String?
    var autoOrder: Bool?

    /// 2.51.0+ speaks thread names; older hosts speak task names (§10 D3).
    var speaksThreads: Bool {
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return true }
        if parts[0] != 2 { return parts[0] > 2 }
        return parts[1] >= 51
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hostId = container.lenient(String.self, forKey: .hostId) ?? ""
        computerId = container.lenient(String.self, forKey: .computerId)
        signKey = container.lenient(String.self, forKey: .signKey)
        boxKey = container.lenient(String.self, forKey: .boxKey)
        cloud = container.lenient(String.self, forKey: .cloud)
        name = container.lenient(String.self, forKey: .name) ?? L("我的电脑")
        version = container.lenient(String.self, forKey: .version) ?? ""
        minApp = container.lenient(String.self, forKey: .minApp)
        schema = container.lenient(Int.self, forKey: .schema) ?? 0
        os = container.lenient(String.self, forKey: .os)
        device = container.lenient(String.self, forKey: .device)
        home = container.lenient(String.self, forKey: .home)
        rev = container.lenient(Int64.self, forKey: .rev) ?? 0
        urls = container.lenient([String].self, forKey: .urls) ?? []
        canUpdate = container.lenient(Bool.self, forKey: .canUpdate) ?? false
        latestVersion = container.lenient(String.self, forKey: .latestVersion)
        autoOrder = container.lenient(Bool.self, forKey: .autoOrder)
    }
}

// MARK: - Bot

struct BotFallback: Codable, Equatable, Sendable {
    var backend: String
    var model: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        backend = container.lenient(String.self, forKey: .backend) ?? ""
        model = container.lenient(String.self, forKey: .model)
    }
}

struct WorkTaskWait: Codable, Equatable, Sendable {
    var kind: String
    var ahead: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = container.lenient(String.self, forKey: .kind) ?? ""
        ahead = container.lenient(Int.self, forKey: .ahead) ?? 0
    }
}

struct WorkTaskSource: Codable, Equatable, Sendable {
    var kind: String
    var id: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = container.lenient(String.self, forKey: .kind) ?? ""
        id = container.lenient(String.self, forKey: .id)
    }
}

struct WorkTask: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var status: String
    var activity: String
    var thread: ThreadRef?
    var wait: WorkTaskWait?
    var cutIn: Bool
    var createdAt: Int64
    var startedAt: Int64?
    var endedAt: Int64?
    var result: String?
    var source: WorkTaskSource?
    var worktree: JSONValue?
    var talk: Bool
    var folder: String?

    var isLive: Bool { status == "working" || status == "needsYou" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, forKey: .id) ?? ""
        title = container.lenient(String.self, forKey: .title) ?? ""
        status = container.lenient(String.self, forKey: .status) ?? ""
        activity = container.lenient(String.self, forKey: .activity) ?? ""
        thread = container.lenient(ThreadRef.self, forKey: .thread)
        wait = container.lenient(WorkTaskWait.self, forKey: .wait)
        cutIn = container.lenient(Bool.self, forKey: .cutIn) ?? false
        createdAt = container.lenient(Int64.self, forKey: .createdAt) ?? 0
        startedAt = container.lenient(Int64.self, forKey: .startedAt)
        endedAt = container.lenient(Int64.self, forKey: .endedAt)
        result = container.lenient(String.self, forKey: .result)
        source = container.lenient(WorkTaskSource.self, forKey: .source)
        worktree = container.lenient(JSONValue.self, forKey: .worktree)
        talk = container.lenient(Bool.self, forKey: .talk) ?? false
        folder = container.lenient(String.self, forKey: .folder)
    }
}

struct ThreadRef: Codable, Equatable, Sendable {
    var id: String
    var title: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, forKey: .id) ?? ""
        title = container.lenient(String.self, forKey: .title) ?? ""
    }
}

struct Bot: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var kind: String
    var members: [String]
    var name: String
    var description: String
    var avatarColor: String
    var avatarShape: String
    var customIcon: JSONValue?
    var backend: String
    var command: String?
    var loginProfile: String?
    var cwd: String
    var managedWorkspace: Bool
    var permission: String
    var mode: String?
    var model: String?
    var modelOptions: [String: String]
    var fastMode: Bool
    var fastModeSupport: String
    var fastModeIssue: String?
    var fallbacks: [BotFallback]?
    var selfFallbacks: Bool?
    var pinned: Bool
    var lead: Bool
    var position: Int
    var section: String?
    var hidden: Bool
    var notify: Bool?
    var connectors: [String]
    var skills: [String]
    var computer: Bool
    var manageTeam: Bool?
    var createdBy: String?
    var rev: Int64
    var status: String
    var activity: String
    var startedAt: Int64?
    var workingChat: String?
    var agentStep: JSONValue?
    var work: [WorkTask]
    var maxThreads: Int?
    var threadWorktrees: Bool?
    var unread: Int
    var waiting: Int
    var lastMessage: String?
    var lastAt: Int64
    var createdAt: Int64

    var isGroup: Bool { kind == "group" }
    var isWorking: Bool { status == "working" || status == "needsInput" }
    var needsInput: Bool { status == "needsInput" }
    var unseen: Int { max(0, unread - waiting) }

    /// Folder shown in the detail page: "Own folder" for managed workspaces,
    /// else the last path component of `cwd`.
    var folderDisplay: String {
        if managedWorkspace { return L("专属文件夹") }
        let trimmed = cwd.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.isEmpty { return L("专属文件夹") }
        return String(trimmed.split(separator: "/").last ?? Substring(L("专属文件夹")))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, forKey: .id) ?? ""
        kind = container.lenient(String.self, forKey: .kind) ?? "agent"
        members = container.lenient([String].self, forKey: .members) ?? []
        name = container.lenient(String.self, forKey: .name) ?? L("智能体")
        description = container.lenient(String.self, forKey: .description) ?? ""
        avatarColor = container.lenient(String.self, forKey: .avatarColor) ?? "blue"
        avatarShape = container.lenient(String.self, forKey: .avatarShape) ?? "blob"
        customIcon = container.lenient(JSONValue.self, forKey: .customIcon)
        backend = container.lenient(String.self, forKey: .backend) ?? "custom"
        command = container.lenient(String.self, forKey: .command)
        loginProfile = container.lenient(String.self, forKey: .loginProfile)
        cwd = container.lenient(String.self, forKey: .cwd) ?? ""
        managedWorkspace = container.lenient(Bool.self, forKey: .managedWorkspace) ?? false
        permission = container.lenient(String.self, forKey: .permission) ?? "ask"
        mode = container.lenient(String.self, forKey: .mode)
        model = container.lenient(String.self, forKey: .model)
        modelOptions = container.lenient([String: String].self, forKey: .modelOptions) ?? [:]
        fastMode = container.lenient(Bool.self, forKey: .fastMode) ?? false
        fastModeSupport = container.lenient(String.self, forKey: .fastModeSupport) ?? "unknown"
        fastModeIssue = container.lenient(String.self, forKey: .fastModeIssue)
        fallbacks = container.lenient([BotFallback].self, forKey: .fallbacks)
        selfFallbacks = container.lenient(Bool.self, forKey: .selfFallbacks)
        pinned = container.lenient(Bool.self, forKey: .pinned) ?? false
        lead = container.lenient(Bool.self, forKey: .lead) ?? false
        position = container.lenient(Int.self, forKey: .position) ?? 0
        section = container.lenient(String.self, forKey: .section)
        hidden = container.lenient(Bool.self, forKey: .hidden) ?? false
        notify = container.lenient(Bool.self, forKey: .notify)
        connectors = container.lenient([String].self, forKey: .connectors) ?? []
        skills = container.lenient([String].self, forKey: .skills) ?? []
        computer = container.lenient(Bool.self, forKey: .computer) ?? false
        manageTeam = container.lenient(Bool.self, forKey: .manageTeam)
        createdBy = container.lenient(String.self, forKey: .createdBy)
        rev = container.lenient(Int64.self, forKey: .rev) ?? 0
        status = container.lenient(String.self, forKey: .status) ?? "idle"
        activity = container.lenient(String.self, forKey: .activity) ?? ""
        startedAt = container.lenient(Int64.self, forKey: .startedAt)
        workingChat = container.lenient(String.self, forKey: .workingChat)
        agentStep = container.lenient(JSONValue.self, forKey: .agentStep)
        work = container.lenient([WorkTask].self, forKey: .work) ?? []
        // Dual-name: live host 2.50.0 sends maxAgents/taskWorktrees,
        // 2.51.0-era sends maxThreads/threadWorktrees.
        if let value = container.lenient(Int.self, forKey: .maxThreads) {
            maxThreads = value
        } else {
            maxThreads = container.lenient(Int.self, forKey: .maxAgents)
        }
        if let value = container.lenient(Bool.self, forKey: .threadWorktrees) {
            threadWorktrees = value
        } else {
            threadWorktrees = container.lenient(Bool.self, forKey: .taskWorktrees)
        }
        unread = container.lenient(Int.self, forKey: .unread) ?? 0
        waiting = container.lenient(Int.self, forKey: .waiting) ?? 0
        lastMessage = container.lenient(String.self, forKey: .lastMessage)
        lastAt = container.lenient(Int64.self, forKey: .lastAt) ?? 0
        createdAt = container.lenient(Int64.self, forKey: .createdAt) ?? 0
    }

    /// Explicit encode: synthesized Encodable is unavailable because
    /// CodingKeys also carries decode-only aliases (maxAgents,
    /// taskWorktrees) with no stored property behind them. Encodes only
    /// the canonical stored properties.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(members, forKey: .members)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(avatarColor, forKey: .avatarColor)
        try container.encode(avatarShape, forKey: .avatarShape)
        try container.encodeIfPresent(customIcon, forKey: .customIcon)
        try container.encode(backend, forKey: .backend)
        try container.encodeIfPresent(command, forKey: .command)
        try container.encodeIfPresent(loginProfile, forKey: .loginProfile)
        try container.encode(cwd, forKey: .cwd)
        try container.encode(managedWorkspace, forKey: .managedWorkspace)
        try container.encode(permission, forKey: .permission)
        try container.encodeIfPresent(mode, forKey: .mode)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encode(modelOptions, forKey: .modelOptions)
        try container.encode(fastMode, forKey: .fastMode)
        try container.encode(fastModeSupport, forKey: .fastModeSupport)
        try container.encodeIfPresent(fastModeIssue, forKey: .fastModeIssue)
        try container.encodeIfPresent(fallbacks, forKey: .fallbacks)
        try container.encodeIfPresent(selfFallbacks, forKey: .selfFallbacks)
        try container.encode(pinned, forKey: .pinned)
        try container.encode(lead, forKey: .lead)
        try container.encode(position, forKey: .position)
        try container.encodeIfPresent(section, forKey: .section)
        try container.encode(hidden, forKey: .hidden)
        try container.encodeIfPresent(notify, forKey: .notify)
        try container.encode(connectors, forKey: .connectors)
        try container.encode(skills, forKey: .skills)
        try container.encode(computer, forKey: .computer)
        try container.encodeIfPresent(manageTeam, forKey: .manageTeam)
        try container.encodeIfPresent(createdBy, forKey: .createdBy)
        try container.encode(rev, forKey: .rev)
        try container.encode(status, forKey: .status)
        try container.encode(activity, forKey: .activity)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(workingChat, forKey: .workingChat)
        try container.encodeIfPresent(agentStep, forKey: .agentStep)
        try container.encode(work, forKey: .work)
        try container.encodeIfPresent(maxThreads, forKey: .maxThreads)
        try container.encodeIfPresent(threadWorktrees, forKey: .threadWorktrees)
        try container.encode(unread, forKey: .unread)
        try container.encode(waiting, forKey: .waiting)
        try container.encodeIfPresent(lastMessage, forKey: .lastMessage)
        try container.encode(lastAt, forKey: .lastAt)
        try container.encode(createdAt, forKey: .createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, members, name, description, avatarColor, avatarShape, customIcon
        case backend, command, loginProfile, cwd, managedWorkspace, permission, mode, model
        case modelOptions, fastMode, fastModeSupport, fastModeIssue, fallbacks, selfFallbacks
        case pinned, lead, position, section, hidden, notify, connectors, skills, computer
        case manageTeam, createdBy, rev, status, activity, startedAt, workingChat, agentStep
        case work, maxThreads, maxAgents, threadWorktrees, taskWorktrees, unread, waiting
        case lastMessage, lastAt, createdAt
    }
}

// MARK: - Entry

struct PermissionOption: Codable, Equatable, Sendable {
    var optionId: String
    var name: String
    var kind: String

    init(optionId: String, name: String, kind: String) {
        self.optionId = optionId
        self.name = name
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        optionId = container.lenient(String.self, forKey: .optionId) ?? ""
        name = container.lenient(String.self, forKey: .name) ?? ""
        kind = container.lenient(String.self, forKey: .kind) ?? ""
    }
}

struct EntryDiff: Codable, Equatable, Sendable {
    var path: String
    var added: Int
    var removed: Int
    var isNew: Bool
    var startLine: Int?
    var patch: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = container.lenient(String.self, forKey: .path) ?? ""
        added = container.lenient(Int.self, forKey: .added) ?? 0
        removed = container.lenient(Int.self, forKey: .removed) ?? 0
        isNew = container.lenient(Bool.self, forKey: .isNew) ?? false
        startLine = container.lenient(Int.self, forKey: .startLine)
        patch = container.lenient(String.self, forKey: .patch)
    }
}

struct EntryLocation: Codable, Equatable, Sendable {
    var path: String
    var line: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = container.lenient(String.self, forKey: .path) ?? ""
        line = container.lenient(Int.self, forKey: .line)
    }
}

struct EntryAttachment: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var size: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, forKey: .id) ?? ""
        name = container.lenient(String.self, forKey: .name) ?? ""
        size = container.lenient(Int.self, forKey: .size) ?? 0
    }
}

struct ReplyQuote: Codable, Equatable, Sendable {
    var id: String
    var author: String?
    var text: String?
    var part: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, forKey: .id) ?? ""
        author = container.lenient(String.self, forKey: .author)
        text = container.lenient(String.self, forKey: .text)
        part = container.lenient(Bool.self, forKey: .part) ?? false
    }
}

struct HandoffInfo: Codable, Equatable, Sendable {
    var status: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = container.lenient(String.self, forKey: .status)
    }
}

struct EntryData: Codable, Equatable, Sendable {
    var text: String?
    var final: Bool?
    var status: String?
    var clientNonce: String?
    var title: String?
    var toolKind: String?
    var toolCallId: String?
    var command: String?
    var detail: String?
    var cwd: String?
    var output: String?
    var diffs: [EntryDiff]?
    var locations: [EntryLocation]?
    var options: [PermissionOption]?
    var decision: Bool?
    var question: String?
    var choices: [String]?
    var recommended: Int?
    var selected: String?
    var author: String?
    var replyTo: ReplyQuote?
    var reactions: [String]?
    var attachments: [EntryAttachment]?
    var files: [JSONValue]?
    var voiceNote: Bool?
    var call: String?
    var callSeconds: Int?
    var pasted: [String]?
    var from: String?
    var memory: JSONValue?
    var memoryFile: JSONValue?
    var compaction: JSONValue?
    var handoff: HandoffInfo?
    var routineId: String?
    var style: String?
    /// The thread this entry belongs to (work threads, `WorkThreadLine`).
    var thread: ThreadRef?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = container.lenient(String.self, forKey: .text)
        final = container.lenient(Bool.self, forKey: .final)
        status = container.lenient(String.self, forKey: .status)
        clientNonce = container.lenient(String.self, forKey: .clientNonce)
        title = container.lenient(String.self, forKey: .title)
        toolKind = container.lenient(String.self, forKey: .toolKind)
        toolCallId = container.lenient(String.self, forKey: .toolCallId)
        command = container.lenient(String.self, forKey: .command)
        detail = container.lenient(String.self, forKey: .detail)
        cwd = container.lenient(String.self, forKey: .cwd)
        output = container.lenient(String.self, forKey: .output)
        diffs = container.lenient([EntryDiff].self, forKey: .diffs)
        locations = container.lenient([EntryLocation].self, forKey: .locations)
        options = container.lenient([PermissionOption].self, forKey: .options)
        decision = container.lenient(Bool.self, forKey: .decision)
        question = container.lenient(String.self, forKey: .question)
        choices = container.lenient([String].self, forKey: .choices)
        recommended = container.lenient(Int.self, forKey: .recommended)
        selected = container.lenient(String.self, forKey: .selected)
        author = container.lenient(String.self, forKey: .author)
        replyTo = container.lenient(ReplyQuote.self, forKey: .replyTo)
        reactions = container.lenient([String].self, forKey: .reactions)
        attachments = container.lenient([EntryAttachment].self, forKey: .attachments)
        files = container.lenient([JSONValue].self, forKey: .files)
        voiceNote = container.lenient(Bool.self, forKey: .voiceNote)
        call = container.lenient(String.self, forKey: .call)
        callSeconds = container.lenient(Int.self, forKey: .callSeconds)
        pasted = container.lenient([String].self, forKey: .pasted)
        from = container.lenient(String.self, forKey: .from)
        memory = container.lenient(JSONValue.self, forKey: .memory)
        memoryFile = container.lenient(JSONValue.self, forKey: .memoryFile)
        compaction = container.lenient(JSONValue.self, forKey: .compaction)
        handoff = container.lenient(HandoffInfo.self, forKey: .handoff)
        routineId = container.lenient(String.self, forKey: .routineId)
        style = container.lenient(String.self, forKey: .style)
        thread = container.lenient(ThreadRef.self, forKey: .thread)
    }

    /// Empty data (used for locally-built entries).
    init() {
        text = nil; final = nil; status = nil; clientNonce = nil; title = nil
        toolKind = nil; toolCallId = nil; command = nil; detail = nil; cwd = nil
        output = nil; diffs = nil; locations = nil; options = nil; decision = nil
        question = nil; choices = nil; recommended = nil; selected = nil; author = nil
        replyTo = nil; reactions = nil; attachments = nil; files = nil; voiceNote = nil
        call = nil; callSeconds = nil; pasted = nil; from = nil; memory = nil
        memoryFile = nil; compaction = nil; handoff = nil; routineId = nil; style = nil
        thread = nil
    }
}

struct Entry: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var seq: Int64
    var botId: String
    var rev: Int64
    var kind: String
    var turn: Int64
    var data: EntryData
    var createdAt: Int64
    var updatedAt: Int64

    /// Whether the chat bubble list shows this entry (§6.4).
    var isChat: Bool {
        switch kind {
        case "user", "permission":
            return true
        case "notice":
            if data.memory != nil || data.memoryFile != nil || data.compaction != nil { return false }
            if data.handoff?.status == "kept" { return false }
            return true
        case "agent":
            return data.final == true
        default:
            return false
        }
    }

    var isReplyable: Bool {
        (kind == "user" || (kind == "agent" && data.final == true)) && !id.hasPrefix("local-")
    }

    /// Approval/decision cards waiting on the user.
    var isWaitingCard: Bool {
        (kind == "permission" || data.decision == true) && data.status == "pending"
    }

    /// Ask/choice card (question + 2–12 options).
    var isAskCard: Bool {
        kind == "permission" && data.question != nil && data.choices != nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, forKey: .id) ?? ""
        seq = container.lenient(Int64.self, forKey: .seq) ?? 0
        botId = container.lenient(String.self, forKey: .botId) ?? ""
        rev = container.lenient(Int64.self, forKey: .rev) ?? 0
        kind = container.lenient(String.self, forKey: .kind) ?? ""
        turn = container.lenient(Int64.self, forKey: .turn) ?? 0
        data = container.lenient(EntryData.self, forKey: .data) ?? EntryData()
        createdAt = container.lenient(Int64.self, forKey: .createdAt) ?? 0
        updatedAt = container.lenient(Int64.self, forKey: .updatedAt) ?? 0
    }

    /// Local optimistic user entry (id starts with "local-", never a host row).
    init(localText text: String, botId: String, clientNonce: String) {
        id = "local-\(clientNonce)"
        seq = 0
        self.botId = botId
        rev = 0
        kind = "user"
        turn = 0
        var data = EntryData()
        data.text = text
        data.clientNonce = clientNonce
        data.status = "sending"
        self.data = data
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        createdAt = now
        updatedAt = now
    }
}
