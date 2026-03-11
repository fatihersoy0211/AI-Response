import AuthenticationServices
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published var session: UserSession?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let authService: AuthService

    init(authService: AuthService = AuthService()) {
        self.authService = authService
        // Restore saved session on launch, then verify it's still valid
        session = KeychainService.loadSession()
        if session != nil {
            Task { await verifySession() }
        }
    }

    /// Ping /auth/me — if the stored token is rejected (401) silently log out.
    private func verifySession() async {
        guard let token = session?.accessToken else { return }
        do {
            _ = try await authService.me(token: token)
        } catch let error as APIError where error.isUnauthorized {
            KeychainService.deleteSession()
            session = nil
        } catch {
            // Network error or other — keep the session, try again later
        }
    }

    var isAuthenticated: Bool { session != nil }

    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let s = try await authService.login(email: email, password: password)
            KeychainService.saveSession(s)
            session = s
        } catch {
            handle(error: error)
        }
    }

    func register(name: String, email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let s = try await authService.register(name: name, email: email, password: password)
            KeychainService.saveSession(s)
            session = s
        } catch {
            handle(error: error)
        }
    }

    /// Called from the SignInWithAppleButton onCompletion handler.
    func handleAppleSignIn(result: Result<ASAuthorization, Error>) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            switch result {
            case .success(let authorization):
                guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let tokenData = cred.identityToken,
                      let identityToken = String(data: tokenData, encoding: .utf8)
                else { throw AppleSignInError.invalidCredential }

                let nameParts = [cred.fullName?.givenName, cred.fullName?.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)

                let credential = AppleCredential(
                    userIdentifier: cred.user,
                    identityToken: identityToken,
                    name: nameParts.isEmpty ? nil : nameParts,
                    email: cred.email
                )
                let s = try await authService.loginWithApple(credential: credential)
                KeychainService.saveSession(s)
                session = s

            case .failure(let error):
                if let authError = error as? ASAuthorizationError {
                    switch authError.code {
                    case .canceled: return
                    case .unknown:
                        errorMessage = "Apple Sign In could not start. Please make sure you are signed in to your Apple ID in Settings → [Your Name]."
                        return
                    default: break
                    }
                }
                throw error
            }
        } catch {
            handle(error: error)
        }
    }

    private func handle(error: Error) {
        if let api = error as? APIError, api.isUnauthorized {
            KeychainService.deleteSession()
            session = nil
        } else {
            errorMessage = error.localizedDescription
        }
    }

    func logout() {
        if let s = session {
            Task { try? await authService.logout(token: s.accessToken) }
        }
        KeychainService.deleteSession()
        session = nil
    }
}
