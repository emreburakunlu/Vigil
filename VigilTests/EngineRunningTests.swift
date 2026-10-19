import Foundation
import Testing
@testable import Vigil

@Suite("Engine · Best efforts")
struct EngineBestEffortTests {
    func fastest(_ target: Double, _ pieces: [(TimeInterval, Double)]) -> TimeInterval? {
        BestEffortFinder.fastest(target, in: BestEffortFinder.timeline(from: EngineFixtures.timeline(pieces)))
    }

    @Test func steadyRun() throws {
        #expect(abs(try #require(fastest(5_000, [(1_800, 4)])) - 1_250) < 1e-6)
        #expect(fastest(10_000, [(1_800, 4)]) == nil) // only 7.2 km
    }

    @Test func findsFastSegmentInsideSlowerRun() throws {
        let pieces: [(TimeInterval, Double)] = [(1_000, 3), (600, 5)] // 3 km slow, then 3 km fast
        #expect(abs(try #require(fastest(1_000, pieces)) - 200) < 1e-6)
        #expect(abs(try #require(fastest(5_000, pieces)) - (600 + 2_000.0 / 3)) < 1e-6)
    }

    @Test func fastSegmentInTheMiddleUsesInterpolation() throws {
        // 7 s sampling so segment boundaries fall between samples.
        let samples = EngineFixtures.timeline([(700, 3), (250, 4.5), (700, 3)], step: 7)
        let best = try #require(BestEffortFinder.fastest(1_000, in: BestEffortFinder.timeline(from: samples)))
        #expect(abs(best - 1_000 / 4.5) < 1e-6)
    }

    @Test func pausesCountAsElapsedTime() throws {
        let pieces: [(TimeInterval, Double)] = [(500, 4), (300, 0), (500, 4)]
        #expect(abs(try #require(fastest(1_000, pieces)) - 250) < 1e-6)
        #expect(abs(try #require(fastest(3_000, pieces)) - 1_050) < 1e-6)
    }

    @Test func gpsSpikesAreCapped() throws {
        var samples = EngineFixtures.timeline([(600, 4)])
        for i in 60..<samples.count { samples[i].value += 500 } // +500 m teleport at t = 300 s
        let timeline = BestEffortFinder.timeline(from: samples.shuffled())
        #expect(abs(timeline.totalDistance - (2_400 - 20 + 50)) < 1e-6) // that 5 s step capped at 10 m/s × 5 s
        #expect(try #require(BestEffortFinder.fastest(1_000, in: timeline)) > 235)
    }

    @Test func degenerateInput() {
        #expect(BestEffortFinder.fastest(1_000, in: BestEffortFinder.timeline(from: [])) == nil)
        #expect(BestEffortFinder.fastest(0, in: BestEffortFinder.timeline(from: EngineFixtures.timeline([(600, 4)]))) == nil)
    }
}

@Suite("Engine · Personal bests")
struct EnginePersonalBestTests {
    let engine = EngineFixtures.engine
    let asOf = TestSupport.referenceDate

    func run(daysAgo: Double, _ pieces: [(TimeInterval, Double)], timeline: Bool = true) -> RunEffortInput {
        let start = asOf.addingTimeInterval(-daysAgo * 86_400)
        let samples = EngineFixtures.timeline(start: start, pieces)
        let duration = pieces.reduce(0) { $0 + $1.0 }
        let workout = EngineFixtures.workout(start: start, duration: duration, distance: samples.last!.value)
        return RunEffortInput(workout: workout, cumulativeDistance: timeline ? samples : [])
    }

    func best(_ category: PersonalBestCategory, _ bests: [PersonalBest]) -> PersonalBest? { bests.first { $0.category == category } }

    @Test func bestEffortsComeFromInsideRuns() throws {
        // 10.5 km: 2 km slow, 5 km fast (4.5 m/s), 3.5 km slow.
        let long = run(daysAgo: 30, [(2_000.0 / 3, 3), (5_000.0 / 4.5, 4.5), (3_500.0 / 3, 3)])
        let bests = engine.personalBests(runs: [long], asOf: asOf)
        let fiveK = try #require(best(.fiveKilometers, bests))
        #expect(abs(try #require(fiveK.duration) - 5_000 / 4.5) < 1e-6)
        #expect(fiveK.workoutID == long.workout.id && fiveK.distanceMeters == 5_000)
        let average = long.workout.duration * 5_000 / long.workout.distanceMeters!
        #expect(try #require(fiveK.duration) < average)
        #expect(best(.tenKilometers, bests) != nil)
        #expect(best(.halfMarathon, bests) == nil)
        #expect(best(.marathon, bests) == nil)
        #expect(best(.longestRun, bests)?.distanceMeters == long.workout.distanceMeters)
        #expect(bests.allSatisfy { !$0.isNew })
    }

    @Test func picksFastestAcrossRunsAndFlagsNew() throws {
        let old = run(daysAgo: 40, [(1_500, 4)])                 // 6 km at 4 m/s
        let recent = run(daysAgo: 2, [(1_400, 3.6), (200, 6)])   // 1.2 km at 6 m/s inside
        let bests = engine.personalBests(runs: [recent, old], asOf: asOf)
        let oneK = try #require(best(.oneKilometer, bests))
        #expect(oneK.workoutID == recent.workout.id && oneK.isNew)
        #expect(abs(try #require(oneK.duration) - 1_000.0 / 6) < 1e-6)
        let fiveK = try #require(best(.fiveKilometers, bests))
        #expect(fiveK.workoutID == old.workout.id && !fiveK.isNew)
    }

    @Test func wholeRunFallbackWithoutTimeline() throws {
        let bare = run(daysAgo: 10, [(1_300, 4)], timeline: false) // 5.2 km in 1 300 s
        let fiveK = try #require(best(.fiveKilometers, engine.personalBests(runs: [bare], asOf: asOf)))
        #expect(abs(try #require(fiveK.duration) - 1_250) < 1e-6)
    }

    @Test func tiesGoToTheEarlierRun() throws {
        let first = run(daysAgo: 20, [(1_500, 4)]), second = run(daysAgo: 5, [(1_500, 4)])
        let bests = engine.personalBests(runs: [second, first], asOf: asOf)
        #expect(best(.fiveKilometers, bests)?.workoutID == first.workout.id)
        #expect(best(.longestRun, bests)?.workoutID == first.workout.id)
    }

    @Test func ignoresNonRunsAndEmptyInput() {
        #expect(engine.personalBests(runs: [], asOf: asOf).isEmpty)
        let lift = RunEffortInput(workout: EngineFixtures.workout(kind: .strength, distance: 5_000), cumulativeDistance: [])
        #expect(engine.personalBests(runs: [lift], asOf: asOf).isEmpty)
    }
}

@Suite("Engine · Aerobic efficiency")
struct EngineAerobicEfficiencyTests {
    let engine = EngineFixtures.engine

    func run(dayOffset: Int, pace: Double, hr: Double, km: Double = 8) -> Workout {
        let start = EngineFixtures.at(EngineFixtures.day(dayOffset), 7)
        return EngineFixtures.workout(start: start, duration: pace * km, distance: km * 1_000, averageHeartRate: hr)
    }

    @Test func fasterAtTheSameHeartRate() throws {
        let runs = (0..<6).map { run(dayOffset: -50 + $0 * 10, pace: 330 - Double($0) * 5, hr: 150) }
            + [run(dayOffset: -3, pace: 260, hr: 178)] // race effort, outside ±10 bpm
        let trend = try #require(engine.aerobicEfficiency(runs: runs, endingOn: EngineFixtures.today, weeks: 8))
        #expect(trend.referenceHeartRate == 150)
        #expect(trend.runsUsed == 6)
        #expect(abs(try #require(trend.paceChangeSecondsPerKilometer) - -25) < 1e-6)
        #expect(trend.points.allSatisfy { $0.runCount >= 1 })
        #expect(trend.points == trend.points.sorted { $0.weekStart < $1.weekStart })
    }

    @Test func normalisesPaceToReferenceHeartRate() throws {
        let runs = [run(dayOffset: -30, pace: 300, hr: 150), run(dayOffset: -20, pace: 300, hr: 150),
                    run(dayOffset: -10, pace: 300, hr: 150), run(dayOffset: -1, pace: 300, hr: 144)]
        let trend = try #require(engine.aerobicEfficiency(runs: runs, endingOn: EngineFixtures.today, weeks: 6))
        // Same pace at a lower HR is more efficient: 300 × 144 / 150 = 288 s/km.
        #expect(trend.points.last.map { abs($0.paceSecondsPerKilometer - 288) < 1e-6 } == true)
        #expect(try #require(trend.paceChangeSecondsPerKilometer) < 0)
    }

    @Test func tooFewRuns() {
        let runs = (0..<3).map { run(dayOffset: -$0 * 7, pace: 320, hr: 150) } + [run(dayOffset: -2, pace: 320, hr: 150, km: 1)]
        #expect(engine.aerobicEfficiency(runs: runs, endingOn: EngineFixtures.today, weeks: 8) == nil)
    }
}
