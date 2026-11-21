import CryptoKit
import Foundation
import Security

/// Per-install device identity: one Ed25519 device key + one X25519 push key.
/// Private keys live in the Keychain and never leave this file's boundary
/// (only signatures and public keys escape). Fresh service names for linGyU —
/// never the other app's Keychain service strings.
struct DeviceIdentity: Sendable {
    let devicePublicKey: Data // 32 bytes, Ed25519 public key (dk)
    let pushPublicKey: Data // 32 bytes, X25519 public key

    var deviceKeyBase64URL: String { Base64URL.encode(devicePublicKey) }

    func sign(_ data: Data) throws -> Data {
        try KeychainStore.sign(data: data, service: KeychainStore.deviceKeyService, account: KeychainStore.context)
    }

    static func loadOrCreate() throws -> DeviceIdentity {
        let devicePub = try KeychainStore.loadOrCreateKey(
            service: KeychainStore.deviceKeyService, kind: .signing)
        let pushPub = try KeychainStore.loadOrCreateKey(
            service: KeychainStore.pushKeyService, kind: .agreement)
        return DeviceIdentity(devicePublicKey: devicePub, pushPublicKey: pushPub)
    }

    /// Preview-only identity built from a raw private-key seed (launch-arg
    /// injection for the Codemagic simulator run). Never persisted, never
    /// touches the Keychain.
    static func preview(deviceSeed: Data) throws -> PreviewIdentity {
        let priv = try Curve25519.Signing.PrivateKey(rawRepresentation: deviceSeed)
        return PreviewIdentity(privateKey: priv)
    }
}

/// In-memory preview identity (simulator screenshot runs only).
struct PreviewIdentity: @unchecked Sendable {
    let privateKey: Curve25519.Signing.PrivateKey

    var devicePublicKey: Data { privateKey.publicKey.rawRepresentation }

    func sign(_ data: Data) throws -> Data {
        try privateKey.signature(for: data)
    }
}

enum KeychainStore {
    static let context = "local"
    static let deviceKeyService = "cn.lingyu.device-key"
    static let pushKeyService = "cn.lingyu.push-key"

    enum KeyKind {
        case signing
        case agreement
    }

    /// Returns the public key (32 raw bytes), creating the key if absent.
    static func loadOrCreateKey(service: String, kind: KeyKind) throws -> Data {
        if let existing = readPublicKey(service: service, kind: kind) {
            return existing
        }
        let privateKey: Data
        let publicKey: Data
        switch kind {
        case .signing:
            let key = Curve25519.Signing.PrivateKey()
            privateKey = key.rawRepresentation
            publicKey = key.publicKey.rawRepresentation
        case .agreement:
            let key = Curve25519.KeyAgreement.PrivateKey()
            privateKey = key.rawRepresentation
            publicKey = key.publicKey.rawRepresentation
        }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: context,
            kSecValueData as String: privateKey,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
        if let group = keychainGroup() {
            query[kSecAttrAccessGroup as String] = group
        }
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // Another process won the race; re-read and use the stored key.
            if let existing = readPublicKey(service: service, kind: kind) {
                return existing
            }
            throw KeychainError.unavailable
        }
        guard status == errSecSuccess else { throw KeychainError.unavailable }
        return publicKey
    }

    static func sign(data: Data, service: String, account: String) throws -> Data {
        guard let seed = readPrivateKey(service: service, account: account) else {
            throw KeychainError.unavailable
        }
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        return try key.signature(for: data)
    }

    static func deleteAll() {
        for service in [deviceKeyService, pushKeyService] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: context,
            ]
            SecItemDelete(query as CFDictionary)
        }
    }

    private static func readPublicKey(service: String, kind: KeyKind) -> Data? {
        guard let seed = readPrivateKey(service: service, account: context) else { return nil }
        switch kind {
        case .signing:
            guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else { return nil }
            return key.publicKey.rawRepresentation
        case .agreement:
            guard let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: seed) else { return nil }
            return key.publicKey.rawRepresentation
        }
    }

    private static func readPrivateKey(service: String, account: String) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let group = keychainGroup() {
            query[kSecAttrAccessGroup as String] = group
        }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else { return nil }
        return data
    }

    /// Team-prefixed Keychain group from the bundle, if present. Unsigned
    /// builds have no usable group — leave it unset rather than failing.
    private static func keychainGroup() -> String? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String,
              !group.isEmpty else { return nil }
        return group
    }
}

enum KeychainError: Error {
    case unavailable
}
