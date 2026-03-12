import SwiftUI
import UniformTypeIdentifiers

struct HomeDashboardView: View {
    let session: UserSession
    let dependencies: AppDependencies
    let openLiveMeeting: () -> Void

    @State private var searchText = ""
    @State private var showUploadAudio = false
    @State private var showJoinMeeting = false
    @State private var showAISummary = false
    @State private var projects: [UserProject] = []
    @State private var uploadProjectId: String = ""

    private var filteredProjects: [UserProject] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return projects }
        return projects.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
            || ($0.goal?.localizedCaseInsensitiveContains(trimmed) == true)
        }
    }

    private var currentGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.x16) {
                HStack {
                    VStack(alignment: .leading, spacing: DS.Spacing.x4) {
                        Text(currentGreeting)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.ColorToken.textSecondary)
                        Text(session.name)
                            .font(DS.Typography.title2)
                            .foregroundStyle(DS.ColorToken.textPrimary)
                    }
                    Spacer()
                    NavigationLink(destination: NotificationsScreen()) {
                        Image(systemName: "bell")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DS.ColorToken.textPrimary)
                            .frame(width: 40, height: 40)
                            .background(DS.ColorToken.surface)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                    .stroke(DS.ColorToken.border, lineWidth: 1)
                            )
                    }
                }

                DSSearchBar(text: $searchText, placeholder: "Search meetings, transcripts, actions")

                DSSectionHeader(title: "Quick Actions")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Spacing.x12) {
                    quickAction("Start Recording", icon: "mic.fill", action: openLiveMeeting)
                    quickAction("Upload Audio", icon: "waveform.badge.plus", action: { showUploadAudio = true })
                    quickAction("Join Meeting", icon: "video.fill", action: { showJoinMeeting = true })
                    quickAction("AI Summary", icon: "sparkles", action: { showAISummary = true })
                }

                DSSectionHeader(title: "Recent Meetings")
                DSEmptyState(
                    icon: "calendar.badge.clock",
                    title: "No meetings yet",
                    message: "Start a recording or join a meeting to see it here."
                )

                DSSectionHeader(title: searchText.trimmingCharacters(in: .whitespaces).isEmpty ? "My Projects" : "Projects")
                if projects.isEmpty {
                    DSEmptyState(
                        icon: "folder.badge.plus",
                        title: "No projects yet",
                        message: "Go to the Projects tab to create your first project."
                    )
                } else if filteredProjects.isEmpty {
                    DSEmptyState(
                        icon: "magnifyingglass",
                        title: "No results",
                        message: "No projects match \"\(searchText.trimmingCharacters(in: .whitespaces))\"."
                    )
                } else {
                    VStack(spacing: DS.Spacing.x8) {
                        ForEach(filteredProjects) { project in
                            NavigationLink(destination: ProjectDetailView(project: project, session: session, dependencies: dependencies)) {
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(DS.ColorToken.primary)
                                        .frame(width: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(project.name)
                                            .font(DS.Typography.bodyMedium)
                                            .foregroundStyle(DS.ColorToken.textPrimary)
                                        Text("Tap to view knowledge base")
                                            .font(DS.Typography.caption)
                                            .foregroundStyle(DS.ColorToken.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(DS.ColorToken.textTertiary)
                                }
                                .padding(DS.Spacing.x16)
                                .background(DS.ColorToken.surface)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).stroke(DS.ColorToken.border, lineWidth: 1))
                            }
                        }
                    }
                }
            }
            .padding(DS.Spacing.x16)
        }
        .background(DS.ColorToken.canvas)
        .navigationTitle("Dashboard")
        .task {
            if let loaded = try? await dependencies.projectRepository.listProjects(token: session.accessToken) {
                projects = loaded
                if uploadProjectId.isEmpty, let first = loaded.first {
                    uploadProjectId = first.projectId
                }
            }
        }
        .sheet(isPresented: $showUploadAudio) {
            UploadAudioSheet(
                isPresented: $showUploadAudio,
                session: session,
                dependencies: dependencies,
                projectRepository: dependencies.projectRepository,
                projects: projects,
                selectedProjectId: $uploadProjectId
            )
        }
        .sheet(isPresented: $showJoinMeeting) {
            JoinMeetingSheet(isPresented: $showJoinMeeting, openLiveMeeting: openLiveMeeting)
        }
        .navigationDestination(isPresented: $showAISummary) {
            AISummaryScreen(session: session, dependencies: dependencies)
                .navigationTitle("AI Summary")
        }
    }

    private func quickAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DS.Spacing.x12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.primary)
                Text(title)
                    .font(DS.Typography.bodyMedium)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DS.Spacing.x16)
            .frame(maxWidth: .infinity)
            .background(DS.ColorToken.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.ColorToken.border, lineWidth: 1)
            )
        }
        .modifier(QuickActionAccessibilityModifier(identifier: title == "Start Recording" ? "startRecordingButton" : nil))
    }
}

private struct QuickActionAccessibilityModifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

// MARK: - Upload Audio Sheet

struct UploadAudioSheet: View {
    @Binding var isPresented: Bool
    let session: UserSession
    let dependencies: AppDependencies
    let projectRepository: any ProjectRepository
    let projects: [UserProject]
    @Binding var selectedProjectId: String

    @State private var isFileImporterPresented = false
    @State private var uploadedFileName: String? = nil
    @State private var uploadedURL: URL? = nil
    @State private var isUploading = false
    @State private var uploadError: String? = nil
    @State private var uploadStatus: String? = nil

    private let allowedTypes: [UTType] = [
        .audio,
        UTType(filenameExtension: "mp3") ?? .audio,
        UTType(filenameExtension: "m4a") ?? .audio,
        UTType(filenameExtension: "wav") ?? .audio,
        UTType(filenameExtension: "aac") ?? .audio
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.x24) {
                    DSAIInsightCard(
                        title: "Upload Audio",
                        message: "Upload a meeting recording to automatically generate a transcript and AI summary."
                    )

                    // Project picker
                    if !projects.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Spacing.x8) {
                            Text("Project")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.ColorToken.textSecondary)
                            Picker("Project", selection: $selectedProjectId) {
                                ForEach(projects) { project in
                                    Text(project.name).tag(project.projectId)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding(.horizontal, DS.Spacing.x12)
                            .padding(.vertical, DS.Spacing.x8)
                            .background(DS.ColorToken.surface)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                    .stroke(DS.ColorToken.border, lineWidth: 1)
                            )
                        }
                    } else {
                        DSAIInsightCard(
                            title: "No projects found",
                            message: "Create a project in the Projects tab first, then upload audio."
                        )
                    }

                    VStack(alignment: .leading, spacing: DS.Spacing.x12) {
                        Text("Supported formats")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.ColorToken.textSecondary)
                        HStack(spacing: DS.Spacing.x8) {
                            ForEach(["MP3", "M4A", "WAV", "AAC"], id: \.self) { format in
                                DSBadge(text: format, tone: DS.ColorToken.primary)
                            }
                        }
                    }

                    if let fileName = uploadedFileName {
                        HStack(spacing: DS.Spacing.x12) {
                            Image(systemName: "waveform.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(DS.ColorToken.success)
                            VStack(alignment: .leading, spacing: DS.Spacing.x4) {
                                Text(fileName)
                                    .font(DS.Typography.bodyMedium)
                                    .foregroundStyle(DS.ColorToken.textPrimary)
                                Text("Ready to process")
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.ColorToken.success)
                            }
                        }
                        .dsCardStyle()
                    }

                    if let error = uploadError {
                        Text(error)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.ColorToken.error)
                            .dsCardStyle()
                    }

                    if let uploadStatus {
                        Text(uploadStatus)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.ColorToken.textSecondary)
                            .dsCardStyle()
                    }

                    DSButton(
                        title: uploadedFileName == nil ? "Choose Audio File" : "Change File",
                        icon: "doc.badge.plus",
                        kind: .secondary
                    ) {
                        isFileImporterPresented = true
                    }

                    if uploadedFileName != nil {
                        DSButton(
                            title: "Process Audio",
                            icon: "sparkles",
                            kind: .primary,
                            isLoading: isUploading,
                            isDisabled: selectedProjectId.isEmpty
                        ) {
                            processAudio()
                        }
                    }
                }
                .padding(DS.Spacing.x16)
            }
            .background(DS.ColorToken.canvas)
            .navigationTitle("Upload Audio")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { isPresented = false }
                }
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: allowedTypes,
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    uploadedFileName = url.lastPathComponent
                    uploadedURL = url
                    uploadError = nil
                }
            }
        }
    }

    private func processAudio() {
        guard let url = uploadedURL, !selectedProjectId.isEmpty else { return }
        isUploading = true
        uploadError = nil
        uploadStatus = "Copying audio into project…"
        Task {
            do {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let fileData = try Data(contentsOf: url)
                let ext = url.pathExtension.lowercased()
                let mimeType: String
                switch ext {
                case "mp3": mimeType = "audio/mpeg"
                case "m4a": mimeType = "audio/m4a"
                case "wav": mimeType = "audio/wav"
                case "aac": mimeType = "audio/aac"
                default:    mimeType = "audio/mpeg"
                }

                let storedURL = try storeImportedAudio(data: fileData, originalURL: url, projectId: selectedProjectId)
                uploadStatus = "Transcribing uploaded audio…"
                let transcriptText: String
                do {
                    transcriptText = try await dependencies.transcriptionService.transcribeAudioFile(at: storedURL)
                } catch {
                    _ = try await projectRepository.importAudioAsset(
                        projectId: selectedProjectId,
                        fileName: url.lastPathComponent,
                        mimeType: mimeType,
                        localFileURL: storedURL,
                        durationSeconds: nil,
                        sourceType: "uploadedAudio",
                        transcript: nil,
                        token: session.accessToken
                    )
                    throw error
                }

                _ = try await projectRepository.importAudioAsset(
                    projectId: selectedProjectId,
                    fileName: url.lastPathComponent,
                    mimeType: mimeType,
                    localFileURL: storedURL,
                    durationSeconds: nil,
                    sourceType: "uploadedAudio",
                    transcript: transcriptText,
                    token: session.accessToken
                )
                uploadStatus = "Transcript attached to selected project"
                isUploading = false
                isPresented = false
            } catch {
                isUploading = false
                uploadError = error.localizedDescription
                uploadStatus = nil
            }
        }
    }

    private func storeImportedAudio(data: Data, originalURL: URL, projectId: String) throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = docs
            .appendingPathComponent("project-audio", isDirectory: true)
            .appendingPathComponent(projectId, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let baseName = UUID().uuidString + "-" + originalURL.lastPathComponent
        let destination = directory.appendingPathComponent(baseName)
        try data.write(to: destination, options: [.atomic])
        return destination
    }
}

// MARK: - Join Meeting Sheet

struct JoinMeetingSheet: View {
    @Binding var isPresented: Bool
    let openLiveMeeting: () -> Void

    @State private var meetingCode = ""
    @State private var meetingName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.x24) {
                    DSAIInsightCard(
                        title: "Join Meeting",
                        message: "Enter a meeting link to open it directly in the meeting app. The AI assistant will start listening automatically."
                    )

                    VStack(spacing: DS.Spacing.x12) {
                        inputField(title: "Meeting Name (optional)", placeholder: "e.g. Q2 Product Review", text: $meetingName, keyboard: .default)
                        inputField(title: "Meeting Link or Code", placeholder: "Paste link or enter code", text: $meetingCode, keyboard: .URL)
                    }
                    .padding(DS.Spacing.x16)
                    .background(DS.ColorToken.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                            .stroke(DS.ColorToken.border, lineWidth: 1)
                    )

                    DSSectionHeader(title: "Quick Platform")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Spacing.x8) {
                            ForEach(meetingPlatforms, id: \.name) { platform in
                                Button {
                                    meetingCode = platform.exampleLink
                                } label: {
                                    DSBadge(text: platform.name, tone: DS.ColorToken.primary)
                                }
                            }
                        }
                    }

                    DSButton(
                        title: "Open Meeting & Start AI",
                        icon: "arrow.up.right.square",
                        kind: .primary,
                        isDisabled: meetingCode.isEmpty
                    ) {
                        openMeetingAndStartAI()
                    }

                    DSButton(
                        title: "AI Assistant Only",
                        icon: "mic.fill",
                        kind: .secondary,
                        isDisabled: meetingCode.isEmpty
                    ) {
                        isPresented = false
                        openLiveMeeting()
                    }
                }
                .padding(DS.Spacing.x16)
            }
            .background(DS.ColorToken.canvas)
            .navigationTitle("Join Meeting")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { isPresented = false }
                }
            }
        }
    }

    private struct MeetingPlatform {
        let name: String
        let exampleLink: String
        let urlScheme: String?
    }

    private let meetingPlatforms: [MeetingPlatform] = [
        MeetingPlatform(name: "Zoom", exampleLink: "https://zoom.us/j/", urlScheme: "zoommtg://"),
        MeetingPlatform(name: "Google Meet", exampleLink: "https://meet.google.com/", urlScheme: nil),
        MeetingPlatform(name: "Teams", exampleLink: "https://teams.microsoft.com/l/meetup-join/", urlScheme: "msteams://")
    ]

    private func openMeetingAndStartAI() {
        // Try to open the meeting URL externally
        if let url = URL(string: meetingCode), meetingCode.hasPrefix("http") {
            // For Zoom: convert https to zoommtg scheme
            var targetURL = url
            if meetingCode.contains("zoom.us") {
                let zoomScheme = meetingCode.replacingOccurrences(of: "https://", with: "zoommtg://")
                if let zoomURL = URL(string: zoomScheme), UIApplication.shared.canOpenURL(zoomURL) {
                    targetURL = zoomURL
                }
            } else if meetingCode.contains("teams.microsoft.com") {
                let teamsScheme = meetingCode.replacingOccurrences(of: "https://", with: "msteams://")
                if let teamsURL = URL(string: teamsScheme), UIApplication.shared.canOpenURL(teamsURL) {
                    targetURL = teamsURL
                }
            }
            UIApplication.shared.open(targetURL, options: [:], completionHandler: nil)
        }
        isPresented = false
        openLiveMeeting()
    }

    private func inputField(title: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x8) {
            Text(title)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.ColorToken.textSecondary)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .padding(.horizontal, DS.Spacing.x12)
                .padding(.vertical, DS.Spacing.x12)
                .background(DS.ColorToken.elevated)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .stroke(DS.ColorToken.border, lineWidth: 1)
                )
        }
    }
}
