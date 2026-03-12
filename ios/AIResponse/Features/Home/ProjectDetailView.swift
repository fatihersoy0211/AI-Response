import SwiftUI
import UniformTypeIdentifiers

struct ProjectDetailView: View {
    let project: UserProject
    let session: UserSession
    let dependencies: AppDependencies
    var onProjectUpdated: (() -> Void)? = nil

    @State private var notesText: String = ""
    @State private var isSaving = false
    @State private var saved = false
    @State private var documents: [ProjectDocument] = []
    @State private var audioAssets: [ProjectAudioAsset] = []
    @State private var transcripts: [TranscriptSegment] = []
    @State private var errorMessage: String?

    // Upload state
    @State private var showDocumentPicker = false
    @State private var showAudioUpload = false
    @State private var isUploadingDoc = false
    @State private var uploadDocStatus: String?
    @State private var uploadDocError: String?

    // Delete confirmation
    @State private var sourceToDelete: (id: String, name: String)?
    @State private var showDeleteConfirm = false

    var body: some View {
        List {
            // Project Knowledge
            notesSection

            // Save button
            if notesText != (project.manualText ?? "") || saved {
                saveSection
            }

            // Error
            if let error = errorMessage {
                Section {
                    Text(error)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.ColorToken.error)
                }
                .listRowBackground(DS.ColorToken.surface)
            }

            // Upload actions
            uploadActionsSection

            // Documents
            if !documents.isEmpty {
                documentsSection
            }

            // Audio Assets
            if !audioAssets.isEmpty {
                audioSection
            }

            // Transcripts
            if !transcripts.isEmpty {
                transcriptsSection
            }

            // Empty state
            if documents.isEmpty && audioAssets.isEmpty && transcripts.isEmpty {
                Section("Knowledge Sources") {
                    DSEmptyState(
                        icon: "tray",
                        title: "No uploaded sources yet",
                        message: "Upload documents (PDF, DOCX, PPTX, TXT) or audio files to enrich the AI context."
                    )
                }
                .listRowBackground(DS.ColorToken.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(DS.ColorToken.canvas)
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { await loadData() } }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPickerSheet(
                isPresented: $showDocumentPicker,
                isUploading: $isUploadingDoc,
                uploadStatus: $uploadDocStatus,
                uploadError: $uploadDocError,
                session: session,
                projectId: project.projectId,
                repository: dependencies.projectRepository,
                onComplete: { Task { await loadData() } }
            )
        }
        .sheet(isPresented: $showAudioUpload) {
            UploadAudioSheet(
                isPresented: $showAudioUpload,
                session: session,
                dependencies: dependencies,
                projectRepository: dependencies.projectRepository,
                projects: [project],
                selectedProjectId: .constant(project.projectId)
            )
            .onDisappear { Task { await loadData() } }
        }
        .confirmationDialog(
            "Delete \"\(sourceToDelete?.name ?? "")\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let s = sourceToDelete { deleteSource(id: s.id, name: s.name) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This source will be permanently removed from the project context.")
        }
    }

    // MARK: - Sections

    private var notesSection: some View {
        Section {
            ZStack(alignment: .topLeading) {
                if notesText.isEmpty {
                    Text("Enter project background, goals, key participants, context, terminology…")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.ColorToken.textTertiary)
                        .padding(.top, 8)
                        .padding(.horizontal, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $notesText)
                    .font(DS.Typography.body)
                    .frame(minHeight: 160)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
        } header: {
            Text("Project Knowledge")
        } footer: {
            Text("The AI reads this first before any transcripts — use it to ground the AI in your project context.")
        }
        .listRowBackground(DS.ColorToken.surface)
    }

    private var saveSection: some View {
        Section {
            Button {
                Task { await saveNotes() }
            } label: {
                HStack {
                    Spacer()
                    if saved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(DS.ColorToken.success)
                    } else if isSaving {
                        ProgressView()
                    } else {
                        Text("Save Knowledge")
                            .font(DS.Typography.bodyMedium)
                            .foregroundStyle(DS.ColorToken.primary)
                    }
                    Spacer()
                }
            }
            .disabled(isSaving)
        }
        .listRowBackground(DS.ColorToken.surface)
    }

    private var uploadActionsSection: some View {
        Section("Add Sources") {
            Button {
                uploadDocError = nil
                uploadDocStatus = nil
                showDocumentPicker = true
            } label: {
                HStack(spacing: DS.Spacing.x12) {
                    uploadActionIcon("doc.badge.plus", color: DS.ColorToken.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upload Document")
                            .font(DS.Typography.bodyMedium)
                            .foregroundStyle(DS.ColorToken.textPrimary)
                        Text("PDF, DOCX, PPTX, TXT")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.ColorToken.textSecondary)
                    }
                    Spacer()
                    if isUploadingDoc {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.ColorToken.textTertiary)
                    }
                }
            }

            Button {
                showAudioUpload = true
            } label: {
                HStack(spacing: DS.Spacing.x12) {
                    uploadActionIcon("waveform.badge.plus", color: DS.ColorToken.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upload Audio")
                            .font(DS.Typography.bodyMedium)
                            .foregroundStyle(DS.ColorToken.textPrimary)
                        Text("MP3, M4A, WAV, AAC → auto-transcribed")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.ColorToken.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.ColorToken.textTertiary)
                }
            }

            if let status = uploadDocStatus {
                HStack(spacing: DS.Spacing.x8) {
                    ProgressView()
                    Text(status)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                }
            }

            if let err = uploadDocError {
                Text(err)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.ColorToken.error)
            }
        }
        .listRowBackground(DS.ColorToken.surface)
    }

    private var documentsSection: some View {
        Section {
            ForEach(documents) { doc in
                HStack(spacing: DS.Spacing.x12) {
                    Image(systemName: docIcon(for: doc.fileType))
                        .foregroundStyle(DS.ColorToken.primary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.fileName)
                            .font(DS.Typography.bodyMedium)
                            .foregroundStyle(DS.ColorToken.textPrimary)
                            .lineLimit(1)
                        Text(doc.fileType)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.ColorToken.textSecondary)
                    }
                    Spacer()
                    DSBadge(text: statusLabel(doc.extractionStatus), tone: statusColor(doc.extractionStatus))
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        sourceToDelete = (id: doc.sourceId, name: doc.fileName)
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text("Documents (\(documents.count))")
        }
        .listRowBackground(DS.ColorToken.surface)
    }

    private var audioSection: some View {
        Section {
            ForEach(audioAssets) { asset in
                HStack(spacing: DS.Spacing.x12) {
                    Image(systemName: "waveform.circle.fill")
                        .foregroundStyle(DS.ColorToken.primary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(asset.title)
                            .font(DS.Typography.bodyMedium)
                            .foregroundStyle(DS.ColorToken.textPrimary)
                            .lineLimit(1)
                        if let dur = asset.durationSeconds {
                            Text(formattedDuration(dur))
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.ColorToken.textSecondary)
                        } else {
                            Text(asset.mimeType)
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.ColorToken.textSecondary)
                        }
                    }
                    Spacer()
                    DSBadge(text: statusLabel(asset.transcriptionStatus), tone: statusColor(asset.transcriptionStatus))
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        sourceToDelete = (id: asset.assetId, name: asset.title)
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text("Audio (\(audioAssets.count))")
        }
        .listRowBackground(DS.ColorToken.surface)
    }

    private var transcriptsSection: some View {
        Section {
            ForEach(transcripts) { segment in
                HStack(spacing: DS.Spacing.x12) {
                    Image(systemName: "waveform")
                        .foregroundStyle(DS.ColorToken.primary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(segment.title)
                            .font(DS.Typography.bodyMedium)
                            .foregroundStyle(DS.ColorToken.textPrimary)
                            .lineLimit(1)
                        Text(segment.sourceType)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.ColorToken.textSecondary)
                    }
                    Spacer()
                    DSBadge(text: "Indexed", tone: DS.ColorToken.success)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        sourceToDelete = (id: segment.sourceId, name: segment.title)
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text("Transcripts (\(transcripts.count))")
        }
        .listRowBackground(DS.ColorToken.surface)
    }

    // MARK: - Actions

    private func loadData() async {
        notesText = (try? await dependencies.projectRepository.loadProjectNotes(
            projectId: project.projectId, token: session.accessToken
        )) ?? project.manualText ?? ""
        documents = (try? await dependencies.projectRepository.listProjectDocuments(
            projectId: project.projectId, token: session.accessToken
        )) ?? []
        audioAssets = (try? await dependencies.projectRepository.listProjectAudioAssets(
            projectId: project.projectId, token: session.accessToken
        )) ?? []
        transcripts = (try? await dependencies.projectRepository.listProjectTranscripts(
            projectId: project.projectId, token: session.accessToken
        )) ?? []
    }

    private func saveNotes() async {
        isSaving = true
        errorMessage = nil
        do {
            _ = try await dependencies.projectRepository.saveProjectNotes(
                projectId: project.projectId, text: notesText, token: session.accessToken
            )
            isSaving = false
            withAnimation { saved = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { saved = false }
            }
            onProjectUpdated?()
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSource(id: String, name: String) {
        Task {
            do {
                try await dependencies.projectRepository.deleteProjectSource(
                    projectId: project.projectId, sourceId: id, token: session.accessToken
                )
                await loadData()
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    // MARK: - Helpers

    private func uploadActionIcon(_ name: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(color.opacity(0.12))
                .frame(width: 32, height: 32)
            Image(systemName: name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
        }
    }

    private func docIcon(for fileType: String) -> String {
        let t = fileType.lowercased()
        if t.contains("pdf") { return "doc.richtext.fill" }
        if t.contains("word") || t.contains("docx") { return "doc.text.fill" }
        if t.contains("ppt") || t.contains("presentation") { return "chart.bar.doc.horizontal.fill" }
        return "doc.fill"
    }

    private func statusLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "completed", "extracted", "indexed": return "Ready"
        case "processing", "transcribing": return "Processing"
        case "pending": return "Pending"
        case "failed": return "Failed"
        default: return raw.capitalized
        }
    }

    private func statusColor(_ raw: String) -> Color {
        switch raw.lowercased() {
        case "completed", "extracted", "indexed": return DS.ColorToken.success
        case "processing", "transcribing": return DS.ColorToken.primary
        case "pending": return DS.ColorToken.textSecondary
        case "failed": return DS.ColorToken.error
        default: return DS.ColorToken.textSecondary
        }
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - DocumentPickerSheet

private struct DocumentPickerSheet: View {
    @Binding var isPresented: Bool
    @Binding var isUploading: Bool
    @Binding var uploadStatus: String?
    @Binding var uploadError: String?

    let session: UserSession
    let projectId: String
    let repository: any ProjectRepository
    let onComplete: () -> Void

    @State private var pickedURL: URL?
    @State private var pickedName: String?
    @State private var showPicker = false

    private let allowedTypes: [UTType] = [
        .pdf,
        UTType(filenameExtension: "docx") ?? .data,
        UTType(filenameExtension: "pptx") ?? .data,
        .plainText,
        .text,
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.x24) {
                    DSAIInsightCard(
                        title: "Upload Document",
                        message: "The AI will extract and index the text so it becomes part of this project's knowledge context."
                    )

                    VStack(alignment: .leading, spacing: DS.Spacing.x12) {
                        Text("Supported formats")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.ColorToken.textSecondary)
                        HStack(spacing: DS.Spacing.x8) {
                            ForEach(["PDF", "DOCX", "PPTX", "TXT"], id: \.self) { fmt in
                                DSBadge(text: fmt, tone: DS.ColorToken.primary)
                            }
                        }
                    }

                    if let name = pickedName {
                        HStack(spacing: DS.Spacing.x12) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(DS.ColorToken.success)
                            VStack(alignment: .leading, spacing: DS.Spacing.x4) {
                                Text(name)
                                    .font(DS.Typography.bodyMedium)
                                    .foregroundStyle(DS.ColorToken.textPrimary)
                                Text("Ready to upload")
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.ColorToken.success)
                            }
                        }
                        .dsCardStyle()
                    }

                    if let status = uploadStatus {
                        HStack(spacing: DS.Spacing.x8) {
                            ProgressView()
                            Text(status)
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.ColorToken.textSecondary)
                        }
                        .dsCardStyle()
                    }

                    if let err = uploadError {
                        Text(err)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.ColorToken.error)
                            .dsCardStyle()
                    }

                    DSButton(
                        title: pickedName == nil ? "Choose File" : "Change File",
                        icon: "doc.badge.plus",
                        kind: .secondary
                    ) {
                        showPicker = true
                    }

                    if pickedName != nil {
                        DSButton(
                            title: "Upload & Index",
                            icon: "arrow.up.doc.fill",
                            kind: .primary,
                            isLoading: isUploading
                        ) {
                            upload()
                        }
                    }
                }
                .padding(DS.Spacing.x16)
            }
            .background(DS.ColorToken.canvas)
            .navigationTitle("Upload Document")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { isPresented = false }
                }
            }
            .fileImporter(
                isPresented: $showPicker,
                allowedContentTypes: allowedTypes,
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    pickedURL = url
                    pickedName = url.lastPathComponent
                    uploadError = nil
                }
            }
        }
    }

    private func upload() {
        guard let url = pickedURL else { return }
        isUploading = true
        uploadError = nil
        uploadStatus = "Reading file…"
        Task {
            do {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                let mime = mimeType(for: url)
                uploadStatus = "Uploading and extracting text…"
                _ = try await repository.uploadFileSource(
                    projectId: projectId,
                    fileName: url.lastPathComponent,
                    mimeType: mime,
                    fileData: data,
                    token: session.accessToken
                )
                await MainActor.run {
                    isUploading = false
                    uploadStatus = nil
                    isPresented = false
                    onComplete()
                }
            } catch {
                await MainActor.run {
                    isUploading = false
                    uploadStatus = nil
                    uploadError = error.localizedDescription
                }
            }
        }
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "txt": return "text/plain"
        default: return "application/octet-stream"
        }
    }
}
