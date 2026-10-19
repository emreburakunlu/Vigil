import Foundation
import Observation

/// Paginated history of one workout kind (newest first).
struct TrainHistory: Sendable {
    var items: [WorkoutSummary] = []
    var groups: [TrainMonthGroup] = []
    /// Start of the oldest interval fetched so far.
    var oldestFetched: Date?
    var hasMore = true
    var isLoadingMore = false
}

enum TrainLoadState: Equatable, Sendable {
    case loading
    case loaded
    case failed
}

/// Screen model for the Train tab (Run and Lift segments share the weekly header and paging logic).
@MainActor
@Observable
final class TrainModel {
    /// Weeks fetched by the first load and by every "older" page.
    static let pageWeeks = 8
    /// Hard stop for scrolling back through history.
    static let maxHistoryWeeks = 156

    private(set) var state: TrainLoadState = .loading
    private(set) var weekly: WeeklyProgress?
    private(set) var runs = TrainHistory()
    private(set) var lifts = TrainHistory()
    private(set) var calendar: Calendar = .current
    private(set) var now: Date = .now

    @ObservationIgnored let routeCache = TrainRouteCache()
    @ObservationIgnored private var lastLoad: Date?

    /// Most recent run, shown by the "no runs this week" state.
    var lastRun: WorkoutSummary? { runs.items.first }

    func loadInitial(_ repository: VigilRepository) async {
        if let lastLoad, state == .loaded, Date.now.timeIntervalSince(lastLoad) < 60 { return }
        if state != .loaded { state = .loading }
        calendar = repository.calendar
        now = repository.now()
        do {
            let end = now
            let start = Self.pageStart(before: end, calendar: calendar)
            let interval = DateInterval(start: start, end: end)
            async let weeklyResult = repository.weeklyProgress(endingOn: repository.today)
            async let runResult = repository.workouts(.run, in: interval)
            async let liftResult = repository.workouts(.strength, in: interval)
            let (week, runItems, liftItems) = try await (weeklyResult, runResult, liftResult)
            weekly = week
            runs = TrainHistory(items: runItems, groups: TrainFormatting.monthGroups(runItems, calendar: calendar),
                                oldestFetched: start, hasMore: true)
            lifts = TrainHistory(items: liftItems, groups: TrainFormatting.monthGroups(liftItems, calendar: calendar),
                                 oldestFetched: start, hasMore: true)
            state = .loaded
            lastLoad = .now
        } catch {
            if state != .loaded { state = .failed }
        }
    }

    /// Fetches the next older page when the list scrolls near its end.
    func loadMore(_ kind: WorkoutKind, repository: VigilRepository) async {
        var history = kind == .run ? runs : lifts
        guard history.hasMore, !history.isLoadingMore, let oldest = history.oldestFetched else { return }
        history.isLoadingMore = true
        store(history, for: kind)
        let start = Self.pageStart(before: oldest, calendar: calendar)
        let weeksBack = calendar.dateComponents([.weekOfYear], from: start, to: now).weekOfYear ?? 0
        do {
            let page = try await repository.workouts(kind, in: DateInterval(start: start, end: oldest))
            history = kind == .run ? runs : lifts
            // Page boundaries are half-open: drop anything we already have.
            let known = Set(history.items.map(\.id))
            history.items += page.filter { !known.contains($0.id) }
            history.groups = TrainFormatting.monthGroups(history.items, calendar: calendar)
            history.oldestFetched = start
            history.hasMore = weeksBack < Self.maxHistoryWeeks
        } catch {
            history = kind == .run ? runs : lifts
            history.hasMore = false
        }
        history.isLoadingMore = false
        store(history, for: kind)
    }

    private func store(_ history: TrainHistory, for kind: WorkoutKind) {
        if kind == .run { runs = history } else { lifts = history }
    }

    /// Start of the page that ends at `date`.
    static func pageStart(before date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .weekOfYear, value: -pageWeeks, to: date) ?? date
    }
}
