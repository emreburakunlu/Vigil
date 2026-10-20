import Foundation
import Testing
@testable import Vigil

@Suite("Widget snapshot freshness")
struct WidgetSnapshotTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(age: TimeInterval) -> WidgetSnapshot {
        .placeholder(now: now.addingTimeInterval(-age), calendar: TestSupport.utc)
    }

    @Test func freshSnapshotIsReady() {
        let s = snapshot(age: 3600)
        #expect(WidgetSnapshot.displayState(snapshot: s, at: now, calendar: TestSupport.utc) == .ready(s))
    }

    @Test func staleBoundaryIs36Hours() {
        #expect(!snapshot(age: 36 * 3600).isStale(at: now))
        #expect(snapshot(age: 36 * 3600 + 1).isStale(at: now))
        #expect(WidgetSnapshot.displayState(snapshot: snapshot(age: 40 * 3600), at: now) == .needsUpdate)
    }

    @Test func missingSnapshotNeedsUpdate() {
        #expect(WidgetSnapshot.displayState(snapshot: nil, at: now) == .needsUpdate)
    }

    @Test func unavailableAppGroupNeedsUpdate() {
        #expect(WidgetSnapshot.displayState(snapshot: snapshot(age: 60), at: now, groupAvailable: false) == .needsUpdate)
    }

    @Test func futureSnapshotIsFresh() {
        #expect(!snapshot(age: -600).isStale(at: now))
    }

    @Test func staleDateIsGeneratedPlus36h() {
        let s = snapshot(age: 0)
        #expect(s.staleDate.timeIntervalSince(s.generatedAt) == 36 * 3600)
    }

    @Test func readinessLabelsAndBand() {
        var s = snapshot(age: 0)
        #expect(s.readinessLabel == "Push day")
        s.readiness = .takeItEasy
        #expect(s.readinessLabel == "Take it easy")
        s.readiness = nil
        #expect(s.readinessLabel == nil)
        s.recoveryBand = nil
        s.recoveryPercent = 40
        #expect(s.resolvedRecoveryBand == .yellow)
    }

    @Test func runProgressClampsAndHandlesZeroGoal() {
        var s = snapshot(age: 0)
        s.weeklyRunDistanceMeters = 40_000
        s.weeklyRunGoalMeters = 25_000
        #expect(s.runProgress == 1)
        s.weeklyRunGoalMeters = 0
        #expect(s.runProgress == 0)
    }

    @Test func snapshotRoundTripsThroughStore() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "vigil-widget-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WidgetSnapshotStore(directory: dir)
        #expect(store.load() == nil)
        let s = WidgetSnapshot.placeholder(now: now)
        try store.save(s)
        #expect(store.load()?.recoveryPercent == s.recoveryPercent)
        try store.delete()
        #expect(store.load() == nil)
    }
}
