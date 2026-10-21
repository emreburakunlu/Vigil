import SwiftUI
import UIKit

@main
struct VigilApp: App {
    @UIApplicationDelegateAdaptor(VigilAppDelegate.self) private var appDelegate
    @State private var container: AppContainer

    init() {
        let container = AppContainer.shared
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

/// Starts process-lifetime work at launch, including background launches without a scene: HealthKit
/// observer queries (background delivery) and clock/time-zone observers.
final class VigilAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let container = AppContainer.shared
        container.installLifecycleObservers()
        container.startHealthObservation()
        return true
    }
}

extension View {
    /// Injects the container and its commonly used parts into the environment.
    func vigilEnvironment(_ container: AppContainer) -> some View {
        environment(container)
            .environment(container.settings)
            .environment(container.liftLog)
            .environment(container.router)
            .modelContainer(container.modelContainer)
    }
}
