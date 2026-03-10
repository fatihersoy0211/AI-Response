import SwiftUI

struct MeetingsCalendarView: View {
    let session: UserSession
    let openLiveMeeting: () -> Void

    @State private var mode: AgendaMode = .daily

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.x16) {
                Picker("Agenda", selection: $mode) {
                    Text("Daily").tag(AgendaMode.daily)
                    Text("Weekly").tag(AgendaMode.weekly)
                }
                .pickerStyle(.segmented)

                DSProgressPill(title: "Calendar Sync", value: 0.92)

                DSSectionHeader(title: "Upcoming Meetings")

                ForEach(sampleMeetings) { meeting in
                    VStack(spacing: DS.Spacing.x8) {
                        NavigationLink(destination: MeetingDetailsView(meeting: meeting)) {
                            DSMeetingCard(
                                title: meeting.title,
                                time: "\(meeting.time) · \(meeting.duration)",
                                source: meeting.source,
                                participants: meeting.participants
                            )
                        }
                        .buttonStyle(.plain)

                        HStack {
                            DSButton(title: "Join", icon: "video.fill", kind: .secondary) {}
                            DSButton(title: "Prepare", icon: "sparkles", kind: .secondary) {}
                        }
                    }
                }

                DSSectionHeader(title: "AI Preparation")
                DSAIInsightCard(
                    title: "Prepare Briefing",
                    message: "AI prepared 3 talking points for your 14:30 stakeholder review."
                )

                DSButton(title: "Start Recording", icon: "mic.fill", kind: .primary, action: openLiveMeeting)
            }
            .padding(DS.Spacing.x16)
        }
        .background(DS.ColorToken.canvas)
        .navigationTitle("Meetings")
    }
}

private enum AgendaMode {
    case daily
    case weekly
}

struct MeetingDigest: Identifiable {
    let id = UUID()
    let title: String
    let time: String
    let duration: String
    let source: String
    let participants: Int
}

private let sampleMeetings: [MeetingDigest] = [
    .init(title: "Executive Weekly", time: "09:30", duration: "45m", source: "Zoom", participants: 7),
    .init(title: "Partner Sync", time: "11:00", duration: "30m", source: "Meet", participants: 4),
    .init(title: "Roadmap Review", time: "14:30", duration: "60m", source: "Teams", participants: 9)
]
