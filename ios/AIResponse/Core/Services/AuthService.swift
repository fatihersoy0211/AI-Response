import Foundation

struct AuthService {
    private let api = APIClient()

    func login(email: String, password: String) async throws -> UserSession {
        let payload = ["email": email, "password": password]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await api.request(path: "/auth/login", method: "POST", body: body)

        let decoded = try JSONDecoder().decode(AuthResponse.self, from: data)
        return decoded.toSession()
    }

    func register(name: String, email: String, password: String) async throws -> UserSession {
        let payload = ["name": name, "email": email, "password": password]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await api.request(path: "/auth/register", method: "POST", body: body)

        let decoded = try JSONDecoder().decode(AuthResponse.self, from: data)
        return decoded.toSession()
    }
}
