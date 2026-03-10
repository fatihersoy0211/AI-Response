import Combine
import Foundation
import UniformTypeIdentifiers

enum ConversationMode: String {
    case idle = "Idle"
    case listening = "Listening"
    case answering = "Answering"
}

@MainActor
final class ConversationViewModel: ObservableObject {
    @Published var mode: ConversationMode = .idle
    @Published var answerText: String = ""
    @Published var contextSummary: String = "Bir proje secin veya olusturun"
    @Published var errorMessage: String?
    @Published var liveTranscript: String = ""

    @Published var projects: [UserProject] = []
    @Published var selectedProjectId: String = ""
    @Published var newProjectName: String = ""

    @Published var sourceTitle: String = ""
    @Published var userDataDraft: String = ""

    private let session: UserSession
    private let audioService: AudioCaptureService
    private let contextService: UserContextService
    private let aiService: AIBackendService
    private var cancellables = Set<AnyCancellable>()

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
        selectedProjectId = projectId
        Task {
            do {
                try await refreshContext()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func uploadUserData() {
        guard !selectedProjectId.isEmpty else {
            errorMessage = "Once proje secin"
            return
        }

        let title = sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = userDataDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !text.isEmpty else { return }

        Task {
            do {
                try await contextService.uploadTextSource(
                    projectId: selectedProjectId,
                    title: title,
                    text: text,
                    token: session.accessToken
                )
                sourceTitle = ""
                userDataDraft = ""
                try await refreshContext()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func uploadPickedFile(url: URL) {
        guard !selectedProjectId.isEmpty else {
            errorMessage = "Once proje secin"
            return
        }

        Task {
            do {
                let access = url.startAccessingSecurityScopedResource()
                defer {
                    if access { url.stopAccessingSecurityScopedResource() }
                }

                let fileData = try Data(contentsOf: url)
                let fileName = url.lastPathComponent
                let ext = url.pathExtension.lowercased()
                let mimeType = ext == "pdf" ? "application/pdf" : "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

                try await contextService.uploadFileSource(
                    projectId: selectedProjectId,
                    fileName: fileName,
                    mimeType: mimeType,
                    fileData: fileData,
                    token: session.accessToken
                )

                try await refreshContext()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshContext() async throws {
        guard !selectedProjectId.isEmpty else {
            contextSummary = "Bir proje secin veya olusturun"
            return
        }

        let context = try await contextService.fetchProjectContext(projectId: selectedProjectId, token: session.accessToken)
        contextSummary = context.summary
    }

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
        guard !selectedProjectId.isEmpty else {
            errorMessage = "Once proje secin"
            return
        }

        guard !liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Once dinleme yapip transkript olusturun"
            return
        }

        Task {
            mode = .answering
            audioService.stopListening()
            answerText = ""

            do {
                let stream = aiService.streamAnswer(
                    projectId: selectedProjectId,
                    transcript: liveTranscript,
                    token: session.accessToken
                )

                for try await chunk in stream {
                    answerText += chunk
                }

                listen()
            } catch {
                mode = .idle
                errorMessage = error.localizedDescription
            }
        }
    }

    func stop() {
        audioService.stopListening()
        mode = .idle
    }
}
