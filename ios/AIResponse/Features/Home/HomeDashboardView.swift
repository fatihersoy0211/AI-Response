import SwiftUI
import UniformTypeIdentifiers

struct HomeDashboardView: View {
    let session: UserSession
    let openLiveMeeting: () -> Void

    @State private var searchText = ""
    @State private var pendingDone = false
    @State private var showUploadAudio = false
    @State private var showJoinMeeting = false
    @State private var showAISummary = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.x16) {
                HStack {
                    VStack(alignment: .leading, spacing: DS.Spacing.x4) {
                        Text("Good morning")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.ColorToken.textSecondary)
                        Text("AI-Meeting Assist")
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

                HStack(spacing: DS.Spacing.x12) {
                    snapshotCard("Today", value: "3 meetings")
                    snapshotCard("Pending", value: "5 actions")
                }

                DSSectionHeader(title: "Quick Actions")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Spacing.x12) {
                    quickAction("Start Recording", icon: "mic.fill", action: openLiveMeeting)
                    quickAction("Upload Audio", icon: "waveform.badge.plus", action: { showUploadAudio = true })
                    quickAction("Join Meeting", icon: "video.fill", action: { showJoinMeeting = true })
                    quickAction("AI Summary", icon: "sparkles", action: { showAISummary = true })
                }

                DSSectionHeader(title: "AI Productivity Insight")
                DSAIInsightCard(
                    title: "Focus Insight",
                    message: "Your last 4 meetings repeated roadmap blockers. Ask AI to draft a single alignment memo."
                )

                DSSectionHeader(title: "Recent Meetings")
                DSMeetingCard(title: "Q2 Product Strategy", time: "09:30 - 10:15", source: "Zoom", participants: 6)
                DSMeetingCard(title: "Client Renewal Sync", time: "11:00 - 11:40", source: "Teams", participants: 4)

                DSSectionHeader(title: "Pending Action")
                DSActionItemCard(
                    title: "Send revised budget assumptions",
                    owner: "You",
                    dueDate: "Today 17:00",
                    priority: "High",
                    done: $pendingDone
                )
            }
            .padding(DS.Spacing.x16)
        }
        .background(DS.ColorToken.canvas)
        .navigationTitle("Dashboard")
        .sheet(isPresented: $showUploadAudio) {
            UploadAudioSheet(isPresented: $showUploadAudio)
        }
        .sheet(isPresented: $showJoinMeeting) {
            JoinMeetingSheet(isPresented: $showJoinMeeting, openLiveMeeting: openLiveMeeting)
        }
        .navigationDestination(isPresented: $showAISummary) {
            AISummaryScreen()
                .navigationTitle("AI Summary")
        }
    }

    private func snapshotCard(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x8) {
            Text(title)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.ColorToken.textSecondary)
            Text(value)
                .font(DS.Typography.heading)
                .foregroundStyle(DS.ColorToken.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCardStyle()
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
    }
}

// MARK: - Upload Audio Sheet

struct UploadAudioSheet: View {
    @Binding var isPresented: Bool
    @State private var isFileImporterPresented = false
    @State private var uploadedFileName: String? = nil
    @State private var isUploading = false

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
                            isLoading: isUploading
                        ) {
                            isUploading = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                isUploading = false
                                isPresented = false
                            }
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
                }
            }
        }
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
                        message: "Enter a meeting code or link to join and enable AI assistance in real time."
                    )

                    VStack(spacing: DS.Spacing.x12) {
                        inputField(title: "Meeting Name (optional)", placeholder: "e.g. Q2 Product Review", text: $meetingName, keyboard: .default)
                        inputField(title: "Meeting Code or Link", placeholder: "Paste link or enter code", text: $meetingCode, keyboard: .URL)
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
                            ForEach(["Zoom", "Google Meet", "Teams", "Webex"], id: \.self) { platform in
                                Button {
                                    meetingCode = "\(platform.lowercased().replacingOccurrences(of: " ", with: "")).meeting/join"
                                } label: {
                                    DSBadge(text: platform, tone: DS.ColorToken.primary)
                                }
                            }
                        }
                    }

                    DSButton(
                        title: "Start with AI Assistant",
                        icon: "mic.fill",
                        kind: .primary,
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
