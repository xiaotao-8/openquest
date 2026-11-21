import Foundation

/// An error from the account cloud: `{"error":{"code","message"}}`.
struct CloudError: LocalizedError, Sendable, Equatable {
    var status: Int
    /// `notFound`, `conflict`, `rateLimited`, … — the server's code.
    var code: String
    var message: String?

    init(status: Int, code: String, message: String? = nil) {
        self.status = status
        self.code = code
        self.message = message
    }

    init(status: Int, body: Data) {
        struct Failure: Decodable {
            struct Detail: Decodable { var code: String; var message: String? }
            var error: Detail
        }
        let decoded = try? JSONDecoder().decode(Failure.self, from: body)
        self.init(status: status, code: decoded?.error.code ?? "http\(status)", message: decoded?.error.message)
    }

    var errorDescription: String? {
        switch code {
        case "rateLimited": return L("配对尝试太频繁。请稍后再试。")
        default: return message ?? L("配对失败。请重试。")
        }
    }

    /// A busy or failing cloud, or a session token that wasn't fresh yet:
    /// trying again later settles it, so background refresh keeps it out
    /// of any error dialog and never kicks the user to the sign-in page.
    var isTransient: Bool { status >= 500 || status == 429 || status == 401 }
    /// The short code expired, was used, or never existed (one-time, 10 minutes).
    var isNotFound: Bool { status == 404 }
}

/// One computer in the account (`GET /v1/computers`). The cloud's `cloud`
/// block is only set for a cloud-hosted computer; own computers have nil.
/// There is deliberately no bot count here — the cloud does not report one.
struct AccountComputer: Decodable, Sendable, Identifiable {
    var computerId: String
    var name: String
    var online: Bool?
    var lastSeenAt: Int64?
    var access: String?
    var cloud: CloudHosting?

    var id: String { computerId }
    var isOnline: Bool { online ?? false }
}

/// Who runs a cloud-hosted computer, where, and whether it is awake
/// (`cloud` in `GET /v1/computers`, flat fields in `GET /v1/cloud-computers`).
struct CloudHosting: Decodable, Sendable {
    var provider: String
    /// Shown as the cloud names it, never hard-coded here.
    var providerName: String
    var region: String
    /// starting | running | stopping | stopped | failed | unknown.
    var state: String

    /// Asleep or falling asleep: a message wakes it, so it isn't offline.
    var isAsleep: Bool { state == "stopped" || state == "stopping" }
}

/// One of the account's cloud computers (`GET /v1/cloud-computers`).
/// `computerId` is nil until the machine has booted and claimed itself
/// into the account. Provider, region and state sit flat beside it.
struct CloudMachine: Decodable, Sendable, Identifiable {
    var cloudComputerId: String
    var name: String
    var computerId: String?
    var snapshots: Bool
    var provider: String
    var providerName: String
    var region: String
    var state: String

    var id: String { cloudComputerId }

    private enum CodingKeys: String, CodingKey {
        case cloudComputerId, name, computerId, snapshots
        case provider, providerName, region, state
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cloudComputerId = try container.decode(String.self, forKey: .cloudComputerId)
        name = try container.decode(String.self, forKey: .name)
        computerId = try container.decodeIfPresent(String.self, forKey: .computerId)
        snapshots = try container.decodeIfPresent(Bool.self, forKey: .snapshots) ?? true
        provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? ""
        providerName = try container.decodeIfPresent(String.self, forKey: .providerName) ?? ""
        region = try container.decodeIfPresent(String.self, forKey: .region) ?? ""
        state = try container.decodeIfPresent(String.self, forKey: .state) ?? "unknown"
    }
}

/// The account's cloud as the cloud describes it (`GET /v1/cloud-computers`).
struct CloudStatus: Decodable, Sendable {
    var cloudComputers: [CloudMachine]?
    /// Whether this account may have cloud computers.
    var available: Bool?
    /// How many it may have at once.
    var limit: Int?

    private enum CodingKeys: String, CodingKey {
        case cloudComputers, available, limit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cloudComputers = try container.decodeIfPresent([CloudMachine].self, forKey: .cloudComputers)
        available = try container.decodeIfPresent(Bool.self, forKey: .available)
        limit = try container.decodeIfPresent(Int.self, forKey: .limit)
    }
}

/// The user-facing `/v1` API: short codes and the cloud-computer lists.
/// The session token comes from the account store, fetched fresh on every
/// request — the app never stores a token itself. No device signature
/// (`Codync-Sig`) is attached: the calls in this batch do not need it.
struct CloudClient: Sendable {
    let baseURL: URL
    let token: @Sendable () async throws -> String
    let session: URLSession

    /// Sent with every request: this app's version and the oldest host it
    /// works with, in the original's `ios/<version>; minHost=<version>` form.
    static let appHeader = "ios/1.0; minHost=\(Compatibility.minHostVersion)"

    init(baseURL: URL, token: @escaping @Sendable () async throws -> String) {
        self.init(baseURL: baseURL, session: .shared, token: token)
    }

    init(baseURL: URL, session: URLSession, token: @escaping @Sendable () async throws -> String) {
        self.baseURL = baseURL
        self.session = session
        self.token = token
    }

    // MARK: - Pairing codes

    /// The pairing link a short code stands for. The cloud hands it out
    /// once; a used or expired code (10 minutes) comes back 404.
    func pairingLink(code: String) async throws -> String {
        struct Res: Decodable { var link: String }
        // The server normalises the code; send the bare 8 characters.
        let bare = code.replacingOccurrences(of: "-", with: "").uppercased()
        let res: Res = try await request("GET", "v1/pairing-codes/\(bare)")
        return res.link
    }

    // MARK: - Computers

    /// Every computer in the account, with online state and, for
    /// cloud-hosted ones, the hosting block. No bot count is reported.
    func computers() async throws -> [AccountComputer] {
        struct Res: Decodable { var computers: [AccountComputer] }
        let res: Res = try await request("GET", "v1/computers")
        return res.computers
    }

    /// The account's cloud computers, whether it may have them, and the limit.
    func cloudStatus() async throws -> CloudStatus {
        try await request("GET", "v1/cloud-computers")
    }

    // MARK: - Plumbing

    func request<T: Decodable>(_ method: String, _ path: String) async throws -> T {
        try await request(method, path, json: nil)
    }

    private func request<T: Decodable>(_ method: String, _ path: String, json: Data?) async throws -> T {
        let url = baseURL.appending(path: path)
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = method
        // Every request carries a freshly fetched token; the SDK caches it
        // for about a minute and refreshes it when it expires.
        req.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        req.setValue(Self.appHeader, forHTTPHeaderField: "Codync-App")
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = json
        }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw CloudError(status: 0, code: "noResponse")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CloudError(status: http.statusCode, body: data)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
