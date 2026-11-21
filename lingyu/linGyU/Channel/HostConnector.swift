import CryptoKit
import Foundation

enum PairingState {
    case idle
    case waiting(checkCode: String)
    case failed(String)
    case paired
}

/// Owns the channel, the computer record, and the mirror. One connector per
/// app launch; the UI observes `state`, `computer`, and `mirror`.
@MainActor
final class HostConnector: ObservableObject {
    @Published private(set) var state: LinkState = .offline
    @Published private(set) var computer: Computer?
    @Published private(set) var hello: HelloReply?
    @Published private(set) var pairingState: PairingState = .idle
    @Published private(set) var pairingError: String?

    let mirror = EventMirror()

    private(set) var connection: ChannelConnection?
    private(set) var api: HostAPI?
    private var runTask: Task<Void, Never>?
    private let computerKey = "cn.lingyu.computer.v1"

    init() {
        computer = loadComputer()
    }

    var isPaired: Bool { computer != nil }

    // MARK: - Normal mode

    func connect(computer: Computer, identity: any SigningIdentity) async {
        disconnect()
        self.computer = computer
        saveComputer(computer)
        let connection = ChannelConnection(computer: computer, identity: identity)
        self.connection = connection
        self.api = HostAPI(connection: connection)
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

    /// Connects with the stored computer, if one is paired.
    func connectIfPaired() async {
        guard let computer else { return }
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

    /// Forgets the computer locally. The host still lists this device until
    /// the user revokes it on the computer.
    func forgetComputer() {
        disconnect()
        computer = nil
        UserDefaults.standard.removeObject(forKey: computerKey)
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
        self.computer = computer
        saveComputer(computer)
    }

    private func saveComputer(_ computer: Computer) {
        if let data = try? JSONEncoder().encode(computer) {
            UserDefaults.standard.set(data, forKey: computerKey)
        }
    }

    private func loadComputer() -> Computer? {
        guard let data = UserDefaults.standard.data(forKey: computerKey),
              let computer = try? JSONDecoder().decode(Computer.self, from: data),
              !computer.id.isEmpty, !computer.signKey.isEmpty else {
            return nil
        }
        return computer
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
