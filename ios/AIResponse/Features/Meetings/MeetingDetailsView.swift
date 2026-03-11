import UIKit
import SwiftUI

struct MeetingDetailsView: View {
    let meeting: MeetingDigest

    @State private var selectedTab: DetailTab = .summary
    @State private var searchText = ""
    @State private var isPlaying = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.x16) {
                VStack(alignment: .leading, spacing: DS.Spacing.x8) {
                    Text(meeting.title)
                        .font(DS.Typography.title2)
                    Text("Today · \(meeting.time) · \(meeting.duration) · \(meeting.participants) participants")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                }
                .dsCardStyle()

                DSAudioPlayerControls(isPlaying: $isPlaying)

                Picker("Detail", selection: $selectedTab) {
                    ForEach(DetailTab.allCases, id: \.self) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                switch selectedTab {
                case .transcript:
                    TranscriptScreen()
                case .summary:
                    DSEmptyState(icon: "sparkles", title: "AI Summary", message: "Open AI Summary from the Dashboard to generate a project-aware summary.")
                case .actions:
                    ActionItemsScreen(compact: true)
                case .decisions:
                    decisionCards
                case .notes:
                    notesCards
                }

                HStack {
                    DSButton(title: "Share", icon: "square.and.arrow.up", kind: .secondary) {
                        let text = "\(meeting.title)\n\(meeting.time) · \(meeting.duration) · \(meeting.participants) participants"
                        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
                        UIApplication.shared.connectedScenes
                            .compactMap { $0 as? UIWindowScene }
                            .flatMap { $0.windows }
                            .first(where: { $0.isKeyWindow })?
                            .rootViewController?.present(av, animated: true)
                    }
                    DSButton(title: "Export", icon: "tray.and.arrow.down", kind: .secondary) {
                        let summary = "Meeting: \(meeting.title)\nTime: \(meeting.time) · \(meeting.duration)\nParticipants: \(meeting.participants)"
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(meeting.title).txt")
                        try? summary.write(to: url, atomically: true, encoding: .utf8)
                        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                        UIApplication.shared.connectedScenes
                            .compactMap { $0 as? UIWindowScene }
                            .flatMap { $0.windows }
                            .first(where: { $0.isKeyWindow })?
                            .rootViewController?.present(av, animated: true)
                    }
                }
            }
            .padding(DS.Spacing.x16)
        }
        .background(DS.ColorToken.canvas)
        .navigationTitle("Meeting Details")
    }

    private var decisionCards: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x12) {
            DSSectionHeader(title: "Decisions")
            decisionCard("Launch candidate date moved to May 18.")
            decisionCard("Pricing experiments limited to enterprise segment.")
        }
    }

    private func decisionCard(_ text: String) -> some View {
        Text(text)
            .font(DS.Typography.body)
            .foregroundStyle(DS.ColorToken.textPrimary)
            .dsCardStyle()
    }

    private var notesCards: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x12) {
            DSSectionHeader(title: "Notes")
            Text("- Validate legal clause updates before Friday.\n- Product to send timeline revision.")
                .font(DS.Typography.body)
                .foregroundStyle(DS.ColorToken.textPrimary)
                .dsCardStyle()
        }
    }
}

enum DetailTab: CaseIterable {
    case transcript
    case summary
    case actions
    case decisions
    case notes

    var title: String {
        switch self {
        case .transcript: return "Transcript"
        case .summary: return "AI Summary"
        case .actions: return "Actions"
        case .decisions: return "Decisions"
        case .notes: return "Notes"
        }
    }
}
