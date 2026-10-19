import Foundation

/// Default `ScoreEngine`. Owner: engine agent.
///
/// Phase 0: deterministic PLACEHOLDER formulas that return plausible values so screens have
/// something to show. Baselines, zones, zone durations, training load, sleep debt and splits are
/// already real; sleep score, recovery, strain, personal bests and insights must be replaced.
struct DefaultScoreEngine: ScoreEngine {
    var calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    var version: Int { DailySummary.currentEngineVersion }

    // MARK: Baselines

    func baselines(on day: LocalDay, history: BaselineHistory) -> PersonalBaselines {
        let windowStart = day.adding(days: -Baseline.windowDays, calendar: calendar)
        let inWindow: (LocalDay) -> Bool = { $0 >= windowStart && $0 < day }
        var metrics: [HealthMetric: Baseline] = [:]
        let vitals = history.vitals.filter { inWindow($0.day) }
        for metric in HealthMetric.vitals {
            if let baseline = Self.baseline(of: vitals.compactMap { $0[metric] }) {
                metrics[metric] = baseline
            }
        }
        let nights = history.nights.filter { $0.isPrimary && inWindow($0.day) }
        let strains = history.strains.filter { inWindow($0.day) }
        return PersonalBaselines(
            day: day,
            metrics: metrics,
            sleepDuration: Self.baseline(of: nights.map(\.asleepDuration)),
            bedtimeMinutes: Self.baseline(of: nights.map { minutesAfterSixPM($0.sleepStart) }),
            dailyStrain: Self.baseline(of: strains.map { Double($0.value) })
        )
    }

    /// Mean and sample standard deviation; nil for an empty list.
    static func baseline(of values: [Double]) -> Baseline? {
        guard !values.isEmpty else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.count > 1
            ? values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
            : 0
        return Baseline(mean: mean, standardDeviation: variance.squareRoot(), sampleCount: values.count)
    }

    private func minutesAfterSixPM(_ date: Date) -> Double {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        return minutes >= 18 * 60 ? minutes - 18 * 60 : minutes + 6 * 60
    }

    // MARK: Sleep (PLACEHOLDER)

    func sleepScore(_ input: SleepScoreInput) -> SleepScore {
        let night = input.night
        let durationScore = Self.clampScore(night.asleepDuration / max(input.target, 1) * 100)
        let efficiencyScore = Self.clampScore(night.efficiency * 100)
        let deepScore = Self.clampScore(night.stageDurations.share(of: .deep) / 0.18 * 100)
        let remScore = Self.clampScore(night.stageDurations.share(of: .rem) / 0.22 * 100)
        let interruptionsScore = Self.clampScore(100 - Double(night.interruptions) * 8)
        let contributors = [
            SleepScoreContributor(kind: .duration, score: durationScore, weight: 0.4),
            SleepScoreContributor(kind: .efficiency, score: efficiencyScore, weight: 0.2),
            SleepScoreContributor(kind: .deepSleep, score: deepScore, weight: 0.15),
            SleepScoreContributor(kind: .remSleep, score: remScore, weight: 0.15),
            SleepScoreContributor(kind: .interruptions, score: interruptionsScore, weight: 0.1),
        ]
        let value = Self.clampScore(contributors.reduce(0) { $0 + Double($1.score) * $1.weight })
        return SleepScore(value: value, band: SleepScoreBand(score: value), contributors: contributors,
                          targetDifference: night.asleepDuration - input.target)
    }

    // MARK: Recovery (PLACEHOLDER)

    func recovery(_ input: RecoveryInput) -> RecoveryScore {
        var factors: [RecoveryFactor] = []
        func factor(_ kind: RecoveryFactorKind, _ metric: HealthMetric, weight: Double) {
            let value = input.vitals?[metric]
            let baseline = input.baselines[metric]?.mean
            var points = 0
            if let value, let baseline, baseline != 0 {
                let relative = (value - baseline) / baseline
                let signed = metric.higherIsBetter == false ? -relative : relative
                points = Int((signed * weight).rounded())
            }
            factors.append(RecoveryFactor(kind: kind, value: value, baseline: baseline, points: points, isAvailable: value != nil))
        }
        factor(.heartRateVariability, .heartRateVariability, weight: 120)
        factor(.restingHeartRate, .restingHeartRate, weight: 80)
        let sleepValue = input.sleepScore.map { Double($0.value) }
        factors.append(RecoveryFactor(kind: .sleep, value: sleepValue, baseline: 75,
                                      points: sleepValue.map { Int((($0 - 75) / 2).rounded()) } ?? 0,
                                      isAvailable: sleepValue != nil))
        factor(.respiratoryRate, .respiratoryRate, weight: -30)
        factor(.wristTemperature, .wristTemperature, weight: -20)

        let value = Self.clampScore(60 + Double(factors.reduce(0) { $0 + $1.points }))
        let band = RecoveryBand(percent: value)
        let suggestion: ReadinessSuggestion = switch band {
        case .green: .push
        case .yellow: .maintain
        case .red: .takeItEasy
        }
        let message: String = switch suggestion {
        case .push: "Recovered well. Good day for intervals."
        case .maintain: "Moderately recovered. Keep it steady today."
        case .takeItEasy: "Your body needs rest. Keep it light today."
        }
        let low = max(0, value - 25), high = min(100, value - 3)
        return RecoveryScore(value: value, band: band, factors: factors, suggestion: suggestion, message: message,
                             suggestedStrain: low...max(low, high),
                             signalsUsed: factors.filter(\.isAvailable).count, signalsTotal: factors.count)
    }

    // MARK: Zones (real)

    func heartRateZones(profile: UserProfile, settings: HeartRateZoneSettings, observedMaxHeartRate: Double?, on date: Date) -> HeartRateZones {
        let age = profile.age(on: date, calendar: calendar) ?? 35
        let estimated = Int((208 - 0.7 * Double(age)).rounded())
        var maxHR = profile.estimatesMaxHeartRate ? estimated : (profile.manualMaxHeartRate ?? estimated)
        var source: HeartRateZoneSource = profile.estimatesMaxHeartRate ? .estimated : .manualMaxHeartRate
        if profile.estimatesMaxHeartRate, let observedMaxHeartRate, Int(observedMaxHeartRate) > maxHR {
            maxHR = Int(observedMaxHeartRate)
        }
        var lowerBounds = [0.5, 0.6, 0.7, 0.8, 0.9].map { Int((Double(maxHR) * $0).rounded()) }
        if settings.usesCustomZones, settings.customUpperBounds.count == 4,
           settings.customUpperBounds == settings.customUpperBounds.sorted() {
            lowerBounds = [lowerBounds[0]] + settings.customUpperBounds.map { $0 + 1 }
            source = .custom
        }
        let zones = (0..<5).map { i in
            HeartRateZone(number: i + 1, name: HeartRateZone.names[i], lowerBound: lowerBounds[i],
                          upperBound: i < 4 ? lowerBounds[i + 1] - 1 : maxHR)
        }
        return HeartRateZones(maxHeartRate: maxHR, source: source, zones: zones)
    }

    func zoneDurations(heartRate: [MetricSample], zones: HeartRateZones, interval: DateInterval) -> ZoneDurations {
        let samples = heartRate.filter { interval.contains($0.date) }.sorted { $0.date < $1.date }
        var seconds = Array(repeating: 0.0, count: 5)
        for (i, sample) in samples.enumerated() {
            let next = i + 1 < samples.count ? samples[i + 1].date : interval.end
            let duration = min(60, max(0, next.timeIntervalSince(sample.date)))
            if let zone = zones.zone(for: sample.value) { seconds[zone - 1] += duration }
        }
        return ZoneDurations(seconds: seconds)
    }

    // MARK: Strain (PLACEHOLDER)

    func workoutStrain(_ input: WorkoutStrainInput) -> WorkoutStrain {
        let durations = zoneDurations(heartRate: input.heartRate, zones: input.zones, interval: input.workout.interval)
        let weights = [1.0, 2.0, 3.0, 4.0, 5.0]
        var load = zip(durations.seconds, weights).reduce(0) { $0 + $1.0 / 60 * $1.1 }
        if load == 0 { load = input.workout.duration / 60 * 1.5 } // no HR: duration-based guess
        let value = Self.clampScore(100 * (1 - exp(-load / 180)))
        return WorkoutStrain(workoutID: input.workout.id, value: value, level: StrainLevel(strain: value),
                             trainingLoad: load, zoneDurations: durations)
    }

    func dailyStrain(day: LocalDay, workouts: [WorkoutStrain], activity: DailyActivity?) -> DailyStrain {
        let everyday = Self.clampScore((activity?.activeEnergyKilocalories ?? 0) / 40)
        let load = workouts.reduce(0) { $0 + $1.trainingLoad } + Double(everyday) * 2
        let value = Self.clampScore(100 * (1 - exp(-load / 220)))
        return DailyStrain(day: day, value: value, level: StrainLevel(strain: value), workouts: workouts,
                           everydayMovement: everyday,
                           zoneDurations: workouts.reduce(ZoneDurations()) { $0 + $1.zoneDurations },
                           trainingLoad: load)
    }

    // MARK: Training load (real)

    func trainingLoad(dailyLoads: [LocalDay: Double], asOf day: LocalDay, historyDays: Int) -> TrainingLoad {
        func mean(endingOn end: LocalDay, length: Int) -> Double {
            (0..<length).reduce(0) { $0 + (dailyLoads[end.adding(days: -$1, calendar: calendar)] ?? 0) } / Double(length)
        }
        let history = (0..<max(1, historyDays)).reversed().map { offset -> TrainingLoadPoint in
            let d = day.adding(days: -offset, calendar: calendar)
            return TrainingLoadPoint(day: d, acute: mean(endingOn: d, length: 7), chronic: mean(endingOn: d, length: 28))
        }
        let acute = mean(endingOn: day, length: 7)
        let chronic = mean(endingOn: day, length: 28)
        let ratio: Double? = chronic > 0 ? acute / chronic : nil
        return TrainingLoad(day: day, acute: acute, chronic: chronic, ratio: ratio,
                            risk: TrainingLoadRisk(ratio: ratio ?? 0), history: history)
    }

    // MARK: Sleep debt (real)

    func sleepDebt(nights: [SleepNight], target: TimeInterval, endingOn day: LocalDay) -> SleepDebt {
        let primary = Dictionary(nights.filter(\.isPrimary).map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let entries = (0..<7).reversed().map { offset -> SleepDebtNight in
            let d = day.adding(days: -offset, calendar: calendar)
            let asleep = primary[d]?.asleepDuration
            return SleepDebtNight(day: d, asleep: asleep, shortfall: asleep.map { max(0, target - $0) } ?? 0)
        }
        return SleepDebt(endingOn: day, target: target, total: entries.reduce(0) { $0 + $1.shortfall },
                         nights: entries, nightsRecorded: entries.filter { $0.asleep != nil }.count)
    }

    // MARK: Personal bests (PLACEHOLDER: whole-run average pace, no best-effort search)

    func personalBests(runs: [RunEffortInput], asOf: Date) -> [PersonalBest] {
        let newCutoff = asOf.addingTimeInterval(-7 * 86_400)
        var bests: [PersonalBest] = []
        for category in PersonalBestCategory.allCases {
            let candidates: [PersonalBest] = runs.compactMap { run in
                guard let distance = run.workout.distanceMeters, distance > 0 else { return nil }
                if let target = category.distanceMeters {
                    guard distance >= target else { return nil }
                    let time = run.workout.duration * target / distance
                    return PersonalBest(category: category, duration: time, distanceMeters: target, date: run.workout.start,
                                        workoutID: run.workout.id, isNew: run.workout.start >= newCutoff)
                }
                return PersonalBest(category: category, duration: nil, distanceMeters: distance, date: run.workout.start,
                                    workoutID: run.workout.id, isNew: run.workout.start >= newCutoff)
            }
            let best = category == .longestRun
                ? candidates.max { $0.distanceMeters < $1.distanceMeters }
                : candidates.min { ($0.duration ?? .infinity) < ($1.duration ?? .infinity) }
            if let best { bests.append(best) }
        }
        return bests
    }

    // MARK: Splits (real)

    func splits(details: RunDetails, units: UnitSystem) -> [RunSplit] {
        SplitCalculator.splits(details: details, units: units)
    }

    // MARK: Insights (PLACEHOLDER)

    func insights(_ input: InsightInput) -> [Insight] {
        let nights = input.nights.filter(\.isPrimary).suffix(7)
        guard nights.count >= 3 else { return [] }
        let starts = nights.map { minutesAfterSixPM($0.sleepStart) }
        let spread = (starts.max() ?? 0) - (starts.min() ?? 0)
        return [Insight(id: "sleep.bedtimeSpread", domain: .sleep,
                        text: "Your bedtime varied by \(Int(spread)) min over the last \(nights.count) nights.", priority: 1)]
    }

    // MARK: Helpers

    static func clampScore(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(100, max(0, value)).rounded())
    }
}
