import SwiftUI

struct HomeDashboardView: View {
    let session: UserSession
    let openLiveMeeting: () -> Void

    @State private var searchText = ""
    @State private var pendingDone = false

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
                    quickAction("Upload Audio", icon: "waveform.badge.plus", action: {})
                    quickAction("Join Meeting", icon: "video.fill", action: {})
                    quickAction("AI Summary", icon: "sparkles", action: {})
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
