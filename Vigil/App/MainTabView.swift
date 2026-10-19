import SwiftUI

/// The five root tabs, each with its own NavigationStack bound to `AppRouter`.
/// The design shows a custom floating tab bar; the design-system agent may restyle this.
struct MainTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    NavigationStack(path: router.path(for: tab)) {
                        root(for: tab).withAppRoutes()
                    }
                }
            }
        }
        .tint(.vAccent)
    }

    @ViewBuilder
    private func root(for tab: AppTab) -> some View {
        switch tab {
        case .today: TodayView()
        case .sleep: SleepView()
        case .train: TrainView()
        case .progress: ProgressTabView()
        case .profile: ProfileView()
        }
    }
}

#Preview {
    MainTabView().vigilPreview()
}
