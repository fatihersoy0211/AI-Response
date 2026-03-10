import Foundation

struct UserSession: Codable {
    let userId: String
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
}

struct AuthResponse: Codable {
    let userId: String
    let accessToken: String
    let refreshToken: String?

    func toSession() -> UserSession {
        UserSession(userId: userId, accessToken: accessToken, refreshToken: refreshToken)
    }
}
