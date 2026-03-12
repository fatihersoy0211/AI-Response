import Foundation
import Security

enum KeychainService {
    private static let service = "com.fatihersoy.airesponse"
    private static let sessionKey = "userSession"

    static func saveSession(_ session: UserSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: sessionKey,
        ]
        // Try update first, then add
        let update: [CFString: Any] = [kSecValueData: data]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = query
            add[kSecValueData] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func loadSession() -> UserSession? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: sessionKey,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(UserSession.self, from: data)
    }

    static func deleteSession() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: sessionKey,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

final class KeychainSessionStore: SessionStoring {
    func saveSession(_ session: UserSession) {
        KeychainService.saveSession(session)
    }

    func loadSession() -> UserSession? {
        KeychainService.loadSession()
    }

    func deleteSession() {
        KeychainService.deleteSession()
    }
}

final class InMemorySessionStore: SessionStoring {
    private var storedSession: UserSession?

    init(initialSession: UserSession? = nil) {
        storedSession = initialSession
    }

    func saveSession(_ session: UserSession) {
        storedSession = session
    }

    func loadSession() -> UserSession? {
        storedSession
    }

    func deleteSession() {
        storedSession = nil
    }
}

// MARK: - Apple identity / profile secure storage

/// Persists the stable Apple userIdentifier (sub) for ASAuthorizationAppleIDProvider
/// credential-state checks on every app launch. This is NOT the session token.
enum AppleIdentityStore {
    private static let service = "com.fatihersoy.airesponse"
    private static let account = "appleUserId"

    static func save(_ userID: String) {
        guard let data = userID.data(using: .utf8) else { return }
        upsert(data: data, account: account)
    }

    static func load() -> String? {
        read(account: account).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func delete() {
        remove(account: account)
    }

    // MARK: Private Keychain helpers

    private static func upsert(data: Data, account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let update: [CFString: Any] = [kSecValueData: data]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = query
            add[kSecValueData] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static func read(account: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func remove(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Persists the user's display name and email received on FIRST Apple Sign In.
/// Apple only provides fullName/email on the very first authorization; this store
/// ensures they survive subsequent sign-ins where Apple returns nil for both fields.
enum AppleProfileStore {
    private static let service = "com.fatihersoy.airesponse"
    private static let nameKey  = "appleUserName"
    private static let emailKey = "appleUserEmail"

    static func saveName(_ name: String) {
        guard !name.isEmpty, let data = name.data(using: .utf8) else { return }
        upsert(data: data, account: nameKey)
    }

    static func saveEmail(_ email: String) {
        guard !email.isEmpty, let data = email.data(using: .utf8) else { return }
        upsert(data: data, account: emailKey)
    }

    static func loadName() -> String? {
        read(account: nameKey).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func loadEmail() -> String? {
        read(account: emailKey).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func delete() {
        remove(account: nameKey)
        remove(account: emailKey)
    }

    // MARK: Private Keychain helpers

    private static func upsert(data: Data, account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let update: [CFString: Any] = [kSecValueData: data]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = query
            add[kSecValueData] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static func read(account: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func remove(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - OpenAI API Key storage

enum APIKeyKeychainStore {
    private static let service = "com.fatihersoy.airesponse"
    private static let account = "openaiApiKey"

    static func save(_ key: String) {
        guard let data = key.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let update: [CFString: Any] = [kSecValueData: data]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = query
            add[kSecValueData] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func load() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static var isSet: Bool { !(load() ?? "").isEmpty }
}
