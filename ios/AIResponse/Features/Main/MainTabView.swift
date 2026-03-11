import SwiftUI

struct MainTabView: View {
    let session: UserSession

    @State private var selectedTab: MainTab = .home
    @State private var showLiveMeeting = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeDashboardView(session: session, openLiveMeeting: { showLiveMeeting = true })
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
                ActionItemsScreen()
            }
            .tabItem {
                Label("Action Items", systemImage: "checkmark.circle")
            }
            .tag(MainTab.actions)

            NavigationStack {
                GlobalSearchScreen()
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }
            .tag(MainTab.search)

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
                LiveMeetingView(session: session, autoStartListening: true)
            }
        }
    }
}

enum MainTab {
    case home
    case meetings
    case actions
    case search
    case settings
}
