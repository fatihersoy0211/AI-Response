import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    let dependencies: AppDependencies

    var body: some View {
        Group {
            if !hasCompletedOnboarding && !dependencies.launchConfiguration.skipOnboarding {
                OnboardingView {
                    hasCompletedOnboarding = true
                }
            } else if let session = appViewModel.session {
                MainTabView(session: session, dependencies: dependencies)
            } else {
                LoginView()
            }
        }
    }
}
