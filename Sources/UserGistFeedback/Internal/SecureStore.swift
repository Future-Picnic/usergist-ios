import Foundation
import Security

// PORTED FROM (concept): packages/sdk-react-native/src/internal/storage.ts
//
// Keychain-backed secrets store for identity, consent, and push token.
// We deliberately scope each entry to the SDK's writeKey hash so two apps
// embedding the SDK against different write keys never collide.
//
// Failures are non-fatal. Credential-bearing values fail closed instead of
// falling back to plaintext UserDefaults; non-secret compatibility state can
// still use the fallback when Keychain is temporarily unavailable.

final class SecureStore {
    /// Logical keys used by the SDK. Stable values become Keychain account
    /// strings; renames require a migration.
    enum Key: String {
        case identity = "studio.usergist.feedback.identity"
        case consent = "studio.usergist.feedback.consent"
        case pushToken = "studio.usergist.feedback.push_token"
        case subjectToken = "studio.usergist.feedback.subject_token"
        case mutationQueue = "studio.usergist.feedback.mutation_queue"
    }

    private let service: String
    private let logger: UserGistLogger
    private let fallback: UserDefaults

    init(writeKeyHash: String, logger: UserGistLogger) {
        self.service = "studio.usergist.feedback.\(writeKeyHash)"
        self.logger = logger
        self.fallback = .standard
    }

    /// Returns the value for `key`, or `nil` if not present / access denied.
    func read(_ key: Key) -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return readFallbackOrMigrate(key)
        }
        guard status == errSecSuccess else {
            logger.warn("SecureStore.read(\(key.rawValue)) failed: \(status)")
            if key.requiresSecureStorage {
                fallback.removeObject(forKey: fallbackKey(key))
                return nil
            }
            return fallbackData(key)
        }
        if let data = item as? Data {
            fallback.removeObject(forKey: fallbackKey(key))
            return data
        }
        return readFallbackOrMigrate(key)
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
        if updateStatus == errSecSuccess {
            fallback.removeObject(forKey: fallbackKey(key))
            return true
        }
        if updateStatus != errSecItemNotFound {
            logger.warn("SecureStore.write(\(key.rawValue)) update failed: \(updateStatus)")
        }
        var addQuery = query
        addQuery.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            logger.warn("SecureStore.write(\(key.rawValue)) add failed: \(addStatus)")
            if key.requiresSecureStorage {
                fallback.removeObject(forKey: fallbackKey(key))
                return false
            }
            fallback.set(data, forKey: fallbackKey(key))
            return fallback.data(forKey: fallbackKey(key)) == data
        }
        fallback.removeObject(forKey: fallbackKey(key))
        return true
    }

    @discardableResult
    func delete(_ key: Key) -> Bool {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        fallback.removeObject(forKey: fallbackKey(key))
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func baseQuery(_ key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }

    private func fallbackKey(_ key: Key) -> String {
        "\(service).fallback.\(key.rawValue)"
    }

    private func fallbackData(_ key: Key) -> Data? {
        fallback.data(forKey: fallbackKey(key))
    }

    private func readFallbackOrMigrate(_ key: Key) -> Data? {
        guard let legacy = fallbackData(key) else { return nil }
        guard key.requiresSecureStorage else { return legacy }
        if write(key, legacy) { return legacy }
        fallback.removeObject(forKey: fallbackKey(key))
        return nil
    }
}

private extension SecureStore.Key {
    var requiresSecureStorage: Bool {
        switch self {
        case .pushToken, .subjectToken, .mutationQueue:
            return true
        case .identity, .consent:
            return false
        }
    }
}
