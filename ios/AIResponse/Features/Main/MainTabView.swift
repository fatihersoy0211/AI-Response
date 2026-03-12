import SwiftUI

struct MainTabView: View {
    let session: UserSession
    let dependencies: AppDependencies

    @State private var selectedTab: MainTab = .home
    @State private var showLiveMeeting = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeDashboardView(session: session, dependencies: dependencies, openLiveMeeting: { showLiveMeeting = true })
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }
            .tag(MainTab.home)

            NavigationStack {
                MeetingsCalendarView(session: session, openLiveMeeting: { showLiveMeeting = true })
            }
            .tabItem {
                Label("Meetings", systemImage: "calendar")
            }
            .tag(MainTab.meetings)

            NavigationStack {
                AIChatView(session: session, dependencies: dependencies)
            }
            .tabItem {
                Label("AI Chat", systemImage: "wand.and.sparkles")
            }
            .tag(MainTab.chat)

            NavigationStack {
                ProjectsTabView(session: session, dependencies: dependencies)
            }
            .tabItem {
                Label("Projects", systemImage: "folder.fill")
            }
            .tag(MainTab.projects)

            NavigationStack {
                SettingsRootView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(MainTab.settings)
        }
        .tint(DS.ColorToken.primary)
        .fullScreenCover(isPresented: $showLiveMeeting) {
            NavigationStack {
                LiveMeetingView(session: session, dependencies: dependencies, autoStartListening: true)
            }
        }
    }
}

enum MainTab {
    case home
    case meetings
    case chat
    case projects
    case settings
}
