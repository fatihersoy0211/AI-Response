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
        var types: [UTType] = [.pdf, .text, .plainText]
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
        if let doc = UTType(filenameExtension: "doc") { types.append(doc) }
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
                    viewModel.stop()   // auto-saves transcript before closing
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
                Text(viewModel.mode == .listening ? "Dinleniyor" : "Hazır")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.ColorToken.textSecondary)
                Spacer()
                DSBadge(text: "Secure", tone: DS.ColorToken.success)
            }

            if viewModel.projects.isEmpty {
                DSEmptyState(
                    icon: "folder.badge.plus",
                    title: "Proje seçilmedi",
                    message: "Sağ üstteki Knowledge butonundan proje oluşturun."
                )
            } else {
                Picker("Proje", selection: $viewModel.selectedProjectId) {
                    ForEach(viewModel.projects) { project in
                        Text(project.name).tag(project.projectId)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.selectedProjectId) { _, newValue in
                    viewModel.selectProject(newValue)
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

    // MARK: - Participants

    private var participants: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x8) {
            Text("Katılımcılar")
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

    // MARK: - Session Log (all previous rounds)

    @ViewBuilder
    private var sessionLogCard: some View {
        if !viewModel.sessionLog.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.x8) {
                DSSectionHeader(title: "Toplantı Geçmişi – \(viewModel.sessionLog.count) tur")
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
            DSSectionHeader(title: "Canlı Transkript")
            Text(viewModel.liveTranscript.isEmpty ? "Konuşmayı dinlemek için Listen'a bas…" : viewModel.liveTranscript)
                .font(DS.Typography.body)
                .foregroundStyle(DS.ColorToken.textPrimary)
            HStack {
                DSButton(title: "Yer İmi", icon: "bookmark", kind: .secondary) {}
                DSButton(title: "Not Ekle", icon: "note.text.badge.plus", kind: .secondary) {}
            }
        }
        .dsCardStyle()
    }

    // MARK: - AI Answer

    private var aiAnswerCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x8) {
            DSSectionHeader(title: "AI Yanıtı")
            if viewModel.mode == .answering && viewModel.answerText.isEmpty {
                HStack(spacing: DS.Spacing.x8) {
                    ProgressView()
                    Text("AI yanıt oluşturuyor…")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                }
            } else {
                Text(viewModel.answerText.isEmpty
                     ? "Respond'a bastığında AI yanıtı burada görünecek."
                     : viewModel.answerText)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.ColorToken.textPrimary)
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
                title: viewModel.mode == .listening ? "Dinliyor…" : "Listen",
                icon: "mic.fill",
                kind: .primary,
                isDisabled: viewModel.mode == .listening
            ) {
                viewModel.listen()
            }
            DSButton(
                title: "Respond",
                icon: "sparkles",
                kind: .secondary,
                isLoading: viewModel.mode == .answering
            ) {
                viewModel.respondAndListenAgain()
            }
            DSButton(title: "Durdur", icon: "stop.fill", kind: .destructive) {
                viewModel.stop()
            }
        }
    }

    // MARK: - Knowledge Sheet

    private var knowledgeSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.x16) {

                    // ── Saved sources ──────────────────────────────────
                    if !viewModel.projectSources.isEmpty {
                        DSSectionHeader(title: "Proje Kaynakları (\(viewModel.projectSources.count))")
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
                    DSSectionHeader(title: "Proje Oluştur")
                    HStack {
                        TextField("Proje adı", text: $viewModel.newProjectName)
                            .padding(.horizontal, DS.Spacing.x12)
                            .padding(.vertical, DS.Spacing.x12)
                            .background(DS.ColorToken.surface)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                    .stroke(DS.ColorToken.border, lineWidth: 1)
                            )
                        DSButton(title: "Oluştur", kind: .primary) {
                            viewModel.createProject()
                        }
                        .frame(width: 110)
                    }

                    // ── Analyze text ───────────────────────────────────
                    DSSectionHeader(title: "Metin Kaynağı Ekle")
                    TextField("Kaynak başlığı", text: $viewModel.sourceTitle)
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

                    DSButton(title: "Metni Analiz Et & Kaydet", icon: "sparkles", kind: .primary) {
                        viewModel.uploadUserData()
                    }

                    // ── Upload file ────────────────────────────────────
                    DSSectionHeader(title: "Dosya Kaynağı Ekle (PDF / DOCX / TXT)")
                    DSButton(title: "Dosya Seç ve Yükle", icon: "doc.badge.plus", kind: .secondary) {
                        isFileImporterPresented = true
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
                    DSSectionHeader(title: "Proje Bağlamı")
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
                    Button("Tamam") { showKnowledgeSheet = false }
                }
            }
        }
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
