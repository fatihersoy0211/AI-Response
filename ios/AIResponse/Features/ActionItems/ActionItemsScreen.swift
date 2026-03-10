import SwiftUI

struct ActionItemsScreen: View {
    var compact = false

    @State private var highDone = false
    @State private var mediumDone = false
    @State private var lowDone = false

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

                DSActionItemCard(
                    title: "Finalize enterprise rollout brief",
                    owner: "Elif",
                    dueDate: "Tomorrow",
                    priority: "High",
                    done: $highDone
                )

                DSActionItemCard(
                    title: "Schedule legal review with procurement",
                    owner: "Burak",
                    dueDate: "Fri",
                    priority: "Medium",
                    done: $mediumDone
                )

                DSActionItemCard(
                    title: "Share follow-up summary with leadership",
                    owner: "Mina",
                    dueDate: "Next Mon",
                    priority: "Low",
                    done: $lowDone
                )
            }
            .padding(DS.Spacing.x16)
        }
        .background(DS.ColorToken.canvas)
        .navigationTitle(compact ? "" : "Action Items")
    }
}
