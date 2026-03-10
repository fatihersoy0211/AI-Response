import SwiftUI

struct NotificationsScreen: View {
    var body: some View {
        List {
            notificationRow("AI summary ready", detail: "Q2 Product Strategy", time: "2m ago")
            notificationRow("Meeting starts in 15 min", detail: "Partner Sync", time: "12m ago")
            notificationRow("Action item reminder", detail: "Budget assumptions due today", time: "1h ago")
            notificationRow("Shared update", detail: "Transcript comments added", time: "3h ago")
        }
        .scrollContentBackground(.hidden)
        .background(DS.ColorToken.canvas)
        .navigationTitle("Updates")
    }

    private func notificationRow(_ title: String, detail: String, time: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x4) {
            Text(title)
                .font(DS.Typography.bodyMedium)
                .foregroundStyle(DS.ColorToken.textPrimary)
            Text(detail)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.ColorToken.textSecondary)
            Text(time)
                .font(DS.Typography.micro)
                .foregroundStyle(DS.ColorToken.textTertiary)
        }
        .padding(.vertical, DS.Spacing.x8)
        .listRowBackground(DS.ColorToken.surface)
    }
}
