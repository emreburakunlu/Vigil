import SwiftUI

/// Onboarding gate → main tabs, plus the "Health access off" state, deep links and appearance.
struct RootView: View {
    @Environment(AppContainer.self) private var container
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var accessState: HealthAccessState?

    var body: some View {
        Group {
            if !settingsStore.settings.onboarding.completed {
                OnboardingFlowView()
            } else if accessState == .likelyDenied {
                HealthAccessDeniedView(onRetry: { Task { await checkAccess() } })
            } else {
                MainTabView()
            }
        }
        .vigilAppearance(settingsStore.settings.appearance)
        .onOpenURL { url in
            if let link = DeepLink(url: url) { router.open(link) }
        }
        .task(id: settingsStore.settings.onboarding.completed) { await checkAccess() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await checkAccess() } }
        }
    }

    private func checkAccess() async {
        guard settingsStore.settings.onboarding.completed else { return }
        accessState = await container.repository.healthAccessState()
    }
}

#Preview("Onboarded") {
    RootView().vigilPreview()
}

#Preview("Onboarding") {
    RootView().vigilPreview(onboarded: false)
}

#Preview("Access denied") {
    RootView().vigilPreview(.healthAccessDenied)
}
