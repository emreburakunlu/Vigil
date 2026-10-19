import Foundation
import Testing
@testable import Vigil

@Suite("Engine · Sleep score")
struct EngineSleepTests {
    let engine = EngineFixtures.engine
    let today = EngineFixtures.today
    let target: TimeInterval = 8 * 3600

    func previousNights(_ count: Int, asleep: TimeInterval = 8 * 3600, bedtimes: [Double]? = nil) -> [SleepNight] {
        (1...count).map { i in
            EngineFixtures.night(EngineFixtures.day(-i), bedtime: bedtimes?[(i - 1) % bedtimes!.count] ?? 300, asleep: asleep)
        }
    }

    func score(_ night: SleepNight, recent: [SleepNight] = []) -> SleepScore {
        engine.sleepScore(SleepScoreInput(night: night, target: target, baselines: nil, recentNights: recent))
    }

    func contributor(_ kind: SleepScoreContributorKind, _ s: SleepScore) -> SleepScoreContributor? {
        s.contributors.first { $0.kind == kind }
    }

    @Test func idealNightScoresHigh() throws {
        let s = score(EngineFixtures.night(today), recent: previousNights(6))
        #expect(s.value >= 95)
        #expect(s.band == .great)
        #expect(s.contributors.map(\.kind) == SleepScoreContributorKind.allCases)
        #expect(abs(s.contributors.reduce(0) { $0 + $1.weight } - 1) < 1e-9)
        #expect(s.targetDifference == 0)
    }

    @Test func totalIsWeightedSumOfSubScores() {
        let nights = [EngineFixtures.night(today, asleep: 6.5 * 3600, awake: 40 * 60, deepShare: 0.09, remShare: 0.15, interruptions: 5),
                      EngineFixtures.night(today), EngineFixtures.night(today, asleep: 5 * 3600, hasStages: false)]
        for night in nights {
            let s = score(night, recent: previousNights(4, bedtimes: [240, 330, 290]))
            let expected = Int(s.contributors.reduce(0) { $0 + Double($1.score) * $1.weight }.rounded())
            #expect(s.value == expected)
            #expect(abs(s.contributors.reduce(0) { $0 + $1.weight } - 1) < 1e-9)
        }
    }

    @Test func durationBoundaries() throws {
        let full = try #require(contributor(.duration, score(EngineFixtures.night(today, asleep: target))))
        let over = try #require(contributor(.duration, score(EngineFixtures.night(today, asleep: target + 3600))))
        let sixty = try #require(contributor(.duration, score(EngineFixtures.night(today, asleep: target * 0.6))))
        let eighty = try #require(contributor(.duration, score(EngineFixtures.night(today, asleep: target * 0.8))))
        #expect(full.score == 100)
        #expect(over.score == 100)
        #expect(sixty.score == 0)
        #expect(eighty.score == 50)
    }

    @Test func moreSleepNeverLowersTheScore() {
        let values = stride(from: 4.0, through: 9.0, by: 0.25).map { score(EngineFixtures.night(today, asleep: $0 * 3600)).value }
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(values.first! < values.last!)
    }

    @Test func sleepDebtRaisesTonightsNeed() throws {
        let rested = try #require(contributor(.duration, score(EngineFixtures.night(today), recent: previousNights(6))))
        let indebted = try #require(contributor(.duration, score(EngineFixtures.night(today), recent: previousNights(6, asleep: 6 * 3600))))
        #expect(rested.score == 100)
        #expect(indebted.score < 100)
        // 6 nights × 2 h short → 12 h debt → need = 8 h + min(1 h, 3 h) = 9 h.
        #expect(engine.sleepNeed(target: target, previousNights: previousNights(6, asleep: 6 * 3600)) == 9 * 3600)
    }

    @Test func noStagesDropsDeepAndREM() {
        let s = score(EngineFixtures.night(today, hasStages: false), recent: previousNights(3))
        #expect(contributor(.deepSleep, s) == nil)
        #expect(contributor(.remSleep, s) == nil)
        #expect(abs(s.contributors.reduce(0) { $0 + $1.weight } - 1) < 1e-9)
    }

    @Test func consistencyNeedsThreeNightsAndRewardsRegularity() throws {
        #expect(contributor(.consistency, score(EngineFixtures.night(today), recent: previousNights(1))) == nil)
        let regular = try #require(contributor(.consistency, score(EngineFixtures.night(today), recent: previousNights(6))))
        let irregular = try #require(contributor(.consistency, score(EngineFixtures.night(today),
                                                                      recent: previousNights(6, bedtimes: [180, 420, 240, 400]))))
        #expect(regular.score == 100)
        #expect(irregular.score < 50)
    }

    @Test func interruptionsAndAwakeTimePenalise() throws {
        let calm = try #require(contributor(.interruptions, score(EngineFixtures.night(today, awake: 10 * 60, interruptions: 1))))
        let restless = try #require(contributor(.interruptions, score(EngineFixtures.night(today, awake: 30 * 60, interruptions: 4))))
        #expect(calm.score == 100)
        #expect(restless.score == 100 - 18 - 20)
    }

    @Test func stageScoreBoundaries() {
        let deep = DefaultScoreEngine.Sleep.deepRange
        #expect(DefaultScoreEngine.stageScore(share: 0, range: deep, penalizesExcess: false) == 0)
        #expect(DefaultScoreEngine.stageScore(share: deep.lowerBound, range: deep, penalizesExcess: false) == 100)
        #expect(DefaultScoreEngine.stageScore(share: 0.4, range: deep, penalizesExcess: false) == 100)
        let rem = DefaultScoreEngine.Sleep.remRange
        #expect(abs(DefaultScoreEngine.stageScore(share: 0.27, range: rem, penalizesExcess: true) - 92) < 1e-9)
        #expect(DefaultScoreEngine.stageScore(share: 0.6, range: rem, penalizesExcess: true) == 60)
    }

    @Test func sleepDebtSumsShortfall() {
        let nights = (0..<7).map { EngineFixtures.night(EngineFixtures.day(-$0), asleep: $0 == 3 ? 9 * 3600 : 7 * 3600) }
            .filter { $0.day != EngineFixtures.day(-5) }
        let debt = engine.sleepDebt(nights: nights, target: target, endingOn: today)
        #expect(debt.nights.count == 7)
        #expect(debt.nightsRecorded == 6)
        #expect(debt.total == 5 * 3600) // five recorded nights 1 h short, one night over target, one missing
        #expect(debt.nights.first?.day == EngineFixtures.day(-6))
    }
}

@Suite("Engine · Baselines")
struct EngineBaselineTests {
    let engine = EngineFixtures.engine
    let today = EngineFixtures.today

    @Test func windowExcludesTodayAndOlderDays() throws {
        let vitals = (0...40).map { DailyVitals(day: EngineFixtures.day(-$0), restingHeartRate: $0 == 0 ? 90 : ($0 > 30 ? 30 : 55)) }
        let baselines = engine.baselines(on: today, history: BaselineHistory(vitals: vitals))
        let rhr = try #require(baselines[.restingHeartRate])
        #expect(rhr.mean == 55)
        #expect(rhr.sampleCount == 30)
    }

    @Test func hrvUsesLogDomain() throws {
        let values: [Double] = [40, 50, 60, 70, 80, 90, 100, 45, 55, 65]
        let vitals = values.enumerated().map { DailyVitals(day: EngineFixtures.day(-1 - $0.offset), heartRateVariability: $0.element) }
        let hrv = try #require(engine.baselines(on: today, history: BaselineHistory(vitals: vitals))[.heartRateVariability])
        let logs = values.map { log($0) }
        let mu = logs.reduce(0, +) / Double(logs.count)
        #expect(abs(hrv.mean - exp(mu)) < 1e-9) // geometric mean, below the arithmetic mean
        #expect(hrv.mean < values.reduce(0, +) / Double(values.count))
        let sigma = EngineMath.standardDeviation(logs)!
        #expect(abs(hrv.standardDeviation / hrv.mean - sigma) < 1e-9)
    }

    @Test func robustBaselineDropsArtefacts() throws {
        let values: [Double] = [54, 55, 56, 55, 54, 56, 55, 55, 120]
        let robust = try #require(DefaultScoreEngine.robustBaseline(of: values))
        #expect(abs(robust.mean - 55) < 1e-9)
        #expect(robust.sampleCount == 9)
    }

    @Test func calibratingUntilSevenDays() throws {
        let vitals = (1...6).map { DailyVitals(day: EngineFixtures.day(-$0), heartRateVariability: 60, restingHeartRate: 55) }
        let six = engine.baselines(on: today, history: BaselineHistory(vitals: vitals))
        #expect(six[.heartRateVariability]?.isEstablished == false)
        let seven = engine.baselines(on: today, history: BaselineHistory(vitals: vitals + [DailyVitals(day: EngineFixtures.day(-7), heartRateVariability: 62, restingHeartRate: 54)]))
        #expect(seven[.heartRateVariability]?.isEstablished == true)
    }

    @Test func emptyHistoryHasNoBaselines() {
        let baselines = engine.baselines(on: today, history: BaselineHistory())
        #expect(baselines.metrics.isEmpty)
        #expect(baselines.sleepDuration == nil)
    }
}
