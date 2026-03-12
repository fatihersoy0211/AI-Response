import SwiftUI

struct AppLaunchConfiguration {
    let isUITestMode: Bool
    let skipOnboarding: Bool
    let useMockServices: Bool
    let preloadAuthenticatedSession: Bool
    let preloadProjectName: String?
    let preloadProjectContext: String?
    let queuedTranscripts: [String]
    let aiResponse: String
    let microphonePermissionGranted: Bool
    let transcriptionFailureMessage: String?
    let aiFailureMessage: String?

    private static func optionalEnvironment(_ key: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[key] else { return nil }
        return value.isEmpty ? nil : value
    }

    static let current = AppLaunchConfiguration(
        isUITestMode: ProcessInfo.processInfo.arguments.contains("-uiTesting"),
        skipOnboarding: ProcessInfo.processInfo.arguments.contains("-uiTesting"),
        useMockServices: ProcessInfo.processInfo.arguments.contains("-uiTesting"),
        preloadAuthenticatedSession: ProcessInfo.processInfo.environment["UITEST_AUTHENTICATED"] != "0",
        preloadProjectName: ProcessInfo.processInfo.environment["UITEST_PRELOAD_PROJECT"] == "0"
            ? nil
            : (optionalEnvironment("UITEST_PROJECT_NAME") ?? "Sample Project"),
        preloadProjectContext: ProcessInfo.processInfo.environment["UITEST_PRELOAD_PROJECT"] == "0"
            ? nil
            : (optionalEnvironment("UITEST_PROJECT_CONTEXT") ?? "Product roadmap, onboarding flow, launch plan"),
        queuedTranscripts: ProcessInfo.processInfo.environment["UITEST_TRANSCRIPTS"]?
            .split(separator: "|")
            .map { String($0) } ?? ["We discussed the product roadmap and onboarding flow."],
        aiResponse: ProcessInfo.processInfo.environment["UITEST_AI_RESPONSE"]
            ?? "Based on your project context and recent discussion, the priority should be onboarding optimization.",
        microphonePermissionGranted: ProcessInfo.processInfo.environment["UITEST_MIC_PERMISSION"] != "denied",
        transcriptionFailureMessage: ProcessInfo.processInfo.environment["UITEST_TRANSCRIPTION_ERROR"],
        aiFailureMessage: ProcessInfo.processInfo.environment["UITEST_AI_ERROR"]
    )

    var preloadedSession: UserSession? {
        guard isUITestMode && preloadAuthenticatedSession else { return nil }
        return UserSession(
            userId: "uitest-user",
            name: "Taylor",
            email: "taylor@example.com",
            accessToken: "uitest-token",
            refreshToken: nil
        )
    }
}

struct AppDependencies {
    let authService: any AuthServicing
    let sessionStore: any SessionStoring
    let speechServiceFactory: @MainActor () -> any SpeechListeningService
    let transcriptionService: any TranscriptionServicing
    let aiService: any AIResponseServicing
    let projectRepository: any ProjectRepository
    let launchConfiguration: AppLaunchConfiguration

    static func makeCurrent() -> AppDependencies {
        let launchConfiguration = AppLaunchConfiguration.current
        if launchConfiguration.useMockServices {
            let projectRepository = InMemoryProjectRepository(launchConfiguration: launchConfiguration)
            return AppDependencies(
                authService: MockAuthService(session: launchConfiguration.preloadedSession),
                sessionStore: InMemorySessionStore(initialSession: launchConfiguration.preloadedSession),
                speechServiceFactory: { MockSpeechService(launchConfiguration: launchConfiguration) },
                transcriptionService: MockTranscriptionService(launchConfiguration: launchConfiguration),
                aiService: MockAIService(launchConfiguration: launchConfiguration),
                projectRepository: projectRepository,
                launchConfiguration: launchConfiguration
            )
        }

        return AppDependencies(
            authService: AuthService(),
            sessionStore: KeychainSessionStore(),
            speechServiceFactory: { AudioCaptureService() },
            transcriptionService: PassthroughTranscriptionService(),
            aiService: AIBackendService(),
            projectRepository: UserContextService(),
            launchConfiguration: launchConfiguration
        )
    }
}

@main
struct AIResponseApp: App {
    private let dependencies: AppDependencies
    @StateObject private var appViewModel: AppViewModel

    init() {
        let dependencies = AppDependencies.makeCurrent()
        self.dependencies = dependencies
        _appViewModel = StateObject(
            wrappedValue: AppViewModel(
                authService: dependencies.authService,
                sessionStore: dependencies.sessionStore,
                launchConfiguration: dependencies.launchConfiguration
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
                .environmentObject(appViewModel)
        }
    }
}
