import SwiftUI

struct GlobalSearchScreen: View {
    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.x16) {
                DSSearchBar(text: $query, placeholder: "Search meetings, transcript, notes, actions")

                if query.isEmpty {
                    DSEmptyState(
                        icon: "doc.text.magnifyingglass",
                        title: "Search your meetings",
                        message: "Type to search across transcripts, action items, and notes."
                    )
                } else {
                    DSEmptyState(
                        icon: "doc.text.magnifyingglass",
                        title: "No results found",
                        message: "Try different keywords or check your spelling."
                    )
                }
            }
            .padding(DS.Spacing.x16)
        }
        .background(DS.ColorToken.canvas)
        .navigationTitle("Search")
    }
}
