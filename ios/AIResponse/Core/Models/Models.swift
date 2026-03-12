import Foundation

// MARK: - Recording Session Models

/// A complete record/listen cycle (start → stop)
struct ListenSession: Identifiable, Equatable {
    let id: UUID
    let projectId: String
    let startedAt: Date
    var finishedAt: Date?
    var segments: [ListenSegment]       // transcript sub-rounds within session
    var audioFileURL: URL?              // local CAF audio file path
    var projectSourceId: String?        // backend source ID after upload

    var combinedTranscript: String {
        segments.map(\.text).joined(separator: " ")
    }

    var formattedDuration: String {
        guard let end = finishedAt else { return "–" }
        let secs = Int(end.timeIntervalSince(startedAt))
        return String(format: "%02d:%02d", secs / 60, secs % 60)
    }
}

/// One transcribed sub-round within a session (SFSpeechRecognizer fires final every ~60s)
struct ListenSegment: Identifiable, Equatable {
    let id: UUID
    let timestamp: String   // "HH:mm:ss"
    let text: String
}

enum RecordingState: Equatable {
    case idle
    case listening          // mic active, transcribing
    case answering          // AI streaming response
    case saving             // uploading transcript/audio to project
    case permissionDenied
}

struct AppleCredential {
    let userIdentifier: String
    let identityToken: String
    let name: String?
    let email: String?
    /// Raw (unhashed) nonce. Backend verifies sha256(nonce) == JWT `nonce` claim.
    let nonce: String?
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
    let goal: String?
    let manualText: String?
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
    let projectId: String
    let fileName: String
    let fileType: String
    let storedPath: String?
    let extractedText: String
    let extractionStatus: String
    let createdAtISO8601: String
    let updatedAtISO8601: String
    var id: String { sourceId }
}

struct TranscriptSegment: Codable, Identifiable {
    let sourceId: String
    let projectId: String
    let sessionId: String?
    let audioAssetId: String?
    let sourceType: String
    let title: String
    let analysis: String
    let segmentTimestampISO8601: String?
    let createdAtISO8601: String
    let isFinal: Bool
    let speakerLabel: String?
    var id: String { sourceId }
}

struct ProjectAudioAsset: Codable, Identifiable {
    let assetId: String
    let projectId: String
    let title: String
    let sourceType: String
    let mimeType: String
    let storedPath: String?
    let durationSeconds: TimeInterval?
    let createdAtISO8601: String
    let transcriptionStatus: String
    var id: String { assetId }
}

struct ProjectSummary: Codable, Identifiable {
    let summaryId: String
    let projectId: String
    let style: String
    let content: String
    let sourceSnapshotHash: String?
    let generatedAtISO8601: String
    var id: String { summaryId }
}

/// Layered context snapshot — typed by source category for layered AI context assembly
struct ProjectContextSnapshot: Codable {
    let projectId: String
    let projectName: String
    let manualText: String            // Layer 2: manual project notes/background
    let documentContext: String       // Layer 3: pre-assembled document analyses
    let transcriptHistory: String     // Layer 4: pre-assembled transcript analyses
    let chatHistory: String
    let mergedText: String
    let documents: [SourceItem]       // for display in knowledge sheet
    let transcripts: [SourceItem]     // for display in knowledge sheet
    let lastUpdatedISO8601: String

    var allSources: [SourceItem] { documents + transcripts }
}

/// A single turn in an AI chat conversation
struct ChatTurn: Codable, Equatable {
    let turnId: String
    let projectId: String
    let role: String   // "user" or "assistant"
    let content: String
    let createdAtISO8601: String
    let turnIndex: Int
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
    /// Registers a new account. Sends a verification email; does NOT return a session.
    func register(name: String, email: String, password: String) async throws
    func verifyEmail(email: String, code: String) async throws -> UserSession
    func forgotPassword(email: String) async throws
    func verifyReset(email: String, code: String, newPassword: String) async throws -> UserSession
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
    func transcribeAudioFile(at fileURL: URL) async throws -> String
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
    func listProjectDocuments(projectId: String, token: String) async throws -> [ProjectDocument]
    func listProjectAudioAssets(projectId: String, token: String) async throws -> [ProjectAudioAsset]
    func listProjectTranscripts(projectId: String, token: String) async throws -> [TranscriptSegment]
    func importAudioAsset(
        projectId: String,
        fileName: String,
        mimeType: String,
        localFileURL: URL?,
        durationSeconds: TimeInterval?,
        sourceType: String,
        transcript: String?,
        token: String
    ) async throws -> ProjectAudioAsset
    func saveChatTurn(projectId: String, role: String, content: String, token: String) async throws -> ChatTurn
    func listChatTurns(projectId: String, token: String) async throws -> [ChatTurn]
    func clearChatTurns(projectId: String, token: String) async throws
    func buildAIGenerationContext(projectId: String, userName: String?, token: String) async throws -> AIGenerationContext
    func saveProjectNotes(projectId: String, text: String, token: String) async throws -> UserProject
    func loadProjectNotes(projectId: String, token: String) async throws -> String
    func deleteProjectSource(projectId: String, sourceId: String, token: String) async throws
    func deleteProject(projectId: String, token: String) async throws
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

// MARK: - Transcript source type / transcription job status

enum TranscriptSourceType: String, Codable {
    case liveListening   = "liveListening"
    case uploadedAudio   = "uploadedAudio"
    case importedMeeting = "importedMeeting"
}

enum TranscriptionJobStatus: String, Codable {
    case pending    = "pending"
    case processing = "processing"
    case completed  = "completed"
    case failed     = "failed"
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
