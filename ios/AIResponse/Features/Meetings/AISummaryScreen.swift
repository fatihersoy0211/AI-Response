import SwiftUI

// MARK: - ViewModel

@MainActor
final class AISummaryViewModel: ObservableObject {
    @Published var projects: [UserProject] = []
    @Published var selectedProjectId: String = "" {
        didSet {
            guard oldValue != selectedProjectId else { return }
            summaryText = ""
            errorMessage = nil
            Task { await generate() }
        }
    }
    @Published var summaryText: String = ""
    @Published var isGenerating = false
    @Published var errorMessage: String?
    @Published var selectedStyle: String = "Executive"

    private let session: UserSession
    private let projectRepository: any ProjectRepository
    private let aiService: any AIResponseServicing
    private var streamTask: Task<Void, Never>?

    let styles = ["Executive", "Technical", "Casual", "Bullet Points"]

    init(session: UserSession, dependencies: AppDependencies) {
        self.session = session
        self.projectRepository = dependencies.projectRepository
        self.aiService = dependencies.aiService
    }

    func prepare() async {
        do {
            projects = try await projectRepository.listProjects(token: session.accessToken)
            if selectedProjectId.isEmpty, let first = projects.first {
                selectedProjectId = first.projectId
            } else if !selectedProjectId.isEmpty {
                await generate()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func generate() async {
        guard !selectedProjectId.isEmpty else { return }
        streamTask?.cancel()
        summaryText = ""
        isGenerating = true
        errorMessage = nil

        let projectName = projects.first(where: { $0.projectId == selectedProjectId })?.name ?? "Project"

        let styleInstruction: String
        switch selectedStyle {
        case "Technical":
            styleInstruction = "Use technical language. Focus on systems, dependencies, and technical decisions."
        case "Casual":
            styleInstruction = "Use a conversational, friendly tone. Keep it brief and human."
        case "Bullet Points":
            styleInstruction = "Respond entirely in bullet point format with short, scannable items."
        default:
            styleInstruction = "Use an executive tone. Be concise, strategic, and action-oriented."
        }

        let prompt = """
        Generate a comprehensive meeting summary in \(selectedStyle) style.
        \(styleInstruction)

        Include the following sections:
        ## Executive Summary
        ## Key Discussion Points
        ## Action Items
        ## Risks & Blockers
        ## Follow-up Suggestions

        Base everything strictly on the project knowledge base. Do not invent information.
        """

        let genContext = AIGenerationContext(
            projectId: selectedProjectId,
            projectName: projectName,
            transcriptHistory: [],
            liveTranscript: prompt,
            userName: session.name
        )

        streamTask = Task {
            do {
                let stream = aiService.streamAnswer(context: genContext, token: session.accessToken)
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    summaryText += chunk
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
            isGenerating = false
        }
    }

    func cancelGeneration() {
        streamTask?.cancel()
        streamTask = nil
        isGenerating = false
    }
}

// MARK: - View

struct AISummaryScreen: View {
    let session: UserSession
    let dependencies: AppDependencies

    @StateObject private var viewModel: AISummaryViewModel

    init(session: UserSession, dependencies: AppDependencies) {
        self.session = session
        self.dependencies = dependencies
        _viewModel = StateObject(wrappedValue: AISummaryViewModel(session: session, dependencies: dependencies))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.x16) {

                // Project picker
                if !viewModel.projects.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Spacing.x4) {
                        Text("Project")
                            .font(DS.Typography.micro)
                            .foregroundStyle(DS.ColorToken.textTertiary)
                        Picker("Project", selection: $viewModel.selectedProjectId) {
                            ForEach(viewModel.projects) { project in
                                Text(project.name).tag(project.projectId)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .dsCardStyle()
                } else if !viewModel.isGenerating {
                    DSEmptyState(
                        icon: "folder.badge.plus",
                        title: "No projects found",
                        message: "Create a project in the AI Chat tab and add knowledge sources, then come back to generate a summary."
                    )
                }

                // Style picker + controls
                if !viewModel.selectedProjectId.isEmpty {
                    HStack(spacing: DS.Spacing.x8) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DS.Spacing.x8) {
                                ForEach(viewModel.styles, id: \.self) { style in
                                    Button {
                                        viewModel.selectedStyle = style
                                        Task { await viewModel.generate() }
                                    } label: {
                                        DSBadge(
                                            text: style,
                                            tone: viewModel.selectedStyle == style ? DS.ColorToken.primary : DS.ColorToken.textSecondary
                                        )
                                    }
                                }
                            }
                        }
                        if viewModel.isGenerating {
                            Button {
                                viewModel.cancelGeneration()
                            } label: {
                                Image(systemName: "stop.circle.fill")
                                    .foregroundStyle(DS.ColorToken.error)
                            }
                        } else {
                            Button {
                                Task { await viewModel.generate() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundStyle(DS.ColorToken.primary)
                            }
                        }
                    }
                }

                // Error
                if let error = viewModel.errorMessage {
                    HStack(spacing: DS.Spacing.x8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(DS.ColorToken.error)
                        Text(error)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.ColorToken.error)
                    }
                    .dsCardStyle()
                }

                // Generating indicator
                if viewModel.isGenerating && viewModel.summaryText.isEmpty {
                    HStack(spacing: DS.Spacing.x8) {
                        ProgressView()
                        Text("Generating \(viewModel.selectedStyle.lowercased()) summary…")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.ColorToken.textSecondary)
                    }
                    .dsCardStyle()
                }

                // Summary content
                if !viewModel.summaryText.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Spacing.x8) {
                        HStack {
                            DSBadge(text: viewModel.selectedStyle, tone: DS.ColorToken.primary)
                            if viewModel.isGenerating {
                                ProgressView().scaleEffect(0.7)
                            }
                            Spacer()
                        }
                        Text(viewModel.summaryText)
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.ColorToken.textPrimary)
                            .textSelection(.enabled)
                    }
                    .dsCardStyle()
                }
            }
            .padding(DS.Spacing.x16)
        }
        .background(DS.ColorToken.canvas)
        .task {
            await viewModel.prepare()
        }
    }
}
