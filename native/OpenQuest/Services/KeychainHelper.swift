import Foundation
import Security

/// 供应商 API Key 只存系统 Keychain，不进 JSON 快照、不进任何文件备份。
enum KeychainHelper {
    private static let service = "com.xiaotao.openquest.providers"

    /// 同进程缓存：钥匙串写失败时（模拟器偶发），当次启动不丢 Key；
    /// 钥匙串仍是跨启动的唯一真相来源，缓存只补当次。
    private static var cache: [String: String] = [:]
    private static let cacheLock = NSLock()

    /// 返回 SecItemAdd 的状态码（errSecSuccess = 0）；调用方需要时可打印诊断。
    @discardableResult
    static func setKey(_ key: String, ref: String) -> OSStatus {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ref,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        let status = SecItemAdd(attrs as CFDictionary, nil)
        cacheLock.withLock { cache[ref] = key }
        return status
    }

    static func key(ref: String) -> String? {
        if let cached = cacheLock.withLock({ cache[ref] }) { return cached }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ref,
        ]
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteKey(ref: String) {
        cacheLock.withLock { cache.removeValue(forKey: ref) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ref,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
