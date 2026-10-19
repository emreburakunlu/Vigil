import Foundation

/// Raw Health data for a span of days, fetched once and reused for many summaries.
struct HealthDataBundle: Sendable {
    var nights: [SleepNight] = []
    var vitals: [DailyVitals] = []
    var activity: [DailyActivity] = []
    var workouts: [Workout] = []
    /// HR samples per workout id.
    var workoutHeartRate: [UUID: [MetricSample]] = [:]

    /// Fetches everything Vigil needs for `interval`.
    static func fetch(from source: any HealthDataSource, interval: DateInterval) async throws -> HealthDataBundle {
        async let nights = source.sleepNights(in: interval)
        async let vitals = source.dailyVitals(in: interval)
        async let activity = source.dailyActivity(in: interval)
        async let workouts = source.workouts(in: interval, kinds: nil)
        var bundle = try await HealthDataBundle(nights: nights, vitals: vitals, activity: activity, workouts: workouts)
        bundle.workoutHeartRate = try await heartRate(for: bundle.workouts, from: source)
        return bundle
    }

    /// Heart-rate samples for each workout, fetched a few at a time in parallel.
    /// `onEach` is called with the number of workouts finished so far.
    static func heartRate(for workouts: [Workout], from source: any HealthDataSource, maxConcurrent: Int = 6,
                          isolation: isolated (any Actor)? = #isolation,
                          onEach: (Int) -> Void = { _ in }) async throws -> [UUID: [MetricSample]] {
        try await withThrowingTaskGroup(of: (UUID, [MetricSample]).self) { group in
            var result: [UUID: [MetricSample]] = [:]
            var pending = workouts[...]
            func addNext() {
                guard let workout = pending.popFirst() else { return }
                group.addTask { (workout.id, try await source.heartRateSamples(in: workout.interval)) }
            }
            for _ in 0..<maxConcurrent { addNext() }
            while let (id, samples) = try await group.next() {
                result[id] = samples
                onEach(result.count)
                try Task.checkCancellation()
                addNext()
            }
            return result
        }
    }
}

/// Turns a `HealthDataBundle` into `DailySummary` values with a `ScoreEngine`. Pure.
struct SummaryBuilder: Sendable {
    var engine: any ScoreEngine
    var calendar: Calendar

    /// Builds summaries for `days` (ascending). Each day's baselines use only earlier days.
    func summaries(for days: [LocalDay], data: HealthDataBundle, settings: VigilSettings, now: Date) -> [DailySummary] {
        let primaryNights = data.nights.filter(\.isPrimary).sorted { $0.sleepEnd < $1.sleepEnd }
        let nightsByDay = Dictionary(primaryNights.map { ($0.day, $0) }, uniquingKeysWith: { _, b in b })
        let vitalsByDay = Dictionary(data.vitals.map { ($0.day, $0) }, uniquingKeysWith: { _, b in b })
        let activityByDay = Dictionary(data.activity.map { ($0.day, $0) }, uniquingKeysWith: { _, b in b })
        let workoutsByDay = Dictionary(grouping: data.workouts) { LocalDay($0.start, calendar: calendar) }
        let observedMax = data.workouts.compactMap(\.maxHeartRate).max()
        let zones = engine.heartRateZones(profile: settings.profile, settings: settings.heartRateZones,
                                          observedMaxHeartRate: observedMax, on: now)

        var strains: [LocalDay: DailyStrain] = [:]
        var result: [DailySummary] = []
        for day in days.sorted() {
            let history = BaselineHistory(vitals: data.vitals, nights: primaryNights, strains: Array(strains.values))
            let baselines = engine.baselines(on: day, history: history)
            let night = nightsByDay[day]
            let sleepScore = night.map { night in
                engine.sleepScore(SleepScoreInput(night: night, target: settings.goals.sleepTarget, baselines: baselines,
                                                  recentNights: primaryNights.filter { $0.day < day }.suffix(7)))
            }
            let workoutStrains = (workoutsByDay[day] ?? []).map { workout in
                engine.workoutStrain(WorkoutStrainInput(workout: workout, heartRate: data.workoutHeartRate[workout.id] ?? [],
                                                        zones: zones, restingHeartRate: vitalsByDay[day]?.restingHeartRate,
                                                        sex: settings.profile.sex))
            }
            let strain = engine.dailyStrain(day: day, workouts: workoutStrains, activity: activityByDay[day])
            let yesterday = day.adding(days: -1, calendar: calendar)
            let loadBeforeToday = strains.isEmpty ? nil : engine.trainingLoad(
                dailyLoads: strains.mapValues(\.trainingLoad), asOf: yesterday, historyDays: 1)
            strains[day] = strain
            let vitals = vitalsByDay[day]
            let hasRecoverySignal = vitals.map { !$0.recordedMetrics.isEmpty } ?? false
            let recovery = (hasRecoverySignal || night != nil)
                ? engine.recovery(RecoveryInput(day: day, vitals: vitals, sleep: night, sleepScore: sleepScore, baselines: baselines,
                                                previousDayStrain: strains[yesterday], trainingLoad: loadBeforeToday))
                : nil
            result.append(DailySummary(day: day, computedAt: now, engineVersion: engine.version, baselines: baselines,
                                       vitals: vitals, activity: activityByDay[day], sleepNightID: night?.id,
                                       sleepDuration: night?.asleepDuration, sleepScore: sleepScore, recovery: recovery,
                                       strain: strain))
        }
        return result
    }
}
