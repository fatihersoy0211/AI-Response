import SwiftUI

struct AISummaryScreen: View {
    @State private var followup = ""
    @State private var expandedRisks = true

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x12) {
            block("Executive Summary", text: "Team aligned on timeline risk and approved phased rollout for enterprise customers.")
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
                DSButton(title: "Regenerate", kind: .secondary) {}
                DSButton(title: "Style: Executive", kind: .secondary) {}
            }
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
