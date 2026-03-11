import SwiftUI

struct ActionItemsScreen: View {
    var compact = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.x12) {
                if !compact {
                    DSSectionHeader(title: "Filters")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Spacing.x8) {
                            DSBadge(text: "Pending", tone: DS.ColorToken.warning)
                            DSBadge(text: "In Progress", tone: DS.ColorToken.primary)
                            DSBadge(text: "Done", tone: DS.ColorToken.success)
                            DSBadge(text: "High Priority", tone: DS.ColorToken.error)
                        }
                    }
                }

                DSEmptyState(
                    icon: "checkmark.circle",
                    title: "No action items yet",
                    message: "Action items extracted from meetings will appear here."
                )
            }
            .padding(DS.Spacing.x16)
        }
        .background(DS.ColorToken.canvas)
        .navigationTitle(compact ? "" : "Action Items")
    }
}
