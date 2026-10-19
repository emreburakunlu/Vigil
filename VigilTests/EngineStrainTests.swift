import Foundation
import Testing
@testable import Vigil

@Suite("Engine · Zones")
struct EngineZoneTests {
    let engine = EngineFixtures.engine
    let date = TestSupport.referenceDate

    @Test func manualMaxHeartRate() {
        let zones = EngineFixtures.zones(max: 190)
        #expect(zones.source == .manualMaxHeartRate)
        #expect(zones.zones.map(\.lowerBound) == [95, 114, 133, 152, 171])
        #expect(zones.zones.map(\.upperBound) == [113, 132, 151, 170, 190])
    }

    @Test func zoneEdges() {
        let zones = EngineFixtures.zones(max: 190)
        #expect(zones.zone(for: 94.9) == nil)
        #expect(zones.zone(for: 95) == 1)
        #expect(zones.zone(for: 113.9) == 1)
        #expect(zones.zone(for: 114) == 2)
        #expect(zones.zone(for: 171) == 5)
        #expect(zones.zone(for: 230) == 5)
    }

    @Test func observedMaxRaisesEstimateOnly() {
        let estimated = engine.heartRateZones(profile: .default, settings: .default, observedMaxHeartRate: 200, on: date)
        #expect(estimated.maxHeartRate == 200) // estimate for age 35 is 184
        #expect(engine.heartRateZones(profile: .default, settings: .default, observedMaxHeartRate: 170, on: date).maxHeartRate == 184)
        #expect(engine.heartRateZones(profile: .default, settings: .default, observedMaxHeartRate: 400, on: date).maxHeartRate == 184)
        var manual = UserProfile.default
        manual.estimatesMaxHeartRate = false
        manual.manualMaxHeartRate = 180
        #expect(engine.heartRateZones(profile: manual, settings: .default, observedMaxHeartRate: 200, on: date).maxHeartRate == 180)
    }

    @Test(arguments: [[120, 110, 150, 170], [120, 120, 150, 170], [120, 140], [0, 120, 150, 170]])
    func invalidCustomZonesFallBack(bounds: [Int]) {
        let zones = engine.heartRateZones(profile: .default, settings: HeartRateZoneSettings(usesCustomZones: true, customUpperBounds: bounds),
                                          observedMaxHeartRate: nil, on: date)
        #expect(zones.source == .estimated)
    }

    @Test func customZonesAboveMaxStayOrdered() {
        let zones = engine.heartRateZones(profile: .default, settings: HeartRateZoneSettings(usesCustomZones: true, customUpperBounds: [130, 150, 170, 190]),
                                          observedMaxHeartRate: nil, on: date)
        #expect(zones.source == .custom)
        #expect(zones.zones.allSatisfy { $0.lowerBound <= $0.upperBound })
        #expect(zones.maxHeartRate == 191)
    }

    @Test func timeInZoneCapsGapsAndIgnoresOutside() {
        let zones = EngineFixtures.zones(max: 190)
        let start = date
        let interval = DateInterval(start: start, duration: 600)
        let samples = [
            MetricSample(date: start.addingTimeInterval(-30), value: 180), // before the workout
            MetricSample(date: start, value: 120),                          // Z2, held 60 s (cap) of a 100 s gap
            MetricSample(date: start.addingTimeInterval(100), value: 160),  // Z4, 20 s
            MetricSample(date: start.addingTimeInterval(120), value: 80),   // below Z1, not counted
            MetricSample(date: start.addingTimeInterval(130), value: 175),  // Z5, held to interval end, capped 60 s
        ]
        let durations = engine.zoneDurations(heartRate: samples.shuffled(), zones: zones, interval: interval)
        #expect(durations.seconds == [0, 60, 0, 20, 60])
        #expect(durations.total == 140)
    }
}

@Suite("Engine · Strain")
struct EngineStrainTests {
    let engine = EngineFixtures.engine
    let zones = EngineFixtures.zones(max: 190)

    func strain(_ workout: Workout, bpm: Double?, rest: Double? = 50, sex: BiologicalSex? = .male) -> WorkoutStrain {
        engine.workoutStrain(WorkoutStrainInput(workout: workout, heartRate: bpm.map { EngineFixtures.heartRate($0, for: workout) } ?? [],
                                                zones: zones, restingHeartRate: rest, sex: sex))
    }

    @Test func banisterCoefficients() {
        #expect(abs(DefaultScoreEngine.trimpPerMinute(reserve: 0.5, sex: .male) - 0.5 * 0.64 * exp(0.96)) < 1e-12)
        #expect(abs(DefaultScoreEngine.trimpPerMinute(reserve: 0.5, sex: .female) - 0.5 * 0.86 * exp(0.835)) < 1e-12)
        #expect(abs(DefaultScoreEngine.trimpPerMinute(reserve: 0.5, sex: nil) - 0.5 * 0.75 * exp(0.8975)) < 1e-12)
        #expect(DefaultScoreEngine.trimpPerMinute(reserve: -1, sex: .male) == 0)
        #expect(DefaultScoreEngine.trimpPerMinute(reserve: 2, sex: .male) == DefaultScoreEngine.trimpPerMinute(reserve: 1, sex: .male))
    }

    @Test func trimpFromHeartRateReserve() {
        let run = EngineFixtures.workout(duration: 3600)
        // HRr = (155 − 50) / (190 − 50) = 0.75 for 60 minutes.
        let s = strain(run, bpm: 155)
        #expect(abs(s.trainingLoad - 60 * 0.75 * 0.64 * exp(1.92 * 0.75)) < 0.01)
        #expect(s.value == DefaultScoreEngine.strain(forLoad: s.trainingLoad))
        #expect(s.zoneDurations.total == 3600)
    }

    @Test func strainScale() {
        #expect(DefaultScoreEngine.strain(forLoad: 0) == 0)
        #expect(DefaultScoreEngine.strain(forLoad: -5) == 0)
        #expect(DefaultScoreEngine.strain(forLoad: 120) == 63)
        #expect(DefaultScoreEngine.strain(forLoad: 10_000) == 100)
        let values = stride(from: 0.0, through: 600, by: 10).map(DefaultScoreEngine.strain(forLoad:))
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func harderAndLongerMeansMoreStrain() {
        let hour = EngineFixtures.workout(duration: 3600)
        let values = stride(from: 100.0, through: 185, by: 5).map { strain(hour, bpm: $0).trainingLoad }
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 < $1 })
        #expect(strain(EngineFixtures.workout(duration: 1800), bpm: 150).trainingLoad < strain(hour, bpm: 150).trainingLoad)
        // Same HR on a higher resting HR uses less of the reserve → less load.
        #expect(strain(hour, bpm: 150, rest: 65).trainingLoad < strain(hour, bpm: 150, rest: 45).trainingLoad)
    }

    @Test func liftingUsesTheSameMethod() {
        let lift = EngineFixtures.workout(kind: .strength, duration: 3000)
        let run = EngineFixtures.workout(kind: .run, duration: 3000)
        #expect(strain(lift, bpm: 125).trainingLoad == strain(run, bpm: 125).trainingLoad)
    }

    @Test func fallbacksWithoutHeartRateSamples() {
        let withAverage = EngineFixtures.workout(duration: 3600, averageHeartRate: 155)
        #expect(abs(strain(withAverage, bpm: nil).trainingLoad - strain(withAverage, bpm: 155).trainingLoad) < 0.5)
        let bare = EngineFixtures.workout(kind: .strength, duration: 3600)
        let assumed = strain(bare, bpm: nil, rest: nil, sex: nil)
        #expect(abs(assumed.trainingLoad - 60 * DefaultScoreEngine.trimpPerMinute(reserve: 0.45, sex: nil)) < 1e-9)
        #expect(assumed.zoneDurations.total == 0)
    }

    @Test func dailyStrainSaturatesAndSeparatesEverydayMovement() {
        let run = strain(EngineFixtures.workout(duration: 3600, activeEnergy: 700), bpm: 155)
        let lift = strain(EngineFixtures.workout(kind: .strength, duration: 3000, activeEnergy: 350), bpm: 125)
        let activity = DailyActivity(day: EngineFixtures.today, steps: 14_000, activeEnergyKilocalories: 1_350,
                                     basalEnergyKilocalories: nil, exerciseMinutes: 110, standHours: 12, goals: nil)
        let day = engine.dailyStrain(day: EngineFixtures.today, workouts: [run, lift], activity: activity)
        #expect(abs(day.trainingLoad - (run.trainingLoad + lift.trainingLoad + 300 * 0.07)) < 1e-9)
        #expect(day.everydayMovement == DefaultScoreEngine.strain(forLoad: 21))
        #expect(day.value >= max(run.value, lift.value))
        #expect(day.value < run.value + lift.value + day.everydayMovement)
        #expect(day.zoneDurations.total == run.zoneDurations.total + lift.zoneDurations.total)
        #expect(day.level == StrainLevel(strain: day.value))

        let rest = engine.dailyStrain(day: EngineFixtures.today, workouts: [], activity: nil)
        #expect(rest.value == 0 && rest.trainingLoad == 0)
    }
}

@Suite("Engine · Training load")
struct EngineTrainingLoadTests {
    let engine = EngineFixtures.engine
    let today = EngineFixtures.today

    func loads(_ value: (Int) -> Double, days: Int = 120) -> [LocalDay: Double] {
        Dictionary(uniqueKeysWithValues: (0..<days).map { (EngineFixtures.day(-$0), value($0)) })
    }

    @Test(arguments: [(0.0, TrainingLoadRisk.detraining), (0.79, .detraining), (0.8, .productive), (1.29, .productive),
                      (1.3, .caution), (1.5, .caution), (1.51, .high), (3, .high)])
    func riskBands(ratio: Double, risk: TrainingLoadRisk) {
        #expect(TrainingLoadRisk(ratio: ratio) == risk)
    }

    @Test func constantLoadIsBalanced() throws {
        let load = engine.trainingLoad(dailyLoads: loads { _ in 80 }, asOf: today, historyDays: 56)
        #expect(try #require(load.ratio) == 1)
        #expect(load.risk == .productive)
        #expect(load.history.count == 56)
        #expect(load.history.allSatisfy { $0.acute == 80 && $0.chronic == 80 })
    }

    @Test func recentSpikeIsHighRisk() throws {
        let load = engine.trainingLoad(dailyLoads: loads { $0 < 7 ? 200 : 60 }, asOf: today, historyDays: 56)
        #expect(try #require(load.ratio) > 1.5)
        #expect(load.risk == .high)
        #expect(load.acute > load.chronic)
    }

    @Test func taperIsDetraining() throws {
        let load = engine.trainingLoad(dailyLoads: loads { $0 < 10 ? 0 : 100 }, asOf: today, historyDays: 28)
        #expect(try #require(load.ratio) < 0.8)
        #expect(load.risk == .detraining)
    }

    @Test func emptyHistory() {
        let load = engine.trainingLoad(dailyLoads: [:], asOf: today, historyDays: 56)
        #expect(load.ratio == nil)
        #expect(load.risk == .detraining)
        #expect(load.history.count == 56)
        #expect(load.history.last?.day == today)
        #expect(load.history.first?.day == EngineFixtures.day(-55))
    }

    @Test func ewmaStep() {
        // One 70-load day after a zero history: acute = 70 × 2/8, chronic = 70 × 2/29.
        let load = engine.trainingLoad(dailyLoads: [today: 70, EngineFixtures.day(-60): 0], asOf: today, historyDays: 7)
        #expect(abs(load.acute - 70 * 0.25) < 1e-9)
        #expect(abs(load.chronic - 70 * 2 / 29) < 1e-9)
    }

    @Test func futureDaysAreIgnored() {
        var d = loads { _ in 50 }
        d[EngineFixtures.day(3)] = 1_000
        #expect(engine.trainingLoad(dailyLoads: d, asOf: today, historyDays: 56).ratio == 1)
    }
}
