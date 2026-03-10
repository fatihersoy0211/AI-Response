import Combine
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published var session: UserSession?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let authService: AuthService

    init(authService: AuthService = AuthService()) {
        self.authService = authService
    }

    var isAuthenticated: Bool {
        session != nil
    }

    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            session = try await authService.login(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func register(name: String, email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            session = try await authService.register(name: name, email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logout() {
        session = nil
    }
}
