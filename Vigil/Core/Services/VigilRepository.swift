import Foundation

/// The one API screens use to get data. Combines the `HealthDataSource`, the `ScoreEngine` and
/// the `DailySummaryStore` cache. Owner: orchestrator (screen agents request additions).
///
/// Usage from a view model:
/// ```swift
/// @MainActor @Observable final class TodayModel {
///     var overview: DayOverview?
///     func load(_ repo: VigilRepository, day: LocalDay) async {
///         overview = try? await repo.dayOverview(for: day)
///     }
/// }
/// ```
/// Phase 0 implementation is straightforward (no incremental caching beyond daily summaries);
/// method signatures are the contract.
@MainActor
final class VigilRepository {
    let dataSource: any HealthDataSource
    let engine: any ScoreEngine
    let settings: SettingsStore
    let summaries: DailySummaryStore
    let calendar: Calendar
    /// Injected clock (tests / mock scenarios).
    let now: @Sendable () -> Date

    init(dataSource: any HealthDataSource, engine: any ScoreEngine, settings: SettingsStore, summaries: DailySummaryStore,
         calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { .now }) {
        self.dataSource = dataSource
        self.engine = engine
        self.settings = settings
        self.summaries = summaries
        self.calendar = calendar
        self.now = now
    }

    var today: LocalDay { LocalDay(now(), calendar: calendar) }

    private var builder: SummaryBuilder { SummaryBuilder(engine: engine, calendar: calendar) }

    // MARK: Access

    /// User-facing Health access state (drives onboarding and the "access off" screen).
    func healthAccessState() async -> HealthAccessState {
        guard dataSource.isHealthDataAvailable else { return .unavailable }
        switch await dataSource.authorizationStatus() {
        case .unavailable: return .unavailable
        case .notDetermined: return .notDetermined
        case .requested:
            let interval = LocalDay.interval(from: today.adding(days: -30, calendar: calendar), through: today, calendar: calendar)
            let nights = (try? await dataSource.sleepNights(in: interval)) ?? []
            let workouts = (try? await dataSource.workouts(in: interval, kinds: nil)) ?? []
            let activity = (try? await dataSource.dailyActivity(in: interval)) ?? []
            return nights.isEmpty && workouts.isEmpty && activity.isEmpty ? .likelyDenied : .connected
        }
    }

    // MARK: Summaries

    /// Cached summary for `day`, recomputed when missing, stale (engine version) or for today.
    func summary(for day: LocalDay) async throws -> DailySummary {
        if day != today, let cached = summaries.summary(for: day), cached.engineVersion == engine.version {
            return cached
        }
        let interval = LocalDay.interval(from: day.adding(days: -Baseline.windowDays, calendar: calendar), through: day, calendar: calendar)
        let data = try await HealthDataBundle.fetch(from: dataSource, interval: interval)
        let built = builder.summaries(for: [day], data: data, settings: settings.settings, now: now())
        let summary = built.last ?? DailySummary(day: day, computedAt: now())
        try? summaries.upsert(summary)
        return summary
    }

    /// Current heart-rate zones.
    func heartRateZones(observedMaxHeartRate: Double? = nil) -> HeartRateZones {
        engine.heartRateZones(profile: settings.settings.profile, settings: settings.settings.heartRateZones,
                              observedMaxHeartRate: observedMaxHeartRate, on: now())
    }

    // MARK: Today

    /// Everything on the Today tab.
    func dayOverview(for day: LocalDay) async throws -> DayOverview {
        let summary = try await summary(for: day)
        let interval = day.interval(in: calendar)
        let night = try await primaryNight(endingOn: day)
        let workouts = try await dataSource.workouts(in: interval, kinds: nil)
        let strainByID = Dictionary((summary.strain?.workouts ?? []).map { ($0.workoutID, $0) }, uniquingKeysWith: { a, _ in a })
        let readings = try await vitalReadings(for: day, vitals: summary.vitals, baselines: summary.baselines)
        let missing = HealthMetric.vitals.filter { summary.vitals?[$0] == nil }
        let completeness: DataCompleteness = summary.vitals == nil && night == nil
            ? .none
            : (missing.isEmpty ? .complete : .partial(missing: missing))
        return DayOverview(day: day, recovery: summary.recovery, sleepNight: night, sleepScore: summary.sleepScore,
                           strain: summary.strain, activity: summary.activity, vitals: readings,
                           workouts: workouts.map { WorkoutSummary(workout: $0, strain: strainByID[$0.id]) },
                           weekly: try await weeklyProgress(endingOn: day), completeness: completeness,
                           updatedAt: summary.computedAt)
    }

    /// Vitals vs. baseline with 9-day sparklines.
    func vitalReadings(for day: LocalDay, vitals: DailyVitals?, baselines: PersonalBaselines?) async throws -> [VitalReading] {
        let trendInterval = LocalDay.interval(from: day.adding(days: -8, calendar: calendar), through: day, calendar: calendar)
        let history = try await dataSource.dailyVitals(in: trendInterval)
        return HealthMetric.vitals.map { metric in
            let value = vitals?[metric]
            let baseline = baselines?[metric]
            let delta = value.flatMap { v in baseline.map { v - $0.mean } }
            let percent = delta.flatMap { d in baseline.flatMap { $0.mean != 0 ? d / $0.mean * 100 : nil } }
            let trend = history.compactMap { v in v[metric].map { MetricSample(date: v.day.startDate(in: calendar), value: $0) } }
            return VitalReading(metric: metric, value: value, baseline: baseline, delta: delta, deltaPercent: percent,
                                status: baseline?.status(of: value) ?? (value == nil ? .missing : .noBaseline), trend: trend)
        }
    }

    // MARK: Sleep

    /// The primary night that ended on `day`.
    func primaryNight(endingOn day: LocalDay) async throws -> SleepNight? {
        let interval = day.interval(in: calendar)
        return try await dataSource.sleepNights(in: interval).last(where: \.isPrimary)
    }

    /// Night detail (Sleep tab "Last night" and Sleep Night screen).
    func sleepNightDetail(endingOn day: LocalDay) async throws -> SleepNightDetail? {
        guard let night = try await primaryNight(endingOn: day) else { return nil }
        let summary = try await summary(for: day)
        let score = summary.sleepScore ?? engine.sleepScore(SleepScoreInput(night: night, target: settings.settings.goals.sleepTarget,
                                                                              baselines: summary.baselines, recentNights: []))
        let readings = try await vitalReadings(for: day, vitals: summary.vitals, baselines: summary.baselines)
        let typical: [SleepStage: ClosedRange<Double>] = [.awake: 0.01...0.05, .rem: 0.20...0.25, .core: 0.45...0.55, .deep: 0.13...0.23]
        return SleepNightDetail(night: night, score: score, vitals: readings, typicalStageShare: typical)
    }

    /// Asleep time and score per night for `start...end` (calendar, trends).
    func sleepHistory(from start: LocalDay, through end: LocalDay) async throws -> [SleepNightSummary] {
        let nights = try await dataSource.sleepNights(in: LocalDay.interval(from: start, through: end, calendar: calendar)).filter(\.isPrimary)
        let byDay = Dictionary(nights.map { ($0.day, $0) }, uniquingKeysWith: { _, b in b })
        let cached = Dictionary(summaries.summaries(from: start, through: end).map { ($0.day, $0) }, uniquingKeysWith: { _, b in b })
        let target = settings.settings.goals.sleepTarget
        return LocalDay.range(from: start, through: min(end, today), calendar: calendar).map { day in
            let night = byDay[day]
            let score = cached[day]?.sleepScore?.value
                ?? night.map { engine.sleepScore(SleepScoreInput(night: $0, target: target, baselines: nil, recentNights: [])).value }
            return SleepNightSummary(day: day, asleep: night?.asleepDuration, score: score)
        }
    }

    /// Sleep debt over the 7 nights ending on `day`.
    func sleepDebt(endingOn day: LocalDay) async throws -> SleepDebt {
        let interval = LocalDay.interval(from: day.adding(days: -6, calendar: calendar), through: day, calendar: calendar)
        let nights = try await dataSource.sleepNights(in: interval)
        return engine.sleepDebt(nights: nights, target: settings.settings.goals.sleepTarget, endingOn: day)
    }

    // MARK: Metrics

    /// Series for the shared Metric detail screen.
    func metricSeries(_ metric: HealthMetric, range: MetricRange, endingOn day: LocalDay) async throws -> MetricSeries {
        let interval = range.interval(endingOn: day, calendar: calendar)
        let samples = try await dataSource.samples(of: metric, in: interval)
        let buckets = Dictionary(grouping: samples) { sample in
            calendar.dateInterval(of: range.bucket, for: sample.date) ?? DateInterval(start: sample.date, duration: 0)
        }
        let points = buckets.map { bucket, values in
            let numbers = values.map(\.value)
            return TimeSeriesPoint(interval: bucket, value: numbers.reduce(0, +) / Double(numbers.count),
                                   minimum: numbers.min(), maximum: numbers.max())
        }.sorted { $0.interval.start < $1.interval.start }
        let values = samples.map(\.value)
        let baselineHistory = try await dataSource.dailyVitals(in: LocalDay.interval(
            from: day.adding(days: -Baseline.windowDays, calendar: calendar), through: day.adding(days: -1, calendar: calendar), calendar: calendar))
        let sources = Dictionary(grouping: samples.compactMap(\.sourceName), by: { $0 }).max { $0.value.count < $1.value.count }?.key
        return MetricSeries(metric: metric, range: range, interval: interval, points: points,
                            average: values.isEmpty ? nil : values.reduce(0, +) / Double(values.count),
                            minimum: values.min(), maximum: values.max(),
                            baseline: DefaultScoreEngine.baseline(of: baselineHistory.compactMap { $0[metric] }),
                            latest: samples.last, sourceName: sources)
    }

    // MARK: Training

    /// Workouts of one kind with strain, newest first.
    func workouts(_ kind: WorkoutKind, in interval: DateInterval) async throws -> [WorkoutSummary] {
        let workouts = try await dataSource.workouts(in: interval, kinds: [kind])
        let zones = heartRateZones()
        var result: [WorkoutSummary] = []
        for workout in workouts.reversed() {
            let hr = try await dataSource.heartRateSamples(in: workout.interval)
            let strain = engine.workoutStrain(WorkoutStrainInput(workout: workout, heartRate: hr, zones: zones, restingHeartRate: nil))
            result.append(WorkoutSummary(workout: workout, strain: strain))
        }
        return result
    }

    /// Run detail. Throws `HealthDataError.notFound` for unknown ids.
    func runDetail(id: UUID) async throws -> RunDetail {
        guard let workout = try await dataSource.workout(id: id) else { throw HealthDataError.notFound }
        let details = try await dataSource.runDetails(for: id)
        let zones = heartRateZones()
        let heartRate = details.heartRate.isEmpty ? try await dataSource.heartRateSamples(in: workout.interval) : details.heartRate
        let strain = engine.workoutStrain(WorkoutStrainInput(workout: workout, heartRate: heartRate, zones: zones, restingHeartRate: nil))
        let bests = engine.personalBests(runs: [RunEffortInput(workout: workout, cumulativeDistance: details.cumulativeDistance)], asOf: now())
        let allBests = try await personalBests()
        let setHere = bests.filter { candidate in allBests.contains { $0.category == candidate.category && $0.workoutID == workout.id } }
        return RunDetail(workout: workout, details: details, splits: engine.splits(details: details, units: settings.settings.units),
                         zones: zones, zoneDurations: strain.zoneDurations, strain: strain, personalBests: setHere)
    }

    /// Lift detail. Throws `HealthDataError.notFound` for unknown ids.
    func liftDetail(id: UUID) async throws -> LiftDetail {
        guard let workout = try await dataSource.workout(id: id) else { throw HealthDataError.notFound }
        let heartRate = try await dataSource.heartRateSamples(in: workout.interval)
        let zones = heartRateZones()
        let strain = engine.workoutStrain(WorkoutStrainInput(workout: workout, heartRate: heartRate, zones: zones, restingHeartRate: nil))
        return LiftDetail(workout: workout, heartRate: heartRate, zones: zones, zoneDurations: strain.zoneDurations, strain: strain)
    }

    /// Rolling 7-day progress ending on `day`.
    func weeklyProgress(endingOn day: LocalDay) async throws -> WeeklyProgress {
        let start = day.adding(days: -6, calendar: calendar)
        let interval = LocalDay.interval(from: start, through: day, calendar: calendar)
        let workouts = try await dataSource.workouts(in: interval, kinds: [.run, .strength])
        let nights = try await dataSource.sleepNights(in: interval).filter(\.isPrimary)
        let days = LocalDay.range(from: start, through: day, calendar: calendar)
        let runs = workouts.filter { $0.kind == .run }
        let lifts = workouts.filter { $0.kind == .strength }
        let goals = settings.settings.goals
        return WeeklyProgress(
            startDay: start, endDay: day,
            runDistanceMeters: runs.reduce(0) { $0 + ($1.distanceMeters ?? 0) },
            runGoalMeters: goals.weeklyRunDistanceMeters,
            runCount: runs.count,
            runDuration: runs.reduce(0) { $0 + $1.duration },
            dailyRunDistanceMeters: days.map { d in runs.filter { LocalDay($0.start, calendar: calendar) == d }.reduce(0) { $0 + ($1.distanceMeters ?? 0) } },
            liftSessions: lifts.count,
            liftGoal: goals.weeklyLiftSessions,
            liftDuration: lifts.reduce(0) { $0 + $1.duration },
            liftEnergyKilocalories: lifts.reduce(0) { $0 + ($1.activeEnergyKilocalories ?? 0) },
            dailyTrainingKinds: days.map { d in Set(workouts.filter { LocalDay($0.start, calendar: calendar) == d }.map(\.kind)) },
            averageSleep: nights.isEmpty ? nil : nights.reduce(0) { $0 + $1.asleepDuration } / Double(nights.count),
            sleepTarget: goals.sleepTarget
        )
    }

    /// Acute vs. chronic training load ending on `day` with `historyDays` of chart history.
    func trainingLoad(endingOn day: LocalDay, historyDays: Int = 56) async throws -> TrainingLoad {
        let first = day.adding(days: -(historyDays + 28), calendar: calendar)
        let cached = summaries.summaries(from: first, through: day)
        var loads = Dictionary(cached.compactMap { s in s.strain.map { (s.day, $0.trainingLoad) } }, uniquingKeysWith: { _, b in b })
        if let todayStrain = try await summary(for: day).strain { loads[day] = todayStrain.trainingLoad }
        return engine.trainingLoad(dailyLoads: loads, asOf: day, historyDays: historyDays)
    }

    /// Personal bests across the last year of runs.
    func personalBests() async throws -> [PersonalBest] {
        let interval = DateInterval(start: calendar.date(byAdding: .year, value: -1, to: now()) ?? now(), end: now())
        let runs = try await dataSource.workouts(in: interval, kinds: [.run])
        return engine.personalBests(runs: runs.map { RunEffortInput(workout: $0, cumulativeDistance: []) }, asOf: now())
    }

    /// Rule-based insights for `day`.
    func insights(for day: LocalDay) async throws -> [Insight] {
        let start = day.adding(days: -27, calendar: calendar)
        let interval = LocalDay.interval(from: start, through: day, calendar: calendar)
        return engine.insights(InsightInput(day: day,
                                            nights: try await dataSource.sleepNights(in: interval),
                                            workouts: try await dataSource.workouts(in: interval, kinds: nil),
                                            summaries: summaries.summaries(from: start, through: day)))
    }
}
