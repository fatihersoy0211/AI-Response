import SwiftUI

struct SettingsRootView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DS.Spacing.x8) {
                    Text("AI-Meeting Assist Pro")
                        .font(DS.Typography.heading)
                    Text("Workspace: Executive Ops")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                    DSProgressPill(title: "AI Credits", value: 0.64)
                }
                .padding(.vertical, DS.Spacing.x8)
            }
            .listRowBackground(DS.ColorToken.surface)

            Section("Workspace") {
                NavigationLink("Integrations") { IntegrationsScreen() }
                NavigationLink("Subscription & Billing") { SubscriptionScreen() }
                NavigationLink("Notification Preferences") { NotificationsScreen() }
            }

            Section("Preferences") {
                NavigationLink("Recording Preferences") { Text("Recording Preferences") }
                NavigationLink("AI Summary Style") { Text("AI Summary Style") }
                NavigationLink("Language") { Text("Language") }
                NavigationLink("Privacy & Security") { Text("Privacy & Security") }
            }

            Section("System States") {
                NavigationLink("Empty & Error States") { StateGalleryScreen() }
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    appViewModel.logout()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(DS.ColorToken.canvas)
        .navigationTitle("Settings")
    }
}

struct IntegrationsScreen: View {
    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.x12) {
                integrationCard("Zoom", connected: true)
                integrationCard("Google Meet", connected: true)
                integrationCard("Microsoft Teams", connected: false)
                integrationCard("Google Calendar", connected: true)
                integrationCard("Slack", connected: false)
                integrationCard("Notion", connected: false)
                integrationCard("CRM", connected: false)
            }
            .padding(DS.Spacing.x16)
        }
        .background(DS.ColorToken.canvas)
        .navigationTitle("Integrations")
    }

    private func integrationCard(_ name: String, connected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: DS.Spacing.x4) {
                Text(name)
                    .font(DS.Typography.bodyMedium)
                Text(connected ? "Connected" : "Not connected")
                    .font(DS.Typography.caption)
                    .foregroundStyle(connected ? DS.ColorToken.success : DS.ColorToken.textSecondary)
            }
            Spacer()
            DSButton(title: connected ? "Manage" : "Connect", kind: .secondary) {}
                .frame(width: 120)
        }
        .dsCardStyle()
    }
}

struct SubscriptionScreen: View {
    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.x12) {
                planCard(title: "Free", price: "$0", features: "5 meetings/month\nBasic transcript")
                planCard(title: "Pro", price: "$24", features: "Unlimited meetings\nAI executive summary\nAction extraction", highlighted: true)
                planCard(title: "Team", price: "$79", features: "Workspace collaboration\nAdmin controls\nAdvanced integrations")

                DSButton(title: "Upgrade to Pro", kind: .primary) {}
                DSButton(title: "Restore Purchase", kind: .tertiary) {}
            }
            .padding(DS.Spacing.x16)
        }
        .background(DS.ColorToken.canvas)
        .navigationTitle("Subscription")
    }

    private func planCard(title: String, price: String, features: String, highlighted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x8) {
            HStack {
                Text(title)
                    .font(DS.Typography.heading)
                Spacer()
                Text(price)
                    .font(DS.Typography.title2)
            }
            Text(features)
                .font(DS.Typography.body)
                .foregroundStyle(DS.ColorToken.textSecondary)
        }
        .padding(DS.Spacing.x16)
        .background(highlighted ? DS.ColorToken.primarySoft : DS.ColorToken.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(highlighted ? DS.ColorToken.primary : DS.ColorToken.border, lineWidth: 1)
        )
    }
}

struct StateGalleryScreen: View {
    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.x12) {
                DSEmptyState(icon: "calendar.badge.exclamationmark", title: "No meetings yet", message: "Connect your calendar or create a manual meeting.", buttonTitle: "Connect Calendar") {}
                DSEmptyState(icon: "text.quote", title: "No transcript available", message: "Start a recording to generate transcript.")
                DSEmptyState(icon: "magnifyingglass", title: "No search results", message: "Try broader keywords.")
                DSEmptyState(icon: "mic.slash", title: "Microphone permission denied", message: "Enable microphone in Settings.", buttonTitle: "Open Settings") {}
                DSEmptyState(icon: "icloud.slash", title: "Network issue", message: "Please check your connection and try again.", buttonTitle: "Retry") {}
                DSEmptyState(icon: "exclamationmark.triangle", title: "Upload failed", message: "PDF/DOCX upload failed. Try again.")
            }
            .padding(DS.Spacing.x16)
        }
        .background(DS.ColorToken.canvas)
        .navigationTitle("States")
    }
}
