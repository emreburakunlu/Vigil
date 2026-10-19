import Foundation
import Observation
import SwiftUI

/// Root tabs, in design order.
enum AppTab: String, CaseIterable, Hashable, Sendable {
    case today
    case sleep
    case train
    case progress
    case profile

    var title: String {
        switch self {
        case .today: "Today"
        case .sleep: "Sleep"
        case .train: "Train"
        case .progress: "Progress"
        case .profile: "Profile"
        }
    }

    /// SF Symbol for the tab item (the design-system agent may swap for custom glyphs).
    var systemImage: String {
        switch self {
        case .today: "gauge.with.needle"
        case .sleep: "moon"
        case .train: "dumbbell"
        case .progress: "chart.line.uptrend.xyaxis"
        case .profile: "person.crop.circle"
        }
    }
}

/// Train tab switch.
enum TrainSegment: String, CaseIterable, Hashable, Sendable {
    case run
    case lift
}

/// Progress tab switch.
enum ProgressSegment: String, CaseIterable, Hashable, Sendable {
    case running
    case lifting
    case body
}

/// Every pushable detail screen. Pushed onto the current tab's `NavigationStack` with
/// `NavigationLink(value: AppRoute.…)` or `router.push(.…)`; resolved by `RouteDestinationView`.
enum AppRoute: Hashable, Sendable {
    case recovery(LocalDay)
    case strain(LocalDay)
    /// Shared Metric detail for any `HealthMetric`.
    case metric(HealthMetric, LocalDay)
    /// Month containing the day.
    case sleepCalendar(LocalDay)
    case sleepNight(LocalDay)
    case runDetail(UUID)
    case liftDetail(UUID)
    #if DEBUG
    /// Developer gallery of empty/error states.
    case stateGallery
    #endif
}

/// Navigation state: selected tab, one path per tab, and segment selections deep links can set.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .today
    var trainSegment: TrainSegment = .run
    var progressSegment: ProgressSegment = .running
    private(set) var paths: [AppTab: [AppRoute]] = [:]

    /// Binding for a tab's `NavigationStack(path:)`.
    func path(for tab: AppTab) -> Binding<[AppRoute]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }

    /// Pushes a route on `tab` (default: the selected tab) and selects that tab.
    func push(_ route: AppRoute, on tab: AppTab? = nil) {
        let target = tab ?? selectedTab
        selectedTab = target
        paths[target, default: []].append(route)
    }

    func popToRoot(_ tab: AppTab? = nil) {
        paths[tab ?? selectedTab] = []
    }

    /// Clears all navigation (after data reset).
    func reset() {
        paths = [:]
        selectedTab = .today
    }

    /// Opens a `vigil://` deep link: selects the tab and replaces its path.
    func open(_ link: DeepLink, today: LocalDay = .today()) {
        switch link {
        case .today: show(.today, [])
        case .recovery(let day): show(.today, [.recovery(day ?? today)])
        case .strain(let day): show(.today, [.strain(day ?? today)])
        case .sleep: show(.sleep, [])
        case .sleepNight(let day): show(.sleep, [.sleepNight(day)])
        case .train: show(.train, [])
        case .run(let id): trainSegment = .run; show(.train, [.runDetail(id)])
        case .lift(let id): trainSegment = .lift; show(.train, [.liftDetail(id)])
        case .progress: show(.progress, [])
        case .profile: show(.profile, [])
        }
    }

    private func show(_ tab: AppTab, _ path: [AppRoute]) {
        selectedTab = tab
        paths[tab] = path
    }
}
