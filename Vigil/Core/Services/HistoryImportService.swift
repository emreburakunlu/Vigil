import Foundation

/// First-launch 90-day import and incremental refreshes. Owner: orchestrator.
///
/// Fetches raw data once, builds `DailySummary` for every day with the engine, writes the cache,
/// refreshes the widget snapshot and records `onboarding.historyImportedAt`.
@MainActor
final class HistoryImportService {
    /// Days imported on first launch.
    static let defaultHistoryDays = 90

    private let repository: VigilRepository
    private let widgetSnapshots: WidgetSnapshotService

    init(repository: VigilRepository, widgetSnapshots: WidgetSnapshotService) {
        self.repository = repository
        self.widgetSnapshots = widgetSnapshots
    }

    /// Imports `days` of history, yielding progress for the import screen.
    func importHistory(days: Int = HistoryImportService.defaultHistoryDays) -> AsyncThrowingStream<ImportProgress, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    try await self.run(days: days) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Recomputes the last `days` days (e.g. after a HealthKit update or settings change).
    func refreshRecent(days: Int = 2) async throws {
        try await run(days: days) { _ in }
    }

    private func run(days: Int, progress: (ImportProgress) -> Void) async throws {
        let calendar = repository.calendar
        let today = repository.today
        let firstDay = today.adding(days: -(days - 1), calendar: calendar)
        // Extra 30 days so the first imported day already has a baseline window.
        let fetchStart = firstDay.adding(days: -Baseline.windowDays, calendar: calendar)
        let interval = LocalDay.interval(from: fetchStart, through: today, calendar: calendar)
        let source = repository.dataSource

        progress(ImportProgress(phase: .sleep, fraction: 0.05, nightsImported: 0, workoutsImported: 0, workoutsTotal: 0))
        let nights = try await source.sleepNights(in: interval)
        try Task.checkCancellation()
        progress(ImportProgress(phase: .vitals, fraction: 0.25, nightsImported: nights.count, workoutsImported: 0, workoutsTotal: 0))
        let vitals = try await source.dailyVitals(in: interval)
        let activity = try await source.dailyActivity(in: interval)
        try Task.checkCancellation()
        let workouts = try await source.workouts(in: interval, kinds: nil)
        var heartRate: [UUID: [MetricSample]] = [:]
        for (index, workout) in workouts.enumerated() {
            try Task.checkCancellation()
            heartRate[workout.id] = try await source.heartRateSamples(in: workout.interval)
            progress(ImportProgress(phase: .workouts, fraction: 0.45 + 0.3 * Double(index + 1) / Double(max(workouts.count, 1)),
                                    nightsImported: nights.count, workoutsImported: index + 1, workoutsTotal: workouts.count))
        }
        progress(ImportProgress(phase: .baselines, fraction: 0.8, nightsImported: nights.count,
                                workoutsImported: workouts.count, workoutsTotal: workouts.count))
        let bundle = HealthDataBundle(nights: nights, vitals: vitals, activity: activity, workouts: workouts, workoutHeartRate: heartRate)
        let builder = SummaryBuilder(engine: repository.engine, calendar: calendar)
        let summaries = builder.summaries(for: LocalDay.range(from: firstDay, through: today, calendar: calendar),
                                          data: bundle, settings: repository.settings.settings, now: repository.now())
        progress(ImportProgress(phase: .scores, fraction: 0.9, nightsImported: nights.count,
                                workoutsImported: workouts.count, workoutsTotal: workouts.count))
        try repository.summaries.upsert(summaries)
        repository.settings.update { $0.onboarding.historyImportedAt = self.repository.now() }
        await widgetSnapshots.refresh()
        progress(ImportProgress(phase: .finished, fraction: 1, nightsImported: nights.count,
                                workoutsImported: workouts.count, workoutsTotal: workouts.count))
    }

    /// Listens for HealthKit updates and refreshes recent days until the task is cancelled.
    /// Started once by the app after onboarding (`VigilApp`).
    func observeHealthUpdates() async {
        for await _ in repository.dataSource.updates() {
            try? await refreshRecent()
        }
    }
}
