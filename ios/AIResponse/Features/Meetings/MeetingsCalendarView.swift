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

                DSSectionHeader(title: "Upcoming Meetings")
                DSEmptyState(
                    icon: "calendar.badge.clock",
                    title: "No upcoming meetings",
                    message: "Scheduled meetings will appear here after calendar sync."
                )

                DSSectionHeader(title: "Start a Meeting Now")
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

struct MeetingDigest: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let time: String
    let duration: String
    let source: String
    let participants: Int
}
