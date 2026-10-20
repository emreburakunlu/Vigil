import Foundation
import HealthKit
import Synchronization
import Testing
@testable import Vigil

@Suite("HealthKit · observer support")
struct HealthKitObserverTests {
    @Test func acknowledgeCompletesExactlyOnce() {
        let count = Mutex(0)
        let gate = ObserverCompletionGate(timeout: .seconds(30)) { count.withLock { $0 += 1 } }
        #expect(!gate.isCompleted)
        gate.acknowledge()
        gate.acknowledge()
        #expect(count.withLock { $0 } == 1)
        #expect(gate.isCompleted)
    }

    @Test func timeoutCompletesWhenNeverAcknowledged() async throws {
        let count = Mutex(0)
        let gate = ObserverCompletionGate(timeout: .milliseconds(50)) { count.withLock { $0 += 1 } }
        try await Task.sleep(for: .milliseconds(500))
        #expect(count.withLock { $0 } == 1)
        gate.acknowledge() // late acknowledge is a no-op
        #expect(count.withLock { $0 } == 1)
    }

    @Test func acknowledgeBeatsTimeout() async throws {
        let count = Mutex(0)
        let gate = ObserverCompletionGate(timeout: .milliseconds(100)) { count.withLock { $0 += 1 } }
        gate.acknowledge()
        try await Task.sleep(for: .milliseconds(500))
        #expect(count.withLock { $0 } == 1)
    }

    @Test func concurrentAcknowledgeRunsOnce() async {
        let count = Mutex(0)
        let gate = ObserverCompletionGate(timeout: .seconds(30)) { count.withLock { $0 += 1 } }
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 { group.addTask { gate.acknowledge() } }
        }
        #expect(count.withLock { $0 } == 1)
    }

    @Test func classifiesObserverErrors() {
        #expect(ObserverOutcome.classify(nil) == .signal)
        #expect(ObserverOutcome.classify(HKError(.errorDatabaseInaccessible)) == .deferUntilUnlock)
        #expect(ObserverOutcome.classify(HKError(.errorAuthorizationDenied)) != .signal)
    }

    @Test func pendingTrackerOnlyHoldsMarkedCategories() {
        let tracker = HealthUpdateTracker()
        #expect(tracker.takePending().isEmpty)
        tracker.markPending(.sleep)
        tracker.markPending(.sleep)
        tracker.markPending(.workouts)
        #expect(tracker.takePending() == [.sleep, .workouts])
        #expect(tracker.takePending().isEmpty)
    }

    @Test func derivedCacheStoresByWorkoutID() async {
        let cache = WorkoutDerivedCache()
        let id = UUID()
        #expect(await cache.value(for: id) == nil)
        let value = WorkoutDerived(hasRoute: true, averageHeartRate: 150, maxHeartRate: 180,
                                   heartRateSource: DataSourceInfo(name: "Watch", bundleIdentifier: "com.apple.health"))
        await cache.store(value, for: id)
        #expect(await cache.value(for: id) == value)
        #expect(await cache.value(for: UUID()) == nil)
        #expect(await cache.count == 1)
    }

    @Test func backgroundDeliveryOnlyForSleepWorkoutsAndHRV() {
        let background = HealthKitTypes.observed.filter { $0.backgroundFrequency != nil }
        #expect(Set(background.map(\.category)) == [.sleep, .workouts, .heartRateVariability])
        #expect(background.first { $0.category == .sleep }?.backgroundFrequency == .immediate)
        #expect(background.first { $0.category == .workouts }?.backgroundFrequency == .immediate)
        #expect(background.first { $0.category == .heartRateVariability }?.backgroundFrequency == .hourly)
        #expect(HealthKitTypes.observed.count == 10)
    }
}
