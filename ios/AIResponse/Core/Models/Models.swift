import AuthenticationServices
import Foundation

// Apple Sign In types — shared between AppleSignInService, AuthService, AppViewModel
struct AppleCredential {
    let userIdentifier: String
    let identityToken: String
    let name: String?
    let email: String?
}

enum AppleSignInError: LocalizedError {
    case invalidCredential

    var errorDescription: String? {
        "Apple credentials could not be retrieved"
    }
}

struct UserSession: Codable {
    let userId: String
    let name: String
    let email: String
    let accessToken: String
    let refreshToken: String?
}

struct UserProject: Codable, Identifiable, Hashable {
    let projectId: String
    let name: String
    let createdAtISO8601: String
    let updatedAtISO8601: String

    var id: String { projectId }
}

struct SourceItem: Codable, Identifiable {
    let sourceId: String
    let sourceType: String
    let title: String
    let analysis: String
    let createdAtISO8601: String

    var id: String { sourceId }
}

struct ProjectContextSummary: Codable {
    let summary: String
    let sources: [SourceItem]
    let lastUpdatedISO8601: String
}

struct AIQueryRequest: Codable {
    let projectId: String
    let transcript: String
    /// All previous transcript rounds accumulated in this session
    let sessionTranscript: String?
    let userName: String?
}

struct AuthResponse: Codable {
    let userId: String
    let name: String
    let email: String
    let accessToken: String
    let refreshToken: String?

    func toSession() -> UserSession {
        UserSession(userId: userId, name: name, email: email, accessToken: accessToken, refreshToken: refreshToken)
    }
}
