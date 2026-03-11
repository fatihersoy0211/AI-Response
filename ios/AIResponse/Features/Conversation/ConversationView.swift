import SwiftUI
import UniformTypeIdentifiers

struct ConversationView: View {
    let session: UserSession
    let dependencies: AppDependencies

    var body: some View {
        LiveMeetingView(session: session, dependencies: dependencies)
    }
}

struct LiveMeetingView: View {
    let session: UserSession
    let dependencies: AppDependencies
    let autoStartListening: Bool

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ConversationViewModel
    @State private var isFileImporterPresented = false
    @State private var showKnowledgeSheet = false
    @State private var elapsedSeconds = 0
    @State private var sessionStart = Date()
    @State private var bookmarkCount = 0
    @State private var waveActive = false
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var allowedFileTypes: [UTType] {
        var types: [UTType] = [.pdf, .text, .plainText]
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
        if let doc = UTType(filenameExtension: "doc") { types.append(doc) }
        return types
    }

    init(session: UserSession, dependencies: AppDependencies, autoStartListening: Bool = false) {
        self.session = session
        self.dependencies = dependencies
        self.autoStartListening = autoStartListening
        _viewModel = StateObject(
            wrappedValue: ConversationViewModel(
                session: session,
                speechService: dependencies.speechServiceFactory(),
                transcriptionService: dependencies.transcriptionService,
                projectRepository: dependencies.projectRepository,
                aiService: dependencies.aiService
            )
        )
    }

    var body: some View {
        ZStack {
            DS.ColorToken.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.x16) {
                    header
                    recordingHero
                    participants
                    sessionLogCard
                    transcriptCard
                    aiAnswerCard
                    controls
                }
                .padding(DS.Spacing.x16)
            }
        }
        .task {
            await viewModel.prepare()
            if autoStartListening {
                viewModel.listen()
                sessionStart = Date()
            }
        }
        .onChange(of: viewModel.mode) { _, newMode in
            withAnimation(newMode == .listening
                ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                : .easeOut(duration: 0.3)) {
                waveActive = newMode == .listening
            }
        }
        .onReceive(ticker) { _ in
            if viewModel.mode != .idle {
                elapsedSeconds = Int(Date().timeIntervalSince(sessionStart))
            }
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
                Button("Close") {
                    viewModel.stop()
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showKnowledgeSheet = true
                } label: {
                    Label("Knowledge", systemImage: "square.and.arrow.down")
                }
                .overlay(alignment: .topTrailing) {
                    if !viewModel.projectSources.isEmpty {
                        Circle()
                            .fill(DS.ColorToken.primary)
                            .frame(width: 8, height: 8)
                            .offset(x: 4, y: -4)
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x12) {
            HStack {
                Circle()
                    .fill(viewModel.mode == .listening ? DS.ColorToken.error : DS.ColorToken.warning)
                    .frame(width: 10, height: 10)
                    .accessibilityIdentifier("listeningIndicator")
                Text(viewModel.mode == .listening ? "Listening" : (viewModel.mode == .answering ? "Answering…" : "Ready"))
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.ColorToken.textSecondary)
                Spacer()
                DSBadge(text: "Secure", tone: DS.ColorToken.success)
            }
            Text(viewModel.transcriptionStatus)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.ColorToken.textSecondary)
                .accessibilityIdentifier("transcriptionStatusLabel")

            if viewModel.didUpdateContext {
                DSBadge(text: "Context Updated", tone: DS.ColorToken.success)
                    .accessibilityIdentifier("contextUpdatedBadge")
            }

            if viewModel.projects.isEmpty {
                DSEmptyState(
                    icon: "folder.badge.plus",
                    title: "No project selected",
                    message: "Tap the Knowledge button (top right) to create a project."
                )
            } else {
                VStack(alignment: .leading, spacing: DS.Spacing.x4) {
                    Text("Active Project")
                        .font(DS.Typography.micro)
                        .foregroundStyle(DS.ColorToken.textTertiary)
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

            // Upload status banner
            if let status = viewModel.uploadStatus {
                HStack(spacing: DS.Spacing.x8) {
                    if status.hasPrefix("✓") {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.ColorToken.success)
                    } else {
                        ProgressView().scaleEffect(0.7)
                    }
                    Text(status)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                }
                .transition(.opacity)
            }
        }
        .dsCardStyle()
    }

    // MARK: - Recording Hero

    private var recordingHero: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x12) {
            Text(viewModel.projects.first(where: { $0.projectId == viewModel.selectedProjectId })?.name ?? "Live Meeting")
                .font(DS.Typography.title2)
                .foregroundStyle(DS.ColorToken.textPrimary)
            Text(formatElapsed(elapsedSeconds))
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
                                .scaleEffect(
                                    y: waveActive ? (index % 2 == 0 ? 2.8 : 1.6) : 1.0,
                                    anchor: .center
                                )
                                .animation(
                                    waveActive
                                        ? .easeInOut(duration: 0.35 + Double(index % 6) * 0.05)
                                            .repeatForever(autoreverses: true)
                                            .delay(Double(index) * 0.025)
                                        : .easeOut(duration: 0.2),
                                    value: waveActive
                                )
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

    // MARK: - Participants

    private var participants: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x8) {
            Text("Participants")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.ColorToken.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.x8) {
                    DSBadge(text: session.name, tone: DS.ColorToken.primary)
                    if bookmarkCount > 0 {
                        DSBadge(text: "\(bookmarkCount) bookmark(s)", tone: DS.ColorToken.warning)
                    }
                }
            }
        }
        .dsCardStyle()
    }

    // MARK: - Session Log (all previous rounds)

    @ViewBuilder
    private var sessionLogCard: some View {
        if !viewModel.sessionLog.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.x8) {
                DSSectionHeader(title: "Session History – \(viewModel.sessionLog.count) round(s)")
                ForEach(viewModel.sessionLog) { entry in
                    VStack(alignment: .leading, spacing: DS.Spacing.x4) {
                        Text(entry.timestamp)
                            .font(DS.Typography.micro)
                            .foregroundStyle(DS.ColorToken.textTertiary)
                        Text(entry.text)
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.ColorToken.textPrimary)
                    }
                    .padding(DS.Spacing.x12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.ColorToken.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                }
            }
            .dsCardStyle()
        }
    }

    // MARK: - Live Transcript

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x8) {
            DSSectionHeader(title: "Live Transcript")
            Text(viewModel.liveTranscript.isEmpty ? "Tap Listen to start transcription…" : viewModel.liveTranscript)
                .font(DS.Typography.body)
                .foregroundStyle(DS.ColorToken.textPrimary)
            HStack {
                DSButton(title: "Bookmark", icon: "bookmark", kind: .secondary) {
                    bookmarkCount += 1
                }
                DSButton(title: "Add Note", icon: "note.text.badge.plus", kind: .secondary) {
                    if !viewModel.liveTranscript.isEmpty {
                        viewModel.userDataDraft = viewModel.liveTranscript
                        viewModel.sourceTitle = "Note \(bookmarkCount + 1)"
                        showKnowledgeSheet = true
                    }
                }
            }
        }
        .dsCardStyle()
    }

    // MARK: - AI Answer

    private var aiAnswerCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x8) {
            DSSectionHeader(title: "AI Response")
            if viewModel.mode == .answering && viewModel.answerText.isEmpty {
                HStack(spacing: DS.Spacing.x8) {
                    ProgressView()
                    Text("Generating AI response…")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                }
            } else {
                Text(viewModel.answerText.isEmpty
                     ? "AI response will appear here after tapping Respond."
                     : viewModel.answerText)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    .accessibilityIdentifier("aiResponseText")
            }
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.ColorToken.error)
            }
        }
        .dsCardStyle()
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: DS.Spacing.x12) {
            DSButton(
                title: viewModel.mode == .listening ? "Listening…" : "Listen",
                icon: "mic.fill",
                kind: .primary,
                isDisabled: viewModel.mode == .listening || viewModel.mode == .answering
            ) {
                viewModel.listen()
            }
            .accessibilityIdentifier("listenButton")
            DSButton(
                title: viewModel.mode == .answering ? "Answering…" : "Respond",
                icon: "sparkles",
                kind: .secondary,
                isLoading: viewModel.mode == .answering,
                isDisabled: viewModel.selectedProjectId.isEmpty
            ) {
                viewModel.respondAndListenAgain()
            }
            .accessibilityIdentifier("responseButton")
            DSButton(title: "Stop", icon: "stop.fill", kind: .destructive) {
                viewModel.stop()
                sessionStart = Date()
                elapsedSeconds = 0
            }
            .accessibilityIdentifier("stopRecordingButton")
        }
    }

    // MARK: - Knowledge Sheet

    private var knowledgeSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.x16) {

                    // ── Error banner ───────────────────────────────────
                    if let error = viewModel.errorMessage {
                        HStack(spacing: DS.Spacing.x8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(DS.ColorToken.error)
                            Text(error)
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.ColorToken.error)
                        }
                        .padding(DS.Spacing.x12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.ColorToken.error.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                    }

                    // ── Select existing project ────────────────────────
                    if !viewModel.projects.isEmpty {
                        DSSectionHeader(title: "Switch Project")
                        VStack(spacing: DS.Spacing.x8) {
                            ForEach(viewModel.projects) { project in
                                Button {
                                    viewModel.selectProject(project.projectId)
                                } label: {
                                    HStack {
                                        Image(systemName: viewModel.selectedProjectId == project.projectId
                                              ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(DS.ColorToken.primary)
                                        Text(project.name)
                                            .font(DS.Typography.bodyMedium)
                                            .foregroundStyle(DS.ColorToken.textPrimary)
                                        Spacer()
                                    }
                                    .padding(DS.Spacing.x12)
                                    .background(viewModel.selectedProjectId == project.projectId
                                                ? DS.ColorToken.primarySoft : DS.ColorToken.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                            .stroke(DS.ColorToken.border, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // ── Saved sources ──────────────────────────────────
                    if !viewModel.projectSources.isEmpty {
                        DSSectionHeader(title: "Project Sources (\(viewModel.projectSources.count))")
                        ForEach(viewModel.projectSources) { source in
                            HStack(spacing: DS.Spacing.x12) {
                                Image(systemName: sourceIcon(source.sourceType))
                                    .font(.system(size: 16))
                                    .foregroundStyle(DS.ColorToken.primary)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: DS.Spacing.x4) {
                                    Text(source.title)
                                        .font(DS.Typography.bodyMedium)
                                        .foregroundStyle(DS.ColorToken.textPrimary)
                                        .lineLimit(1)
                                    Text(source.sourceType.uppercased())
                                        .font(DS.Typography.micro)
                                        .foregroundStyle(DS.ColorToken.textTertiary)
                                }
                                Spacer()
                                DSBadge(text: "✓", tone: DS.ColorToken.success)
                            }
                            .dsCardStyle()
                        }
                    }

                    // ── Create project ─────────────────────────────────
                    DSSectionHeader(title: "Create New Project")
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
                            .accessibilityIdentifier("projectNameField")
                        DSButton(title: "Create", kind: .primary) {
                            viewModel.createProject()
                        }
                        .frame(width: 110)
                        .accessibilityIdentifier("saveProjectButton")
                    }

                    // ── Analyze text ───────────────────────────────────
                    if !viewModel.selectedProjectId.isEmpty {
                        DSSectionHeader(title: "Add Text Source")
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

                        DSButton(title: "Analyze & Save Text", icon: "sparkles", kind: .primary) {
                            viewModel.uploadUserData()
                        }

                        // ── Upload file ────────────────────────────────────
                        DSSectionHeader(title: "Add File Source (PDF / DOCX / TXT)")
                        DSButton(title: "Select & Upload File", icon: "doc.badge.plus", kind: .secondary) {
                            isFileImporterPresented = true
                        }
                    }

                    if let status = viewModel.uploadStatus {
                        HStack(spacing: DS.Spacing.x8) {
                            if status.hasPrefix("✓") {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.ColorToken.success)
                            } else {
                                ProgressView().scaleEffect(0.8)
                            }
                            Text(status)
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.ColorToken.textSecondary)
                        }
                    }

                    // ── Context summary ────────────────────────────────
                    if !viewModel.selectedProjectId.isEmpty {
                        DSSectionHeader(title: "Project Context")
                        Text(viewModel.contextSummary)
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.ColorToken.textSecondary)
                            .dsCardStyle()
                    }
                }
                .padding(DS.Spacing.x16)
            }
            .background(DS.ColorToken.canvas)
            .navigationTitle("Meeting Knowledge")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        viewModel.errorMessage = nil
                        showKnowledgeSheet = false
                    }
                }
            }
        }
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private func sourceIcon(_ type: String) -> String {
        switch type {
        case "file": return "doc.fill"
        case "transcript": return "waveform"
        case "text": return "text.alignleft"
        default: return "doc.text"
        }
    }
}
