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
    @Published var transcriptionStatus: String = "Ready to listen"
    @Published var didUpdateContext = false

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
    private let speechService: any SpeechListeningService
    private let transcriptionService: any TranscriptionServicing
    private let projectRepository: any ProjectRepository
    private let aiService: any AIResponseServicing
    private var cancellables = Set<AnyCancellable>()
    private var aiTask: Task<Void, Never>?
    private var activeListenSessionStartCount = 0

    var transcriptMemory: [String] {
        sessionLog.map { "[\($0.timestamp)] \($0.text)" }
    }

    init(
        session: UserSession,
        speechService: (any SpeechListeningService)? = nil,
        transcriptionService: (any TranscriptionServicing)? = nil,
        projectRepository: any ProjectRepository = UserContextService(),
        aiService: any AIResponseServicing = AIBackendService()
    ) {
        self.session = session
        self.speechService = speechService ?? AudioCaptureService()
        self.transcriptionService = transcriptionService ?? PassthroughTranscriptionService()
        self.projectRepository = projectRepository
        self.aiService = aiService

        self.speechService.liveTranscriptPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.liveTranscript = text
                self?.transcriptionStatus = text.isEmpty ? "Listening active" : "Transcribing current session"
            }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    func prepare() async {
        do {
            let granted = await speechService.requestPermissions()
            if !granted {
                errorMessage = "Speech or microphone permission denied"
                transcriptionStatus = "Microphone permission denied"
                return
            }
            try await loadProjects()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadProjects() async throws {
        let loaded = try await projectRepository.listProjects(token: session.accessToken)
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
                let created = try await projectRepository.createProject(name: name, token: session.accessToken)
                newProjectName = ""
                projects.insert(created, at: 0)
                selectedProjectId = created.projectId
                try await refreshContext()
                didUpdateContext = true
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
                let source = try await projectRepository.uploadTextSource(
                    projectId: selectedProjectId, title: title, text: text, token: session.accessToken
                )
                sourceTitle = ""
                userDataDraft = ""
                projectSources.insert(source, at: 0)
                try await refreshContext()
                didUpdateContext = true
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

                let source = try await projectRepository.uploadFileSource(
                    projectId: selectedProjectId, fileName: fileName,
                    mimeType: mimeType, fileData: fileData, token: session.accessToken
                )
                projectSources.insert(source, at: 0)
                try await refreshContext()
                didUpdateContext = true
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
        let context = try await projectRepository.fetchProjectContext(
            projectId: selectedProjectId, token: session.accessToken
        )
        contextSummary = context.summary
        projectSources = context.sources
    }

    // MARK: - Recording & AI

    func listen() {
        do {
            try speechService.startListening()
            activeListenSessionStartCount += 1
            mode = .listening
            transcriptionStatus = "Listening active"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func respondAndListenAgain() {
        guard !selectedProjectId.isEmpty else { errorMessage = "Please select a project first"; return }
        let wasListening = mode == .listening
        aiTask?.cancel()
        aiTask = Task {
            let latestTranscript = await finalizeCurrentTranscriptIfNeeded()
            if wasListening {
                speechService.stopListening()
            }

            let currentTranscript = latestTranscript ?? ""
            let context = AIGenerationContext(
                projectId: selectedProjectId,
                projectName: projects.first(where: { $0.projectId == selectedProjectId })?.name ?? "Project",
                transcriptHistory: transcriptMemory,
                liveTranscript: currentTranscript,
                userName: session.name
            )

            mode = .answering
            transcriptionStatus = "Generating response"
            answerText = ""

            do {
                let stream = aiService.streamAnswer(context: context, token: session.accessToken)

                for try await chunk in stream {
                    if Task.isCancelled { break }
                    answerText += chunk
                }

                if !Task.isCancelled && wasListening {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if !Task.isCancelled {
                        listen()
                    }
                } else if !Task.isCancelled {
                    mode = .idle
                    transcriptionStatus = "Response ready"
                }
            } catch {
                if !Task.isCancelled {
                    mode = .idle
                    errorMessage = error.localizedDescription
                    transcriptionStatus = "Response failed"
                }
            }
        }
    }

    func stop() {
        aiTask?.cancel()
        aiTask = nil
        speechService.stopListening()
        mode = .idle
        transcriptionStatus = "Listening stopped"

        Task {
            _ = await finalizeCurrentTranscriptIfNeeded()
        }
    }

    private func makeTranscriptTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM HH:mm"
        return "Meeting Transcript – \(formatter.string(from: Date()))"
    }

    @discardableResult
    private func finalizeCurrentTranscriptIfNeeded() async -> String? {
        guard !selectedProjectId.isEmpty else { return nil }

        do {
            let transcript = try await transcriptionService.finalizeTranscript(from: liveTranscript)
            guard !transcript.isEmpty else {
                transcriptionStatus = "No transcript captured"
                return nil
            }

            if sessionLog.last?.text == transcript {
                return transcript
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let entry = TranscriptEntry(timestamp: formatter.string(from: Date()), text: transcript)
            sessionLog.append(entry)

            let source = try await projectRepository.saveTranscript(
                projectId: selectedProjectId,
                title: makeTranscriptTitle(),
                transcript: transcript,
                token: session.accessToken
            )
            projectSources.insert(source, at: 0)
            try await refreshContext()
            didUpdateContext = true
            transcriptionStatus = "Transcript saved"
            return transcript
        } catch {
            errorMessage = error.localizedDescription
            transcriptionStatus = "Transcription failed"
            return nil
        }
    }
}
