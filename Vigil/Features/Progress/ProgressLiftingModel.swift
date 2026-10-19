import Foundation
import Observation

/// A weekly intensity series (average session heart rate or strain).
struct ProgressIntensitySeries: Hashable, Sendable {
    var points: [ProgressPoint]
    /// Latest week with sessions.
    var latest: Double
    /// Latest minus the previous week with sessions.
    var delta: Double?
}

/// Everything on Progress → Lifting that depends on the selected range.
struct ProgressLiftingContent: Hashable, Sendable {
    /// Sessions per week (value = count).
    var sessions: [ProgressBar]
    var sessionGoal: Int
    var averageSessions: Double
    /// Lifting seconds per week.
    var time: [ProgressBar]
    var averageTime: TimeInterval
    /// Active kilocalories per week.
    var calories: [ProgressBar]
    var averageCalories: Double
    var heartRate: ProgressIntensitySeries?
    var strain: ProgressIntensitySeries?
    var heatmap: ProgressHeatmap
    var tickDates: [Date]
    var totalSessions: Int
}

/// Screen model for Progress → Lifting.
@MainActor
@Observable
final class ProgressLiftingModel {
    private(set) var phase: ProgressPhase = .loading
    private(set) var content: ProgressLiftingContent?

    func load(repository: VigilRepository, range: ProgressRange) async {
        if content == nil { phase = .loading }
        do {
            content = try await Self.buildContent(repository: repository, range: range)
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            if content == nil { phase = .failed }
        }
    }

    static func buildContent(repository: VigilRepository, range: ProgressRange) async throws -> ProgressLiftingContent {
        let calendar = repository.calendar
        let today = repository.today
        let weeks = range.weeks
        let interval = range.interval(endingOn: today, calendar: calendar)
        let starts = ProgressAggregation.weekStarts(weeks: weeks, endingOn: today, calendar: calendar)
        let first = starts[0]

        // One fetch for runs and lifts (heatmap needs both). Strain comes from cached summaries: no per-workout HR reads.
        let workouts = try await repository.dataSource.workouts(in: interval, kinds: [.run, .strength])
        let lifts = workouts.filter { $0.kind == .strength }
        let cached = repository.summaries.summaries(from: first, through: today)
        var strainByWorkout: [UUID: Double] = [:]
        for summary in cached {
            for workout in summary.strain?.workouts ?? [] { strainByWorkout[workout.workoutID] = Double(workout.value) }
        }

        func perWeek(_ value: (Workout) -> Double) -> [Double] {
            ProgressAggregation.weeklySums(lifts.map { (LocalDay($0.start, calendar: calendar), value($0)) }, first: first, count: weeks, calendar: calendar)
        }
        func bars(_ values: [Double]) -> [ProgressBar] {
            values.enumerated().map { ProgressBar(id: $0.offset, start: starts[$0.offset].startDate(in: calendar), value: $0.element) }
        }
        let counts = perWeek { _ in 1 }
        let seconds = perWeek(\.duration)
        let kcal = perWeek { $0.activeEnergyKilocalories ?? 0 }
        let weekCount = Double(weeks)

        func series(_ items: [(day: LocalDay, value: Double)]) -> ProgressIntensitySeries? {
            let means = ProgressAggregation.weeklyMeans(items, first: first, count: weeks, calendar: calendar)
            let points = means.enumerated().compactMap { index, mean in
                mean.map { ProgressPoint(date: starts[index].startDate(in: calendar), value: $0) }
            }
            guard let last = points.last else { return nil }
            return ProgressIntensitySeries(points: points, latest: last.value,
                                           delta: points.count >= 2 ? last.value - points[points.count - 2].value : nil)
        }
        let heartRate = series(lifts.compactMap { w in w.averageHeartRate.map { (LocalDay(w.start, calendar: calendar), $0) } })
        let strain = series(lifts.compactMap { w in strainByWorkout[w.id].map { (LocalDay(w.start, calendar: calendar), $0) } })

        var kinds: [LocalDay: Set<WorkoutKind>] = [:]
        for workout in workouts { kinds[LocalDay(workout.start, calendar: calendar), default: []].insert(workout.kind) }
        let heatmap = ProgressAggregation.heatmap(workoutKinds: kinds, weeks: weeks, today: today, calendar: calendar)

        return ProgressLiftingContent(
            sessions: bars(counts), sessionGoal: repository.settings.settings.goals.weeklyLiftSessions,
            averageSessions: counts.reduce(0, +) / weekCount,
            time: bars(seconds), averageTime: seconds.reduce(0, +) / weekCount,
            calories: bars(kcal), averageCalories: kcal.reduce(0, +) / weekCount,
            heartRate: heartRate, strain: strain, heatmap: heatmap,
            tickDates: ProgressAggregation.tickDates(starts.map { $0.startDate(in: calendar) }),
            totalSessions: lifts.count)
    }
}
