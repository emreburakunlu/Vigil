import SwiftUI

/// The five root tabs, each with its own NavigationStack bound to `AppRouter`.
///
/// The system tab bar is hidden and replaced by `VTabBar` (floating pill, design-system agent). Native
/// `TabView` still hosts the pages so each tab keeps its state. The bar hides while a detail screen is
/// pushed (the design shows it on tab roots only). While the Sleep tab is selected the whole window is
/// forced to the dark colour scheme so system chrome matches the night palette.
struct MainTabView: View {
    @Environment(AppRouter.self) private var router

    /// Tabs visited so far; pages are created lazily and then kept alive so each tab keeps its state.
    @State private var visited: Set<AppTab> = [.today]

    var body: some View {
        @Bindable var router = router
        ZStack {
            ForEach(AppTab.allCases, id: \.self) { tab in
                if visited.contains(tab) || router.selectedTab == tab {
                    let isSelected = router.selectedTab == tab
                    NavigationStack(path: router.path(for: tab)) {
                        root(for: tab).withAppRoutes()
                    }
                    .opacity(isSelected ? 1 : 0)
                    .allowsHitTesting(isSelected)
                    .accessibilityHidden(!isSelected)
                    .zIndex(isSelected ? 1 : 0)
                }
            }
        }
        .onChange(of: router.selectedTab, initial: true) { _, tab in visited.insert(tab) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsTabBar {
                VTabBar(selection: $router.selectedTab)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(VMotion.ease(duration: 0.35), value: showsTabBar)
        .preferredColorScheme(router.selectedTab == .sleep ? .dark : nil)
        .tint(.vAccent)
    }

    /// Tab roots show the bar; pushed detail screens don't.
    private var showsTabBar: Bool {
        router.paths[router.selectedTab]?.isEmpty ?? true
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
