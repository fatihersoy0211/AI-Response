import SwiftUI

struct SettingsRootView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var showLogoutConfirm = false

    private var session: UserSession? { appViewModel.session }

    var body: some View {
        List {
            // ── Tappable profile card ─────────────────────────────────
            Section {
                NavigationLink(destination: ProfileScreen()) {
                    HStack(spacing: DS.Spacing.x16) {
                        ZStack {
                            Circle()
                                .fill(DS.ColorToken.primary.opacity(0.18))
                                .frame(width: 54, height: 54)
                            Text(initials)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(DS.ColorToken.primary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session?.name ?? "—")
                                .font(DS.Typography.heading)
                                .foregroundStyle(DS.ColorToken.textPrimary)
                            Text(session?.email ?? "—")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.ColorToken.textSecondary)
                            Text("View & edit profile →")
                                .font(DS.Typography.micro)
                                .foregroundStyle(DS.ColorToken.primary)
                        }
                    }
                    .padding(.vertical, DS.Spacing.x8)
                }
            }
            .listRowBackground(DS.ColorToken.surface)

            Section("Workspace") {
                NavigationLink("Integrations") { IntegrationsScreen() }
                NavigationLink("Subscription & Billing") { SubscriptionScreen() }
                NavigationLink("Notification Preferences") { NotificationsScreen() }
            }

            Section("Preferences") {
                NavigationLink("Recording Preferences") { RecordingPreferencesScreen() }
                NavigationLink("AI Summary Style") { AISummaryStyleScreen() }
                NavigationLink("Language") { LanguageScreen() }
                NavigationLink("Privacy & Security") { PrivacySecurityScreen() }
            }

            Section("System States") {
                NavigationLink("Empty & Error States") { StateGalleryScreen() }
            }

            // ── Sign Out ──────────────────────────────────────────────
            Section {
                Button(role: .destructive) {
                    showLogoutConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign Out")
                    }
                }
            } footer: {
                Text("You are signed in as \(session?.email ?? "—")")
                    .font(DS.Typography.micro)
            }
        }
        .scrollContentBackground(.hidden)
        .background(DS.ColorToken.canvas)
        .navigationTitle("Settings")
        .confirmationDialog("Sign out?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { appViewModel.logout() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will be signed out and need to log in again.")
        }
    }

    private var initials: String {
        guard let name = session?.name, !name.isEmpty else { return "?" }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - Profile Screen

struct ProfileScreen: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @AppStorage("user.phone") private var phone: String = ""
    @AppStorage("user.bio") private var bio: String = ""
    @AppStorage("user.company") private var company: String = ""
    @State private var editPhone: String = ""
    @State private var editBio: String = ""
    @State private var editCompany: String = ""
    @State private var showLogoutConfirm = false
    @State private var saved = false

    private var session: UserSession? { appViewModel.session }

    var body: some View {
        List {
            // ── Avatar ────────────────────────────────────────────────
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: DS.Spacing.x8) {
                        ZStack {
                            Circle()
                                .fill(DS.ColorToken.primary.opacity(0.18))
                                .frame(width: 80, height: 80)
                            Text(initials)
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(DS.ColorToken.primary)
                        }
                        Text(session?.name ?? "—")
                            .font(DS.Typography.heading)
                        DSBadge(text: "Free Plan", tone: DS.ColorToken.primary)
                    }
                    Spacer()
                }
                .padding(.vertical, DS.Spacing.x12)
            }
            .listRowBackground(DS.ColorToken.surface)

            // ── Account Info (read-only) ───────────────────────────────
            Section("Account") {
                LabeledContent("Name", value: session?.name ?? "—")
                LabeledContent("Email", value: session?.email ?? "—")
                LabeledContent("Member since") {
                    Text("2026")
                        .foregroundStyle(DS.ColorToken.textSecondary)
                }
            }
            .listRowBackground(DS.ColorToken.surface)

            // ── Editable personal info ────────────────────────────────
            Section("Personal Information") {
                HStack {
                    Label("Phone", systemImage: "phone")
                        .frame(width: 120, alignment: .leading)
                    TextField("+90 555 000 00 00", text: $editPhone)
                        .keyboardType(.phonePad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Label("Company", systemImage: "building.2")
                        .frame(width: 120, alignment: .leading)
                    TextField("Your company", text: $editCompany)
                        .multilineTextAlignment(.trailing)
                }
            }
            .listRowBackground(DS.ColorToken.surface)

            Section("Bio") {
                TextEditor(text: $editBio)
                    .frame(minHeight: 80)
            }
            .listRowBackground(DS.ColorToken.surface)

            // ── Save button ────────────────────────────────────────────
            Section {
                Button {
                    phone = editPhone
                    bio = editBio
                    company = editCompany
                    withAnimation { saved = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { saved = false }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if saved {
                            Label("Saved", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(DS.ColorToken.success)
                        } else {
                            Text("Save Changes")
                                .font(DS.Typography.bodyMedium)
                                .foregroundStyle(DS.ColorToken.primary)
                        }
                        Spacer()
                    }
                }
            }
            .listRowBackground(DS.ColorToken.surface)

            // ── Membership ────────────────────────────────────────────
            Section("Membership") {
                HStack {
                    VStack(alignment: .leading, spacing: DS.Spacing.x4) {
                        Text("Free Plan")
                            .font(DS.Typography.bodyMedium)
                        Text("5 meetings/month · Basic transcription")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.ColorToken.textSecondary)
                    }
                    Spacer()
                    DSBadge(text: "Active", tone: DS.ColorToken.success)
                }
                NavigationLink("Upgrade to Pro") { SubscriptionScreen() }
            }
            .listRowBackground(DS.ColorToken.surface)

            // ── Sign Out ──────────────────────────────────────────────
            Section {
                Button(role: .destructive) {
                    showLogoutConfirm = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        Spacer()
                    }
                }
            }
            .listRowBackground(DS.ColorToken.surface)
        }
        .scrollContentBackground(.hidden)
        .background(DS.ColorToken.canvas)
        .navigationTitle("My Profile")
        .onAppear {
            editPhone = phone
            editBio = bio
            editCompany = company
        }
        .confirmationDialog("Sign out?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { appViewModel.logout() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will be signed out and need to log in again.")
        }
    }

    private var initials: String {
        guard let name = session?.name, !name.isEmpty else { return "?" }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - Integrations

struct IntegrationsScreen: View {
    @State private var connections: [String: Bool] = [
        "Zoom": false,
        "Google Meet": false,
        "Microsoft Teams": false,
        "Google Calendar": false,
        "Slack": false,
        "Notion": false,
        "CRM": false
    ]
    private let order = ["Zoom", "Google Meet", "Microsoft Teams", "Google Calendar", "Slack", "Notion", "CRM"]

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.x12) {
                ForEach(order, id: \.self) { name in
                    let connected = connections[name] ?? false
                    integrationCard(name, connected: connected) {
                        connections[name] = !connected
                    }
                }
            }
            .padding(DS.Spacing.x16)
        }
        .background(DS.ColorToken.canvas)
        .navigationTitle("Integrations")
    }

    private func integrationCard(_ name: String, connected: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: DS.Spacing.x4) {
                Text(name)
                    .font(DS.Typography.bodyMedium)
                Text(connected ? "Connected" : "Not connected")
                    .font(DS.Typography.caption)
                    .foregroundStyle(connected ? DS.ColorToken.success : DS.ColorToken.textSecondary)
            }
            Spacer()
            DSButton(title: connected ? "Manage" : "Connect", kind: connected ? .tertiary : .secondary, action: action)
                .frame(width: 120)
        }
        .dsCardStyle()
    }
}

// MARK: - Subscription

struct SubscriptionScreen: View {
    @State private var selectedPlan = "Free"
    @State private var showUpgradeAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.x12) {
                planCard(title: "Free", price: "$0", features: "5 meetings/month\nBasic transcript")
                planCard(title: "Pro", price: "$24", features: "Unlimited meetings\nAI executive summary\nAction extraction", highlighted: true)
                planCard(title: "Team", price: "$79", features: "Workspace collaboration\nAdmin controls\nAdvanced integrations")

                DSButton(title: "Upgrade to Pro", kind: .primary) {
                    showUpgradeAlert = true
                }
                DSButton(title: "Restore Purchase", kind: .tertiary) {
                    showUpgradeAlert = true
                }
            }
            .padding(DS.Spacing.x16)
        }
        .background(DS.ColorToken.canvas)
        .navigationTitle("Subscription")
        .alert("Subscription", isPresented: $showUpgradeAlert) {
            Button("OK") {}
        } message: {
            Text("This would connect to the App Store in production.")
        }
    }

    private func planCard(title: String, price: String, features: String, highlighted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x8) {
            HStack {
                Text(title)
                    .font(DS.Typography.heading)
                Spacer()
                Text(price)
                    .font(DS.Typography.title2)
                if title == selectedPlan {
                    DSBadge(text: "Current", tone: DS.ColorToken.success)
                }
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

// MARK: - Recording Preferences

struct RecordingPreferencesScreen: View {
    @AppStorage("recording.autoStart") private var autoStart = false
    @AppStorage("recording.background") private var backgroundRecording = true
    @AppStorage("recording.noiseCancellation") private var noiseCancellation = true
    @AppStorage("recording.quality") private var quality = "High"

    private let qualities = ["Standard", "High", "Lossless"]

    var body: some View {
        List {
            Section("Automation") {
                Toggle("Auto-start when meeting begins", isOn: $autoStart)
                Toggle("Allow background recording", isOn: $backgroundRecording)
            }
            .listRowBackground(DS.ColorToken.surface)

            Section("Audio") {
                Toggle("Noise cancellation", isOn: $noiseCancellation)
                Picker("Quality", selection: $quality) {
                    ForEach(qualities, id: \.self) { q in
                        Text(q).tag(q)
                    }
                }
            }
            .listRowBackground(DS.ColorToken.surface)

            Section("Storage") {
                HStack {
                    Text("Auto-delete recordings after")
                    Spacer()
                    Text("30 days")
                        .foregroundStyle(DS.ColorToken.textSecondary)
                }
                HStack {
                    Text("Local storage used")
                    Spacer()
                    Text("—")
                        .foregroundStyle(DS.ColorToken.textSecondary)
                }
            }
            .listRowBackground(DS.ColorToken.surface)
        }
        .scrollContentBackground(.hidden)
        .background(DS.ColorToken.canvas)
        .navigationTitle("Recording Preferences")
    }
}

// MARK: - AI Summary Style

struct AISummaryStyleScreen: View {
    @AppStorage("summary.style") private var summaryStyle = "Executive"
    @AppStorage("summary.includeActions") private var includeActions = true
    @AppStorage("summary.includeRisks") private var includeRisks = true
    @AppStorage("summary.length") private var summaryLength = "Medium"

    private let styles = ["Executive", "Technical", "Casual", "Bullet Points"]
    private let lengths = ["Short", "Medium", "Detailed"]

    var body: some View {
        List {
            Section("Style") {
                Picker("Summary Style", selection: $summaryStyle) {
                    ForEach(styles, id: \.self) { s in
                        Text(s).tag(s)
                    }
                }
                .pickerStyle(.inline)
            }
            .listRowBackground(DS.ColorToken.surface)

            Section("Content") {
                Toggle("Include action items", isOn: $includeActions)
                Toggle("Include risks & blockers", isOn: $includeRisks)
                Picker("Summary length", selection: $summaryLength) {
                    ForEach(lengths, id: \.self) { l in
                        Text(l).tag(l)
                    }
                }
            }
            .listRowBackground(DS.ColorToken.surface)

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: DS.Spacing.x4) {
                        Text("Preview Style")
                            .font(DS.Typography.bodyMedium)
                        Text("Current: \(summaryStyle) · \(summaryLength)")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.ColorToken.textSecondary)
                    }
                    Spacer()
                    DSBadge(text: summaryStyle, tone: DS.ColorToken.primary)
                }
            }
            .listRowBackground(DS.ColorToken.surface)
        }
        .scrollContentBackground(.hidden)
        .background(DS.ColorToken.canvas)
        .navigationTitle("AI Summary Style")
    }
}

// MARK: - Language

struct LanguageScreen: View {
    @AppStorage("app.language") private var selectedLanguage = "Turkish"

    private let languages = [
        ("Turkish", "tr"),
        ("English", "en"),
        ("German", "de"),
        ("French", "fr"),
        ("Spanish", "es"),
        ("Italian", "it"),
        ("Portuguese", "pt"),
        ("Japanese", "ja"),
        ("Korean", "ko"),
        ("Chinese", "zh")
    ]

    var body: some View {
        List {
            Section("Transcription Language") {
                ForEach(languages, id: \.0) { language, code in
                    Button {
                        selectedLanguage = language
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: DS.Spacing.x4) {
                                Text(language)
                                    .font(DS.Typography.bodyMedium)
                                    .foregroundStyle(DS.ColorToken.textPrimary)
                                Text(code.uppercased())
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.ColorToken.textSecondary)
                            }
                            Spacer()
                            if selectedLanguage == language {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(DS.ColorToken.primary)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
            }
            .listRowBackground(DS.ColorToken.surface)
        }
        .scrollContentBackground(.hidden)
        .background(DS.ColorToken.canvas)
        .navigationTitle("Language")
    }
}

// MARK: - Privacy & Security

struct PrivacySecurityScreen: View {
    @AppStorage("privacy.e2e") private var e2eEncryption = true
    @AppStorage("privacy.localOnly") private var localStorageOnly = false
    @AppStorage("privacy.analytics") private var allowAnalytics = true
    @State private var showDeleteAlert = false

    var body: some View {
        List {
            Section("Security") {
                Toggle("End-to-end encryption", isOn: $e2eEncryption)
                Toggle("Store transcripts locally only", isOn: $localStorageOnly)
                HStack {
                    Text("Session")
                    Spacer()
                    DSBadge(text: "Secure", tone: DS.ColorToken.success)
                }
            }
            .listRowBackground(DS.ColorToken.surface)

            Section("Analytics") {
                Toggle("Allow anonymous usage analytics", isOn: $allowAnalytics)
                HStack {
                    Text("Data retention")
                    Spacer()
                    Text("90 days")
                        .foregroundStyle(DS.ColorToken.textSecondary)
                }
            }
            .listRowBackground(DS.ColorToken.surface)

            Section("Data Management") {
                NavigationLink("Export My Data") {
                    DataExportScreen()
                }
                Button("Delete All Data", role: .destructive) {
                    showDeleteAlert = true
                }
            }
            .listRowBackground(DS.ColorToken.surface)
        }
        .scrollContentBackground(.hidden)
        .background(DS.ColorToken.canvas)
        .navigationTitle("Privacy & Security")
        .alert("Delete All Data", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {}
        } message: {
            Text("This will permanently delete all your meetings, transcripts, and summaries. This action cannot be undone.")
        }
    }
}

// MARK: - Data Export

struct DataExportScreen: View {
    @State private var isExporting = false
    @State private var exported = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.x16) {
                DSAIInsightCard(
                    title: "Export Your Data",
                    message: "Download all your meetings, transcripts, summaries, and action items as a ZIP archive."
                )

                DSEmptyState(
                    icon: "tray.and.arrow.down",
                    title: "No data to export yet",
                    message: "Complete a few meetings to generate exportable data."
                )

                DSButton(
                    title: exported ? "Download ZIP" : "Generate Export",
                    icon: exported ? "tray.and.arrow.down" : "arrow.up.doc",
                    kind: .primary,
                    isLoading: isExporting
                ) {
                    if !exported {
                        isExporting = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            isExporting = false
                            exported = true
                        }
                    }
                }
            }
            .padding(DS.Spacing.x16)
        }
        .background(DS.ColorToken.canvas)
        .navigationTitle("Export Data")
    }
}

// MARK: - State Gallery

struct StateGalleryScreen: View {
    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.x12) {
                DSEmptyState(icon: "calendar.badge.exclamationmark", title: "No meetings yet", message: "Connect your calendar or create a manual meeting.", buttonTitle: "Connect Calendar") {}
                DSEmptyState(icon: "text.quote", title: "No transcript available", message: "Start a recording to generate transcript.")
                DSEmptyState(icon: "magnifyingglass", title: "No search results", message: "Try broader keywords.")
                DSEmptyState(icon: "mic.slash", title: "Microphone permission denied", message: "Enable microphone in Settings.", buttonTitle: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                DSEmptyState(icon: "icloud.slash", title: "Network issue", message: "Please check your connection and try again.", buttonTitle: "Retry") {}
                DSEmptyState(icon: "exclamationmark.triangle", title: "Upload failed", message: "PDF/DOCX upload failed. Try again.")
            }
            .padding(DS.Spacing.x16)
        }
        .background(DS.ColorToken.canvas)
        .navigationTitle("States")
    }
}
