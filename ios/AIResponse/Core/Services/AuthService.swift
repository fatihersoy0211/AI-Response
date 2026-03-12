import Foundation

struct AuthService: AuthServicing {
    private let api = APIClient()

    func login(email: String, password: String) async throws -> UserSession {
        let payload = ["email": email, "password": password]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await api.request(path: "/auth/login", method: "POST", body: body)
        return try JSONDecoder().decode(AuthResponse.self, from: data).toSession()
    }

    func register(name: String, email: String, password: String) async throws {
        let payload = ["name": name, "email": email, "password": password]
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await api.request(path: "/auth/register", method: "POST", body: body)
    }

    func verifyEmail(email: String, code: String) async throws -> UserSession {
        let payload = ["email": email, "code": code]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await api.request(path: "/auth/verify-email", method: "POST", body: body)
        return try JSONDecoder().decode(AuthResponse.self, from: data).toSession()
    }

    func forgotPassword(email: String) async throws {
        let payload = ["email": email]
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await api.request(path: "/auth/forgot-password", method: "POST", body: body)
    }

    func verifyReset(email: String, code: String, newPassword: String) async throws -> UserSession {
        let payload = ["email": email, "code": code, "newPassword": newPassword]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await api.request(path: "/auth/verify-reset", method: "POST", body: body)
        return try JSONDecoder().decode(AuthResponse.self, from: data).toSession()
    }

    func loginWithApple(credential: AppleCredential) async throws -> UserSession {
        var payload: [String: Any] = [
            "identityToken": credential.identityToken,
            "userIdentifier": credential.userIdentifier,
        ]
        if let name  = credential.name  { payload["name"]  = name  }
        if let email = credential.email { payload["email"] = email }
        if let nonce = credential.nonce { payload["nonce"] = nonce }
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

struct MockAuthService: AuthServicing {
    let session: UserSession?

    func login(email: String, password: String) async throws -> UserSession {
        try resolvedSession()
    }

    func register(name: String, email: String, password: String) async throws {
        // Mock: immediately succeeds without sending email
    }

    func verifyEmail(email: String, code: String) async throws -> UserSession {
        try resolvedSession()
    }

    func forgotPassword(email: String) async throws {}

    func verifyReset(email: String, code: String, newPassword: String) async throws -> UserSession {
        try resolvedSession()
    }

    func loginWithApple(credential: AppleCredential) async throws -> UserSession {
        try resolvedSession()
    }

    func me(token: String) async throws {}

    func logout(token: String) async throws {}

    private func resolvedSession() throws -> UserSession {
        guard let session else {
            throw TestFailure.forced("Missing mock session")
        }
        return session
    }
}
