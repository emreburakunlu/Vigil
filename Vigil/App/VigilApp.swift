import SwiftUI

@main
struct VigilApp: App {
    @State private var container: AppContainer

    init() {
        let container = AppContainer.forCurrentLaunch()
        _container = State(initialValue: container)
        // Must be installed before launch finishes so a tap on a notification is delivered.
        NotificationDelegate.install { [router = container.router] url in
            if let link = DeepLink(url: url) { router.open(link) }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .vigilEnvironment(container)
                .task(id: container.settings.settings.onboarding.completed) { await container.start() }
        }
    }
}

extension View {
    /// Injects the container and its commonly used parts into the environment.
    func vigilEnvironment(_ container: AppContainer) -> some View {
        environment(container)
            .environment(container.settings)
            .environment(container.router)
            .modelContainer(container.modelContainer)
    }
}
