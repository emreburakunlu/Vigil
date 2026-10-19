import SwiftUI

@main
struct VigilApp: App {
    @State private var container = AppContainer.forCurrentLaunch()

    var body: some Scene {
        WindowGroup {
            RootView()
                .vigilEnvironment(container)
                .task { await container.start() }
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
