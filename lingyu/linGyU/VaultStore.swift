import Foundation
import Security
import SwiftUI

/// 安全凭证库: the user keeps their own logins here and decides which
/// ones an agent may use. Metadata (title, username, permission) lives in
/// UserDefaults; the password itself lives only in the keychain, never in
/// UserDefaults or any file.
struct VaultLogin: Codable, Identifiable {
    var id = UUID()
    var title: String
    var username: String
    /// "ask" (ask every time) or "auto" (agent may use it directly).
    var agentPermission: String
    var createdAt: Date = Date()
}

@MainActor
final class VaultStore: ObservableObject {
    static let key = "cn.lingyu.vault.v1"
    @Published private(set) var logins: [VaultLogin] = []

    init() { load() }

    func add(title: String, username: String, password: String, permission: String) {
        let login = VaultLogin(title: title, username: username, agentPermission: permission)
        guard VaultKeychain.save(password, id: login.id) else { return }
        logins.append(login)
        save()
    }

    func update(id: UUID, title: String, username: String, password: String?, permission: String) {
        guard let index = logins.firstIndex(where: { $0.id == id }) else { return }
        if let password, !password.isEmpty {
            guard VaultKeychain.save(password, id: id) else { return }
        }
        logins[index].title = title
        logins[index].username = username
        logins[index].agentPermission = permission
        save()
    }

    func delete(id: UUID) {
        logins.removeAll { $0.id == id }
        VaultKeychain.delete(id: id)
        save()
    }

    func password(for id: UUID) -> String? {
        VaultKeychain.read(id: id)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([VaultLogin].self, from: data) else { return }
        logins = decoded
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(logins), forKey: Self.key)
    }
}

enum VaultKeychain {
    static let service = "cn.lingyu.vault"

    static func save(_ password: String, id: UUID) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    static func read(id: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(id: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }
}
