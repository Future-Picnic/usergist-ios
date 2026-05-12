import Foundation
import Security

// PORTED FROM (concept): packages/sdk-react-native/src/internal/storage.ts
//
// Keychain-backed secrets store for identity, consent, and push token.
// We deliberately scope each entry to the SDK's writeKey hash so two apps
// embedding the SDK against different write keys never collide.
//
// Failures are non-fatal: Keychain access can fail when entitlements are
// missing (e.g. host app didn't add the Keychain entitlement) or when the
// device is in a transient locked state. Callers should treat a `nil`
// read as "no data yet" and tolerate a `false` write as best-effort.

final class SecureStore {
    /// Logical keys used by the SDK. Stable values become Keychain account
    /// strings; renames require a migration.
    enum Key: String {
        case identity = "studio.ritmus.feedback.identity"
        case consent = "studio.ritmus.feedback.consent"
        case pushToken = "studio.ritmus.feedback.push_token"
    }

    private let service: String
    private let logger: RitmusLogger

    init(writeKeyHash: String, logger: RitmusLogger) {
        self.service = "studio.ritmus.feedback.\(writeKeyHash)"
        self.logger = logger
    }

    /// Returns the value for `key`, or `nil` if not present / access denied.
    func read(_ key: Key) -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            logger.warn("SecureStore.read(\(key.rawValue)) failed: \(status)")
            return nil
        }
        return item as? Data
    }

    /// Stores `data` against `key`. Returns `false` on failure (logged).
    @discardableResult
    func write(_ key: Key, _ data: Data) -> Bool {
        let query = baseQuery(key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // Available after first device unlock; survives backups, reboots,
            // and works for background push token updates.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus != errSecItemNotFound {
            logger.warn("SecureStore.write(\(key.rawValue)) update failed: \(updateStatus)")
        }
        var addQuery = query
        addQuery.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            logger.warn("SecureStore.write(\(key.rawValue)) add failed: \(addStatus)")
            return false
        }
        return true
    }

    @discardableResult
    func delete(_ key: Key) -> Bool {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func baseQuery(_ key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }
}
