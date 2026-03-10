import SwiftUI

struct GlobalSearchScreen: View {
    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.x16) {
                DSSearchBar(text: $query, placeholder: "Search meetings, transcript, notes, actions")

                DSSectionHeader(title: "Recent Searches")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.x8) {
                        DSBadge(text: "Q2 roadmap")
                        DSBadge(text: "budget assumptions")
                        DSBadge(text: "renewal risks")
                    }
                }

                DSSectionHeader(title: "Results · Meetings")
                DSMeetingCard(title: "Q2 Product Strategy", time: "Today 09:30", source: "Zoom", participants: 6)

                DSSectionHeader(title: "Results · Transcript")
                Text("\"Capacity risk may shift pilot by one week.\"")
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    .dsCardStyle()

                DSSectionHeader(title: "Results · Action Items")
                DSEmptyState(
                    icon: "doc.text.magnifyingglass",
                    title: "No Matching Actions",
                    message: "Try broader keywords or clear filters."
                )
            }
            .padding(DS.Spacing.x16)
        }
        .background(DS.ColorToken.canvas)
        .navigationTitle("Search")
    }
}
