import Foundation
import Security

/// API keys live here, not in `profiles.json`. That file is plain text in
/// Documents and is backed up; a key written there would be a credential in a
/// synced folder.
enum KeychainService {
    static let service = "com.toshit.mevin"

    static func key(for provider: AIProvider) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func hasKey(for provider: AIProvider) -> Bool {
        key(for: provider) != nil
    }

    static func setKey(_ raw: String, for provider: AIProvider) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }
        deleteKey(for: provider)
        let payload: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(payload as CFDictionary, nil)
    }

    static func deleteKey(for provider: AIProvider) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.account
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Last four characters only. Anything more would be a fragment in a log.
    static func lastFour(for provider: AIProvider) -> String? {
        guard let key = key(for: provider), key.count >= 4 else { return nil }
        return String(key.suffix(4))
    }

    static func masked(for provider: AIProvider) -> String? {
        guard let four = lastFour(for: provider) else { return nil }
        return "••••••••••••\(four)"
    }
}
