import SwiftUI

/// Maps an `AppRoute` to its screen. The initializers used here are the CONTRACT between the
/// orchestrator and screen agents: keep them stable (`RecoveryDetailView(day:)`, …).
struct RouteDestinationView: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .recovery(let day): RecoveryDetailView(day: day)
        case .strain(let day): StrainDetailView(day: day)
        case .metric(let metric, let day): MetricDetailView(metric: metric, day: day)
        case .sleepCalendar(let month): SleepCalendarView(month: month)
        case .sleepNight(let day): SleepNightView(day: day)
        case .runDetail(let id): RunDetailView(workoutID: id)
        case .liftDetail(let id): LiftDetailView(workoutID: id)
        #if DEBUG
        case .stateGallery: StateGalleryView()
        #endif
        }
    }
}

extension View {
    /// Registers `AppRoute` destinations. Apply once to the root view of each tab's NavigationStack.
    func withAppRoutes() -> some View {
        navigationDestination(for: AppRoute.self) { RouteDestinationView(route: $0) }
    }
}
