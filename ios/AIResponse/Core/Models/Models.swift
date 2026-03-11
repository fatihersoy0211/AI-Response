import Foundation

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

protocol AuthServicing {
    func login(email: String, password: String) async throws -> UserSession
    func register(name: String, email: String, password: String) async throws -> UserSession
    func loginWithApple(credential: AppleCredential) async throws -> UserSession
    func me(token: String) async throws
    func logout(token: String) async throws
}

protocol SessionStoring {
    func saveSession(_ session: UserSession)
    func loadSession() -> UserSession?
    func deleteSession()
}

protocol TranscriptionServicing {
    func finalizeTranscript(from rawTranscript: String) async throws -> String
}

protocol AIResponseServicing {
    func streamAnswer(context: AIGenerationContext, token: String) -> AsyncThrowingStream<String, Error>
}

protocol ProjectRepository {
    func listProjects(token: String) async throws -> [UserProject]
    func createProject(name: String, token: String) async throws -> UserProject
    func uploadTextSource(projectId: String, title: String, text: String, token: String) async throws -> SourceItem
    func uploadFileSource(projectId: String, fileName: String, mimeType: String, fileData: Data, token: String) async throws -> SourceItem
    func saveTranscript(projectId: String, title: String, transcript: String, token: String) async throws -> SourceItem
    func fetchProjectContext(projectId: String, token: String) async throws -> ProjectContextSummary
}

struct AIGenerationContext: Equatable {
    let projectId: String
    let projectName: String
    let projectContext: String
    let currentTranscript: String
    let transcriptMemory: [String]
    let userName: String?
    let persona: String

    var combinedTranscriptMemory: String {
        transcriptMemory.joined(separator: "\n")
    }
}

enum TestFailure: LocalizedError {
    case forced(String)

    var errorDescription: String? {
        switch self {
        case .forced(let message):
            return message
        }
    }
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
