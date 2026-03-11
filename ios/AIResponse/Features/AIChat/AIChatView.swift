import Combine
import SwiftUI

// MARK: - ChatMessage

struct ChatMessage: Identifiable {
    let id: UUID
    let role: ChatRole
    var content: String
    var isStreaming: Bool
    let timestamp: Date

    init(id: UUID = UUID(), role: ChatRole, content: String = "", isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
        self.timestamp = Date()
    }
}

enum ChatRole {
    case user
    case assistant
}

// MARK: - AIChatViewModel

@MainActor
final class AIChatViewModel: ObservableObject {
    @Published var projects: [UserProject] = []
    @Published var selectedProjectId: String = "" {
        didSet {
            guard oldValue != selectedProjectId else { return }
            currentMessages = allMessages[selectedProjectId] ?? []
            Task { try? await loadContext() }
        }
    }
    @Published var currentMessages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isStreaming = false
    @Published var errorMessage: String?

    private var allMessages: [String: [ChatMessage]] = [:]
    private var contextSnapshotByProject: [String: ProjectContextSnapshot] = [:]
    private var streamTask: Task<Void, Never>?

    private let session: UserSession
    private let projectRepository: any ProjectRepository
    private let aiService: any AIResponseServicing

    init(
        session: UserSession,
        projectRepository: any ProjectRepository,
        aiService: any AIResponseServicing
    ) {
        self.session = session
        self.projectRepository = projectRepository
        self.aiService = aiService
    }

    // MARK: Lifecycle

    func prepare() async {
        do {
            projects = try await projectRepository.listProjects(token: session.accessToken)
            if selectedProjectId.isEmpty, let first = projects.first {
                selectedProjectId = first.projectId
            }
            if !selectedProjectId.isEmpty {
                try await loadContext()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadContext() async throws {
        let snapshot = try await projectRepository.fetchProjectContextSnapshot(
            projectId: selectedProjectId, token: session.accessToken
        )
        contextSnapshotByProject[selectedProjectId] = snapshot
    }

    // MARK: Messaging

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !selectedProjectId.isEmpty else { return }

        let userMsg = ChatMessage(role: .user, content: text)
        append(userMsg, to: selectedProjectId)
        inputText = ""

        // Placeholder streaming message
        let assistantMsg = ChatMessage(role: .assistant, isStreaming: true)
        append(assistantMsg, to: selectedProjectId)
        let assistantId = assistantMsg.id
        let projectId = selectedProjectId

        // Build ChatTurn array for /ai/chat endpoint (excludes streaming placeholder)
        let chatTurns: [ChatTurn] = currentMessages
            .dropLast()   // drop streaming placeholder
            .map { ChatTurn(role: $0.role == .user ? "user" : "assistant", content: $0.content) }

        streamTask?.cancel()
        streamTask = Task {
            isStreaming = true
            do {
                let stream = aiService.streamChat(
                    projectId: projectId,
                    messages: chatTurns,
                    userName: session.name,
                    token: session.accessToken
                )
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    patch(id: assistantId, projectId: projectId) { $0.content += chunk }
                }
                patch(id: assistantId, projectId: projectId) { $0.isStreaming = false }
            } catch {
                if !Task.isCancelled {
                    patch(id: assistantId, projectId: projectId) {
                        $0.content = "Error: \(error.localizedDescription)"
                        $0.isStreaming = false
                    }
                }
            }
            isStreaming = false
        }
    }

    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        // Mark last assistant message as done
        if var msgs = allMessages[selectedProjectId],
           let idx = msgs.indices.last, msgs[idx].role == .assistant {
            msgs[idx].isStreaming = false
            if msgs[idx].content.isEmpty { msgs[idx].content = "(cancelled)" }
            allMessages[selectedProjectId] = msgs
            currentMessages = msgs
        }
    }

    func clearHistory() {
        stopStreaming()
        allMessages[selectedProjectId] = []
        currentMessages = []
    }

    // MARK: Helpers

    private func append(_ msg: ChatMessage, to projectId: String) {
        var msgs = allMessages[projectId] ?? []
        msgs.append(msg)
        allMessages[projectId] = msgs
        if projectId == selectedProjectId { currentMessages = msgs }
    }

    private func patch(id: UUID, projectId: String, update: (inout ChatMessage) -> Void) {
        guard var msgs = allMessages[projectId],
              let idx = msgs.firstIndex(where: { $0.id == id }) else { return }
        update(&msgs[idx])
        allMessages[projectId] = msgs
        if projectId == selectedProjectId { currentMessages = msgs }
    }
}

// MARK: - AIChatView

struct AIChatView: View {
    let session: UserSession
    let dependencies: AppDependencies

    @StateObject private var viewModel: AIChatViewModel

    init(session: UserSession, dependencies: AppDependencies) {
        self.session = session
        self.dependencies = dependencies
        _viewModel = StateObject(wrappedValue: AIChatViewModel(
            session: session,
            projectRepository: dependencies.projectRepository,
            aiService: dependencies.aiService
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                projectPickerBar
                messageList
                inputBar
            }
            .background(DS.ColorToken.canvas)
            .navigationTitle("AI Chat")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !viewModel.currentMessages.isEmpty {
                        Button("Clear") { viewModel.clearHistory() }
                            .foregroundStyle(DS.ColorToken.error)
                            .font(DS.Typography.caption)
                    }
                }
            }
            .task { await viewModel.prepare() }
        }
    }

    // MARK: Project Picker

    private var projectPickerBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Spacing.x8) {
                Image(systemName: "folder")
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .font(.system(size: 14))

                if viewModel.projects.isEmpty {
                    Text("No projects — create one in Live Meeting")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                } else {
                    Picker("Project", selection: $viewModel.selectedProjectId) {
                        ForEach(viewModel.projects) { project in
                            Text(project.name).tag(project.projectId)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("chatProjectPicker")
                }
                Spacer()
            }
            .padding(.horizontal, DS.Spacing.x16)
            .padding(.vertical, DS.Spacing.x8)
            .background(DS.ColorToken.surface)

            Rectangle().fill(DS.ColorToken.border).frame(height: 1)
        }
    }

    // MARK: Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.currentMessages.isEmpty {
                    emptyState
                } else {
                    LazyVStack(alignment: .leading, spacing: DS.Spacing.x12) {
                        ForEach(viewModel.currentMessages) { msg in
                            ChatBubble(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding(DS.Spacing.x16)
                }
            }
            .onChange(of: viewModel.currentMessages.count) { _, _ in
                if let last = viewModel.currentMessages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.x16) {
            Spacer()
            DSAIInsightCard(
                title: "AI Project Chat",
                message: viewModel.selectedProjectId.isEmpty
                    ? "Select or create a project to start chatting."
                    : "Ask anything about this project. The AI will answer only from the project's stored knowledge."
            )
            .padding(.horizontal, DS.Spacing.x16)

            if !viewModel.selectedProjectId.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.x8) {
                    Text("Try asking:")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                    ForEach(suggestionChips, id: \.self) { chip in
                        Button(chip) {
                            viewModel.inputText = chip
                            viewModel.sendMessage()
                        }
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.ColorToken.primary)
                        .padding(.horizontal, DS.Spacing.x12)
                        .padding(.vertical, DS.Spacing.x8)
                        .background(DS.ColorToken.primarySoft)
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, DS.Spacing.x16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
        }
    }

    private var suggestionChips: [String] {
        ["Summarise this project", "What are the key goals?", "What decisions were made?"]
    }

    // MARK: Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(DS.ColorToken.border).frame(height: 1)
            HStack(alignment: .bottom, spacing: DS.Spacing.x8) {
                TextField("Ask about this project…", text: $viewModel.inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, DS.Spacing.x12)
                    .padding(.vertical, DS.Spacing.x8)
                    .background(DS.ColorToken.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .stroke(DS.ColorToken.border, lineWidth: 1)
                    )
                    .onSubmit {
                        if !viewModel.isStreaming { viewModel.sendMessage() }
                    }
                    .accessibilityIdentifier("chatInput")

                Button {
                    viewModel.isStreaming ? viewModel.stopStreaming() : viewModel.sendMessage()
                } label: {
                    Image(systemName: viewModel.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(
                            (viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isStreaming)
                                ? DS.ColorToken.border
                                : DS.ColorToken.primary
                        )
                }
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isStreaming)
                .accessibilityIdentifier("chatSendButton")
            }
            .padding(.horizontal, DS.Spacing.x12)
            .padding(.vertical, DS.Spacing.x8)
            .background(DS.ColorToken.canvas)
        }
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.x8) {
            if message.role == .assistant {
                ZStack {
                    Circle()
                        .fill(DS.ColorToken.primarySoft)
                        .frame(width: 30, height: 30)
                    Image(systemName: "sparkles")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.ColorToken.primary)
                }
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: DS.Spacing.x4) {
                if message.isStreaming && message.content.isEmpty {
                    HStack(spacing: DS.Spacing.x8) {
                        ProgressView().scaleEffect(0.75)
                        Text("Thinking…")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.ColorToken.textSecondary)
                    }
                    .padding(.horizontal, DS.Spacing.x12)
                    .padding(.vertical, DS.Spacing.x8)
                    .background(DS.ColorToken.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .stroke(DS.ColorToken.border, lineWidth: 1)
                    )
                } else {
                    Text(message.content)
                        .font(DS.Typography.body)
                        .foregroundStyle(message.role == .user ? .white : DS.ColorToken.textPrimary)
                        .padding(.horizontal, DS.Spacing.x12)
                        .padding(.vertical, DS.Spacing.x8)
                        .background(message.role == .user ? DS.ColorToken.primary : DS.ColorToken.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                        .overlay(
                            Group {
                                if message.role == .assistant {
                                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                        .stroke(DS.ColorToken.border, lineWidth: 1)
                                }
                            }
                        )
                        .textSelection(.enabled)
                }

                Text(message.timestamp, style: .time)
                    .font(DS.Typography.micro)
                    .foregroundStyle(DS.ColorToken.textTertiary)
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .user {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(DS.ColorToken.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}
