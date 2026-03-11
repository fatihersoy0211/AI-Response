import EventKit
import SwiftUI

struct MeetingsCalendarView: View {
    let session: UserSession
    let openLiveMeeting: () -> Void

    @StateObject private var calendarService = CalendarService()
    @State private var mode: AgendaMode = .daily

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.x16) {
                Picker("Agenda", selection: $mode) {
                    Text("Today").tag(AgendaMode.daily)
                    Text("This Week").tag(AgendaMode.weekly)
                }
                .pickerStyle(.segmented)

                // Calendar permission banner
                if calendarService.authorizationStatus == .notDetermined {
                    calendarPermissionBanner
                } else if calendarService.authorizationStatus == .denied || calendarService.authorizationStatus == .restricted {
                    calendarDeniedBanner
                }

                DSSectionHeader(title: mode == .daily ? "Today's Meetings" : "This Week's Meetings")

                let events = filteredEvents
                if events.isEmpty {
                    DSEmptyState(
                        icon: "calendar.badge.clock",
                        title: "No upcoming meetings",
                        message: calendarService.authorizationStatus == .fullAccess
                            ? "No meetings scheduled for this period."
                            : "Connect your calendar to see upcoming meetings here."
                    )
                } else {
                    ForEach(events, id: \.eventIdentifier) { event in
                        calendarEventCard(event)
                    }
                }

                DSSectionHeader(title: "Start a Meeting Now")
                DSButton(title: "Start Recording", icon: "mic.fill", kind: .primary, action: openLiveMeeting)
            }
            .padding(DS.Spacing.x16)
        }
        .background(DS.ColorToken.canvas)
        .navigationTitle("Meetings")
        .task {
            await calendarService.requestAccess()
        }
    }

    private var filteredEvents: [EKEvent] {
        switch mode {
        case .daily:
            return calendarService.events.filter { Calendar.current.isDateInToday($0.startDate) }
        case .weekly:
            return calendarService.events
        }
    }

    private var calendarPermissionBanner: some View {
        HStack(spacing: DS.Spacing.x12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 20))
                .foregroundStyle(DS.ColorToken.primary)
            VStack(alignment: .leading, spacing: DS.Spacing.x4) {
                Text("Connect Calendar")
                    .font(DS.Typography.bodyMedium)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                Text("Allow access to see your scheduled meetings here.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.ColorToken.textSecondary)
            }
            Spacer()
            Button("Allow") {
                Task { await calendarService.requestAccess() }
            }
            .font(DS.Typography.caption)
            .foregroundStyle(DS.ColorToken.primary)
        }
        .dsCardStyle()
    }

    private var calendarDeniedBanner: some View {
        HStack(spacing: DS.Spacing.x12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 20))
                .foregroundStyle(DS.ColorToken.warning)
            VStack(alignment: .leading, spacing: DS.Spacing.x4) {
                Text("Calendar Access Denied")
                    .font(DS.Typography.bodyMedium)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                Text("Enable calendar access in Settings to see your meetings here.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.ColorToken.textSecondary)
            }
            Spacer()
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(DS.Typography.caption)
            .foregroundStyle(DS.ColorToken.primary)
        }
        .dsCardStyle()
    }

    private func calendarEventCard(_ event: EKEvent) -> some View {
        HStack(spacing: DS.Spacing.x12) {
            VStack(spacing: DS.Spacing.x4) {
                Text(timeString(event.startDate))
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.ColorToken.primary)
                Rectangle()
                    .fill(DS.ColorToken.primary)
                    .frame(width: 2)
                Text(timeString(event.endDate))
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.ColorToken.textSecondary)
            }
            .frame(width: 48)

            VStack(alignment: .leading, spacing: DS.Spacing.x4) {
                Text(event.title ?? "Untitled")
                    .font(DS.Typography.bodyMedium)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    .lineLimit(1)
                if let calendar = event.calendar {
                    Text(calendar.title)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                }
                if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "location")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                openLiveMeeting()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.primary)
                    .frame(width: 36, height: 36)
                    .background(DS.ColorToken.primarySoft)
                    .clipShape(Circle())
            }
        }
        .dsCardStyle()
    }

    private func timeString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}

// MARK: - Calendar Service

@MainActor
final class CalendarService: ObservableObject {
    @Published var events: [EKEvent] = []
    @Published var authorizationStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    private let store = EKEventStore()

    func requestAccess() async {
        do {
            if #available(iOS 17.0, *) {
                try await store.requestFullAccessToEvents()
            } else {
                try await store.requestAccess(to: .event)
            }
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            await fetchEvents()
        } catch {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        }
    }

    func fetchEvents() async {
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
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
