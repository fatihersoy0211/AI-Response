import SwiftUI

struct ProjectDetailView: View {
    let project: UserProject
    let session: UserSession
    let dependencies: AppDependencies

    @State private var notesText: String = ""
    @State private var isSaving = false
    @State private var saved = false
    @State private var documents: [ProjectDocument] = []
    @State private var transcripts: [TranscriptSegment] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            // Project Knowledge (manual text input)
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
                        .frame(minHeight: 200)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                }
            } header: {
                Text("Project Knowledge")
            } footer: {
                Text("The AI reads this first before any transcripts — use it to ground the AI in your project context.")
            }
            .listRowBackground(DS.ColorToken.surface)

            // Save button
            if notesText != (project.manualText ?? "") || saved {
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

            // Error
            if let error = errorMessage {
                Section {
                    Text(error)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.ColorToken.error)
                }
                .listRowBackground(DS.ColorToken.surface)
            }

            // Documents
            if !documents.isEmpty {
                Section("Documents") {
                    ForEach(documents) { doc in
                        HStack(spacing: DS.Spacing.x12) {
                            Image(systemName: "doc.text.fill")
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
                            DSBadge(text: doc.extractionStatus, tone: DS.ColorToken.success)
                        }
                    }
                }
                .listRowBackground(DS.ColorToken.surface)
            }

            // Transcripts
            if !transcripts.isEmpty {
                Section("Transcripts") {
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
                    }
                }
                .listRowBackground(DS.ColorToken.surface)
            }

            if documents.isEmpty && transcripts.isEmpty {
                Section("Knowledge Sources") {
                    DSEmptyState(
                        icon: "tray",
                        title: "No uploaded sources yet",
                        message: "Upload documents or audio files to enrich the AI context."
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
    }

    private func loadData() async {
        notesText = (try? await dependencies.projectRepository.loadProjectNotes(projectId: project.projectId, token: session.accessToken)) ?? project.manualText ?? ""
        documents = (try? await dependencies.projectRepository.listProjectDocuments(projectId: project.projectId, token: session.accessToken)) ?? []
        transcripts = (try? await dependencies.projectRepository.listProjectTranscripts(projectId: project.projectId, token: session.accessToken)) ?? []
    }

    private func saveNotes() async {
        isSaving = true
        errorMessage = nil
        do {
            _ = try await dependencies.projectRepository.saveProjectNotes(projectId: project.projectId, text: notesText, token: session.accessToken)
            isSaving = false
            withAnimation { saved = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { saved = false }
            }
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }
}
