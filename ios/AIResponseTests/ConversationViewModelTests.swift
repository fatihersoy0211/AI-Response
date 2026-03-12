import XCTest
@testable import AIResponse

@MainActor
final class ConversationViewModelTests: XCTestCase {
    func testPersonaAndProjectContextAreIncludedInAIRequest() async throws {
        let repository = makeRepository()
        let aiService = MockAIService(responseText: "ok")
        let viewModel = makeViewModel(repository: repository, aiService: aiService)

        try await viewModel.loadProjects()
        viewModel.respondAndListenAgain()
        await settle()

        let context = try XCTUnwrap(aiService.recordedContexts.last)
        XCTAssertEqual(context.projectName, "Apollo")
        XCTAssertTrue(context.liveTranscript.contains("Roadmap"))
        XCTAssertEqual(context.userName, "Morgan")
    }

    func testResponseWorksWithoutTranscriptHistory() async throws {
        let repository = makeRepository()
        let aiService = MockAIService(responseText: "Context-only answer")
        let viewModel = makeViewModel(repository: repository, aiService: aiService)

        try await viewModel.loadProjects()
        viewModel.respondAndListenAgain()
        await settle()

        XCTAssertEqual(viewModel.answerText, "Context-only answer")
        XCTAssertEqual(aiService.recordedContexts.last?.transcriptHistory.count, 1)
    }

    func testStartStopAndListenAgain() async throws {
        let speechService = MockSpeechService(queuedTranscripts: ["first session", "second session"])
        let repository = makeRepository()
        let viewModel = makeViewModel(speechService: speechService, repository: repository)

        try await viewModel.loadProjects()
        viewModel.listen()

        XCTAssertEqual(viewModel.mode, .listening)
        XCTAssertEqual(viewModel.transcriptionStatus, "Listening active")

        viewModel.stop()
        await settle()
        XCTAssertEqual(viewModel.mode, .idle)

        viewModel.listen()
        XCTAssertEqual(viewModel.mode, .listening)
        XCTAssertEqual(speechService.startCallCount, 2)
    }

    func testStopPersistsTranscriptAndKeepsOrderAcrossSessions() async throws {
        let speechService = MockSpeechService(queuedTranscripts: ["First transcript", "Second transcript"])
        let repository = makeRepository()
        let viewModel = makeViewModel(speechService: speechService, repository: repository)

        try await viewModel.loadProjects()
        viewModel.listen()
        viewModel.stop()
        await settle()

        viewModel.listen()
        viewModel.stop()
        await settle()

        XCTAssertEqual(viewModel.sessionLog.map(\.text), ["First transcript", "Second transcript"])
        let storedTexts = await repository.storedSourceTexts(projectId: "project-1")
        XCTAssertTrue(storedTexts.contains("First transcript"))
        XCTAssertTrue(storedTexts.contains("Second transcript"))
    }

    func testLaterResponseUsesUpdatedTranscriptMemory() async throws {
        let speechService = MockSpeechService(queuedTranscripts: ["Roadmap discussion", "Onboarding blockers"])
        let repository = makeRepository()
        let aiService = MockAIService(responseText: "updated answer")
        let viewModel = makeViewModel(speechService: speechService, repository: repository, aiService: aiService)

        try await viewModel.loadProjects()
        viewModel.listen()
        viewModel.stop()
        await settle()
        viewModel.listen()
        viewModel.stop()
        await settle()

        viewModel.respondAndListenAgain()
        await settle()

        let context = try XCTUnwrap(aiService.recordedContexts.last)
        XCTAssertEqual(context.transcriptHistory.count, 2)
        XCTAssertTrue(context.transcriptHistory[0].contains("Roadmap"))
        XCTAssertEqual(context.liveTranscript, "Onboarding blockers")
    }

    func testMicrophonePermissionDeniedShowsError() async {
        let speechService = MockSpeechService(permissionGranted: false)
        let viewModel = makeViewModel(speechService: speechService, repository: makeRepository())

        await viewModel.prepare()

        XCTAssertEqual(viewModel.errorMessage, "Speech or microphone permission denied")
        XCTAssertEqual(viewModel.transcriptionStatus, "Microphone permission denied")
    }

    func testTranscriptionFailureIsReported() async throws {
        let speechService = MockSpeechService(queuedTranscripts: ["raw transcript"])
        let repository = makeRepository()
        let viewModel = makeViewModel(
            speechService: speechService,
            transcriptionService: MockTranscriptionService(failureMessage: "Transcription failed"),
            repository: repository
        )

        try await viewModel.loadProjects()
        viewModel.listen()
        viewModel.stop()
        await settle()

        XCTAssertEqual(viewModel.errorMessage, "Transcription failed")
        XCTAssertEqual(viewModel.transcriptionStatus, "Transcription failed")
    }

    private func makeViewModel(
        speechService: MockSpeechService? = nil,
        transcriptionService: any TranscriptionServicing = PassthroughTranscriptionService(),
        repository: InMemoryProjectRepository,
        aiService: MockAIService = MockAIService(responseText: "answer")
    ) -> ConversationViewModel {
        ConversationViewModel(
            session: UserSession(
                userId: "user-1",
                name: "Morgan",
                email: "morgan@example.com",
                accessToken: "token",
                refreshToken: nil
            ),
            speechService: speechService ?? MockSpeechService(),
            transcriptionService: transcriptionService,
            projectRepository: repository,
            aiService: aiService
        )
    }

    private func makeRepository() -> InMemoryProjectRepository {
        let now = ISO8601DateFormatter().string(from: Date())
        return InMemoryProjectRepository(
            projects: [
                UserProject(projectId: "project-1", name: "Apollo", goal: nil, createdAtISO8601: now, updatedAtISO8601: now)
            ],
            sourcesByProjectId: [
                "project-1": [
                    SourceItem(
                        sourceId: "source-1",
                        sourceType: "text",
                        title: "Brief",
                        analysis: "Roadmap, onboarding, launch plan",
                        createdAtISO8601: now
                    )
                ]
            ],
            sourceTextsByProjectId: [
                "project-1": ["Roadmap, onboarding, launch plan"]
            ]
        )
    }

    private func settle() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }
}
