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
