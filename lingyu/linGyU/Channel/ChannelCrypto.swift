import CryptoKit
import Foundation

/// Channel crypto: handshake math + ChaCha20-Poly1305 frame codec.
/// Pure functions and two small structs — no I/O, no sockets.
/// All primitives are CryptoKit. Labels are protocol bytes (copy verbatim).
///
/// HKDF-SHA256 is done by hand with HMAC because Phase 1 only ever needs
/// L = 32 (one T(1) block):
///   prk  = HMAC-SHA256(key: TH, msg: ss)                 (HKDF-Extract)
///   kX   = HMAC-SHA256(key: prk, msg: info || 0x01)      (HKDF-Expand, L=32)
enum ChannelCrypto {
    static let hs1Label = "codync/hs1/v1"
    static let hs2Label = "codync/hs2/v1"
    static let d2hLabel = "codync/d2h/v1"
    static let h2dLabel = "codync/h2d/v1"
    static let frameLabel = "codync/frame/v1"
    static let pairCheckLabel = "codync/pair-check/v1"
    static let offerLabel = "codync/offer/v1"

    static func computerId(hostSignPub: Data) -> String {
        Base64URL.encode(Digest.sha256(hostSignPub).prefix(16))
    }

    static func hs1Input(hostSignPub: Data, devicePub: Data, ephemeralPub: Data, nonce: Data) -> Data {
        let cidRaw = Digest.sha256(hostSignPub).prefix(16)
        return Data(hs1Label.utf8) + cidRaw + devicePub + ephemeralPub + nonce
    }

    static func transcriptHash(hostSignPub: Data, devicePub: Data, ephemeralPub: Data, nonce: Data, hostEphemeralPub: Data) -> Data {
        let cidRaw = Digest.sha256(hostSignPub).prefix(16)
        return Digest.sha256(Data(hs2Label.utf8) + cidRaw + devicePub + ephemeralPub + nonce + hostEphemeralPub)
    }

    static func deriveKeys(transcriptHash: Data, sharedSecret: Data) -> (d2h: SymmetricKey, h2d: SymmetricKey)? {
        guard !sharedSecret.allSatisfy({ $0 == 0 }) else { return nil }
        let prkData = Data(HMAC<SHA256>.authenticationCode(for: sharedSecret, using: SymmetricKey(data: transcriptHash)))
        let prk = SymmetricKey(data: prkData)
        let d2h = SymmetricKey(data: Data(HMAC<SHA256>.authenticationCode(for: Data(d2hLabel.utf8) + Data([0x01]), using: prk)))
        let h2d = SymmetricKey(data: Data(HMAC<SHA256>.authenticationCode(for: Data(h2dLabel.utf8) + Data([0x01]), using: prk)))
        return (d2h, h2d)
    }

    static func pairCheckCode(devicePub: Data, hostSignPub: Data) -> String {
        let hash = Digest.sha256(Data(pairCheckLabel.utf8) + devicePub + hostSignPub)
        var value: UInt32 = 0
        for byte in hash.prefix(4) { value = (value << 8) | UInt32(byte) }
        return String(format: "%06d", value % 1_000_000)
    }

    static func offerId(codeBytes: Data) -> String {
        Base64URL.encode(Digest.sha256(Data(offerLabel.utf8) + codeBytes).prefix(16))
    }
}

enum ChannelCryptoError: Error {
    case badCounter
    case decryptFailed
    case malformed
    case tooLarge
    case exhausted
}

/// Seals one inner message into one or more frames.
/// Counter starts at 0, +1 per frame; never wraps (2^32 -> exhausted).
struct FrameSealer {
    let key: SymmetricKey
    private(set) var counter: UInt64 = 0

    static let maxChunk = 262_144

    mutating func seal(message: Data) throws -> [(counter: UInt64, json: String)] {
        var frames: [(counter: UInt64, json: String)] = []
        var rest = message
        repeat {
            let take = min(rest.count, Self.maxChunk)
            let chunk = rest.prefix(take)
            rest = rest.dropFirst(take)
            let final = rest.isEmpty
            guard counter < UInt64(UInt32.max) + 1 else { throw ChannelCryptoError.exhausted }
            let json = try sealChunk(chunk: Data(chunk), counter: counter, final: final)
            frames.append((counter, json))
            counter += 1
        } while !rest.isEmpty
        return frames
    }

    private func sealChunk(chunk: Data, counter: UInt64, final: Bool) throws -> String {
        let nonce = Self.makeNonce(counter: counter)
        let aad = Data(ChannelCrypto.frameLabel.utf8) + U64.bigEndian(counter)
        var plaintext = Data([final ? 0x00 : 0x01])
        plaintext.append(chunk)
        let sealed = try ChaChaPoly.seal(plaintext, using: key, nonce: nonce, authenticating: aad)
        let d = Base64URL.encode(sealed.combined)
        return "{\"t\":\"f\",\"c\":\(counter),\"d\":\"\(d)\"}"
    }

    static func makeNonce(counter: UInt64) -> ChaChaPoly.Nonce {
        var bytes = Data([0, 0, 0, 0])
        bytes.append(U64.bigEndian(counter))
        return try! ChaChaPoly.Nonce(data: bytes)
    }
}

/// Opens frames in strict counter order, reassembling one inner message.
struct FrameOpener {
    let key: SymmetricKey
    let limit: Int
    private(set) var counter: UInt64 = 0
    private var buffer = Data()

    /// Explicit init: the memberwise init is private because `buffer` is
    /// a private stored property.
    init(key: SymmetricKey, limit: Int) {
        self.key = key
        self.limit = limit
    }

    mutating func open(counter: UInt64, ciphertext: Data) throws -> Data? {
        guard counter == self.counter else { throw ChannelCryptoError.badCounter }
        guard ciphertext.count >= 17 else { throw ChannelCryptoError.malformed }
        let nonce = FrameSealer.makeNonce(counter: counter)
        let aad = Data(ChannelCrypto.frameLabel.utf8) + U64.bigEndian(counter)
        let sealed: ChaChaPoly.SealedBox
        let plaintext: Data
        do {
            sealed = try ChaChaPoly.SealedBox(combined: ciphertext)
            plaintext = try ChaChaPoly.open(sealed, using: key, authenticating: aad)
        } catch {
            throw ChannelCryptoError.decryptFailed
        }
        guard let flag = plaintext.first, flag <= 0x01 else { throw ChannelCryptoError.malformed }
        let chunk = plaintext.dropFirst()
        guard buffer.count + chunk.count <= limit else { throw ChannelCryptoError.tooLarge }
        buffer.append(chunk)
        self.counter += 1
        if flag == 0x00 {
            let done = buffer
            buffer = Data()
            return done
        }
        return nil
    }
}
