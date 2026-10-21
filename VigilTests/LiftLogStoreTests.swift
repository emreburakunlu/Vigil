import Foundation
import SwiftData
import Testing
@testable import Vigil

@MainActor
@Suite("LiftLogStore")
struct LiftLogStoreTests {
    private func makeStore() throws -> (LiftLogStore, ModelContainer) {
        let container = try PersistenceController.makeContainer(.inMemory)
        return (LiftLogStore(container: container), container)
    }

    @Test func startUpdateFinishAppearsInRecent() throws {
        let (store, container) = try makeStore()
        let started = store.startSession(title: "Push", now: Date(timeIntervalSince1970: 1_000))
        #expect(store.startSession(title: "Other").id == started.id)
        store.updateActive {
            $0.exercises = [LoggedExercise(name: "Bench Press", sets: [LoggedSet(reps: 5, weightKilograms: 80, isCompleted: true)])]
        }
        store.finishActive(now: Date(timeIntervalSince1970: 2_000))
        #expect(store.active == nil)
        #expect(store.recent.count == 1)
        #expect(store.recent[0].end != nil)
        #expect(store.recentExerciseNames == ["Bench Press"])
        // Persisted and reloaded by a fresh store.
        #expect(LiftLogStore(container: container).recent.count == 1)
    }

    @Test func finishWithoutCompletedSetsDropsSession() throws {
        let (store, container) = try makeStore()
        store.startSession(title: "Empty")
        store.updateActive { $0.exercises = [LoggedExercise(name: "Squat", sets: [LoggedSet(reps: 5, weightKilograms: 100)])] }
        store.finishActive()
        #expect(store.active == nil)
        #expect(store.recent.isEmpty)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<LiftSessionRecord>()) == 0)
    }

    @Test func lastPerformanceIsCaseInsensitiveAndNewest() throws {
        let (store, _) = try makeStore()
        for (index, weight) in [60.0, 70.0].enumerated() {
            store.startSession(title: "Day", now: Date(timeIntervalSince1970: Double(index) * 100_000))
            store.updateActive {
                $0.exercises = [LoggedExercise(name: "Deadlift", sets: [LoggedSet(reps: 5, weightKilograms: weight, isCompleted: true)])]
            }
            store.finishActive(now: Date(timeIntervalSince1970: Double(index) * 100_000 + 3_000))
        }
        #expect(store.lastPerformance(of: "deadlift")?.sets.first?.weightKilograms == 70)
        #expect(store.lastPerformance(of: "Row") == nil)
    }
}
