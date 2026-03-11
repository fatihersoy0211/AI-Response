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

// MARK: - New typed source models

struct ProjectDocument: Codable, Identifiable {
    let sourceId: String
    let sourceType: String   // "text" or "file"
    let title: String
    let analysis: String
    let createdAtISO8601: String
    var id: String { sourceId }
}

struct TranscriptSegment: Codable, Identifiable {
    let sourceId: String
    let title: String
    let analysis: String
    let createdAtISO8601: String
    var id: String { sourceId }
}

struct ProjectAudioAsset: Codable, Identifiable {
    let assetId: String
    let title: String
    let mimeType: String
    let createdAtISO8601: String
    var id: String { assetId }
}

struct ProjectSummary: Codable, Identifiable {
    let summaryId: String
    let style: String
    let content: String
    let generatedAtISO8601: String
    var id: String { summaryId }
}

/// Layered context snapshot — typed by source category for layered AI context assembly
struct ProjectContextSnapshot: Codable {
    let projectName: String
    let documentContext: String       // Layer 2: pre-assembled document analyses
    let transcriptHistory: String     // Layer 3: pre-assembled transcript analyses
    let documents: [SourceItem]       // for display in knowledge sheet
    let transcripts: [SourceItem]     // for display in knowledge sheet
    let lastUpdatedISO8601: String

    var allSources: [SourceItem] { documents + transcripts }
}

/// A single turn in an AI chat conversation
struct ChatTurn: Codable, Equatable {
    let role: String   // "user" or "assistant"
    let content: String
}

// MARK: - AI request/context models

struct AIQueryRequest: Codable {
    let projectId: String
    let liveTranscript: String
    let transcriptHistory: String?
    let userName: String?
}

// MARK: - Protocols

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
    func streamChat(projectId: String, messages: [ChatTurn], userName: String?, token: String) -> AsyncThrowingStream<String, Error>
}

protocol ProjectRepository {
    func listProjects(token: String) async throws -> [UserProject]
    func createProject(name: String, token: String) async throws -> UserProject
    func uploadTextSource(projectId: String, title: String, text: String, token: String) async throws -> SourceItem
    func uploadFileSource(projectId: String, fileName: String, mimeType: String, fileData: Data, token: String) async throws -> SourceItem
    func saveTranscript(projectId: String, title: String, transcript: String, token: String) async throws -> SourceItem
    func fetchProjectContext(projectId: String, token: String) async throws -> ProjectContextSummary
    func fetchProjectContextSnapshot(projectId: String, token: String) async throws -> ProjectContextSnapshot
    func saveAudioAsset(projectId: String, title: String, mimeType: String, token: String) async throws -> ProjectAudioAsset
    func saveProjectSummary(projectId: String, style: String, content: String, token: String) async throws -> ProjectSummary
    func listProjectSummaries(projectId: String, token: String) async throws -> [ProjectSummary]
}

// MARK: - AI Generation Context

struct AIGenerationContext: Equatable {
    let projectId: String
    let projectName: String
    /// Layer 3: historical transcript rounds from this session
    let transcriptHistory: [String]
    /// Layer 4: most recent live transcript (freshest context layer)
    let liveTranscript: String
    let userName: String?

    var combinedTranscriptHistory: String {
        transcriptHistory.joined(separator: "\n")
    }
}

// MARK: - Utility

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
