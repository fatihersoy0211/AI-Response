import Combine
import Foundation
import UniformTypeIdentifiers

enum ConversationMode: String {
    case idle = "Idle"
    case listening = "Listening"
    case answering = "Answering"
}

/// One captured speech round in the session
struct TranscriptEntry: Identifiable {
    let id = UUID()
    let timestamp: String
    let text: String
}

@MainActor
final class ConversationViewModel: ObservableObject {
    @Published var mode: ConversationMode = .idle
    @Published var answerText: String = ""
    @Published var contextSummary: String = "Select or create a project"
    @Published var errorMessage: String?
    @Published var liveTranscript: String = ""

    /// All completed listen rounds in this session
    @Published var sessionLog: [TranscriptEntry] = []

    /// Sources already in the selected project
    @Published var projectSources: [SourceItem] = []

    @Published var projects: [UserProject] = []
    @Published var selectedProjectId: String = ""
    @Published var newProjectName: String = ""
    @Published var sourceTitle: String = ""
    @Published var userDataDraft: String = ""

    /// Status feedback during uploads
    @Published var uploadStatus: String? = nil

    private let session: UserSession
    private let audioService: AudioCaptureService
    private let contextService: UserContextService
    private let aiService: AIBackendService
    private var cancellables = Set<AnyCancellable>()
    /// Reference to the running AI stream task so Stop can cancel it
    private var aiTask: Task<Void, Never>?

    /// Full accumulated transcript text from previous rounds in this session.
    var sessionTranscript: String {
        sessionLog.map { "[\($0.timestamp)] \($0.text)" }.joined(separator: "\n")
    }

    init(
        session: UserSession,
        audioService: AudioCaptureService? = nil,
        contextService: UserContextService = UserContextService(),
        aiService: AIBackendService = AIBackendService()
    ) {
        self.session = session
        self.audioService = audioService ?? AudioCaptureService()
        self.contextService = contextService
        self.aiService = aiService

        self.audioService.$liveTranscript
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.liveTranscript = text
            }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    func prepare() async {
        do {
            let granted = await audioService.requestPermissions()
            if !granted {
                errorMessage = "Speech or microphone permission denied"
                return
            }
            try await loadProjects()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadProjects() async throws {
        let loaded = try await contextService.listProjects(token: session.accessToken)
        projects = loaded

        if selectedProjectId.isEmpty, let first = loaded.first {
            selectedProjectId = first.projectId
        }

        if !selectedProjectId.isEmpty {
            try await refreshContext()
        }
    }

    // MARK: - Projects

    func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        Task {
            do {
                let created = try await contextService.createProject(name: name, token: session.accessToken)
                newProjectName = ""
                projects.insert(created, at: 0)
                selectedProjectId = created.projectId
                try await refreshContext()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func selectProject(_ projectId: String) {
        guard projectId != selectedProjectId else { return }
        selectedProjectId = projectId
        sessionLog = []
        Task {
            do { try await refreshContext() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    // MARK: - Knowledge Upload

    func uploadUserData() {
        guard !selectedProjectId.isEmpty else { errorMessage = "Please select a project first"; return }
        let title = sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = userDataDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !text.isEmpty else { return }

        uploadStatus = "Analyzing text…"
        Task {
            do {
                let source = try await contextService.uploadTextSource(
                    projectId: selectedProjectId, title: title, text: text, token: session.accessToken
                )
                sourceTitle = ""
                userDataDraft = ""
                projectSources.insert(source, at: 0)
                try await refreshContext()
                uploadStatus = "✓ Text saved"
                errorMessage = nil
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                uploadStatus = nil
            } catch {
                uploadStatus = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func uploadPickedFile(url: URL) {
        guard !selectedProjectId.isEmpty else { errorMessage = "Please select a project first"; return }

        uploadStatus = "Uploading and analyzing file…"
        Task {
            do {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }

                let fileData = try Data(contentsOf: url)
                let fileName = url.lastPathComponent
                let ext = url.pathExtension.lowercased()
                let mimeType: String
                switch ext {
                case "pdf":  mimeType = "application/pdf"
                case "txt":  mimeType = "text/plain"
                case "doc":  mimeType = "application/msword"
                default:     mimeType = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
                }

                let source = try await contextService.uploadFileSource(
                    projectId: selectedProjectId, fileName: fileName,
                    mimeType: mimeType, fileData: fileData, token: session.accessToken
                )
                projectSources.insert(source, at: 0)
                try await refreshContext()
                uploadStatus = "✓ \(fileName) saved"
                errorMessage = nil
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                uploadStatus = nil
            } catch {
                uploadStatus = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshContext() async throws {
        guard !selectedProjectId.isEmpty else {
            contextSummary = "Select or create a project"
            projectSources = []
            return
        }
        let context = try await contextService.fetchProjectContext(
            projectId: selectedProjectId, token: session.accessToken
        )
        contextSummary = context.summary
        projectSources = context.sources
    }

    // MARK: - Recording & AI

    func listen() {
        do {
            try audioService.startListening()
            mode = .listening
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func respondAndListenAgain() {
        guard !selectedProjectId.isEmpty else { errorMessage = "Please select a project first"; return }

        let capturedTranscript = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !capturedTranscript.isEmpty else {
            errorMessage = "Start listening first to generate a transcript"
            return
        }

        // 1. Commit this round to the session log
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let entry = TranscriptEntry(timestamp: formatter.string(from: Date()), text: capturedTranscript)
        sessionLog.append(entry)

        // 2. Build accumulated context from all PREVIOUS rounds (not current)
        let previousRounds = sessionLog.dropLast()
        let accumulatedContext: String? = previousRounds.isEmpty
            ? nil
            : previousRounds.map { "[\($0.timestamp)] \($0.text)" }.joined(separator: "\n")

        // Cancel any in-progress AI task before starting a new one
        aiTask?.cancel()
        aiTask = Task {
            mode = .answering
            audioService.stopListening()
            answerText = ""

            do {
                let stream = aiService.streamAnswer(
                    projectId: selectedProjectId,
                    transcript: capturedTranscript,
                    sessionTranscript: accumulatedContext,
                    token: session.accessToken
                )

                for try await chunk in stream {
                    if Task.isCancelled { break }
                    answerText += chunk
                }

                // 3. Auto-start next listen round — only if not cancelled
                if !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if !Task.isCancelled {
                        listen()
                    }
                }
            } catch {
                if !Task.isCancelled {
                    mode = .idle
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func stop() {
        // Cancel running AI stream immediately
        aiTask?.cancel()
        aiTask = nil

        audioService.stopListening()
        mode = .idle

        // Auto-save full session transcript to project knowledge base (background)
        let fullTranscript = sessionTranscript
        guard !selectedProjectId.isEmpty, !fullTranscript.isEmpty else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM HH:mm"
        let title = "Meeting Transcript – \(formatter.string(from: Date()))"

        Task {
            do {
                let source = try await contextService.saveTranscript(
                    projectId: selectedProjectId,
                    title: title,
                    transcript: fullTranscript,
                    token: session.accessToken
                )
                projectSources.insert(source, at: 0)
                try await refreshContext()
            } catch {
                // Silent fail – session log is still visible in the UI
            }
        }
    }
}
