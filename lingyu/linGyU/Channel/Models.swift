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
    /// The agent backends on this computer (`hello` carries them; there
    /// is no standalone `backends` method). Nil from a host that
    /// doesn't name them — the Extensions page then shows its
    /// disabled state instead of inventing agents.
    var backends: [Backend]?
    /// Whether a signed-in phone may offer to bring this computer
    /// into its account (`joinAccount`). Nil from an older host.
    var canJoinAccount: Bool?

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
        backends = container.lenient([Backend].self, forKey: .backends)
        canJoinAccount = container.lenient(Bool.self, forKey: .canJoinAccount)
    }
}

// MARK: - Backend

/// One agent backend on the computer (`hello.backends`): its install
/// and sign-in state, and its login profiles. Only the fields the
/// Extensions page shows; everything decodes leniently.
struct Backend: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var available: Bool
    var command: String
    var installHint: String
    /// ACP registry id, for the agent's icon.
    var registry: String?
    var description: String?
    var installed: Bool?
    /// Known by name: it can install and sign in to it.
    var curated: Bool?
    /// Missing when the host can't tell.
    var signedIn: Bool?
    var canInstall: Bool?
    /// Only for an agent that runs on Node.js, on a computer without its own.
    var node: String?
    var loginProfiles: [BackendLoginProfile]?
    var defaultLoginProfile: BackendDefaultLogin?
    var loginProfileSignIn: String?
    /// The variable names its API key usually goes in, to start a key form with.
    var loginKeys: [String]?

    /// It can't run until Node.js is added to the computer.
    var needsNode: Bool { node == "missing" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, forKey: .id) ?? ""
        name = container.lenient(String.self, forKey: .name) ?? ""
        available = container.lenient(Bool.self, forKey: .available) ?? false
        command = container.lenient(String.self, forKey: .command) ?? ""
        installHint = container.lenient(String.self, forKey: .installHint) ?? ""
        registry = container.lenient(String.self, forKey: .registry)
        description = container.lenient(String.self, forKey: .description)
        installed = container.lenient(Bool.self, forKey: .installed)
        curated = container.lenient(Bool.self, forKey: .curated)
        signedIn = container.lenient(Bool.self, forKey: .signedIn)
        canInstall = container.lenient(Bool.self, forKey: .canInstall)
        node = container.lenient(String.self, forKey: .node)
        loginProfiles = container.lenient([BackendLoginProfile].self, forKey: .loginProfiles)
        defaultLoginProfile = container.lenient(BackendDefaultLogin.self, forKey: .defaultLoginProfile)
        loginProfileSignIn = container.lenient(String.self, forKey: .loginProfileSignIn)
        loginKeys = container.lenient([String].self, forKey: .loginKeys)
    }
}

struct BackendLoginProfile: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String?
    var kind: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, forKey: .id) ?? ""
        name = container.lenient(String.self, forKey: .name)
        kind = container.lenient(String.self, forKey: .kind)
    }
}

struct BackendDefaultLogin: Codable, Hashable, Sendable {
    var name: String?
    var label: String?
    var email: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.lenient(String.self, forKey: .name)
        label = container.lenient(String.self, forKey: .label)
        email = container.lenient(String.self, forKey: .email)
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
    /// View card payload (kind "view", FishPocket `show_view`).
    /// Nil on every host that has no view cards — codync-host 2.51.0
    /// has none (probe 2026-11-22: `view-reply` → 404 unknown method).
    var view: ViewCardPayload?
    /// Learning proposal payload (kind "learning", FishPocket
    /// `learning-answer`). Nil likewise; same probe: 404 unknown method.
    var learning: LearningProposal?
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
        view = container.lenient(ViewCardPayload.self, forKey: .view)
        learning = container.lenient(LearningProposal.self, forKey: .learning)
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
        view = nil; learning = nil
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
        case "user", "permission", "view", "learning":
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

// MARK: - Routines

/// One scheduled task (Codync Routine.swift): a name, an instruction the
/// bot runs, and one or more triggers. Decoded leniently like the other
/// models: an unknown field never fails the whole listing.
struct Routine: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var botId: String
    var name: String
    var instruction: String
    var triggers: [RoutineTrigger]
    var enabled: Bool
    var createdAt: Int64
    var updatedAt: Int64
    var triggerDescriptions: [String]
    var nextRunAt: Int64?
    var timeoutSeconds: Int?
    var lastError: String?

    var nextRunDate: Date? {
        nextRunAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
    }

    init(id: String, botId: String, name: String, instruction: String,
         triggers: [RoutineTrigger] = [], enabled: Bool = true,
         createdAt: Int64 = 0, updatedAt: Int64 = 0,
         triggerDescriptions: [String] = [], nextRunAt: Int64? = nil,
         timeoutSeconds: Int? = nil, lastError: String? = nil) {
        self.id = id
        self.botId = botId
        self.name = name
        self.instruction = instruction
        self.triggers = triggers
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.triggerDescriptions = triggerDescriptions
        self.nextRunAt = nextRunAt
        self.timeoutSeconds = timeoutSeconds
        self.lastError = lastError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, forKey: .id) ?? ""
        botId = container.lenient(String.self, forKey: .botId) ?? ""
        name = container.lenient(String.self, forKey: .name) ?? ""
        instruction = container.lenient(String.self, forKey: .instruction) ?? ""
        triggers = container.lenient([RoutineTrigger].self, forKey: .triggers) ?? []
        enabled = container.lenient(Bool.self, forKey: .enabled) ?? true
        createdAt = container.lenient(Int64.self, forKey: .createdAt) ?? 0
        updatedAt = container.lenient(Int64.self, forKey: .updatedAt) ?? 0
        triggerDescriptions = container.lenient([String].self, forKey: .triggerDescriptions) ?? []
        nextRunAt = container.lenient(Int64.self, forKey: .nextRunAt)
        timeoutSeconds = container.lenient(Int.self, forKey: .timeoutSeconds)
        lastError = container.lenient(String.self, forKey: .lastError)
    }
}

/// One trigger of a routine. `type` is "interval" | "once" | "cron" |
/// "webhook" | "event" (live host 2.51.0 rejects "at": the one-off
/// variant is "once"). Only the fields the type uses are set: `seconds`
/// for interval, `at` for a one-off time, `expression` for cron, `event`
/// + `filters` for events.
struct RoutineTrigger: Codable, Equatable, Sendable {
    var type: String
    var seconds: Int64?
    var at: Int64?
    var expression: String?
    var timeZone: String?
    var source: String?
    var event: String?
    var filters: [String: String]?

    init(type: String, seconds: Int64? = nil, at: Int64? = nil,
         expression: String? = nil, timeZone: String? = nil,
         source: String? = nil, event: String? = nil,
         filters: [String: String]? = nil) {
        self.type = type
        self.seconds = seconds
        self.at = at
        self.expression = expression
        self.timeZone = timeZone
        self.source = source
        self.event = event
        self.filters = filters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = container.lenient(String.self, forKey: .type) ?? ""
        seconds = container.lenient(Int64.self, forKey: .seconds)
        at = container.lenient(Int64.self, forKey: .at)
        expression = container.lenient(String.self, forKey: .expression)
        timeZone = container.lenient(String.self, forKey: .timeZone)
        source = container.lenient(String.self, forKey: .source)
        event = container.lenient(String.self, forKey: .event)
        filters = container.lenient([String: String].self, forKey: .filters)
    }
}

/// One execution of a routine. A retry of a run that failed before acting
/// waits until `notBefore`.
struct RoutineRun: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var routineId: String
    var botId: String
    var status: String
    var createdAt: Int64
    var finishedAt: Int64?
    var detail: String?
    var notBefore: Int64?

    var isActive: Bool {
        ["pending", "starting", "running", "recovering"].contains(status)
    }

    var isFailed: Bool { status == "failed" || status == "interrupted" }

    /// The delivered text of a finished run (live host 2.51.0 puts the
    /// run's result here; `detail` is usually null).
    var result: String?

    init(id: String, routineId: String, botId: String, status: String,
         createdAt: Int64 = 0, finishedAt: Int64? = nil,
         detail: String? = nil, notBefore: Int64? = nil, result: String? = nil) {
        self.id = id
        self.routineId = routineId
        self.botId = botId
        self.status = status
        self.createdAt = createdAt
        self.finishedAt = finishedAt
        self.detail = detail
        self.notBefore = notBefore
        self.result = result
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, forKey: .id) ?? ""
        routineId = container.lenient(String.self, forKey: .routineId) ?? ""
        botId = container.lenient(String.self, forKey: .botId) ?? ""
        status = container.lenient(String.self, forKey: .status) ?? ""
        createdAt = container.lenient(Int64.self, forKey: .createdAt) ?? 0
        finishedAt = container.lenient(Int64.self, forKey: .finishedAt)
        detail = container.lenient(String.self, forKey: .detail)
        notBefore = container.lenient(Int64.self, forKey: .notBefore)
        result = container.lenient(String.self, forKey: .result)
    }
}

/// A deadline a bot set for itself: one later turn in its own chat, then
/// it is gone.
struct FollowUp: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var botId: String
    /// When it is due (Unix ms).
    var at: Int64
    var note: String
    var createdAt: Int64

    init(id: String, botId: String, at: Int64, note: String, createdAt: Int64 = 0) {
        self.id = id
        self.botId = botId
        self.at = at
        self.note = note
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, forKey: .id) ?? ""
        botId = container.lenient(String.self, forKey: .botId) ?? ""
        at = container.lenient(Int64.self, forKey: .at) ?? 0
        note = container.lenient(String.self, forKey: .note) ?? ""
        createdAt = container.lenient(Int64.self, forKey: .createdAt) ?? 0
    }
}

/// Everything `routines {botId}` returns: the routines, their recent
/// runs, and the follow-ups still waiting (nil on a host from before
/// follow-ups).
struct RoutineListing: Codable, Sendable {
    var routines: [Routine]
    var runs: [RoutineRun]
    var followUps: [FollowUp]?

    init(routines: [Routine] = [], runs: [RoutineRun] = [], followUps: [FollowUp]? = []) {
        self.routines = routines
        self.runs = runs
        self.followUps = followUps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        routines = container.lenient([Routine].self, forKey: .routines) ?? []
        runs = container.lenient([RoutineRun].self, forKey: .runs) ?? []
        followUps = container.lenient([FollowUp].self, forKey: .followUps)
    }
}

/// A routine's webhook: `url` is public through the cloud (nil while the
/// cloud is off), `localUrl` works on the host itself.
struct RoutineWebhook: Codable, Equatable, Sendable {
    var url: String?
    var localUrl: String
    var key: String
    var connected: Bool
    var needsAccount: Bool?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = container.lenient(String.self, forKey: .url)
        localUrl = container.lenient(String.self, forKey: .localUrl) ?? ""
        key = container.lenient(String.self, forKey: .key) ?? ""
        connected = container.lenient(Bool.self, forKey: .connected) ?? false
        needsAccount = container.lenient(Bool.self, forKey: .needsAccount)
    }
}

// MARK: - View card + learning proposal (FishPocket show_view / learning; Phase 4, agent F)
//
// Appended only — no existing model above was changed. Both payloads ride
// on `EntryData.view` / `EntryData.learning` (new optional fields, nil on
// hosts without them). codync-host 2.51.0 has neither: its EntryKind is
// only user/agent/thought/tool/plan/permission/notice
// (host/src/store/model.rs), `view-reply`, `dismiss-view` and
// `learning-answer` all answer 404 "unknown method" on the live host
// (probe 2026-11-22, /tmp/agent-f-probe.py), and the preview bot's own
// tool search finds no `show_view` tool. Until a host gains them, the
// cards render from Preview seed data only, and every host-bound button
// is a disabled state with a reason (§1.6.4). Entry kinds are "view"
// and "learning" (defined here, since the host defines none); see
// phase4/agent-f/wiring-notes.md for the ChatView wiring.

extension JSONValue {
    /// Numeric view of a JSON value (for formulas and charts): ints and
    /// doubles as-is, numeric strings parsed, anything else nil.
    var asDouble: Double? {
        switch self {
        case .int(let value): return Double(value)
        case .double(let value): return value
        case .string(let value): return Double(value)
        default: return nil
        }
    }

    var asBool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var asString: String? {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value): return DeepViewNumber.format(value)
        case .bool(let value): return value ? L("是") : L("否")
        default: return nil
        }
    }

    /// The values of an array value, or nil.
    var asArray: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }
}

extension Entry {
    /// A view card entry: kind "view" with a payload.
    var isViewCard: Bool { kind == "view" && data.view != nil }
    /// A learning proposal entry: kind "learning" with a payload.
    var isLearningCard: Bool { kind == "learning" && data.learning != nil }
}

/// Number formatting shared by formulas, metrics and charts: `%g`
/// (1240, not 1240.0; 0.5, not 0.500000).
enum DeepViewNumber {
    static func format(_ value: Double) -> String {
        if value.isNaN || value.isInfinite { return "" }
        if value.truncatingRemainder(dividingBy: 1) == 0, abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(format: "%g", value)
    }
}

/// One deep-view node (`{type, ...}`), decoded leniently: an unknown
/// field or a mistyped node never fails the whole card — the node renders
/// as its text, or not at all.
struct DeepViewNode: Codable, Equatable, Sendable {
    var type: String
    /// Chart kind for `chart` nodes (`line` / `bar` / `donut` / ...).
    var kind: String?
    var label: String?
    var text: String?
    var title: String?
    var detail: String?
    var placeholder: String?
    var html: String?
    var unit: String?
    var tone: String?
    /// Literal value, or a formula object `{"=": "a + b"}`.
    var value: JSONValue?
    var children: [DeepViewNode]?
    var columns: [String]?
    var rows: [[JSONValue]]?
    var series: [DeepViewSeries]?
    var labels: [String]?
    var options: [DeepViewOption]?
    var fields: [DeepViewField]?
    var sources: [DeepViewSource]?
    var min: Double?
    var max: Double?
    var step: Double?
    var readonly: Bool?
    var multiline: Bool?
    var action: String?

    init(type: String) {
        self.type = type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = container.lenient(String.self, forKey: .type) ?? "text"
        kind = container.lenient(String.self, forKey: .kind)
        label = container.lenient(String.self, forKey: .label)
        text = container.lenient(String.self, forKey: .text)
        title = container.lenient(String.self, forKey: .title)
        detail = container.lenient(String.self, forKey: .detail)
        placeholder = container.lenient(String.self, forKey: .placeholder)
        html = container.lenient(String.self, forKey: .html)
        unit = container.lenient(String.self, forKey: .unit)
        tone = container.lenient(String.self, forKey: .tone)
        value = container.lenient(JSONValue.self, forKey: .value)
        children = container.lenient([DeepViewNode].self, forKey: .children)
        columns = container.lenient([String].self, forKey: .columns)
        rows = container.lenient([[JSONValue]].self, forKey: .rows)
        series = container.lenient([DeepViewSeries].self, forKey: .series)
        labels = container.lenient([String].self, forKey: .labels)
        options = container.lenient([DeepViewOption].self, forKey: .options)
        fields = container.lenient([DeepViewField].self, forKey: .fields)
        sources = container.lenient([DeepViewSource].self, forKey: .sources)
        min = container.lenient(Double.self, forKey: .min)
        max = container.lenient(Double.self, forKey: .max)
        step = container.lenient(Double.self, forKey: .step)
        readonly = container.lenient(Bool.self, forKey: .readonly)
        multiline = container.lenient(Bool.self, forKey: .multiline)
        action = container.lenient(String.self, forKey: .action)
    }

    /// The node's display text: literal text/value, or a formula
    /// evaluated against the current form values. A formula that cannot
    /// be computed shows its source text, never a crash or a blank.
    func displayText(values: [String: JSONValue]) -> String {
        if let value {
            return DeepViewValue.display(value, values: values)
        }
        return text ?? label ?? title ?? ""
    }

    /// True when the node's value is a formula object.
    var isFormula: Bool {
        if case .object(let dict) = value, dict["="] != nil { return true }
        return false
    }
}

/// One chart series: a label and one number per x label.
struct DeepViewSeries: Codable, Equatable, Sendable {
    var label: String
    /// Raw values (numbers or numeric strings); non-numeric entries
    /// become 0 when drawn, so a bad cell cannot break the chart.
    var values: [JSONValue]

    var numbers: [Double] { values.map { $0.asDouble ?? 0 } }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = container.lenient(String.self, forKey: .label) ?? ""
        values = container.lenient([JSONValue].self, forKey: .values) ?? []
    }
}

/// One option of an `options` / `choice` node: a label row plus an
/// optional description line underneath.
struct DeepViewOption: Codable, Equatable, Sendable, Identifiable {
    var label: String
    var detail: String?
    var value: String?
    var selected: Bool

    var id: String { value ?? label }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = container.lenient(String.self, forKey: .label) ?? ""
        detail = container.lenient(String.self, forKey: .detail)
            ?? container.lenient(String.self, forKey: .description)
        value = container.lenient(String.self, forKey: .value)
        selected = container.lenient(Bool.self, forKey: .selected) ?? false
    }

    /// `description` is a decode-only alias for `detail`, so encode is
    /// manual: the synthesized one would demand a `description` property.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(label, forKey: .label)
        try container.encodeIfPresent(detail, forKey: .detail)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encode(selected, forKey: .selected)
    }

    private enum CodingKeys: String, CodingKey {
        case label, detail, description, value, selected
    }
}

/// One field of a `form` node. `id` falls back to `key`, then `label`.
struct DeepViewField: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var type: String
    var label: String
    var value: JSONValue?
    var readonly: Bool
    var placeholder: String?
    var min: Double?
    var max: Double?
    var step: Double?
    var options: [DeepViewOption]?
    var multiline: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawId = container.lenient(String.self, forKey: .id)
            ?? container.lenient(String.self, forKey: .key)
        label = container.lenient(String.self, forKey: .label) ?? ""
        id = rawId ?? label
        type = container.lenient(String.self, forKey: .type) ?? "text"
        value = container.lenient(JSONValue.self, forKey: .value)
        readonly = container.lenient(Bool.self, forKey: .readonly) ?? false
        placeholder = container.lenient(String.self, forKey: .placeholder)
        min = container.lenient(Double.self, forKey: .min)
        max = container.lenient(Double.self, forKey: .max)
        step = container.lenient(Double.self, forKey: .step)
        options = container.lenient([DeepViewOption].self, forKey: .options)
        multiline = container.lenient(Bool.self, forKey: .multiline) ?? false
    }

    /// `key` is a decode-only alias for `id`, so encode is manual: the
    /// synthesized one would demand a `key` property.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(label, forKey: .label)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encode(readonly, forKey: .readonly)
        try container.encodeIfPresent(placeholder, forKey: .placeholder)
        try container.encodeIfPresent(min, forKey: .min)
        try container.encodeIfPresent(max, forKey: .max)
        try container.encodeIfPresent(step, forKey: .step)
        try container.encodeIfPresent(options, forKey: .options)
        try container.encode(multiline, forKey: .multiline)
    }

    private enum CodingKeys: String, CodingKey {
        case id, key, type, label, value, readonly, placeholder
        case min, max, step, options, multiline
    }
}

/// One entry of a `sources` node.
struct DeepViewSource: Codable, Equatable, Sendable, Identifiable {
    var title: String
    var url: String?

    var id: String { title + (url ?? "") }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = container.lenient(String.self, forKey: .title) ?? ""
        url = container.lenient(String.self, forKey: .url)
    }
}

/// A view card: `{id, title, view}` (FishPocket `team["views"]` shape).
struct ViewCardPayload: Codable, Equatable, Sendable {
    var id: String
    var title: String
    var view: DeepViewNode

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, forKey: .id) ?? ""
        title = container.lenient(String.self, forKey: .title) ?? L("视图")
        view = container.lenient(DeepViewNode.self, forKey: .view) ?? DeepViewNode(type: "stack")
    }
}

/// A learning proposal (FishPocket `live["learning"]`): a skill the
/// bot taught itself, or a change to the folder's AGENTS.md.
/// `kind` is "skill" or "agents".
struct LearningProposal: Codable, Equatable, Sendable {
    var id: String
    var kind: String
    var title: String
    var summary: String?
    var target: String?
    var preview: String?
    var diff: String?

    /// The preview body, capped by the card at 220pt.
    var previewText: String { diff ?? preview ?? summary ?? "" }

    var isAgentsChange: Bool { kind == "agents" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, forKey: .id) ?? ""
        kind = container.lenient(String.self, forKey: .kind) ?? "skill"
        title = container.lenient(String.self, forKey: .title) ?? ""
        summary = container.lenient(String.self, forKey: .summary)
        target = container.lenient(String.self, forKey: .target)
        preview = container.lenient(String.self, forKey: .preview)
        diff = container.lenient(String.self, forKey: .diff)
    }
}

/// Value display + formula evaluation for deep-view nodes. Formulas are
/// only `+ - * / ( )` and field references (bare `name` or `{name}`);
/// anything else — unknown field, non-numeric input, divide by zero,
/// bad syntax — evaluates to nil and the caller shows the source text.
enum DeepViewValue {
    static func display(_ value: JSONValue, values: [String: JSONValue]) -> String {
        if case .object(let dict) = value, let raw = dict["="]?.asString {
            if let result = FormulaEvaluator.evaluate(raw, values: values) {
                return DeepViewNumber.format(result)
            }
            return raw
        }
        return value.asString ?? ""
    }

    /// The numeric value of a node value (literal or computed formula),
    /// for charts, metrics and progress bars.
    static func number(_ value: JSONValue?, values: [String: JSONValue]) -> Double? {
        guard let value else { return nil }
        if case .object(let dict) = value, let raw = dict["="]?.asString {
            return FormulaEvaluator.evaluate(raw, values: values)
        }
        return value.asDouble
    }
}

enum FormulaEvaluator {
    /// Evaluates `expr` with field values taken from `values` (numeric
    /// fields only). Returns nil on any failure — the caller shows the
    /// source text instead.
    static func evaluate(_ expr: String, values: [String: JSONValue]) -> Double? {
        var numbers: [String: Double] = [:]
        for (key, value) in values {
            if let number = value.asDouble { numbers[key] = number }
        }
        var parser = Parser(expr, numbers: numbers)
        guard let result = parser.parseExpression(), parser.atEnd else { return nil }
        guard result.isFinite else { return nil }
        return result
    }

    private struct Parser {
        private var tokens: [Token]
        private var index = 0
        private var numbers: [String: Double]

        init(_ expr: String, numbers: [String: Double]) {
            self.numbers = numbers
            self.tokens = Self.tokenize(expr)
        }

        private enum Token: Equatable {
            case number(Double)
            case name(String)
            case op(Character)
            case lparen
            case rparen
        }

        private static func tokenize(_ expr: String) -> [Token] {
            var out: [Token] = []
            let chars = Array(expr)
            var i = 0
            while i < chars.count {
                let ch = chars[i]
                if ch.isWhitespace { i += 1; continue }
                if ch.isNumber || ch == "." {
                    var j = i
                    var seenDot = false
                    while j < chars.count, chars[j].isNumber || chars[j] == "." {
                        if chars[j] == "." {
                            if seenDot { break }
                            seenDot = true
                        }
                        j += 1
                    }
                    if let number = Double(String(chars[i..<j])) { out.append(.number(number)) }
                    i = j
                    continue
                }
                if ch == "{" {
                    var j = i + 1
                    while j < chars.count, chars[j] != "}" { j += 1 }
                    let name = String(chars[(i + 1)..<min(j, chars.count)])
                        .trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { out.append(.name(name)) }
                    i = min(j + 1, chars.count)
                    continue
                }
                if ch.isLetter || ch == "_" {
                    var j = i
                    while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" { j += 1 }
                    out.append(.name(String(chars[i..<j])))
                    i = j
                    continue
                }
                if "+-*/".contains(ch) { out.append(.op(ch)); i += 1; continue }
                if ch == "(" { out.append(.lparen); i += 1; continue }
                if ch == ")" { out.append(.rparen); i += 1; continue }
                // Any other character makes the whole expression invalid.
                return []
            }
            return out
        }

        var atEnd: Bool { index >= tokens.count }

        mutating func parseExpression() -> Double? {
            guard var result = parseTerm() else { return nil }
            while index < tokens.count, case .op(let ch) = tokens[index], ch == "+" || ch == "-" {
                index += 1
                guard let rhs = parseTerm() else { return nil }
                result = ch == "+" ? result + rhs : result - rhs
            }
            return result
        }

        private mutating func parseTerm() -> Double? {
            guard var result = parseFactor() else { return nil }
            while index < tokens.count, case .op(let ch) = tokens[index], ch == "*" || ch == "/" {
                index += 1
                guard let rhs = parseFactor() else { return nil }
                if ch == "*" { result *= rhs } else {
                    guard rhs != 0 else { return nil }
                    result /= rhs
                }
            }
            return result
        }

        private mutating func parseFactor() -> Double? {
            guard index < tokens.count else { return nil }
            switch tokens[index] {
            case .number(let value):
                index += 1
                return value
            case .name(let name):
                index += 1
                return numbers[name]
            case .op("-"):
                index += 1
                guard let value = parseFactor() else { return nil }
                return -value
            case .lparen:
                index += 1
                guard let value = parseExpression() else { return nil }
                guard index < tokens.count, tokens[index] == .rparen else { return nil }
                index += 1
                return value
            default:
                return nil
            }
        }
    }
}
