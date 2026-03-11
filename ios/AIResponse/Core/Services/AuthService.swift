import Foundation

struct AuthService {
    private let api = APIClient()

    func login(email: String, password: String) async throws -> UserSession {
        let payload = ["email": email, "password": password]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await api.request(path: "/auth/login", method: "POST", body: body)
        return try JSONDecoder().decode(AuthResponse.self, from: data).toSession()
    }

    func register(name: String, email: String, password: String) async throws -> UserSession {
        let payload = ["name": name, "email": email, "password": password]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await api.request(path: "/auth/register", method: "POST", body: body)
        return try JSONDecoder().decode(AuthResponse.self, from: data).toSession()
    }

    func loginWithApple(credential: AppleCredential) async throws -> UserSession {
        var payload: [String: Any] = [
            "identityToken": credential.identityToken,
            "userIdentifier": credential.userIdentifier,
        ]
        if let name = credential.name { payload["name"] = name }
        if let email = credential.email { payload["email"] = email }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await api.request(path: "/auth/apple", method: "POST", body: body)
        return try JSONDecoder().decode(AuthResponse.self, from: data).toSession()
    }

    func me(token: String) async throws -> Void {
        _ = try await api.request(path: "/auth/me", token: token)
    }

    func logout(token: String) async throws {
        _ = try await api.request(path: "/auth/logout", method: "POST", token: token)
    }
}
