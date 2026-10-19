import Foundation
import WidgetKit

/// Builds the `WidgetSnapshot` from the repository, writes it to the App Group and reloads
/// widget timelines.
///
/// The app calls `scheduleRefresh()` (debounced, fire-and-forget) after summaries change: after the
/// history import, after each HealthKit observer update, on foreground, and after settings changes that
/// affect widgets (units, goals). `refresh()` does the work immediately and is what tests / launch use.
@MainActor
final class WidgetSnapshotService {
    private let repository: VigilRepository
    private let store: WidgetSnapshotStore
    private let debounce: Duration
    private var pending: Task<Void, Never>?

    /// Called with each snapshot after it was saved; the app uses it to refresh the morning notification.
    var onSnapshot: (@MainActor (WidgetSnapshot) async -> Void)?

    init(repository: VigilRepository, store: WidgetSnapshotStore = WidgetSnapshotStore(), debounce: Duration = .seconds(2)) {
        self.repository = repository
        self.store = store
        self.debounce = debounce
    }

    /// Coalesces bursts (several HealthKit observers fire together) into one snapshot write.
    /// The last snapshot written, if any (used to put real values in the morning notification).
    func currentSnapshot() -> WidgetSnapshot? { store.load() }

    func scheduleRefresh() {
        pending?.cancel()
        let delay = debounce
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    /// Computes today's snapshot, saves it and reloads all Vigil widgets. Errors are logged, not thrown.
    @discardableResult
    func refresh() async -> WidgetSnapshot? {
        do {
            let snapshot = try await makeSnapshot(for: repository.today)
            try store.save(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
            await onSnapshot?(snapshot)
            return snapshot
        } catch {
            print("Vigil: widget snapshot refresh failed: \(error)")
            return nil
        }
    }

    /// Builds the snapshot for `day` without saving it.
    func makeSnapshot(for day: LocalDay) async throws -> WidgetSnapshot {
        let calendar = repository.calendar
        let summary = try await repository.summary(for: day)
        let weekly = try await repository.weeklyProgress(endingOn: day)
        let settings = repository.settings.settings
        return WidgetSnapshot(
            generatedAt: repository.now(),
            day: day.startDate(in: calendar),
            units: settings.units,
            recoveryPercent: summary.recovery?.value,
            recoveryBand: summary.recovery?.band,
            readiness: summary.recovery?.suggestion,
            sleepScore: summary.sleepScore?.value,
            sleepDuration: summary.sleepDuration,
            strain: summary.strain?.value,
            strainLevel: summary.strain?.level,
            weeklyRunDistanceMeters: weekly.runDistanceMeters,
            weeklyRunGoalMeters: weekly.runGoalMeters,
            weeklyLiftSessions: weekly.liftSessions,
            weeklyLiftGoal: weekly.liftGoal,
            weekStart: weekly.startDay.startDate(in: calendar),
            weekEnd: weekly.endDay.startDate(in: calendar)
        )
    }

    /// Removes the snapshot (Delete local data).
    func clear() {
        pending?.cancel()
        try? store.delete()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
