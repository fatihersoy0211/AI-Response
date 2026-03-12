import AuthenticationServices
import Foundation

// MARK: - Apple credential validity

enum AppleCredentialValidity {
    case authorized
    case invalidated    // revoked, notFound, or transferred
    case unknown        // network / system error — treat conservatively
}

// MARK: - Auth state machine

enum AuthState: Equatable {
    case loading            // validating a saved session — show splash/loading UI
    case authenticated(UserSession)
    case unauthenticated

    static func == (lhs: AuthState, rhs: AuthState) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading), (.unauthenticated, .unauthenticated): return true
        case (.authenticated(let a), .authenticated(let b)): return a.userId == b.userId
        default: return false
        }
    }
}

// MARK: - AppViewModel

@MainActor
final class AppViewModel: ObservableObject {
    @Published var authState: AuthState = .loading
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Lightweight UX session memory — stored in UserDefaults (not sensitive)
    @Published private(set) var lastSignInProvider: String? =
        UserDefaults.standard.string(forKey: "lastSignInProvider")
    @Published private(set) var lastSignInAt: Date? = {
        let ts = UserDefaults.standard.double(forKey: "lastSignInTimestamp")
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }()

    private let authService: any AuthServicing
    private let sessionStore: any SessionStoring
    private let launchConfiguration: AppLaunchConfiguration

    // MARK: - Backwards-compatible computed properties

    /// Returns the current session when authenticated; nil otherwise.
    var session: UserSession? {
        guard case .authenticated(let s) = authState else { return nil }
        return s
    }

    var isAuthenticated: Bool {
        guard case .authenticated = authState else { return false }
        return true
    }

    // MARK: - Init

    init(
        authService: any AuthServicing = AuthService(),
        sessionStore: any SessionStoring = KeychainSessionStore(),
        launchConfiguration: AppLaunchConfiguration = .current
    ) {
        self.authService = authService
        self.sessionStore = sessionStore
        self.launchConfiguration = launchConfiguration

        if let preloaded = launchConfiguration.preloadedSession {
            // UI test fast-path: skip all validation
            authState = .authenticated(preloaded)
        } else if let saved = sessionStore.loadSession() {
            authState = .loading
            Task { await restoreSession(saved) }
        } else {
            authState = .unauthenticated
        }
    }

    // MARK: - Session restoration

    /// Full restoration path: Apple credential state check → backend token check → authenticate.
    private func restoreSession(_ saved: UserSession) async {
        // 1. If the user previously signed in with Apple, validate their credential state first.
        //    This detects revoked accounts before we ever try the backend.
        if let appleUserID = AppleIdentityStore.load() {
            let credState = await appleCredentialState(for: appleUserID)
            if credState == .invalidated {
                // Apple has revoked or removed this credential — force re-login
                signOutCleanly()
                return
            }
            // .authorized or .unknown → proceed (network issues shouldn't sign the user out)
        }

        // 2. Verify the backend token is still accepted.
        do {
            try await authService.me(token: saved.accessToken)
            completeAuthentication(saved, provider: UserDefaults.standard.string(forKey: "lastSignInProvider"))
        } catch let error as APIError where error.isUnauthorized {
            // Token explicitly rejected — clear and re-login
            signOutCleanly()
        } catch {
            // Network unreachable or other transient error: restore session optimistically.
            // The user should not be logged out because their Wi-Fi is off.
            completeAuthentication(saved, provider: UserDefaults.standard.string(forKey: "lastSignInProvider"))
        }
    }

    // MARK: - Email / password

    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let s = try await authService.login(email: email, password: password)
            completeAuthentication(s, provider: "email")
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
            completeAuthentication(s, provider: "email")
        } catch {
            handle(error: error)
        }
    }

    // MARK: - Apple Sign In

    /// Called from LoginView's `SignInWithAppleButton` onCompletion handler.
    /// `nonce` is the raw (unhashed) nonce generated in the view before the Apple sheet appeared.
    func handleAppleSignIn(result: Result<ASAuthorization, Error>, nonce: String?) async {
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

                // Persist the stable Apple userIdentifier for future credential-state checks.
                // This is the only reliable long-lived Apple identity reference.
                AppleIdentityStore.save(cred.user)

                // Apple provides fullName and email ONLY on the very first authorization.
                // Persist them immediately so they are never lost on subsequent sign-ins.
                let givenName  = cred.fullName?.givenName?.trimmingCharacters(in: .whitespaces) ?? ""
                let familyName = cred.fullName?.familyName?.trimmingCharacters(in: .whitespaces) ?? ""
                let fullName   = [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")

                if !fullName.isEmpty {
                    AppleProfileStore.saveName(fullName)
                }
                if let email = cred.email, !email.isEmpty {
                    AppleProfileStore.saveEmail(email)
                }

                // Use persisted profile as fallback when Apple omits fields on returning sign-ins.
                let resolvedName  = fullName.isEmpty  ? AppleProfileStore.loadName()  : fullName
                let resolvedEmail = (cred.email?.isEmpty == false) ? cred.email : AppleProfileStore.loadEmail()

                let credential = AppleCredential(
                    userIdentifier: cred.user,
                    identityToken: identityToken,
                    name: resolvedName,
                    email: resolvedEmail,
                    nonce: nonce
                )
                let s = try await authService.loginWithApple(credential: credential)
                completeAuthentication(s, provider: "apple")

            case .failure(let error):
                if let authError = error as? ASAuthorizationError {
                    switch authError.code {
                    case .canceled:
                        return  // User tapped Cancel — not an error, just dismiss
                    case .unknown:
                        errorMessage = "Apple Sign In could not be completed. Please make sure you are signed in to iCloud by going to Settings → [Your Name]."
                        return
                    default:
                        throw authError
                    }
                }
                throw error
            }
        } catch {
            // During a sign-in attempt the user is NOT yet authenticated.
            // A 401 from the backend means "auth failed" — show the error rather than
            // silently calling signOutCleanly() (which shows no message at all).
            if let api = error as? APIError {
                errorMessage = api.localizedDescription
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Sign out

    func logout() {
        if let s = session {
            Task { try? await authService.logout(token: s.accessToken) }
        }
        signOutCleanly()
    }

    // MARK: - Helpers

    private func completeAuthentication(_ session: UserSession, provider: String?) {
        sessionStore.saveSession(session)
        authState = .authenticated(session)

        // Persist lightweight UX session memory (non-sensitive)
        if let provider {
            UserDefaults.standard.set(provider, forKey: "lastSignInProvider")
            lastSignInProvider = provider
        }
        let now = Date()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "lastSignInTimestamp")
        lastSignInAt = now
    }

    private func signOutCleanly() {
        sessionStore.deleteSession()
        AppleIdentityStore.delete()
        AppleProfileStore.delete()
        authState = .unauthenticated
    }

    private func handle(error: Error) {
        if let api = error as? APIError, api.isUnauthorized {
            signOutCleanly()
        } else {
            errorMessage = error.localizedDescription
        }
    }

    /// Bridges ASAuthorizationAppleIDProvider's callback API into async/await.
    private func appleCredentialState(for userID: String) async -> AppleCredentialValidity {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
                switch state {
                case .authorized:
                    continuation.resume(returning: .authorized)
                case .revoked, .notFound, .transferred:
                    continuation.resume(returning: .invalidated)
                @unknown default:
                    continuation.resume(returning: .unknown)
                }
            }
        }
    }
}
