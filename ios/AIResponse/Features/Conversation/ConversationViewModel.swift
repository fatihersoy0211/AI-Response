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

    /// All completed listen rounds in this session (legacy display)
    @Published var sessionLog: [TranscriptEntry] = []

    /// New: recording state machine
    @Published var recordingState: RecordingState = .idle

    /// New: rolling 36-sample audio level history for live waveform
    @Published var audioLevelHistory: [Float] = Array(repeating: 0, count: 36)

    /// New: current in-progress listen session
    @Published var currentSession: ListenSession? = nil

    /// New: all completed sessions this app launch
    @Published var allSessions: [ListenSession] = []

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

        self.speechService.audioLevelPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.shiftAudioLevel(level)
            }
            .store(in: &cancellables)
    }

    private func shiftAudioLevel(_ level: Float) {
        audioLevelHistory.removeFirst()
        audioLevelHistory.append(level)
    }

    // MARK: - Lifecycle

    func prepare() async {
        do {
            let granted = await speechService.requestPermissions()
            if !granted {
                errorMessage = "Speech or microphone permission denied"
                transcriptionStatus = "Microphone permission denied"
                recordingState = .permissionDenied
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
        allSessions = []
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
        // Check permission state
        if recordingState == .permissionDenied {
            errorMessage = "Microphone or speech recognition permission denied. Please enable in Settings."
            return
        }

        do {
            try speechService.startListening(for: selectedProjectId)
            activeListenSessionStartCount += 1

            // Create a new listen session
            currentSession = ListenSession(
                id: UUID(),
                projectId: selectedProjectId,
                startedAt: Date(),
                finishedAt: nil,
                segments: [],
                audioFileURL: nil,
                projectSourceId: nil
            )

            recordingState = .listening
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
            var audioURL: URL? = nil
            if wasListening {
                audioURL = speechService.stopListening()
            }
            let latestTranscript = await finalizeSession(audioURL: audioURL)

            let currentTranscript = latestTranscript ?? ""
            let context = AIGenerationContext(
                projectId: selectedProjectId,
                projectName: projects.first(where: { $0.projectId == selectedProjectId })?.name ?? "Project",
                transcriptHistory: transcriptMemory,
                liveTranscript: currentTranscript,
                userName: session.name
            )

            mode = .answering
            recordingState = .answering
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
                    recordingState = .idle
                    transcriptionStatus = "Response ready"
                }
            } catch {
                if !Task.isCancelled {
                    mode = .idle
                    recordingState = .idle
                    errorMessage = error.localizedDescription
                    transcriptionStatus = "Response failed"
                }
            }
        }
    }

    func stop() {
        aiTask?.cancel()
        aiTask = nil
        let audioURL = speechService.stopListening()
        mode = .idle
        recordingState = .saving
        transcriptionStatus = "Listening stopped"

        Task {
            await finalizeSession(audioURL: audioURL)
        }
    }

    private func makeTranscriptTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM HH:mm"
        return "Meeting Transcript – \(formatter.string(from: Date()))"
    }

    @discardableResult
    private func finalizeSession(audioURL: URL?) async -> String? {
        guard var session = currentSession else { return nil }
        session.finishedAt = Date()
        session.audioFileURL = audioURL

        // Save transcript to project
        let transcript: String?
        do {
            transcript = try await transcriptionService.finalizeTranscript(from: liveTranscript)
        } catch {
            transcriptionStatus = "Transcription failed"
            recordingState = .idle
            currentSession = nil
            return nil
        }

        guard let text = transcript, !text.isEmpty else {
            transcriptionStatus = "No transcript captured"
            recordingState = .idle
            currentSession = nil
            return nil
        }

        // Add segment to session
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let seg = ListenSegment(id: UUID(), timestamp: formatter.string(from: Date()), text: text)
        session.segments.append(seg)
        currentSession = session

        // Also append to legacy sessionLog for transcript memory
        let entry = TranscriptEntry(timestamp: formatter.string(from: Date()), text: text)
        sessionLog.append(entry)

        guard !selectedProjectId.isEmpty else {
            allSessions.append(session)
            recordingState = .idle
            currentSession = nil
            return text
        }

        // Save transcript as project source
        do {
            let source = try await projectRepository.saveTranscript(
                projectId: selectedProjectId,
                title: makeTranscriptTitle(),
                transcript: text,
                token: self.session.accessToken
            )
            projectSources.insert(source, at: 0)
            session.projectSourceId = source.sourceId

            // Register audio asset with project (if we have a file)
            if let url = audioURL {
                let mimeType = "audio/x-caf"
                _ = try? await projectRepository.saveAudioAsset(
                    projectId: selectedProjectId,
                    title: url.lastPathComponent,
                    mimeType: mimeType,
                    token: self.session.accessToken
                )
            }

            allSessions.append(session)
            try await refreshContext()
            didUpdateContext = true
            transcriptionStatus = "Transcript saved"
        } catch {
            // Save failed — still record the session locally
            allSessions.append(session)
            errorMessage = error.localizedDescription
            transcriptionStatus = "Save failed"
        }

        recordingState = .idle
        currentSession = nil
        return text
    }
}
