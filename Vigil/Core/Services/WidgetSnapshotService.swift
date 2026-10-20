import Foundation
import WidgetKit

/// Builds the `WidgetSnapshot` from the repository, writes it to the App Group and reloads
/// widget timelines.
///
/// The app calls `scheduleRefresh()` (debounced, fire-and-forget) after summaries change: after the
/// history import, after each HealthKit observer update, on foreground, and after settings changes that
/// affect widgets (units, goals). `refresh()` does the work immediately and is what tests / launch use.
/// Nothing is written before onboarding is completed (or after "Delete local data").
@MainActor
final class WidgetSnapshotService {
    /// An unchanged snapshot is still re-saved after this long, so the widget's 36 h staleness never trips
    /// while the app keeps refreshing.
    static let resaveInterval: TimeInterval = 6 * 3600

    private let repository: VigilRepository
    private let store: WidgetSnapshotStore
    private let debounce: Duration
    private let reloadTimelines: @MainActor () -> Void
    private var pending: Task<Void, Never>?

    /// Called with each snapshot after a refresh; the app uses it to refresh the morning notification.
    var onSnapshot: (@MainActor (WidgetSnapshot) async -> Void)?

    init(repository: VigilRepository, store: WidgetSnapshotStore = WidgetSnapshotStore(), debounce: Duration = .seconds(2),
         reloadTimelines: @escaping @MainActor () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        self.repository = repository
        self.store = store
        self.debounce = debounce
        self.reloadTimelines = reloadTimelines
    }

    /// The last snapshot written, if any (used to put real values in the morning notification).
    func currentSnapshot() -> WidgetSnapshot? { store.load() }

    private var isOnboarded: Bool { repository.settings.settings.onboarding.completed }

    /// Coalesces bursts (several changes together) into one snapshot write.
    func scheduleRefresh() {
        pending?.cancel()
        guard isOnboarded else { return }
        let delay = debounce
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    /// Computes today's snapshot, saves it and reloads all Vigil widgets. Errors are logged, not thrown.
    /// An equivalent snapshot (ignoring `generatedAt`) saved less than `resaveInterval` ago is not re-saved
    /// and timelines aren't reloaded.
    @discardableResult
    func refresh() async -> WidgetSnapshot? {
        guard isOnboarded else { return nil }
        do {
            let snapshot = try await makeSnapshot(for: repository.today)
            // Local data may have been deleted while the snapshot was being built.
            guard isOnboarded else { return nil }
            if let stored = store.load(), Self.isEquivalent(stored, snapshot),
               snapshot.generatedAt.timeIntervalSince(stored.generatedAt) < Self.resaveInterval {
                await onSnapshot?(stored)
                return stored
            }
            try store.save(snapshot)
            reloadTimelines()
            await onSnapshot?(snapshot)
            return snapshot
        } catch {
            print("Vigil: widget snapshot refresh failed: \(error)")
            return nil
        }
    }

    /// Same content apart from `generatedAt`.
    static func isEquivalent(_ a: WidgetSnapshot, _ b: WidgetSnapshot) -> Bool {
        var a = a
        a.generatedAt = b.generatedAt
        return a == b
    }

    /// Builds the snapshot for `day` without saving it.
    func makeSnapshot(for day: LocalDay) async throws -> WidgetSnapshot {
        let calendar = repository.calendar
        async let weeklyResult = repository.weeklyProgress(endingOn: day)
        let summary = try await repository.summary(for: day)
        let weekly = try await weeklyResult
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
        pending = nil
        try? store.delete()
        reloadTimelines()
    }
}
