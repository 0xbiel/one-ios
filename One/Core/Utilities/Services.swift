import Foundation
import Security
import CryptoKit

struct RuntimeConfiguration: Sendable {
    static let localSimulatorURL = URL(string: "http://127.0.0.1:8000/api/v1")!
    let apiBaseURL: URL
    let isDemoMode: Bool

    init(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        let configured = (info["ONE_API_BASE_URL"] as? String).flatMap(URL.init(string:))
        apiBaseURL = configured ?? Self.localSimulatorURL
        // Demo data is only used when no API URL is supplied (for previews and
        // unit tests). A configured loopback, LAN, or Tailscale URL is live.
        isDemoMode = configured == nil
    }
}

protocol SessionKeyStore: Sendable {
    func save(_ value: Data, for key: String) throws
    func load(_ key: String) throws -> Data?
    func delete(_ key: String) throws
}

struct KeychainSessionStore: SessionKeyStore {
    func save(_ value: Data, for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: value] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus))
        }

        var newItem = query
        newItem[kSecValueData as String] = value
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
        }
    }

    func load(_ key: String) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        return item as? Data
    }

    func delete(_ key: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}

struct EncryptedArtifactStore {
    private let key: SymmetricKey
    init(keyData: Data) { key = SymmetricKey(data: SHA256.hash(data: keyData)) }
    func seal(_ data: Data) throws -> Data { try AES.GCM.seal(data, using: key).combined! }
    func open(_ data: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }
}

/// Preview and mock authentication must never overwrite a real Keychain session.
final class InMemorySessionStore: SessionKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func save(_ value: Data, for key: String) throws { lock.lock(); defer { lock.unlock() }; values[key] = value }
    func load(_ key: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[key] }
    func delete(_ key: String) throws { lock.lock(); defer { lock.unlock() }; values.removeValue(forKey: key) }
}
