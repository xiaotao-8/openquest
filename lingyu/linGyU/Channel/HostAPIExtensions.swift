import Foundation

/// Wire models + typed wrappers for the marketplace / usage / network
/// methods (Phase 3, agent D). Shapes mirror the original's
/// `Market.swift` / `Models.swift` (Usage, UsageProvider, UsageWindow,
/// UsageService) and the live host 2.51.0, probed 2026-11-22:
/// `usage`, `networkView`, `skills`, `marketSkills`, `agentModels`,
/// `agentGear`, `setUsageShown`, `setUsageOrder` answer; `connectors`,
/// `marketConnectors`, `installConnector`, `removeConnector` exist but
/// fail on this host while its credential storage is locked
/// ("Secure credential storage is locked or unavailable");
/// `networkStatus` and the other `network*` verbs are loopback-only
/// (403 from a phone) — only `networkView` is readable remotely.
/// Every field decodes leniently: a host that omits or mistypes one
/// must not fail the whole reply.

// MARK: - Usage

/// One computer's usage: per-provider limit windows plus the agents
/// the Usage screen can show or hide. `services` is absent from a
/// host older than the chooser.
struct Usage: Codable, Sendable {
    var providers: [UsageProvider]
    var services: [UsageService]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providers = container.lenient([UsageProvider].self, forKey: .providers) ?? []
        services = container.lenient([UsageService].self, forKey: .services)
    }

    private enum CodingKeys: String, CodingKey { case providers, services }
}

/// An agent the Usage screen can show or hide. The host keeps the
/// choice, so every app follows it.
struct UsageService: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var shown: Bool
    /// The agent's ACP registry id, which its logo goes by. Without one, its `id`.
    var registry: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, forKey: .id) ?? ""
        name = container.lenient(String.self, forKey: .name) ?? ""
        shown = container.lenient(Bool.self, forKey: .shown) ?? true
        registry = container.lenient(String.self, forKey: .registry)
    }

    private enum CodingKeys: String, CodingKey { case id, name, shown, registry }
}

struct UsageProvider: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var windows: [UsageWindow]
    var source: String
    var updatedAt: Int64
    /// Since when the default login's checks fail, which leaves `windows` from before. Nil while they work.
    var failedAt: Int64?
    /// The agent's ACP registry id, which its logo goes by. Absent from a host that doesn't name it.
    var registry: String?
    /// What the default login is called, when the host knows. Only sent beside `loginProfiles`.
    var defaultLoginProfile: String?
    /// The agent's other logins, each with its own windows. Empty for an agent with one login: `windows` is then all there is.
    var loginProfiles: [UsageLoginProfile]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, forKey: .id) ?? ""
        name = container.lenient(String.self, forKey: .name) ?? ""
        windows = container.lenient([UsageWindow].self, forKey: .windows) ?? []
        source = container.lenient(String.self, forKey: .source) ?? ""
        updatedAt = container.lenient(Int64.self, forKey: .updatedAt) ?? 0
        failedAt = container.lenient(Int64.self, forKey: .failedAt)
        registry = container.lenient(String.self, forKey: .registry)
        defaultLoginProfile = container.lenient(String.self, forKey: .defaultLoginProfile)
        loginProfiles = container.lenient([UsageLoginProfile].self, forKey: .loginProfiles) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, windows, source, updatedAt, failedAt, registry, defaultLoginProfile, loginProfiles
    }

    /// The agent's logins, the default one first. A single entry for an agent with one login.
    var logins: [UsageLogin] {
        [UsageLogin(id: nil, name: defaultLoginProfile, windows: windows, failedAt: failedAt)]
            + loginProfiles.map { UsageLogin(id: $0.id, name: $0.name, windows: $0.windows, failedAt: $0.failedAt) }
    }

    /// Whether any login has a reading at all.
    var hasReading: Bool { logins.contains { !$0.windows.isEmpty } }
}

/// One of an agent's logins with what it has used. The default login has no id, and no name unless the host knows it.
struct UsageLogin: Hashable, Sendable, Identifiable {
    var id: String?
    var name: String?
    var windows: [UsageWindow]
    /// Since when its checks fail, which leaves `windows` from before. Nil while they work.
    var failedAt: Int64?

    /// Shown, but not current: its last check failed.
    var isOutOfDate: Bool { failedAt != nil && !windows.isEmpty }

    /// Plan windows. A note (today's tokens, a dollar balance) is not a limit.
    var limits: [UsageWindow] { windows.filter { $0.text == nil } }

    var tightest: UsageWindow? { limits.max { $0.percent < $1.percent } }
}

/// Another login of an agent (a signed-in account) and what it has used. No windows: no reading yet.
struct UsageLoginProfile: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var windows: [UsageWindow]
    var updatedAt: Int64
    /// Since when its checks fail, which leaves `windows` from before. Nil while they work.
    var failedAt: Int64?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, forKey: .id) ?? ""
        name = container.lenient(String.self, forKey: .name) ?? ""
        windows = container.lenient([UsageWindow].self, forKey: .windows) ?? []
        updatedAt = container.lenient(Int64.self, forKey: .updatedAt) ?? 0
        failedAt = container.lenient(Int64.self, forKey: .failedAt)
    }

    private enum CodingKeys: String, CodingKey { case id, name, windows, updatedAt, failedAt }
}

struct UsageWindow: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var label: String
    var percent: Double
    var resetsAt: Int64?
    /// Human text when only that is known ("Sep 26 at 12pm (Asia/Taipei)").
    var resetsText: String?
    /// A reading that isn't a share of a cap ("$4.20", "1.2M tokens", "Unlimited"). Shown instead of the percent.
    var text: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, forKey: .id) ?? ""
        label = container.lenient(String.self, forKey: .label) ?? ""
        percent = container.lenient(Double.self, forKey: .percent) ?? 0
        resetsAt = container.lenient(Int64.self, forKey: .resetsAt)
        resetsText = container.lenient(String.self, forKey: .resetsText)
        text = container.lenient(String.self, forKey: .text)
    }

    private enum CodingKeys: String, CodingKey { case id, label, percent, resetsAt, resetsText, text }

    var resetDate: Date? {
        resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
    }
}

// MARK: - Marketplace

struct InstalledConnector: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var description: String
    var registryName: String?
    /// `local` (a command the agent starts), `remote` (a URL) or `composio`.
    var kind: String
    var command: String?
    var url: String?
    /// Names of the keys and headers that are set; their values stay on the computer.
    var keys: [String]
    var logo: String?
    /// Remote servers: `none`, `signedOut` (waits for sign-in; bots don't get it yet) or `signedIn`.
    var auth: String?
    var canSignIn: Bool?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, forKey: .id) ?? ""
        name = container.lenient(String.self, forKey: .name) ?? ""
        description = container.lenient(String.self, forKey: .description) ?? ""
        registryName = container.lenient(String.self, forKey: .registryName)
        kind = container.lenient(String.self, forKey: .kind) ?? ""
        command = container.lenient(String.self, forKey: .command)
        url = container.lenient(String.self, forKey: .url)
        keys = container.lenient([String].self, forKey: .keys) ?? []
        logo = container.lenient(String.self, forKey: .logo)
        auth = container.lenient(String.self, forKey: .auth)
        canSignIn = container.lenient(Bool.self, forKey: .canSignIn)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, registryName, kind, command, url, keys, logo, auth, canSignIn
    }

    var needsSignIn: Bool { auth == "signedOut" }
}

struct MarketConnector: Codable, Hashable, Sendable, Identifiable {
    var name: String
    var title: String
    var description: String?
    var version: String?
    var website: String?
    var installed: Bool
    var options: [MarketInstallOption]
    var id: String { name }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.lenient(String.self, forKey: .name) ?? ""
        title = container.lenient(String.self, forKey: .title) ?? name
        description = container.lenient(String.self, forKey: .description)
        version = container.lenient(String.self, forKey: .version)
        website = container.lenient(String.self, forKey: .website)
        installed = container.lenient(Bool.self, forKey: .installed) ?? false
        options = container.lenient([MarketInstallOption].self, forKey: .options) ?? []
    }

    private enum CodingKeys: String, CodingKey { case name, title, description, version, website, installed, options }
}

struct MarketInstallOption: Codable, Hashable, Sendable, Identifiable {
    var id: String
    /// npm | pypi | oci | remote
    var kind: String
    var label: String
    var inputs: [MarketInstallInput]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, forKey: .id) ?? ""
        kind = container.lenient(String.self, forKey: .kind) ?? ""
        label = container.lenient(String.self, forKey: .label) ?? ""
        inputs = container.lenient([MarketInstallInput].self, forKey: .inputs) ?? []
    }

    private enum CodingKeys: String, CodingKey { case id, kind, label, inputs }
}

struct MarketInstallInput: Codable, Hashable, Sendable, Identifiable {
    var name: String
    var description: String?
    var secret: Bool
    var required: Bool
    var `default`: String?
    var placeholder: String?
    var id: String { name }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.lenient(String.self, forKey: .name) ?? ""
        description = container.lenient(String.self, forKey: .description)
        secret = container.lenient(Bool.self, forKey: .secret) ?? false
        required = container.lenient(Bool.self, forKey: .required) ?? false
        `default` = container.lenient(String.self, forKey: .default)
        placeholder = container.lenient(String.self, forKey: .placeholder)
    }

    private enum CodingKeys: String, CodingKey { case name, description, secret, required, `default`, placeholder }
}

struct InstalledSkill: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var description: String
    var source: String
    var path: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, forKey: .id) ?? ""
        name = container.lenient(String.self, forKey: .name) ?? ""
        description = container.lenient(String.self, forKey: .description) ?? ""
        source = container.lenient(String.self, forKey: .source) ?? ""
        path = container.lenient(String.self, forKey: .path) ?? ""
    }

    private enum CodingKeys: String, CodingKey { case id, name, description, source, path }
}

struct MarketSkill: Codable, Hashable, Sendable, Identifiable {
    /// Folder name in anthropics/skills.
    var source: String
    var name: String
    var description: String
    var installed: Bool
    var id: String { source }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = container.lenient(String.self, forKey: .source) ?? ""
        name = container.lenient(String.self, forKey: .name) ?? ""
        description = container.lenient(String.self, forKey: .description) ?? ""
        installed = container.lenient(Bool.self, forKey: .installed) ?? false
    }

    private enum CodingKeys: String, CodingKey { case source, name, description, installed }
}

/// Skills, connectors, rules and plugins an agent keeps for itself (`agentGear`).
struct AgentGear: Decodable, Sendable {
    var skills: [AgentGearItem]
    var connectors: [AgentGearItem]
    var rules: [AgentGearItem]
    var plugins: [AgentGearItem]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        skills = container.lenient([AgentGearItem].self, forKey: .skills) ?? []
        connectors = container.lenient([AgentGearItem].self, forKey: .connectors) ?? []
        rules = container.lenient([AgentGearItem].self, forKey: .rules) ?? []
        plugins = container.lenient([AgentGearItem].self, forKey: .plugins) ?? []
    }

    private enum CodingKeys: String, CodingKey { case skills, connectors, rules, plugins }
}

struct AgentGearItem: Decodable, Sendable, Hashable, Identifiable {
    var name: String
    var description: String
    var detail: String
    var id: String { name }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.lenient(String.self, forKey: .name) ?? ""
        description = container.lenient(String.self, forKey: .description) ?? ""
        detail = container.lenient(String.self, forKey: .detail) ?? ""
    }

    private enum CodingKeys: String, CodingKey { case name, description, detail }
}

/// An agent backend's models and modes (`agentModels`).
struct AgentModels: Decodable, Sendable {
    var models: [AgentModel]
    var currentModelId: String?
    var defaultModelOptions: Bool?
    var fastMode: Bool?
    var modes: [AgentMode]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        models = container.lenient([AgentModel].self, forKey: .models) ?? []
        currentModelId = container.lenient(String.self, forKey: .currentModelId)
        defaultModelOptions = container.lenient(Bool.self, forKey: .defaultModelOptions)
        fastMode = container.lenient(Bool.self, forKey: .fastMode)
        modes = container.lenient([AgentMode].self, forKey: .modes) ?? []
    }

    private enum CodingKeys: String, CodingKey { case models, currentModelId, defaultModelOptions, fastMode, modes }
}

struct AgentModel: Decodable, Sendable, Hashable, Identifiable {
    var id: String
    var name: String
    var description: String?
    var options: [String]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, forKey: .id) ?? ""
        name = container.lenient(String.self, forKey: .name) ?? ""
        description = container.lenient(String.self, forKey: .description)
        options = container.lenient([String].self, forKey: .options)
    }

    private enum CodingKeys: String, CodingKey { case id, name, description, options }
}

struct AgentMode: Decodable, Sendable, Hashable, Identifiable {
    var id: String
    var name: String
    var description: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, forKey: .id) ?? ""
        name = container.lenient(String.self, forKey: .name) ?? ""
        description = container.lenient(String.self, forKey: .description)
    }

    private enum CodingKeys: String, CodingKey { case id, name, description }
}

// MARK: - Network

/// `networkView`: every network this computer is in, plus the cloud
/// assistants switch and whether they can reach this computer at all.
/// Never an invite: phones read it too.
struct NetworkStatus: Decodable, Sendable {
    var joined: Bool
    var networks: [NetworkInfo]
    var assistants: Bool
    var assistantsAvailable: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        joined = container.lenient(Bool.self, forKey: .joined) ?? false
        networks = container.lenient([NetworkInfo].self, forKey: .networks) ?? []
        assistants = container.lenient(Bool.self, forKey: .assistants) ?? false
        assistantsAvailable = container.lenient(Bool.self, forKey: .assistantsAvailable) ?? false
    }

    private enum CodingKeys: String, CodingKey { case joined, networks, assistants, assistantsAvailable }
}

struct NetworkInfo: Decodable, Sendable, Identifiable {
    var id: String
    var key: String?
    var name: String
    var computer: String?
    var role: String?
    var canInvite: Bool
    var canRecover: Bool
    /// The relay this network runs on (`public`, a self-hosted relay URL, or `private`).
    var connector: String?
    var computers: [NetworkComputer]
    var rules: [NetworkRule]
    var defaultAccess: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, forKey: .id) ?? ""
        key = container.lenient(String.self, forKey: .key)
        name = container.lenient(String.self, forKey: .name) ?? ""
        computer = container.lenient(String.self, forKey: .computer)
        role = container.lenient(String.self, forKey: .role)
        canInvite = container.lenient(Bool.self, forKey: .canInvite) ?? false
        canRecover = container.lenient(Bool.self, forKey: .canRecover) ?? false
        connector = container.lenient(String.self, forKey: .connector)
        computers = container.lenient([NetworkComputer].self, forKey: .computers) ?? []
        rules = container.lenient([NetworkRule].self, forKey: .rules) ?? []
        defaultAccess = container.lenient(String.self, forKey: .defaultAccess)
    }

    private enum CodingKeys: String, CodingKey {
        case id, key, name, computer, role, canInvite, canRecover, connector, computers, rules, defaultAccess
    }
}

struct NetworkComputer: Decodable, Sendable, Hashable, Identifiable {
    var name: String
    var role: String?
    var me: Bool
    var online: Bool
    var agents: [NetworkAgent]
    var canRemove: Bool
    var canPromote: Bool
    var id: String { name }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.lenient(String.self, forKey: .name) ?? ""
        role = container.lenient(String.self, forKey: .role)
        me = container.lenient(Bool.self, forKey: .me) ?? false
        online = container.lenient(Bool.self, forKey: .online) ?? false
        agents = container.lenient([NetworkAgent].self, forKey: .agents) ?? []
        canRemove = container.lenient(Bool.self, forKey: .canRemove) ?? false
        canPromote = container.lenient(Bool.self, forKey: .canPromote) ?? false
    }

    private enum CodingKeys: String, CodingKey { case name, role, me, online, agents, canRemove, canPromote }
}

struct NetworkAgent: Decodable, Sendable, Hashable, Identifiable {
    var id: String
    var name: String
    var kind: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, forKey: .id) ?? ""
        name = container.lenient(String.self, forKey: .name) ?? ""
        kind = container.lenient(String.self, forKey: .kind) ?? ""
    }

    private enum CodingKeys: String, CodingKey { case id, name, kind }
}

/// `deny *@server → *`: letters from `fromAgent` on `fromComputer` to `toAgent` here.
struct NetworkRule: Decodable, Sendable, Hashable {
    var fromComputer: String
    var fromAgent: String
    var toAgent: String
    var access: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fromComputer = container.lenient(String.self, forKey: .fromComputer) ?? "*"
        fromAgent = container.lenient(String.self, forKey: .fromAgent) ?? "*"
        toAgent = container.lenient(String.self, forKey: .toAgent) ?? "*"
        access = container.lenient(String.self, forKey: .access) ?? ""
    }

    private enum CodingKeys: String, CodingKey { case fromComputer, fromAgent, toAgent, access }

    /// "allow *@* → *" — the host's own display form.
    var text: String { "\(access) \(fromAgent)@\(fromComputer) → \(toAgent)" }
}

// MARK: - Calls

extension HostAPI {
    private func marketBody(_ dict: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: dict)
    }

    private func marketDecode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    /// The computer's usage. `refresh` re-reads the providers first.
    func usage(refresh: Bool) async throws -> Usage {
        let data = try await connection.call(method: "usage", body: try marketBody(["refresh": refresh]))
        return try marketDecode(Usage.self, from: data)
    }

    /// Which agents show on the Usage screen, and in what order.
    func setUsageShown(id: String, shown: Bool) async throws -> Usage {
        let data = try await connection.call(method: "setUsageShown", body: try marketBody(["id": id, "shown": shown]))
        return try marketDecode(Usage.self, from: data)
    }

    func setUsageOrder(ids: [String]) async throws -> Usage {
        let data = try await connection.call(method: "setUsageOrder", body: try marketBody(["ids": ids]))
        return try marketDecode(Usage.self, from: data)
    }

    /// Installed MCP connectors. Fails on a host whose credential
    /// storage is locked — the caller shows the host's reason.
    func connectors() async throws -> [InstalledConnector] {
        struct Items: Decodable { var items: [InstalledConnector] }
        let data = try await connection.call(method: "connectors", body: try marketBody([:]))
        return try marketDecode(Items.self, from: data).items
    }

    /// Installed skills.
    func skills() async throws -> [InstalledSkill] {
        struct Items: Decodable { var items: [InstalledSkill] }
        let data = try await connection.call(method: "skills", body: try marketBody([:]))
        return try marketDecode(Items.self, from: data).items
    }

    /// The skill registry: 19 skills on the live host, each with an
    /// `installed` flag. No search: the whole list comes at once.
    func marketSkills() async throws -> [MarketSkill] {
        struct Items: Decodable { var items: [MarketSkill] }
        let data = try await connection.call(method: "marketSkills", body: try marketBody([:]))
        return try marketDecode(Items.self, from: data).items
    }

    /// A page of the connector registry (featured first), or of a
    /// search. Pass the returned cursor to get the next page; nil
    /// means there is none.
    func marketConnectors(search: String, cursor: String? = nil) async throws -> (items: [MarketConnector], next: String?) {
        struct Page: Decodable { var items: [MarketConnector]; var nextCursor: String? }
        let data = try await connection.call(
            method: "marketConnectors",
            body: try marketBody(["search": search, "cursor": cursor ?? ""]),
            timeout: 60)
        let page = try marketDecode(Page.self, from: data)
        return (page.items, page.nextCursor)
    }

    /// An agent backend's models and modes. Starts a probe session on
    /// the computer; allow up to 5 minutes.
    func agentModels(backend: String) async throws -> AgentModels {
        let data = try await connection.call(
            method: "agentModels",
            body: try marketBody(["backend": backend]),
            timeout: 300)
        return try marketDecode(AgentModels.self, from: data)
    }

    /// What one agent already keeps for itself in the user's home:
    /// its skills, connectors, rules and plugins.
    func agentGear(backend: String) async throws -> AgentGear {
        let data = try await connection.call(method: "agentGear", body: try marketBody(["backend": backend]))
        return try marketDecode(AgentGear.self, from: data)
    }

    /// Installs a skill by its registry source. The host reports a
    /// missing SKILL.md for an unknown source.
    func installSkill(source: String) async throws {
        _ = try await connection.call(method: "installSkill", body: try marketBody(["source": source]), timeout: 60)
    }

    /// Removes an installed skill by its id.
    func removeSkill(id: String) async throws {
        _ = try await connection.call(method: "removeSkill", body: try marketBody(["id": id]))
    }

    /// Installs a registry connector with one of its options and the
    /// option's inputs. Returns the installed connector.
    func installConnector(registryName: String, option: String, inputs: [String: String]) async throws -> InstalledConnector {
        struct Installed: Decodable { var connector: InstalledConnector }
        let data = try await connection.call(
            method: "installConnector",
            body: try marketBody(["registryName": registryName, "option": option, "inputs": inputs]),
            timeout: 45)
        return try marketDecode(Installed.self, from: data).connector
    }

    /// Removes an installed connector by its id.
    func removeConnector(id: String) async throws {
        _ = try await connection.call(method: "removeConnector", body: try marketBody(["id": id]))
    }

    /// This computer's networks, as the phone may read them. Asks the
    /// others in the background when what they offer is stale.
    func networkView() async throws -> NetworkStatus {
        let data = try await connection.call(method: "networkView", body: try marketBody([:]))
        return try marketDecode(NetworkStatus.self, from: data)
    }

    /// Brings this computer into the phone's account: the computer
    /// asks its user, then signs the claim. `certificate` is the
    /// phone's device certificate (nil until the device-certificate
    /// flow lands — the host refuses without one). Returns the signed
    /// claim, for the cloud to complete.
    func joinAccount(claimId: String, nonce: String, certificate: [String: Any]?) async throws -> Data {
        var dict: [String: Any] = ["claimId": claimId, "nonce": nonce]
        dict["certificate"] = certificate ?? NSNull()
        return try await connection.call(method: "joinAccount", body: try marketBody(dict), timeout: 120)
    }
}

extension HostCallError {
    /// The host has no such method (live probe: `market` → 404
    /// "unknown method"). The UI shows a disabled state, not an error.
    var isUnknownMethod: Bool {
        if case .failed(let message) = self {
            return message.lowercased().contains("unknown method")
        }
        return false
    }

    /// The host's message for a failed call, if it has one.
    var hostMessage: String? {
        switch self {
        case .failed(let message): return message
        case .unauthorized(let message): return message
        default: return nil
        }
    }
}
