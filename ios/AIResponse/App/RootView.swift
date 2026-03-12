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
            } else {
                switch appViewModel.authState {
                case .loading:
                    // Session is being restored/validated — hold here to prevent UI flashing
                    ZStack {
                        DS.ColorToken.canvas.ignoresSafeArea()
                        ProgressView()
                            .tint(DS.ColorToken.primary)
                            .scaleEffect(1.2)
                    }
                    .transition(.opacity)

                case .authenticated(let session):
                    MainTabView(session: session, dependencies: dependencies)
                        .transition(.opacity)

                case .unauthenticated:
                    LoginView()
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appViewModel.authState)
    }
}
