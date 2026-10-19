import Foundation
@testable import Vigil

/// Synthetic inputs for the engine suites (UTC calendar, reference day Mon 19 Oct 2026).
enum EngineFixtures {
    static let calendar = TestSupport.utc
    static let engine = DefaultScoreEngine(calendar: TestSupport.utc)
    static let today = LocalDay(year: 2026, month: 10, day: 19)

    static func day(_ offset: Int) -> LocalDay { today.adding(days: offset, calendar: calendar) }

    /// Date at `hour:minute` on `day` (UTC).
    static func at(_ day: LocalDay, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: day.startDate(in: calendar))!
    }

    /// A primary night waking on `day`. `bedtime` is minutes after 18:00 the evening before.
    static func night(_ day: LocalDay, bedtime: Double = 300, asleep: TimeInterval = 8 * 3600,
                      awake: TimeInterval = 15 * 60, deepShare: Double = 0.18, remShare: Double = 0.22,
                      interruptions: Int = 1, latency: TimeInterval = 10 * 60, hasStages: Bool = true) -> SleepNight {
        let evening = at(day.adding(days: -1, calendar: calendar), 18)
        let inBedStart = evening.addingTimeInterval(bedtime * 60)
        let sleepStart = inBedStart.addingTimeInterval(latency)
        let sleepEnd = sleepStart.addingTimeInterval(asleep + awake)
        let total = asleep + awake
        var durations = SleepStageDurations()
        durations.awake = awake
        if hasStages {
            durations.deep = deepShare * total
            durations.rem = remShare * total
            durations.core = asleep - durations.deep - durations.rem
        } else {
            durations.unspecified = asleep
        }
        return SleepNight(id: "\(day.isoString)-primary", day: day, isPrimary: true, inBedStart: inBedStart,
                          inBedEnd: sleepEnd.addingTimeInterval(5 * 60), sleepStart: sleepStart, sleepEnd: sleepEnd,
                          segments: [], stageDurations: durations, interruptions: interruptions, sources: [])
    }

    static func baseline(_ mean: Double, _ sd: Double, count: Int = 30) -> Baseline {
        Baseline(mean: mean, standardDeviation: sd, sampleCount: count)
    }

    /// Established baselines: HRV 61 ms (σ_ln 0.1), RHR 55 ± 2, RR 14.6 ± 0.3, temp 36.4 ± 0.1.
    static func baselines(count: Int = 30) -> PersonalBaselines {
        PersonalBaselines(day: today, metrics: [
            .heartRateVariability: baseline(61, 6.1, count: count),
            .restingHeartRate: baseline(55, 2, count: count),
            .respiratoryRate: baseline(14.6, 0.3, count: count),
            .wristTemperature: baseline(36.4, 0.1, count: count),
        ])
    }

    static func vitals(hrv: Double? = 61, rhr: Double? = 55, rr: Double? = 14.6, temp: Double? = 36.4) -> DailyVitals {
        DailyVitals(day: today, heartRateVariability: hrv, restingHeartRate: rhr, respiratoryRate: rr, wristTemperature: temp)
    }

    static func sleepScore(_ value: Int) -> SleepScore {
        SleepScore(value: value, band: SleepScoreBand(score: value), contributors: [], targetDifference: 0)
    }

    static func recoveryInput(vitals: DailyVitals? = vitals(), sleep: Int? = 75, baselines: PersonalBaselines = baselines(),
                              previousDayStrain: DailyStrain? = nil, trainingLoad: TrainingLoad? = nil) -> RecoveryInput {
        RecoveryInput(day: today, vitals: vitals, sleep: nil, sleepScore: sleep.map(sleepScore), baselines: baselines,
                      previousDayStrain: previousDayStrain, trainingLoad: trainingLoad)
    }

    static func zones(max: Int = 190) -> HeartRateZones {
        var profile = UserProfile.default
        profile.estimatesMaxHeartRate = false
        profile.manualMaxHeartRate = max
        return engine.heartRateZones(profile: profile, settings: .default, observedMaxHeartRate: nil, on: TestSupport.referenceDate)
    }

    static func workout(kind: WorkoutKind = .run, start: Date = TestSupport.referenceDate, duration: TimeInterval = 3600,
                        distance: Double? = nil, averageHeartRate: Double? = nil, activeEnergy: Double? = nil,
                        id: UUID = UUID()) -> Workout {
        Workout(id: id, kind: kind, activityName: kind == .run ? "Outdoor Run" : "Traditional Strength Training", title: nil,
                start: start, end: start.addingTimeInterval(duration), duration: duration,
                activeEnergyKilocalories: activeEnergy, totalEnergyKilocalories: nil,
                averageHeartRate: averageHeartRate, maxHeartRate: nil, distanceMeters: distance,
                elevationGainMeters: nil, elevationLossMeters: nil,
                source: DataSourceInfo(name: "Test", bundleIdentifier: nil), heartRateSource: nil, isIndoor: false, hasRoute: false)
    }

    /// Constant heart rate sampled every 5 s across `workout`.
    static func heartRate(_ bpm: Double, for workout: Workout, every step: TimeInterval = 5) -> [MetricSample] {
        stride(from: 0, to: workout.duration, by: step).map { MetricSample(date: workout.start.addingTimeInterval($0), value: bpm) }
    }

    /// Cumulative distance sampled every `step` s from piecewise constant speeds [(seconds, m/s)].
    static func timeline(start: Date = TestSupport.referenceDate, _ pieces: [(TimeInterval, Double)], step: TimeInterval = 5) -> [MetricSample] {
        var samples = [MetricSample(date: start, value: 0)]
        var t = 0.0, d = 0.0
        for (duration, speed) in pieces {
            var elapsed = 0.0
            while elapsed < duration - 1e-9 {
                let dt = min(step, duration - elapsed)
                t += dt; d += speed * dt; elapsed += dt
                samples.append(MetricSample(date: start.addingTimeInterval(t), value: d))
            }
        }
        return samples
    }
}
