import Foundation
import WidgetKit

/// Builds the `WidgetSnapshot` from the repository, writes it to the App Group and reloads
/// widget timelines. Call after imports, refreshes and settings changes that affect widgets.
@MainActor
final class WidgetSnapshotService {
    private let repository: VigilRepository
    private let store: WidgetSnapshotStore

    init(repository: VigilRepository, store: WidgetSnapshotStore = WidgetSnapshotStore()) {
        self.repository = repository
        self.store = store
    }

    /// Computes today's snapshot, saves it and reloads all Vigil widgets. Errors are logged, not thrown.
    func refresh() async {
        do {
            let snapshot = try await makeSnapshot(for: repository.today)
            try store.save(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("Vigil: widget snapshot refresh failed: \(error)")
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
        try? store.delete()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
