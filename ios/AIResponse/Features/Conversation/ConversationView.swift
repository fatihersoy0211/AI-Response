import SwiftUI
import UniformTypeIdentifiers

struct ConversationView: View {
    let session: UserSession

    var body: some View {
        LiveMeetingView(session: session)
    }
}

struct LiveMeetingView: View {
    let session: UserSession

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ConversationViewModel
    @State private var isFileImporterPresented = false
    @State private var showKnowledgeSheet = false

    private var allowedFileTypes: [UTType] {
        var types: [UTType] = [.pdf]
        if let docx = UTType(filenameExtension: "docx") {
            types.append(docx)
        }
        return types
    }

    init(session: UserSession) {
        self.session = session
        _viewModel = StateObject(wrappedValue: ConversationViewModel(session: session))
    }

    var body: some View {
        ZStack {
            DS.ColorToken.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.x16) {
                    header
                    recordingHero
                    participants
                    transcriptCard
                    aiAnswerCard
                    controls
                }
                .padding(DS.Spacing.x16)
            }
        }
        .task {
            await viewModel.prepare()
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: allowedFileTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let first = urls.first {
                    viewModel.uploadPickedFile(url: first)
                }
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showKnowledgeSheet) {
            knowledgeSheet
        }
        .navigationTitle("Live Meeting")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showKnowledgeSheet = true
                } label: {
                    Label("Knowledge", systemImage: "square.and.arrow.down")
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x12) {
            HStack {
                Circle()
                    .fill(viewModel.mode == .listening ? DS.ColorToken.error : DS.ColorToken.warning)
                    .frame(width: 10, height: 10)
                Text(viewModel.mode == .listening ? "Recording Active" : "Ready")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.ColorToken.textSecondary)
                Spacer()
                DSBadge(text: "Secure", tone: DS.ColorToken.success)
            }

            if viewModel.projects.isEmpty {
                DSEmptyState(icon: "folder.badge.plus", title: "No project selected", message: "Create a project to keep this meeting knowledge organized.")
            } else {
                Picker("Project", selection: $viewModel.selectedProjectId) {
                    ForEach(viewModel.projects) { project in
                        Text(project.name).tag(project.projectId)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.selectedProjectId) { _, newValue in
                    viewModel.selectProject(newValue)
                }
            }
        }
        .dsCardStyle()
    }

    private var recordingHero: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x12) {
            Text("Executive Weekly Sync")
                .font(DS.Typography.title2)
                .foregroundStyle(DS.ColorToken.textPrimary)
            Text("00:14:22")
                .font(DS.Typography.displayLarge)
                .foregroundStyle(DS.ColorToken.textPrimary)

            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(DS.ColorToken.primarySoft)
                .frame(height: 56)
                .overlay {
                    HStack(spacing: DS.Spacing.x4) {
                        ForEach(0..<36, id: \.self) { index in
                            Capsule()
                                .fill(index % 3 == 0 ? DS.ColorToken.primary : DS.ColorToken.aiAccent)
                                .frame(width: 3, height: CGFloat((index % 8) + 8))
                        }
                    }
                }
        }
        .padding(DS.Spacing.x16)
        .background(
            LinearGradient(
                colors: [DS.ColorToken.primary.opacity(0.95), DS.ColorToken.aiAccent.opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
    }

    private var participants: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x8) {
            Text("Participants")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.ColorToken.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.x8) {
                    DSBadge(text: "Elif", tone: DS.ColorToken.primary)
                    DSBadge(text: "Burak", tone: DS.ColorToken.aiAccent)
                    DSBadge(text: "Mina", tone: DS.ColorToken.warning)
                }
            }
        }
        .dsCardStyle()
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x8) {
            DSSectionHeader(title: "Live Transcript")
            Text(viewModel.liveTranscript.isEmpty ? "Waiting for speech input..." : viewModel.liveTranscript)
                .font(DS.Typography.body)
                .foregroundStyle(DS.ColorToken.textPrimary)
            HStack {
                DSButton(title: "Bookmark Moment", icon: "bookmark", kind: .secondary) {}
                DSButton(title: "Add Note", icon: "note.text.badge.plus", kind: .secondary) {}
            }
        }
        .dsCardStyle()
    }

    private var aiAnswerCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x8) {
            DSSectionHeader(title: "AI Response")
            Text(viewModel.answerText.isEmpty ? "AI response will appear here in real time." : viewModel.answerText)
                .font(DS.Typography.body)
                .foregroundStyle(DS.ColorToken.textPrimary)
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.ColorToken.error)
            }
        }
        .dsCardStyle()
    }

    private var controls: some View {
        HStack(spacing: DS.Spacing.x12) {
            DSButton(title: viewModel.mode == .listening ? "Resume" : "Listen", icon: "mic.fill", kind: .primary) {
                viewModel.listen()
            }
            DSButton(title: "Respond", icon: "sparkles", kind: .secondary) {
                viewModel.respondAndListenAgain()
            }
            DSButton(title: "Stop", icon: "stop.fill", kind: .destructive) {
                viewModel.stop()
            }
        }
    }

    private var knowledgeSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.x16) {
                    DSSectionHeader(title: "Create Project")
                    HStack {
                        TextField("Project name", text: $viewModel.newProjectName)
                            .padding(.horizontal, DS.Spacing.x12)
                            .padding(.vertical, DS.Spacing.x12)
                            .background(DS.ColorToken.surface)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                    .stroke(DS.ColorToken.border, lineWidth: 1)
                            )
                        DSButton(title: "Create", kind: .primary) {
                            viewModel.createProject()
                        }
                        .frame(width: 120)
                    }

                    DSSectionHeader(title: "Analyze Text Source")
                    TextField("Source title", text: $viewModel.sourceTitle)
                        .padding(.horizontal, DS.Spacing.x12)
                        .padding(.vertical, DS.Spacing.x12)
                        .background(DS.ColorToken.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                .stroke(DS.ColorToken.border, lineWidth: 1)
                        )

                    TextEditor(text: $viewModel.userDataDraft)
                        .frame(minHeight: 120)
                        .padding(DS.Spacing.x8)
                        .background(DS.ColorToken.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                .stroke(DS.ColorToken.border, lineWidth: 1)
                        )

                    DSButton(title: "Analyze Text", kind: .primary) {
                        viewModel.uploadUserData()
                    }

                    DSSectionHeader(title: "Analyze File Source")
                    DSButton(title: "Upload PDF or DOCX", icon: "doc.badge.plus", kind: .secondary) {
                        isFileImporterPresented = true
                    }

                    DSSectionHeader(title: "Project Context")
                    Text(viewModel.contextSummary)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                        .dsCardStyle()
                }
                .padding(DS.Spacing.x16)
            }
            .background(DS.ColorToken.canvas)
            .navigationTitle("Meeting Knowledge")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showKnowledgeSheet = false }
                }
            }
        }
    }
}
