import Foundation
import Security

/// Account is the macOS user, matching `security add-generic-password -s <service> -a $USER`.
enum KeychainStore {
    /// An item's ACL is bound to the build that stored it, so a differently-signed build is
    /// refused rather than told "missing" — and the two need different fixes.
    enum ReadResult {
        case value(String)
        case missing
        case refused(OSStatus)
    }

    static func read(service: String) -> ReadResult {
        var query = baseQuery(service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return .missing }
        guard status == errSecSuccess else { return .refused(status) }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            return .missing
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .missing : .value(trimmed)
    }

    static func write(_ value: String, service: String) {
        let query = baseQuery(service: service)
        let data = Data(value.utf8)

        if SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecSuccess {
            return
        }
        // An earlier build's ACL refuses the update; replacing the item rebinds it to this build.
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        SecItemAdd(insert as CFDictionary, nil)
    }

    static func delete(service: String) {
        SecItemDelete(baseQuery(service: service) as CFDictionary)
    }

    private static func baseQuery(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: NSUserName(),
        ]
    }
}
