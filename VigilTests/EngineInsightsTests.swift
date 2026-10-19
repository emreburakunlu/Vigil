import Foundation
import Testing
@testable import Vigil

@Suite("Engine · Insights")
struct EngineInsightsTests {
    let engine = EngineFixtures.engine
    let today = EngineFixtures.today

    func summary(_ offset: Int, hrv: Double? = nil, sleepScore: Int? = nil, recovery: Int? = nil, strain: Int? = nil) -> DailySummary {
        let day = EngineFixtures.day(offset)
        return DailySummary(
            day: day, computedAt: TestSupport.referenceDate,
            vitals: hrv.map { DailyVitals(day: day, heartRateVariability: $0) },
            sleepScore: sleepScore.map(EngineFixtures.sleepScore),
            recovery: recovery.map { RecoveryScore(value: $0, band: RecoveryBand(percent: $0), factors: [], suggestion: .maintain,
                                                   message: "", suggestedStrain: 0...0, signalsUsed: 5, signalsTotal: 5) },
            strain: strain.map { DailyStrain(day: day, value: $0, level: StrainLevel(strain: $0), workouts: [], everydayMovement: 0,
                                             zoneDurations: ZoneDurations(), trainingLoad: Double($0)) })
    }

    func insights(nights: [SleepNight] = [], workouts: [Workout] = [], summaries: [DailySummary] = []) -> [Insight] {
        engine.insights(InsightInput(day: today, nights: nights, workouts: workouts, summaries: summaries))
    }

    /// Strength sessions at 18:30 every third day; nights after them `liftSleep`, others 7 h 40.
    func liftingFortnight(liftSleep: TimeInterval) -> (nights: [SleepNight], workouts: [Workout]) {
        let liftDays = Set(stride(from: -18, through: 0, by: 3))
        let workouts = liftDays.sorted().map {
            EngineFixtures.workout(kind: .strength, start: EngineFixtures.at(EngineFixtures.day($0), 18, 30), duration: 3_600)
        }
        let nights = (-20...0).map { offset in
            EngineFixtures.night(EngineFixtures.day(offset), asleep: liftDays.contains(offset - 1) ? liftSleep : 7 * 3600 + 40 * 60)
        }
        return (nights, workouts)
    }

    @Test func emptyInputHasNoInsights() {
        #expect(insights().isEmpty)
    }

    @Test func restDaySleep() throws {
        let data = liftingFortnight(liftSleep: 7 * 3600)
        let result = insights(nights: data.nights, workouts: data.workouts)
        let insight = try #require(result.first { $0.id == "sleep.restDayDuration.strength" })
        #expect(insight.text == "You sleep 40 min more on rest days than after lifting.")
        #expect(insight.domain == .sleep)
        #expect(!result.contains { $0.id == "sleep.restDayDuration.run" }) // no runs
    }

    @Test func smallSleepDifferenceIsNotAnInsight() {
        let data = liftingFortnight(liftSleep: 7 * 3600 + 30 * 60) // 10 min less
        #expect(!insights(nights: data.nights, workouts: data.workouts).contains { $0.id.hasPrefix("sleep.restDayDuration") })
    }

    @Test func trainingStreak() throws {
        let data = liftingFortnight(liftSleep: 7 * 3600)
        let insight = try #require(insights(workouts: data.workouts).first { $0.id == "training.weeklyStreak" })
        #expect(insight.text == "You've trained at least twice a week for 3 weeks in a row.")
    }

    @Test func hrvTrend() throws {
        let rising = (0..<14).map { summary(-13 + $0, hrv: 50 * pow(1.01, Double($0))) }
        let insight = try #require(insights(summaries: rising).first { $0.id == "recovery.hrvTrend" })
        #expect(insight.text == "Your HRV has risen 14% over the last 14 days.")
        let falling = (0..<14).map { summary(-13 + $0, hrv: 60 * pow(0.99, Double($0))) }
        #expect(insights(summaries: falling).first { $0.id == "recovery.hrvTrend" }?.text == "Your HRV has fallen 12% over the last 14 days.")
        let flat = (0..<14).map { summary(-13 + $0, hrv: $0.isMultiple(of: 2) ? 58 : 62) }
        #expect(!insights(summaries: flat).contains { $0.id == "recovery.hrvTrend" })
        #expect(!insights(summaries: Array(rising.suffix(9))).contains { $0.id == "recovery.hrvTrend" })
    }

    @Test func sleepStreak() throws {
        let summaries = (0..<10).map { summary(-9 + $0, sleepScore: $0 >= 5 ? 78 : 62) }
        let insight = try #require(insights(summaries: summaries).first { $0.id == "sleep.goodStreak" })
        #expect(insight.text == "5 nights in a row with a sleep score of 70 or more.")
        #expect(!insights(summaries: Array(summaries.prefix(9)) + [summary(0, sleepScore: 50)]).contains { $0.id == "sleep.goodStreak" })
    }

    @Test func recoveryAfterHeavyDays() throws {
        let summaries = (0..<28).map { i -> DailySummary in
            let offset = -27 + i
            let heavyYesterday = (offset - 1).isMultiple(of: 2)
            return summary(offset, recovery: heavyYesterday ? 45 : 65, strain: offset.isMultiple(of: 2) ? 80 : 30)
        }
        let insight = try #require(insights(summaries: summaries).first { $0.id == "recovery.afterHeavyDays" })
        #expect(insight.text == "Recovery averages 20 points lower the day after high-strain days.")
    }

    @Test func bedtimeSpreadAndEarlyDeepSleep() throws {
        let nights = (-13...0).map { offset -> SleepNight in
            let thisWeek = offset > -7
            let bedtime: Double = thisWeek ? (offset.isMultiple(of: 2) ? 240 : 330) : 300
            return EngineFixtures.night(EngineFixtures.day(offset), bedtime: bedtime, deepShare: bedtime < 300 ? 0.20 : 0.15)
        }
        let result = insights(nights: nights)
        let spread = try #require(result.first { $0.id == "sleep.bedtimeSpread" })
        #expect(spread.text.hasPrefix("Your bedtime varied by "))
        #expect(spread.text.hasSuffix("min this week, up from 0 min last week."))
        let deep = try #require(result.first { $0.id == "sleep.earlyBedtimeDeep" })
        #expect(deep.text == "Deep sleep is 33% higher on nights you're in bed before 23:00.")
    }

    @Test func lateWorkoutsAndSleepScore() throws {
        var workouts: [Workout] = [], summaries: [DailySummary] = [], nights: [SleepNight] = []
        for offset in -9...0 {
            let day = EngineFixtures.day(offset)
            let late = offset.isMultiple(of: 2)
            nights.append(EngineFixtures.night(day))
            summaries.append(summary(offset, sleepScore: late ? 70 : 82))
            // Night onset ≈ 23:10 the evening before; a late workout ends 21:30.
            let evening = EngineFixtures.at(day.adding(days: -1, calendar: EngineFixtures.calendar), late ? 20 : 7, 30)
            workouts.append(EngineFixtures.workout(start: evening, duration: 3_600))
        }
        let insight = try #require(insights(nights: nights, workouts: workouts, summaries: summaries).first { $0.id == "sleep.lateWorkout" })
        #expect(insight.text == "Your sleep score averages 12 points lower after workouts that end within 3 hours of bedtime.")
    }

    @Test func orderingIsDeterministic() {
        let data = liftingFortnight(liftSleep: 6 * 3600)
        let summaries = (0..<14).map { summary(-13 + $0, hrv: 50 * pow(1.02, Double($0)), sleepScore: 80) }
        let first = insights(nights: data.nights, workouts: data.workouts, summaries: summaries)
        let second = insights(nights: data.nights.shuffled(), workouts: data.workouts.shuffled(), summaries: summaries.shuffled())
        #expect(first == second)
        #expect(first.count >= 3)
        #expect(zip(first, first.dropFirst()).allSatisfy { $0.priority > $1.priority || ($0.priority == $1.priority && $0.id < $1.id) })
    }
}

@Suite("Engine · Performance")
struct EnginePerformanceTests {
    @Test func ninetyDaysComputeQuickly() {
        let calendar = EngineFixtures.calendar
        let days = (0..<120).map { EngineFixtures.day(-119 + $0) }
        var bundle = HealthDataBundle()
        for (i, day) in days.enumerated() {
            bundle.nights.append(EngineFixtures.night(day, bedtime: 280 + Double(i % 5) * 10, asleep: 7 * 3600 + Double(i % 7) * 600))
            bundle.vitals.append(DailyVitals(day: day, heartRateVariability: 55 + Double(i % 9), restingHeartRate: 53 + Double(i % 4),
                                             respiratoryRate: 14.5, wristTemperature: 36.4, oxygenSaturation: 97))
            bundle.activity.append(DailyActivity(day: day, steps: 9_000, activeEnergyKilocalories: 700, basalEnergyKilocalories: nil,
                                                 exerciseMinutes: 45, standHours: 11, goals: nil))
            if i % 2 == 0 {
                let w = EngineFixtures.workout(start: EngineFixtures.at(day, 7), duration: 3_000, distance: 9_000, activeEnergy: 600)
                bundle.workouts.append(w)
                bundle.workoutHeartRate[w.id] = EngineFixtures.heartRate(150, for: w)
            }
        }
        let builder = SummaryBuilder(engine: EngineFixtures.engine, calendar: calendar)
        let efforts = bundle.workouts.map { RunEffortInput(workout: $0, cumulativeDistance: EngineFixtures.timeline(start: $0.start, [(3_000, 3)], step: 1)) }
        let engine = EngineFixtures.engine
        let clock = ContinuousClock()
        var summaries: [DailySummary] = []
        let summaryTime = clock.measure {
            summaries = builder.summaries(for: Array(days.suffix(90)), data: bundle, settings: .default, now: TestSupport.referenceDate)
        }
        let restTime = clock.measure {
            _ = engine.personalBests(runs: efforts, asOf: TestSupport.referenceDate)
            _ = engine.insights(InsightInput(day: EngineFixtures.today, nights: bundle.nights, workouts: bundle.workouts, summaries: summaries))
            _ = engine.trainingLoad(dailyLoads: Dictionary(uniqueKeysWithValues: summaries.compactMap { s in s.strain.map { (s.day, $0.trainingLoad) } }),
                                    asOf: EngineFixtures.today, historyDays: 56)
            _ = engine.aerobicEfficiency(runs: bundle.workouts, endingOn: EngineFixtures.today, weeks: 13)
        }
        print("ENGINE-PERF summaries=\(summaryTime) bests+insights+load=\(restTime)")
        let elapsed = summaryTime + restTime
        #expect(summaries.count == 90)
        #expect(summaries.allSatisfy { $0.recovery != nil && $0.sleepScore != nil })
        // Debug build in the simulator; release on device is several times faster.
        #expect(elapsed < .seconds(1), "90-day engine pass took \(elapsed)")
    }
}
