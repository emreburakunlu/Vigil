import Foundation
import UIKit

/// First-launch 90-day import and incremental refreshes. Owner: orchestrator.
///
/// Fetches raw data once, builds `DailySummary` for every day through `VigilRepository.buildSummaries`
/// (the same path single-day reads use), writes the cache, refreshes the widget snapshot and records
/// `onboarding.historyImportedAt` (import only).
@MainActor
final class HistoryImportService {
    /// Days imported on first launch.
    static let defaultHistoryDays = 90
    /// Bounds for `refreshRecent()` without an explicit day count.
    static let recentDaysRange = 2...14

    private let repository: VigilRepository
    private let widgetSnapshots: WidgetSnapshotService

    /// Called after an import or refresh rewrote summaries (the container bumps `dataVersion`).
    var onDataChanged: (@MainActor () -> Void)?
    /// How long HealthKit observer events are collected before one refresh runs (foreground / background).
    var coalesceDelay: Duration = .seconds(20)
    var backgroundCoalesceDelay: Duration = .seconds(3)
    /// Whether the app is in the foreground (background launches get a shorter coalescing window).
    var isForeground: @MainActor () -> Bool = { UIApplication.shared.applicationState == .active }

    private var pendingUpdates: [HealthDataUpdate] = []
    private var coalesceTask: Task<Void, Never>?

    init(repository: VigilRepository, widgetSnapshots: WidgetSnapshotService) {
        self.repository = repository
        self.widgetSnapshots = widgetSnapshots
    }

    /// Imports `days` of history, yielding progress for the import screen.
    func importHistory(days: Int = HistoryImportService.defaultHistoryDays) -> AsyncThrowingStream<ImportProgress, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    try await self.run(days: days, isImport: true) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Recomputes recent days (after a HealthKit update, on foreground or after a settings change).
    /// With `days == nil`, covers every day since the last settled summary through today
    /// (`recentDaysRange`), so a gap of several days without opening the app is filled.
    /// Does nothing before onboarding is completed (or after "Delete local data").
    func refreshRecent(days: Int? = nil) async throws {
        guard repository.settings.settings.onboarding.completed else { return }
        try await run(days: days ?? recentDayCount(), isImport: false) { _ in }
    }

    /// Days `refreshRecent()` rebuilds: from the oldest day in the last 14 that is missing or not settled
    /// (computed before its day ended + 6 h), through today; at least 2.
    func recentDayCount() -> Int {
        let calendar = repository.calendar
        let today = repository.today
        let oldest = today.adding(days: -(Self.recentDaysRange.upperBound - 1), calendar: calendar)
        let stamps = Dictionary(repository.summaries.stamps(from: oldest, through: today).map { ($0.day, $0) },
                                uniquingKeysWith: { _, b in b })
        let needing = LocalDay.range(from: oldest, through: today, calendar: calendar).first { day in
            guard let stamp = stamps[day] else { return true }
            let settled = day.adding(days: 1, calendar: calendar).startDate(in: calendar).addingTimeInterval(VigilRepository.settleDelay)
            return stamp.computedAt < settled
        }
        let count = (needing.map { $0.days(to: today, calendar: calendar) } ?? 0) + 1
        return min(max(count, Self.recentDaysRange.lowerBound), Self.recentDaysRange.upperBound)
    }

    private func run(days: Int, isImport: Bool, progress: (ImportProgress) -> Void) async throws {
        let calendar = repository.calendar
        let today = repository.today
        let firstDay = today.adding(days: -(max(days, 1) - 1), calendar: calendar)
        // Extra 30 days so the first imported day already has a baseline window.
        let fetchStart = firstDay.adding(days: -Baseline.windowDays, calendar: calendar)
        let interval = LocalDay.interval(from: fetchStart, through: today, calendar: calendar)
        let builtInterval = LocalDay.interval(from: firstDay, through: today, calendar: calendar)
        let source = repository.dataSource

        progress(ImportProgress(phase: .sleep, fraction: 0.05, nightsImported: 0, workoutsImported: 0, workoutsTotal: 0))
        let nights = try await source.sleepNights(in: interval)
        // Only primary nights inside the imported days count ("90 nights" for 90 days, not the baseline window).
        let nightCount = nights.filter { $0.isPrimary && builtInterval.contains($0.sleepEnd) }.count
        try Task.checkCancellation()
        progress(ImportProgress(phase: .vitals, fraction: 0.25, nightsImported: nightCount, workoutsImported: 0, workoutsTotal: 0))
        async let vitalsResult = source.dailyVitals(in: interval, nights: nights)
        async let activityResult = source.dailyActivity(in: interval)
        let workouts = WorkoutDeduplication.deduplicated(try await source.workouts(in: interval, kinds: nil))
        let vitals = try await vitalsResult
        let activity = try await activityResult
        try Task.checkCancellation()
        let scored = workouts.filter { builtInterval.contains($0.start) }
        let heartRate = try await HealthDataBundle.heartRate(for: scored, from: source) { done in
            progress(ImportProgress(phase: .workouts, fraction: 0.45 + 0.3 * Double(done) / Double(max(scored.count, 1)),
                                    nightsImported: nightCount, workoutsImported: done, workoutsTotal: scored.count))
        }
        progress(ImportProgress(phase: .baselines, fraction: 0.8, nightsImported: nightCount,
                                workoutsImported: scored.count, workoutsTotal: scored.count))
        let bundle = HealthDataBundle(nights: nights, vitals: vitals, activity: activity, workouts: workouts, workoutHeartRate: heartRate)
        try await repository.buildSummaries(from: firstDay, through: today, data: bundle)
        progress(ImportProgress(phase: .scores, fraction: 0.9, nightsImported: nightCount,
                                workoutsImported: scored.count, workoutsTotal: scored.count))
        if isImport {
            repository.settings.update { $0.onboarding.historyImportedAt = self.repository.now() }
        }
        onDataChanged?()
        await widgetSnapshots.refresh()
        progress(ImportProgress(phase: .finished, fraction: 1, nightsImported: nightCount,
                                workoutsImported: scored.count, workoutsTotal: scored.count))
    }

    /// Listens for HealthKit updates until the task is cancelled. Events are coalesced: the first one
    /// starts a short window (`coalesceDelay`, shorter in the background); then one refresh runs (today only
    /// when nothing but activity changed) and every collected update is acknowledged, which lets a
    /// background launch finish. Started once per process by `AppContainer.startHealthObservation()`.
    func observeHealthUpdates() async {
        for await update in repository.dataSource.updates() {
            pendingUpdates.append(update)
            guard coalesceTask == nil else { continue }
            let delay = isForeground() ? coalesceDelay : backgroundCoalesceDelay
            coalesceTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                await self?.processPendingUpdates()
            }
        }
    }

    /// Runs one refresh for the collected updates, then acknowledges them (also when the refresh fails).
    func processPendingUpdates() async {
        let batch = pendingUpdates
        pendingUpdates = []
        coalesceTask = nil
        guard !batch.isEmpty else { return }
        let categories = batch.reduce(into: Set<HealthDataCategory>()) { $0.formUnion($1.categories) }
        repository.invalidateRecent()
        try? await refreshRecent(days: categories == [.activity] ? 1 : nil)
        for update in batch { update.acknowledge() }
    }
}
