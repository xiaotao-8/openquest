import Foundation
import Security

/// Retained IM account model (bridge page removed 2026-11-22:
/// Feishu / DingTalk / Slack / WeChat all dropped by user decision).
/// Kept so a future bridge can reuse the same stored shape
/// (`cn.lingyu.imConnections.v1`) and keychain service
/// (`cn.lingyu.im-bridge`); nothing in the app reads it today.

/// One signed-in IM account. Tokens are never stored here; only the two
/// keychain items keyed by `id.accessToken` / `id.refreshToken` hold them.
struct IMConnection: Codable, Identifiable, Equatable {
    var id: UUID
    var platform: String
    var botId: String?
    var createdAt: Date
    var displayName: String?
    var avatarURL: String?
    var teamName: String?
    var expiresAt: Date?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Date()
    }
}

enum IMConnectionStore {
    private static let key = "cn.lingyu.imConnections.v1"

    /// Loads the signed-in accounts. Records from the old credential form
    /// (no display name — they were never usable, the bridge engine never
    /// existed) are dropped here, together with their keychain items.
    /// The bridge page was removed 2026-11-22, so no new records are created.
    static func load() -> [IMConnection] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let connections = try? JSONDecoder().decode([IMConnection].self, from: data) else {
            return []
        }
        let kept = connections.filter { $0.displayName != nil }
        if kept.count != connections.count {
            for dropped in connections where dropped.displayName == nil {
                IMKeychain.delete(account: dropped.id.uuidString + ".field1")
                IMKeychain.delete(account: dropped.id.uuidString + ".field2")
            }
            save(kept)
        }
        return kept
    }

    static func save(_ connections: [IMConnection]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(connections), forKey: key)
    }
}

/// Keychain storage for IM tokens, mirroring VaultKeychain: one
/// generic-password item per value, this-device-only, never written to a
/// file and never printed.
enum IMKeychain {
    private static let service = "cn.lingyu.im-bridge"

    static func save(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
