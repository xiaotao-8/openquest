import CryptoKit
import Foundation

enum PairingState: Equatable {
    case idle
    case waiting(checkCode: String)
    case failed(String)
    case paired
}

/// Owns the channel, the computers, and the mirror. One connector per
/// app launch; the UI observes `state`, `computers`, `computer`, and
/// `mirror`. Several own computers may be paired; exactly one is current
/// and the connection, roster, and chat all follow it.
@MainActor
final class HostConnector: ObservableObject {
    @Published private(set) var state: LinkState = .offline
    /// All paired own computers, in pairing order.
    @Published private(set) var computers: [Computer] = []
    /// The id of the current computer.
    @Published private(set) var selectedComputerId: String?
    /// Cloud computers on the account (display list; connection needs the
    /// account sign-in, a later phase).
    @Published private(set) var cloudComputers: [CloudComputer] = []
    @Published private(set) var hello: HelloReply?
    @Published private(set) var pairingState: PairingState = .idle
    @Published private(set) var pairingError: String?

    /// The current computer: the selected one, or the first paired one.
    var computer: Computer? {
        if let id = selectedComputerId,
           let found = computers.first(where: { $0.id == id }) {
            return found
        }
        return computers.first
    }

    let mirror = EventMirror()

    private(set) var connection: ChannelConnection?
    private(set) var api: HostAPI?
    private var runTask: Task<Void, Never>?
    private let computersKey = "cn.lingyu.computers.v1"
    private let selectedKey = "cn.lingyu.selectedComputer.v1"
    private let cloudComputersKey = "cn.lingyu.cloudComputers.v1"
    /// The pre-list single-computer key; read once for migration, then
    /// dropped. Never written again.
    private let legacyComputerKey = "cn.lingyu.computer.v1"

    /// Live-preview dial reporter: forwarded to the channel so each dial
    /// attempt is logged to the diagnostics card. Nil in normal use.
    private(set) var dialReporter: (@Sendable (String) -> Void)?

    func setDialReporter(_ reporter: (@Sendable (String) -> Void)?) {
        dialReporter = reporter
    }

    init() {
        computers = loadComputers()
        selectedComputerId = UserDefaults.standard.string(forKey: selectedKey)
        cloudComputers = loadCloudComputers()
    }

    var isPaired: Bool { !computers.isEmpty }

    /// Whether another cloud computer may be added (account limit is 3).
    var canAddCloudComputer: Bool { cloudComputers.count < CloudComputer.accountLimit }

    /// Adds a cloud computer to the list. Returns false — and adds nothing
    /// — once the account limit of 3 is reached.
    @discardableResult
    func addCloudComputer(_ computer: CloudComputer) -> Bool {
        guard canAddCloudComputer,
              !cloudComputers.contains(where: { $0.id == computer.id }) else {
            return false
        }
        cloudComputers.append(computer)
        saveCloudComputers()
        return true
    }

    /// Replaces the cloud list with computers fetched from the account
    /// (only cloud-hosted ones are shown here). Callers map the account
    /// response into display records; no bot count is invented.
    func updateCloudComputers(_ list: [CloudComputer]) {
        cloudComputers = list
        saveCloudComputers()
    }

    /// Drops account-fetched cloud computers and restores the pre-login
    /// display item (unknown state). Used on sign-out and account deletion.
    func resetCloudComputers() {
        cloudComputers = Self.seededCloudComputers
        saveCloudComputers()
    }

    // MARK: - Normal mode

    func connect(computer: Computer, identity: any SigningIdentity) async {
        disconnect()
        upsertComputer(computer)
        selectedComputerId = computer.id
        saveComputers()
        let connection = ChannelConnection(computer: computer, identity: identity)
        self.connection = connection
        self.api = HostAPI(connection: connection)
        await connection.setDialReporter(dialReporter)
        await connection.setStateChangeHandler { [weak self] newState in
            Task { @MainActor in
                self?.state = newState
            }
        }
        await connection.setHelloReplyHandler { [weak self] reply in
            Task { @MainActor in
                guard let self else { return }
                self.hello = reply
                self.api?.speaksThreads = reply.speaksThreads
                self.mergeHello(reply)
            }
        }
        runTask = Task { await connection.run() }
        if let api = self.api {
            mirror.start(api: api)
        }
    }

    /// Connects with the current computer, if one is paired.
    func connectIfPaired() async {
        guard let computer else { return }
        do {
            let identity = try DeviceIdentity.loadOrCreate()
            await connect(computer: computer, identity: identity)
        } catch {
            state = .stopped(.failed(L("读取设备密钥失败。请重新配对。")))
        }
    }

    /// Switches the current computer and connects to it. The roster and
    /// chat follow the newly selected computer.
    func selectComputer(_ computer: Computer) async {
        guard computers.contains(where: { $0.id == computer.id }) else { return }
        await connectIfPairedTo(computer)
    }

    private func connectIfPairedTo(_ computer: Computer) async {
        do {
            let identity = try DeviceIdentity.loadOrCreate()
            await connect(computer: computer, identity: identity)
        } catch {
            state = .stopped(.failed(L("读取设备密钥失败。请重新配对。")))
        }
    }

    func disconnect() {
        runTask?.cancel()
        runTask = nil
        mirror.stop()
        let connection = self.connection
        self.connection = nil
        api = nil
        hello = nil
        Task { await connection?.stop() }
    }

    /// Forgets one computer locally. The host still lists this device
    /// until the user revokes it on the computer. If it was the current
    /// computer, the next paired one becomes current and connects.
    func forgetComputer(_ computer: Computer) {
        let wasCurrent = self.computer?.id == computer.id
        if wasCurrent { disconnect() }
        computers.removeAll { $0.id == computer.id }
        if selectedComputerId == computer.id {
            selectedComputerId = computers.first?.id
        }
        saveComputers()
        if wasCurrent, computers.first != nil {
            Task { await connectIfPaired() }
        }
    }

    /// Forgets every paired computer locally (start over). The hosts still
    /// list this device until the user revokes it on each computer.
    func forgetAllComputers() {
        disconnect()
        computers = []
        selectedComputerId = nil
        UserDefaults.standard.removeObject(forKey: computersKey)
        UserDefaults.standard.removeObject(forKey: selectedKey)
        UserDefaults.standard.removeObject(forKey: legacyComputerKey)
        KeychainStore.deleteAll()
    }

    // MARK: - Pairing

    /// Runs the full pairing flow for a validated link. Shows the 6-digit
    /// check code while waiting for approval on the computer, then reconnects
    /// in normal mode. Throws the host's message on failure.
    func pair(link: PairingLink, deviceName: String) async throws -> Computer {
        pairingState = .idle
        pairingError = nil
        let identity: DeviceIdentity
        do {
            identity = try DeviceIdentity.loadOrCreate()
        } catch {
            let message = L("读取设备密钥失败。请重试。")
            pairingState = .failed(message)
            throw HostCallError.failed(message)
        }
        let computer = Computer(from: link)
        let checkCode = Self.checkCode(devicePub: identity.devicePublicKey, hostSignKey: link.signKey)
        let pairing = ChannelConnection(computer: computer, identity: identity, pairingCode: link.codeBase64URL)
        await pairing.enableStopAfterFirstServe()
        await pairing.setStateChangeHandler { [weak self] (newState: LinkState) in
            Task { @MainActor in
                guard let self else { return }
                if case .stopped(let reason) = newState {
                    switch reason {
                    case .failed(let message):
                        self.pairingState = .failed(message)
                    case .unauthorized(let message):
                        self.pairingState = .failed(message)
                    case .upgradeRequired:
                        self.pairingState = .failed(L("电脑版本太旧。请先更新电脑。"))
                    }
                }
            }
        }
        let runTask = Task { await pairing.run() }
        defer { runTask.cancel() }
        do {
            try await pairing.ready(within: 15)
        } catch let error as HostCallError {
            let message: String
            switch error {
            case .unreachable:
                message = L("连不上这台电脑。请确认在同一网络，或已接入 Tailscale。")
            case .failed(let text), .unauthorized(let text):
                message = text
            default:
                message = L("配对失败。请重试。")
            }
            pairingState = .failed(message)
            await pairing.stop()
            throw error
        }
        pairingState = .waiting(checkCode: checkCode)
        let bodyData = try JSONSerialization.data(withJSONObject: [
            "code": link.codeBase64URL,
            "name": deviceName,
            "platform": "ios",
        ] as [String: Any])
        let replyData: Data
        do {
            replyData = try await pairing.call(method: "pair", body: bodyData, timeout: 150)
        } catch {
            let message = hostErrorMessage(error)
            pairingState = .failed(message)
            await pairing.stop()
            throw error
        }
        struct PairReply: Decodable { var computerId: String; var name: String? }
        guard let reply = try? JSONDecoder().decode(PairReply.self, from: replyData),
              reply.computerId == computer.id else {
            let message = L("电脑身份不符。请重新配对。")
            pairingState = .failed(message)
            await pairing.stop()
            throw HostCallError.failed(message)
        }
        // The host closes with 4100 paired; the pairing transport goes
        // offline (stopAfterFirstServe). Wait for that before normal mode.
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let current = await pairing.state
            if case .offline = current { break }
            if case .stopped = current { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        await pairing.stop()
        pairingState = .paired
        await connect(computer: computer, identity: identity)
        return computer
    }

    /// The 6-digit check code both sides display (§8.4). Derived locally
    /// from public keys; never sent on the wire.
    static func checkCode(devicePub: Data, hostSignKey: Data) -> String {
        ChannelCrypto.pairCheckCode(devicePub: devicePub, hostSignPub: hostSignKey)
    }

    // MARK: - Computer record

    private func mergeHello(_ reply: HelloReply) {
        guard var computer else { return }
        if !reply.name.isEmpty { computer.name = reply.name }
        if let boxKey = reply.boxKey,
           let boxData = Base64URL.decode(boxKey), boxData.count == 32 {
            computer.boxKey = boxKey
        }
        let validUrls = reply.urls.filter { url in
            guard let parts = URLComponents(string: url),
                  let scheme = parts.scheme, (scheme == "http" || scheme == "https"),
                  parts.host != nil else { return false }
            return true
        }
        if !validUrls.isEmpty { computer.urls = Array(validUrls.prefix(16)) }
        if let cloud = reply.cloud, !cloud.isEmpty { computer.cloud = cloud }
        if let device = reply.device { computer.device = device }
        // Hello only ever arrives over the winning direct URL (this
        // build has no relay transport), so the route is direct — the
        // chat subtitle's connection icon reads it (relay → cloud,
        // direct → wifi, no route → network).
        computer.route = "direct"
        upsertComputer(computer)
        saveComputers()
    }

    /// Inserts the computer, or replaces the stored record with the same id.
    private func upsertComputer(_ computer: Computer) {
        if let index = computers.firstIndex(where: { $0.id == computer.id }) {
            computers[index] = computer
        } else {
            computers.append(computer)
        }
    }

    private func saveComputers() {
        if let data = try? JSONEncoder().encode(computers) {
            UserDefaults.standard.set(data, forKey: computersKey)
        }
        if let id = selectedComputerId {
            UserDefaults.standard.set(id, forKey: selectedKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectedKey)
        }
    }

    /// Loads the stored list, migrating the old single-computer record
    /// into a one-item list (pairing survives the upgrade).
    private func loadComputers() -> [Computer] {
        if let data = UserDefaults.standard.data(forKey: computersKey),
           let list = try? JSONDecoder().decode([Computer].self, from: data) {
            return list.filter { !$0.id.isEmpty && !$0.signKey.isEmpty }
        }
        if let data = UserDefaults.standard.data(forKey: legacyComputerKey),
           let computer = try? JSONDecoder().decode(Computer.self, from: data),
           !computer.id.isEmpty, !computer.signKey.isEmpty {
            let list = [computer]
            UserDefaults.standard.removeObject(forKey: legacyComputerKey)
            if let data = try? JSONEncoder().encode(list) {
                UserDefaults.standard.set(data, forKey: computersKey)
            }
            return list
        }
        return []
    }

    private func saveCloudComputers() {
        if let data = try? JSONEncoder().encode(cloudComputers) {
            UserDefaults.standard.set(data, forKey: cloudComputersKey)
        }
    }

    /// The pre-login display item: the account's one cloud computer
    /// (United States, 1 bot). Its state is unknown until the account
    /// sign-in lands — never shown as online.
    private static let seededCloudComputers = [
        CloudComputer(id: "cloud-1", name: "云电脑", region: "美国", botCount: 1)
    ]

    /// Loads the stored cloud list, seeding the account's one cloud
    /// computer (United States, 1 bot) the first time. Its state is
    /// unknown until the account sign-in lands — never shown as online.
    private func loadCloudComputers() -> [CloudComputer] {
        if let data = UserDefaults.standard.data(forKey: cloudComputersKey),
           let list = try? JSONDecoder().decode([CloudComputer].self, from: data) {
            return list
        }
        let seeded = Self.seededCloudComputers
        if let data = try? JSONEncoder().encode(seeded) {
            UserDefaults.standard.set(data, forKey: cloudComputersKey)
        }
        return seeded
    }

    private func hostErrorMessage(_ error: Error) -> String {
        switch error {
        case HostCallError.failed(let message):
            return message
        case HostCallError.unauthorized(let message):
            return message
        case HostCallError.unreachable:
            return L("连接断开了。请重试。")
        case HostCallError.timeout:
            return L("等太久了。请在电脑上重新出示配对码。")
        default:
            return L("配对失败。请重试。")
        }
    }
}
