import SwiftUI

struct AISummaryScreen: View {
    @State private var followup = ""
    @State private var expandedRisks = true
    @State private var showStylePicker = false
    @State private var selectedStyle = "Executive"
    @State private var isRegenerating = false
    @State private var regenerateCount = 0

    private let styles = ["Executive", "Technical", "Casual", "Bullet Points"]

    private var currentSummary: String {
        switch (selectedStyle, regenerateCount % 2) {
        case ("Executive", _):
            return regenerateCount == 0
                ? "Team aligned on timeline risk and approved phased rollout for enterprise customers."
                : "Leadership consensus reached on phased enterprise deployment. Timeline risk acknowledged and mitigation plan approved."
        case ("Technical", _):
            return regenerateCount == 0
                ? "Analytics pipeline capacity identified as critical bottleneck. Migration dependency creates 1-week pilot delay risk."
                : "System capacity constraints in the data pipeline require prioritized sprint allocation before pilot launch."
        case ("Casual", _):
            return "We all agreed there's a risk with the timeline but decided to go ahead with the rollout in phases. The team's on board."
        case ("Bullet Points", _):
            return "• Phased rollout approved\n• Timeline risk acknowledged\n• CS enablement plan defined\n• Pricing narrative finalized"
        default:
            return "Team aligned on timeline risk and approved phased rollout for enterprise customers."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x12) {
            block("Executive Summary", text: currentSummary)
            block("Key Discussion Points", text: "1. Capacity limits in analytics pipeline\n2. CS enablement plan\n3. Pricing narrative for renewals")

            VStack(alignment: .leading, spacing: DS.Spacing.x8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedRisks.toggle()
                    }
                } label: {
                    HStack {
                        Text("Risks / Blockers")
                            .font(DS.Typography.heading)
                        Spacer()
                        Image(systemName: expandedRisks ? "chevron.up" : "chevron.down")
                    }
                    .foregroundStyle(DS.ColorToken.textPrimary)
                }
                if expandedRisks {
                    Text("Data migration dependency may delay the pilot by 1 week.")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                }
            }
            .dsCardStyle()

            block("Action Items", text: "- Elif: Share revised roadmap by Thu\n- Burak: Validate budget assumptions by Fri")
            block("Follow-up Suggestions", text: "Ask AI to draft a stakeholder update email and a one-page execution memo.")

            DSAIAssistantInputBar(text: $followup) {
                followup = ""
            }

            HStack {
                DSButton(title: isRegenerating ? "Regenerating…" : "Regenerate", kind: .secondary, isLoading: isRegenerating) {
                    guard !isRegenerating else { return }
                    isRegenerating = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        isRegenerating = false
                        regenerateCount += 1
                    }
                }
                DSButton(title: "Style: \(selectedStyle)", kind: .secondary) {
                    showStylePicker = true
                }
            }
        }
        .confirmationDialog("Summary Style", isPresented: $showStylePicker, titleVisibility: .visible) {
            ForEach(styles, id: \.self) { style in
                Button(style) {
                    selectedStyle = style
                    regenerateCount = 0
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func block(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x8) {
            Text(title)
                .font(DS.Typography.heading)
                .foregroundStyle(DS.ColorToken.textPrimary)
            Text(text)
                .font(DS.Typography.body)
                .foregroundStyle(DS.ColorToken.textSecondary)
        }
        .dsCardStyle()
    }
}
