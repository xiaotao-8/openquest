import CryptoKit
import Foundation

/// Anything that can sign the handshake: the Keychain device key or an
/// in-memory preview identity. Only the public key and signatures escape.
protocol SigningIdentity: Sendable {
    var devicePublicKey: Data { get }
    func sign(_ data: Data) throws -> Data
}

extension DeviceIdentity: SigningIdentity {}
extension PreviewIdentity: SigningIdentity {}

enum LinkState: Sendable {
    case offline
    case connecting
    case ready
    case waiting(String)
    case stopped(StopReason)
}

enum StopReason: Sendable {
    case unauthorized(String)
    case upgradeRequired
    case failed(String)
}

enum ChannelOutcome: Sendable {
    case again
    case retry(String)
    case stop(StopReason)
}

/// The channel supervisor: direct race, handshake, heartbeat, backoff.
/// One actor owns the socket, the sealer/opener, and the call/stream tables.
/// Pairing mode: `pairingCode` set, no inner `hello` is sent, only `pair`.
actor ChannelConnection {
    let computer: Computer
    private let identity: any SigningIdentity
    private let pairingCode: String?

    private(set) var state: LinkState = .offline
    var onStateChange: (@Sendable (LinkState) -> Void)?
    var onHelloReply: (@Sendable (HelloReply) -> Void)?
    /// Pairing transports stop after the first serve instead of reconnecting.
    var stopAfterFirstServe = false

    private var isStopped = false
    private var socket: URLSessionChannelSocket?
    private var sealer: FrameSealer?
    private var opener: FrameOpener?
    private var outbound: AsyncStream<String>.Continuation?
    private var writerTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var lastReceived = Date.distantPast
    private var connectedSince: Date?
    private var backoffAttempt = 0
    private var nextRequestId: UInt32 = 0

    var calls: [UInt32: CheckedContinuation<Data, Error>] = [:]
    var streams: [UInt32: AsyncThrowingStream<Data, Error>.Continuation] = [:]

    init(computer: Computer, identity: any SigningIdentity, pairingCode: String? = nil) {
        self.computer = computer
        self.identity = identity
        self.pairingCode = pairingCode
    }

    var isPairing: Bool { pairingCode != nil }

    // MARK: - Supervisor

    func run() async {
        setState(.connecting)
        while !isStopped {
            let outcome = await connectOnce()
            if stopAfterFirstServe {
                // Pairing transport: one serve is the whole job. Go offline;
                // the connector watches for this to start normal mode.
                setState(.offline)
                isStopped = true
                return
            }
            switch outcome {
            case .again:
                backoffAttempt = 0
                setState(.connecting)
                continue
            case .retry(let reason):
                setState(.waiting(reason))
                let delay = backoffDelay()
                backoffAttempt += 1
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if isStopped { break }
                setState(.connecting)
            case .stop(let reason):
                setState(.stopped(reason))
                isStopped = true
                return
            }
        }
    }

    func stop() {
        isStopped = true
        socket?.close(code: 1000)
        setState(.stopped(.failed("Stopped")))
    }

    func reconnectNow() {
        socket?.close(code: 1000)
    }

    /// Waits until the channel is ready, a terminal stop, or the timeout.
    func ready(within timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            switch state {
            case .ready:
                return
            case .stopped(let reason):
                throw stopError(reason)
            default:
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        throw HostCallError.unreachable
    }

    // MARK: - One connection attempt

    private func connectOnce() async -> ChannelOutcome {
        let urls = computer.urls
        guard !urls.isEmpty else {
            return .retry(L("无法连接电脑。请确认在同一网络，或已接入 Tailscale。"))
        }
        guard let winner = await race(urls: urls) else {
            return .retry(L("无法连接电脑。请确认在同一网络，或已接入 Tailscale。"))
        }
        if isStopped {
            return .stop(.unauthorized(L("这台电脑的身份变了。请重新配对。")))
        }
        return await serve(socket: winner.socket, sealer: winner.sealer, opener: winner.opener)
    }

    /// Races all direct URLs in parallel; the first completed handshake
    /// within 1.5 s wins. A `reject` only fails that one address.
    private func race(urls: [String]) async -> (URLSessionChannelSocket, FrameSealer, FrameOpener)? {
        await withTaskGroup(of: RaceResult.self) { group in
            for url in urls {
                group.addTask {
                    if let result = await self.attempt(url: url) {
                        return RaceResult.won(result.0, result.1, result.2)
                    }
                    return RaceResult.failed
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                return RaceResult.timedOut
            }
            var remaining = urls.count
            while let result = await group.next() {
                switch result {
                case .won(let socket, let sealer, let opener):
                    group.cancelAll()
                    return (socket, sealer, opener)
                case .failed:
                    remaining -= 1
                    if remaining == 0 {
                        group.cancelAll()
                        return nil
                    }
                case .timedOut:
                    group.cancelAll()
                    return nil
                }
            }
            return nil
        }
    }

    private enum RaceResult {
        case won(URLSessionChannelSocket, FrameSealer, FrameOpener)
        case failed
        case timedOut
    }

    /// One dial + handshake attempt. Returns nil on any failure.
    private func attempt(url: String) async -> (URLSessionChannelSocket, FrameSealer, FrameOpener)? {
        let socket: URLSessionChannelSocket
        do {
            socket = try Dialer.dial(url)
        } catch {
            return nil
        }
        do {
            let (sealer, opener) = try await performHandshake(socket: socket)
            return (socket, sealer, opener)
        } catch ChannelHandshakeError.identityChanged {
            // Terminal for the whole transport, not just this address.
            markIdentityChanged()
            socket.close(code: 4001)
            return nil
        } catch ChannelHandshakeError.rejected(let code) {
            socket.close(code: 1000)
            if isPairing {
                // A pairing reject is terminal: the code is closed, spent,
                // or the host refused this device.
                markPairingRejected(code: code)
            }
            return nil
        } catch {
            socket.close(code: 1000)
            return nil
        }
    }

    private func markIdentityChanged() {
        isStopped = true
        setState(.stopped(.unauthorized(L("这台电脑的身份变了。请重新配对。"))))
    }

    private func markPairingRejected(code: String?) {
        isStopped = true
        let message: String
        switch code {
        case "pairingClosed":
            message = L("配对码已关闭。请在电脑上出示一个新的配对码。")
        case "rateLimited":
            message = L("配对尝试太频繁。请稍后再试。")
        case "unauthorized":
            message = L("这台设备不被这台电脑允许。")
        default:
            message = L("配对被拒绝。请在电脑上出示一个新的配对码。")
        }
        setState(.stopped(.failed(message)))
    }

    // MARK: - Handshake

    private func performHandshake(socket: URLSessionChannelSocket) async throws -> (FrameSealer, FrameOpener) {
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let ephemeralPub = ephemeral.publicKey.rawRepresentation
        let nonce = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let devicePub = identity.devicePublicKey
        let hs1 = ChannelCrypto.hs1Input(
            hostSignPub: computer.signKeyData, devicePub: devicePub,
            ephemeralPub: ephemeralPub, nonce: nonce)
        let signature: Data
        do {
            signature = try identity.sign(hs1)
        } catch {
            throw ChannelHandshakeError.failed
        }
        var hello: [String: Any] = [
            "t": "hello", "v": 1,
            "dk": Base64URL.encode(devicePub),
            "ek": Base64URL.encode(ephemeralPub),
            "n": Base64URL.encode(nonce),
            "sig": Base64URL.encode(signature),
        ]
        if isPairing { hello["pair"] = true }
        guard let helloData = try? JSONSerialization.data(withJSONObject: hello),
              let helloText = String(data: helloData, encoding: .utf8) else {
            throw ChannelHandshakeError.failed
        }
        do {
            try await socket.sendText(helloText)
        } catch {
            throw ChannelHandshakeError.failed
        }
        let raw: String
        do {
            raw = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { try await socket.receiveText() }
                group.addTask {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                    throw ChannelHandshakeError.timeout
                }
                guard let first = try await group.next() else {
                    throw ChannelHandshakeError.failed
                }
                group.cancelAll()
                return first
            }
        } catch let error as ChannelHandshakeError {
            throw error
        } catch {
            throw ChannelHandshakeError.failed
        }
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChannelHandshakeError.failed
        }
        if json["t"] as? String == "reject" {
            throw ChannelHandshakeError.rejected(code: json["code"] as? String)
        }
        guard json["t"] as? String == "welcome",
              let ekText = json["ek"] as? String,
              let ekHost = Base64URL.decode(ekText), ekHost.count == 32,
              let sigText = json["sig"] as? String,
              let sig = Base64URL.decode(sigText), sig.count == 64 else {
            throw ChannelHandshakeError.failed
        }
        let transcript = ChannelCrypto.transcriptHash(
            hostSignPub: computer.signKeyData, devicePub: devicePub,
            ephemeralPub: ephemeralPub, nonce: nonce, hostEphemeralPub: ekHost)
        do {
            let hostKey = try Curve25519.Signing.PublicKey(rawRepresentation: computer.signKeyData)
            guard hostKey.isValidSignature(sig, for: transcript) else {
                throw ChannelHandshakeError.identityChanged
            }
        } catch let error as ChannelHandshakeError {
            throw error
        } catch {
            throw ChannelHandshakeError.failed
        }
        let sharedSecret: Data
        do {
            let secret = try ephemeral.sharedSecretFromKeyAgreement(with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: ekHost))
            sharedSecret = secret.withUnsafeBytes { Data($0) }
        } catch {
            throw ChannelHandshakeError.failed
        }
        guard let keys = ChannelCrypto.deriveKeys(transcriptHash: transcript, sharedSecret: sharedSecret) else {
            throw ChannelHandshakeError.failed
        }
        return (FrameSealer(key: keys.d2h), FrameOpener(key: keys.h2d, limit: 16 * 1024 * 1024))
    }

    // MARK: - Serve

    private func serve(socket: URLSessionChannelSocket, sealer: FrameSealer, opener: FrameOpener) async -> ChannelOutcome {
        self.socket = socket
        self.sealer = sealer
        self.opener = opener
        self.nextRequestId = 0
        self.lastReceived = Date()
        self.connectedSince = Date()
        startWriter(socket: socket)
        startHeartbeat()
        setState(.ready)
        if !isPairing {
            do {
                let replyData = try await call(method: "hello", body: Data("{}".utf8), timeout: 20)
                if let reply = try? JSONDecoder().decode(HelloReply.self, from: replyData) {
                    onHelloReply?(reply)
                }
            } catch {
                return finishServe(outcome: .retry(L("连接已建立，但电脑没有回应。正在重试。")))
            }
        }
        // Inbound loop: the actor stays reentrant at this await.
        var outcome: ChannelOutcome = .retry(L("连接断开了。正在重连。"))
        while true {
            do {
                let text = try await socket.receiveText()
                lastReceived = Date()
                try dispatchInbound(text)
            } catch let closed as SocketClosed {
                outcome = outcome(forCloseCode: closed.code)
                break
            } catch {
                outcome = .retry(L("连接断开了。正在重连。"))
                break
            }
        }
        return finishServe(outcome: outcome)
    }

    private func finishServe(outcome: ChannelOutcome) -> ChannelOutcome {
        if let since = connectedSince, Date().timeIntervalSince(since) >= 60 {
            backoffAttempt = 0
        }
        connectedSince = nil
        writerTask?.cancel()
        writerTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        outbound?.finish()
        outbound = nil
        failAllCalls(with: HostCallError.unreachable)
        failAllStreams(with: HostCallError.unreachable)
        socket?.close(code: 1000)
        socket = nil
        sealer = nil
        opener = nil
        if case .stop = outcome {
            isStopped = true
        }
        return outcome
    }

    private func outcome(forCloseCode code: Int) -> ChannelOutcome {
        switch code {
        case 1000:
            return .retry(L("连接断开了。正在重连。"))
        case 4001, 4003:
            return .stop(.unauthorized(L("这台设备已不被这台电脑允许。请重新配对。")))
        case 4400:
            return .stop(.upgradeRequired)
        case 4011, 4100:
            return .again
        case 4008, 4013, 4002, 1006, 1011:
            return .retry(L("连接断开了。正在重连。"))
        default:
            return .retry(L("连接断开了。正在重连。"))
        }
    }

    private func startWriter(socket: URLSessionChannelSocket) {
        let (stream, continuation) = AsyncStream<String>.makeStream()
        outbound = continuation
        writerTask = Task {
            for await text in stream {
                do {
                    try await socket.sendText(text)
                } catch {
                    // The receive loop owns the outcome; a dead socket
                    // surfaces there. Ignore send errors here.
                    break
                }
            }
        }
    }

    private func startHeartbeat() {
        heartbeatTask = Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self else { return }
                let dead = await self.silenceExceeded()
                if dead {
                    await self.closeSilently()
                    return
                }
            }
        }
    }

    private func silenceExceeded() -> Bool {
        Date().timeIntervalSince(lastReceived) > 45
    }

    private func closeSilently() {
        socket?.close(code: 1011)
    }

    private func backoffDelay() -> TimeInterval {
        let cap = min(30.0, pow(2.0, Double(backoffAttempt)))
        return TimeInterval.random(in: 0...cap)
    }

    private func setState(_ newState: LinkState) {
        state = newState
        onStateChange?(newState)
    }

    private func stopError(_ reason: StopReason) -> Error {
        switch reason {
        case .unauthorized(let message):
            return HostCallError.unauthorized(message)
        case .upgradeRequired:
            return HostCallError.upgradeRequired
        case .failed(let message):
            return HostCallError.failed(message)
        }
    }

    // MARK: - Outbound

    func enqueueInner(_ data: Data) throws {
        guard var sealer, let continuation = outbound else {
            throw HostCallError.unreachable
        }
        let frames = try sealer.seal(message: data)
        self.sealer = sealer
        for frame in frames {
            continuation.yield(frame.json)
        }
    }

    private func dispatchInbound(_ text: String) throws {
        guard let data = text.data(using: .utf8) else { return }
        guard var opener else { return }
        guard let frame = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              frame["t"] as? String == "f",
              let counterNumber = frame["c"] as? NSNumber,
              let dText = frame["d"] as? String,
              let ciphertext = Base64URL.decode(dText) else {
            // Not a frame (e.g. a stray plaintext message): ignore.
            return
        }
        let counter = counterNumber.uint64Value
        let message: Data?
        do {
            message = try opener.open(counter: counter, ciphertext: ciphertext)
        } catch {
            socket?.close(code: 4002)
            throw error
        }
        self.opener = opener
        guard let message, let inner = try? JSONSerialization.jsonObject(with: message) as? [String: Any] else {
            return
        }
        dispatchInner(inner)
    }
}

enum ChannelHandshakeError: Error {
    case failed
    case timeout
    case identityChanged
    case rejected(code: String?)
}
