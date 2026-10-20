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
///
/// ## Summary cache rules
/// - A cached summary is **usable** when its engine version and settings fingerprint match and either
///   it is *settled* (computed at least `settleDelay` after its day ended), or it was built in this
///   process since the last `invalidateRecent()` and is younger than `recentSummaryTTL`.
/// - Every build goes through `buildSummaries(from:through:data:)`, which seeds the builder with the cached
///   strains of the days before, so a one-day build, a refresh and the import agree for the same day.
/// - Workouts are deduplicated with `WorkoutDeduplication` everywhere they feed scores, counts or lists.
@MainActor
final class VigilRepository {
    let dataSource: any HealthDataSource
    let engine: any ScoreEngine
    let settings: SettingsStore
    let summaries: DailySummaryStore
    let calendar: Calendar
    /// Injected clock (tests / mock scenarios).
    let now: @Sendable () -> Date
    let personalBestCache: PersonalBestCache

    /// Summaries of days that haven't settled yet (today, yesterday until 06:00) are reused this long.
    static let recentSummaryTTL: TimeInterval = 10 * 60
    /// A day's summary is final once computed this long after the day ended (late watch syncs, morning wake).
    static let settleDelay: TimeInterval = 6 * 3600
    /// Days of workouts scanned for the observed max heart rate.
    static let observedMaxHeartRateDays = 365

    init(dataSource: any HealthDataSource, engine: any ScoreEngine, settings: SettingsStore, summaries: DailySummaryStore,
         calendar: Calendar = .autoupdatingCurrent, now: @escaping @Sendable () -> Date = { .now },
         personalBestCache: PersonalBestCache = PersonalBestCache(fileURL: nil)) {
        self.dataSource = dataSource
        self.engine = engine
        self.settings = settings
        self.summaries = summaries
        self.calendar = calendar
        self.now = now
        self.personalBestCache = personalBestCache
    }

    var today: LocalDay { LocalDay(now(), calendar: calendar) }

    // MARK: Caches

    /// Unsettled days built in this process since the last invalidation.
    private var freshBuilds: Set<LocalDay> = []
    /// Bumped by `resetCaches()`; builds that started before a reset don't write their results.
    private(set) var cacheGeneration = 0
    /// `.some(value)` once the observed max HR is known for this launch.
    private var observedMaxHeartRateCache: Double??
    private var observedMaxHeartRateTask: Task<Double?, any Error>?
    /// Health access was confirmed in this session (F13).
    private var accessConfirmed = false

    /// New Health data arrived (or the day / foreground changed): unsettled summaries are rebuilt on next read.
    func invalidateRecent() {
        freshBuilds.removeAll()
    }

    /// "Delete local data": drop every in-memory and on-disk cache owned by the repository and stop
    /// in-flight builds from writing.
    func resetCaches() {
        cacheGeneration += 1
        freshBuilds.removeAll()
        personalBestCache.reset()
        observedMaxHeartRateCache = nil
        observedMaxHeartRateTask = nil
        accessConfirmed = false
    }

    private var builder: SummaryBuilder { SummaryBuilder(engine: engine, calendar: calendar) }

    // MARK: Access

    /// User-facing Health access state (drives onboarding and the "access off" screen).
    ///
    /// HealthKit hides read denial, so "likely denied" means: permission was requested and none of activity,
    /// sleep, workouts or characteristics/body mass returned anything in the last 90 days. Errors (e.g. a
    /// locked device) are not evidence of denial and resolve to `.connected` (not cached).
    /// `.connected` is cached for the session; `resetCaches()` clears it.
    func healthAccessState() async -> HealthAccessState {
        guard dataSource.isHealthDataAvailable else { return .unavailable }
        switch await dataSource.authorizationStatus() {
        case .unavailable: return .unavailable
        case .notDetermined: return .notDetermined
        case .requested:
            if accessConfirmed { return .connected }
            let interval = LocalDay.interval(from: today.adding(days: -89, calendar: calendar), through: today, calendar: calendar)
            let source = dataSource
            var sawError = false
            let checks: [@Sendable () async throws -> Bool] = [
                { try await !source.dailyActivity(in: interval).isEmpty },
                { try await !source.sleepNights(in: interval).isEmpty },
                { try await !source.workouts(in: interval, kinds: nil).isEmpty },
                {
                    let c = try await source.characteristics()
                    return c.dateOfBirth != nil || c.biologicalSex != nil || c.latestBodyMass != nil
                },
                { try await !source.bodyMassSamples(in: interval).isEmpty },
            ]
            for check in checks {
                do {
                    if try await check() {
                        accessConfirmed = true
                        return .connected
                    }
                } catch {
                    sawError = true
                }
            }
            return sawError ? .connected : .likelyDenied
        }
    }

    // MARK: Heart-rate zones

    /// Highest workout max HR over the last 365 days, read once per launch. The one observed-max source
    /// used by summaries, details and `heartRateZones()`.
    func observedMaxHeartRate() async -> Double? {
        if let cached = observedMaxHeartRateCache { return cached }
        let task: Task<Double?, any Error>
        if let running = observedMaxHeartRateTask {
            task = running
        } else {
            let source = dataSource
            let interval = DateInterval(start: now().addingTimeInterval(-Double(Self.observedMaxHeartRateDays) * 86_400), end: now())
            task = Task { try await source.workouts(in: interval, kinds: nil).compactMap(\.maxHeartRate).max() }
            observedMaxHeartRateTask = task
        }
        do {
            let value = try await task.value
            if observedMaxHeartRateTask == task {
                observedMaxHeartRateCache = .some(value)
                observedMaxHeartRateTask = nil
            }
            return value
        } catch {
            if observedMaxHeartRateTask == task { observedMaxHeartRateTask = nil }
            return nil
        }
    }

    /// Current heart-rate zones. With `nil`, uses the launch's observed max HR once `observedMaxHeartRate()` ran.
    func heartRateZones(observedMaxHeartRate: Double? = nil) -> HeartRateZones {
        engine.heartRateZones(profile: settings.settings.profile, settings: settings.settings.heartRateZones,
                              observedMaxHeartRate: observedMaxHeartRate ?? (observedMaxHeartRateCache ?? nil), on: now())
    }

    /// Zones after loading the observed max HR.
    func currentHeartRateZones() async -> HeartRateZones {
        heartRateZones(observedMaxHeartRate: await observedMaxHeartRate())
    }

    /// Fingerprint of the settings summaries are computed with right now.
    func currentSettingsFingerprint() async -> String {
        let zones = await currentHeartRateZones()
        return SummarySettingsFingerprint.make(settings: settings.settings, zones: zones)
    }

    // MARK: Summaries

    /// Whether a cached stamp can be returned without rebuilding (see the type documentation).
    func isUsable(_ stamp: DailySummaryStore.Stamp, fingerprint: String) -> Bool {
        guard stamp.engineVersion == engine.version, stamp.settingsFingerprint == fingerprint else { return false }
        let settled = stamp.day.adding(days: 1, calendar: calendar).startDate(in: calendar).addingTimeInterval(Self.settleDelay)
        if stamp.computedAt >= settled { return true }
        return freshBuilds.contains(stamp.day) && abs(now().timeIntervalSince(stamp.computedAt)) < Self.recentSummaryTTL
    }

    /// Cached summary for `day`, rebuilt when missing or not usable.
    func summary(for day: LocalDay) async throws -> DailySummary {
        let fingerprint = await currentSettingsFingerprint()
        if let stamp = summaries.stamps(from: day, through: day).first, isUsable(stamp, fingerprint: fingerprint),
           let cached = summaries.summary(for: day) {
            return cached
        }
        return try await buildSummaries(from: day, through: day).last ?? DailySummary(day: day, computedAt: now())
    }

    /// Builds summaries for `first...last` (fetching the bundle unless given), writes them to the cache
    /// and returns them. The only place summaries are computed; also used by `HistoryImportService`.
    /// Results of a build that started before `resetCaches()` are returned but not written.
    @discardableResult
    func buildSummaries(from first: LocalDay, through last: LocalDay, data: HealthDataBundle? = nil) async throws -> [DailySummary] {
        guard first <= last else { return [] }
        let generation = cacheGeneration
        let bundle: HealthDataBundle
        if let data {
            bundle = data
        } else {
            let interval = LocalDay.interval(from: first.adding(days: -Baseline.windowDays, calendar: calendar), through: last, calendar: calendar)
            bundle = try await HealthDataBundle.fetch(from: dataSource, interval: interval, heartRateFrom: first.startDate(in: calendar))
        }
        let zones = await currentHeartRateZones()
        let currentSettings = settings.settings
        let fingerprint = SummarySettingsFingerprint.make(settings: currentSettings, zones: zones)
        let previousStrains = summaries.strains(from: first.adding(days: -SummaryBuilder.strainHistoryDays, calendar: calendar),
                                                through: first.adding(days: -1, calendar: calendar))
        let built = await builder.build(for: LocalDay.range(from: first, through: last, calendar: calendar), data: bundle,
                                        settings: currentSettings, now: now(), previousStrains: previousStrains,
                                        zones: zones, settingsFingerprint: fingerprint)
        guard generation == cacheGeneration else { return built }
        do {
            try summaries.upsert(built)
            freshBuilds.formUnion(built.map(\.day))
        } catch {
            print("Vigil: failed to cache summaries: \(error)")
        }
        return built
    }

    /// Makes sure every day in `start...end` (clamped to today) has a usable cached summary, building the
    /// missing/stale ones in one batch. Prefer `ensuredSummaries(from:through:)`, which also returns them
    /// (no second decode through `summaries.summaries(from:through:)`).
    func ensureSummaries(from start: LocalDay, through end: LocalDay) async throws {
        _ = try await ensuredSummaries(from: start, through: end)
    }

    /// Same as `ensureSummaries`, returning the usable summaries of `start...end`, oldest first. Charts that
    /// read many days of cached scores call this so they never show gaps just because those days were never opened.
    func ensuredSummaries(from start: LocalDay, through end: LocalDay) async throws -> [DailySummary] {
        let end = min(end, today)
        guard start <= end else { return [] }
        let fingerprint = await currentSettingsFingerprint()
        let usable = Set(summaries.stamps(from: start, through: end).filter { isUsable($0, fingerprint: fingerprint) }.map(\.day))
        let days = LocalDay.range(from: start, through: end, calendar: calendar)
        guard let firstMissing = days.first(where: { !usable.contains($0) }) else {
            return summaries.summaries(from: start, through: end)
        }
        let before = firstMissing > start
            ? summaries.summaries(from: start, through: firstMissing.adding(days: -1, calendar: calendar))
            : []
        return before + (try await buildSummaries(from: firstMissing, through: end))
    }

    /// Strain for one workout: the cached summary's value when it is current, otherwise computed.
    private func strain(for workout: Workout, heartRate: [MetricSample], zones: HeartRateZones, fingerprint: String) -> WorkoutStrain {
        let day = LocalDay(workout.start, calendar: calendar)
        let cached = summaries.summary(for: day)
        if let cached, cached.engineVersion == engine.version, cached.settingsFingerprint == fingerprint,
           let strain = cached.strain?.workouts.first(where: { $0.workoutID == workout.id }) {
            return strain
        }
        return engine.workoutStrain(WorkoutStrainInput(workout: workout, heartRate: heartRate, zones: zones,
                                                       restingHeartRate: cached?.vitals?.restingHeartRate,
                                                       sex: settings.settings.profile.sex))
    }

    /// Workouts in `interval` (optionally of `kinds`), deduplicated.
    func dedupedWorkouts(in interval: DateInterval, kinds: Set<WorkoutKind>?) async throws -> [Workout] {
        WorkoutDeduplication.deduplicated(try await dataSource.workouts(in: interval, kinds: kinds))
    }

    // MARK: Today

    /// Everything on the Today tab. One fetch each of nights, vitals and workouts for `[day-8, day]`.
    func dayOverview(for day: LocalDay) async throws -> DayOverview {
        let source = dataSource
        let window = LocalDay.interval(from: day.adding(days: -8, calendar: calendar), through: day, calendar: calendar)
        async let workoutsResult = source.workouts(in: window, kinds: nil)
        async let summaryResult = summary(for: day)
        let nights = try await source.sleepNights(in: window)
        async let vitalsResult = source.dailyVitals(in: window, nights: nights)
        let workouts = WorkoutDeduplication.deduplicated(try await workoutsResult)
        let summary = try await summaryResult
        let history = try await vitalsResult

        let dayInterval = day.interval(in: calendar)
        let night = nights.last { $0.isPrimary && dayInterval.contains($0.sleepEnd) }
        let strainByID = Dictionary((summary.strain?.workouts ?? []).map { ($0.workoutID, $0) }, uniquingKeysWith: { a, _ in a })
        let readings = vitalReadings(vitals: summary.vitals, baselines: summary.baselines, history: history)
        let missing = HealthMetric.vitals.filter { summary.vitals?[$0] == nil }
        let completeness: DataCompleteness = summary.vitals == nil && night == nil
            ? .none
            : (missing.isEmpty ? .complete : .partial(missing: missing))
        return DayOverview(day: day, recovery: summary.recovery, sleepNight: night, sleepScore: summary.sleepScore,
                           strain: summary.strain, activity: summary.activity, vitals: readings,
                           workouts: workouts.filter { dayInterval.contains($0.start) }
                               .map { WorkoutSummary(workout: $0, strain: strainByID[$0.id]) },
                           weekly: weeklyProgress(endingOn: day, workouts: workouts, nights: nights), completeness: completeness,
                           updatedAt: summary.computedAt)
    }

    /// Vitals vs. baseline with 9-day sparklines.
    func vitalReadings(for day: LocalDay, vitals: DailyVitals?, baselines: PersonalBaselines?) async throws -> [VitalReading] {
        let trendInterval = LocalDay.interval(from: day.adding(days: -8, calendar: calendar), through: day, calendar: calendar)
        let history = try await dataSource.dailyVitals(in: trendInterval)
        return vitalReadings(vitals: vitals, baselines: baselines, history: history)
    }

    /// Vitals vs. baseline from an already-fetched 9-day vitals history.
    func vitalReadings(vitals: DailyVitals?, baselines: PersonalBaselines?, history: [DailyVitals]) -> [VitalReading] {
        HealthMetric.vitals.map { metric in
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

    /// Primary nights (with bedtime and wake times) for `start...end`, oldest first.
    /// `sleepHistory` only carries asleep time and score, so the bedtime/wake-time consistency trend needs this.
    func primarySleepNights(from start: LocalDay, through end: LocalDay) async throws -> [SleepNight] {
        try await dataSource
            .sleepNights(in: LocalDay.interval(from: start, through: end, calendar: calendar))
            .filter(\.isPrimary)
    }

    /// Night detail (Sleep tab "Last night" and Sleep Night screen). One nights + one vitals fetch.
    func sleepNightDetail(endingOn day: LocalDay) async throws -> SleepNightDetail? {
        let source = dataSource
        let window = LocalDay.interval(from: day.adding(days: -8, calendar: calendar), through: day, calendar: calendar)
        let nights = try await source.sleepNights(in: window)
        let dayInterval = day.interval(in: calendar)
        guard let night = nights.last(where: { $0.isPrimary && dayInterval.contains($0.sleepEnd) }) else { return nil }
        async let vitalsResult = source.dailyVitals(in: window, nights: nights)
        let summary = try await summary(for: day)
        let history = try await vitalsResult
        let score = summary.sleepScore ?? engine.sleepScore(SleepScoreInput(night: night, target: settings.settings.goals.sleepTarget,
                                                                              baselines: summary.baselines, recentNights: []))
        let readings = vitalReadings(vitals: summary.vitals, baselines: summary.baselines, history: history)
        let typical: [SleepStage: ClosedRange<Double>] = [.awake: 0.01...0.05, .rem: 0.20...0.25, .core: 0.45...0.55, .deep: 0.13...0.23]
        return SleepNightDetail(night: night, score: score, vitals: readings, typicalStageShare: typical)
    }

    /// Asleep time and score per night for `start...end` (calendar, trends), from the summary cache, so
    /// today's entry matches "Last night".
    func sleepHistory(from start: LocalDay, through end: LocalDay) async throws -> [SleepNightSummary] {
        sleepNightSummaries(from: start, through: end, summaries: try await ensuredSummaries(from: start, through: end))
    }

    /// `sleepHistory` plus the primary nights of the same range, fetched concurrently (Sleep trends).
    func sleepTrend(from start: LocalDay, through end: LocalDay) async throws -> (summaries: [SleepNightSummary], nights: [SleepNight]) {
        let source = dataSource
        async let nightsResult = source.sleepNights(in: LocalDay.interval(from: start, through: end, calendar: calendar))
        let cached = try await ensuredSummaries(from: start, through: end)
        let nights = try await nightsResult.filter(\.isPrimary)
        return (sleepNightSummaries(from: start, through: end, summaries: cached), nights)
    }

    private func sleepNightSummaries(from start: LocalDay, through end: LocalDay, summaries: [DailySummary]) -> [SleepNightSummary] {
        let byDay = Dictionary(summaries.map { ($0.day, $0) }, uniquingKeysWith: { _, b in b })
        return LocalDay.range(from: start, through: min(end, today), calendar: calendar).map { day in
            SleepNightSummary(day: day, asleep: byDay[day]?.sleepDuration, score: byDay[day]?.sleepScore?.value)
        }
    }

    /// Sleep debt over the 7 nights ending on `day`.
    func sleepDebt(endingOn day: LocalDay) async throws -> SleepDebt {
        let interval = LocalDay.interval(from: day.adding(days: -6, calendar: calendar), through: day, calendar: calendar)
        let nights = try await dataSource.sleepNights(in: interval)
        return engine.sleepDebt(nights: nights, target: settings.settings.goals.sleepTarget, endingOn: day)
    }

    // MARK: Metrics

    /// Series for the shared Metric detail screen. The baseline comes from the day's cached summary
    /// (same as Today); only uncached days compute it from 30 days of vitals.
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
        let baseline: Baseline?
        if !HealthMetric.vitals.contains(metric) {
            baseline = nil
        } else if let cached = summaries.summary(for: day)?.baselines {
            baseline = cached[metric]
        } else {
            let history = try await dataSource.dailyVitals(in: LocalDay.interval(
                from: day.adding(days: -Baseline.windowDays, calendar: calendar), through: day.adding(days: -1, calendar: calendar),
                calendar: calendar))
            baseline = DefaultScoreEngine.baseline(of: history.compactMap { $0[metric] })
        }
        let sources = Dictionary(grouping: samples.compactMap(\.sourceName), by: { $0 }).max { $0.value.count < $1.value.count }?.key
        return MetricSeries(metric: metric, range: range, interval: interval, points: points,
                            average: values.isEmpty ? nil : values.reduce(0, +) / Double(values.count),
                            minimum: values.min(), maximum: values.max(),
                            baseline: baseline, latest: samples.last, sourceName: sources)
    }

    // MARK: Training

    /// Workouts of one kind, newest first, deduplicated. `strain` comes from the cached day summaries
    /// (nil when the day isn't cached yet); no heart-rate reads.
    func workouts(_ kind: WorkoutKind, in interval: DateInterval) async throws -> [WorkoutSummary] {
        let workouts = try await dedupedWorkouts(in: interval, kinds: [kind])
        guard let first = workouts.first, let last = workouts.last else { return [] }
        let cached = summaries.summaries(from: LocalDay(first.start, calendar: calendar), through: LocalDay(last.start, calendar: calendar))
        let strainByID = Dictionary(cached.flatMap { $0.strain?.workouts ?? [] }.map { ($0.workoutID, $0) }, uniquingKeysWith: { a, _ in a })
        return workouts.reversed().map { WorkoutSummary(workout: $0, strain: strainByID[$0.id]) }
    }

    /// The GPS route of a run (empty for indoor runs or when no route was recorded).
    /// Used by the Train list's mini route previews; `runDetail(id:)` is the full-screen source.
    func trainRoute(for workoutID: UUID) async -> [RouteLocation] {
        (try? await dataSource.route(for: workoutID)) ?? []
    }

    /// Run detail. Throws `HealthDataError.notFound` for unknown ids.
    /// "Personal bests set here" is filled only once the personal-best cache is warm (after Progress →
    /// Running scanned the year once), so opening a run never triggers a full scan.
    func runDetail(id: UUID) async throws -> RunDetail {
        guard let workout = try await dataSource.workout(id: id) else { throw HealthDataError.notFound }
        let source = dataSource
        async let detailsResult = source.runDetails(for: id)
        let zones = await currentHeartRateZones()
        let fingerprint = SummarySettingsFingerprint.make(settings: settings.settings, zones: zones)
        let details = try await detailsResult
        let heartRate = details.heartRate.isEmpty ? try await dataSource.heartRateSamples(in: workout.interval) : details.heartRate
        let strain = strain(for: workout, heartRate: heartRate, zones: zones, fingerprint: fingerprint)
        if personalBestCache.efforts(for: id) == nil {
            personalBestCache.store([id: engine.personalBests(runs: [RunEffortInput(workout: workout, cumulativeDistance: details.cumulativeDistance)],
                                                              asOf: now())])
        }
        let setHere = personalBestCache.warm ? try await personalBests().filter { $0.workoutID == id } : []
        return RunDetail(workout: workout, details: details, splits: engine.splits(details: details, units: settings.settings.units),
                         zones: zones, zoneDurations: strain.zoneDurations, strain: strain, personalBests: setHere)
    }

    /// Lift detail. Throws `HealthDataError.notFound` for unknown ids.
    func liftDetail(id: UUID) async throws -> LiftDetail {
        guard let workout = try await dataSource.workout(id: id) else { throw HealthDataError.notFound }
        let source = dataSource
        async let heartRateResult = source.heartRateSamples(in: workout.interval)
        let zones = await currentHeartRateZones()
        let fingerprint = SummarySettingsFingerprint.make(settings: settings.settings, zones: zones)
        let heartRate = try await heartRateResult
        let strain = strain(for: workout, heartRate: heartRate, zones: zones, fingerprint: fingerprint)
        return LiftDetail(workout: workout, heartRate: heartRate, zones: zones, zoneDurations: strain.zoneDurations, strain: strain)
    }

    /// Rolling 7-day progress ending on `day`.
    func weeklyProgress(endingOn day: LocalDay) async throws -> WeeklyProgress {
        let source = dataSource
        let interval = LocalDay.interval(from: day.adding(days: -6, calendar: calendar), through: day, calendar: calendar)
        async let workoutsResult = source.workouts(in: interval, kinds: [.run, .strength])
        let nights = try await source.sleepNights(in: interval)
        return weeklyProgress(endingOn: day, workouts: WorkoutDeduplication.deduplicated(try await workoutsResult), nights: nights)
    }

    /// Rolling 7-day progress from already-fetched (deduplicated) workouts and nights; anything outside
    /// the 7 days is ignored.
    func weeklyProgress(endingOn day: LocalDay, workouts allWorkouts: [Workout], nights allNights: [SleepNight]) -> WeeklyProgress {
        let start = day.adding(days: -6, calendar: calendar)
        let interval = LocalDay.interval(from: start, through: day, calendar: calendar)
        let workouts = allWorkouts.filter { interval.contains($0.start) && ($0.kind == .run || $0.kind == .strength) }
        let nights = allNights.filter { $0.isPrimary && interval.contains($0.sleepEnd) }
        let days = LocalDay.range(from: start, through: day, calendar: calendar)
        let workoutDays = workouts.map { LocalDay($0.start, calendar: calendar) }
        let runs = workouts.filter { $0.kind == .run }
        let lifts = workouts.filter { $0.kind == .strength }
        let goals = settings.settings.goals
        return WeeklyProgress(
            startDay: start, endDay: day,
            runDistanceMeters: runs.reduce(0) { $0 + ($1.distanceMeters ?? 0) },
            runGoalMeters: goals.weeklyRunDistanceMeters,
            runCount: runs.count,
            runDuration: runs.reduce(0) { $0 + $1.duration },
            dailyRunDistanceMeters: days.map { d in
                zip(workouts, workoutDays).filter { $0.0.kind == .run && $0.1 == d }.reduce(0) { $0 + ($1.0.distanceMeters ?? 0) }
            },
            liftSessions: lifts.count,
            liftGoal: goals.weeklyLiftSessions,
            liftDuration: lifts.reduce(0) { $0 + $1.duration },
            liftEnergyKilocalories: lifts.reduce(0) { $0 + ($1.activeEnergyKilocalories ?? 0) },
            dailyTrainingKinds: days.map { d in Set(zip(workouts, workoutDays).filter { $0.1 == d }.map(\.0.kind)) },
            averageSleep: nights.isEmpty ? nil : nights.reduce(0) { $0 + $1.asleepDuration } / Double(nights.count),
            sleepTarget: goals.sleepTarget
        )
    }

    /// Acute vs. chronic training load ending on `day` with `historyDays` of chart history.
    func trainingLoad(endingOn day: LocalDay, historyDays: Int = 56) async throws -> TrainingLoad {
        let first = day.adding(days: -(historyDays + 28), calendar: calendar)
        let cached = try await ensuredSummaries(from: first, through: day)
        let loads = Dictionary(cached.compactMap { s in s.strain.map { (s.day, $0.trainingLoad) } }, uniquingKeysWith: { _, b in b })
        return engine.trainingLoad(dailyLoads: loads, asOf: day, historyDays: historyDays)
    }

    /// Personal bests across the last year of runs. Each run's distance timeline is read once ever
    /// (persisted in `PersonalBestCache`), four at a time, off the main actor.
    func personalBests() async throws -> [PersonalBest] {
        let interval = DateInterval(start: calendar.date(byAdding: .year, value: -1, to: now()) ?? now(), end: now())
        let runs = try await dataSource.workouts(in: interval, kinds: [.run])
        let missing = runs.filter { personalBestCache.efforts(for: $0.id) == nil }
        var transient: [UUID: [PersonalBest]] = [:]
        if !missing.isEmpty || !personalBestCache.warm {
            let generation = cacheGeneration
            let scanned = await Self.scanEfforts(missing, source: dataSource, engine: engine, asOf: now())
            transient = scanned.failed
            if generation == cacheGeneration { personalBestCache.store(scanned.found, markWarm: true) }
            transient.merge(scanned.found) { a, _ in a }
        }
        var best: [PersonalBestCategory: PersonalBest] = [:]
        for run in runs {
            for effort in personalBestCache.efforts(for: run.id) ?? transient[run.id] ?? [] where Self.isBetter(effort, than: best[effort.category]) {
                best[effort.category] = effort
            }
        }
        let newSince = now().addingTimeInterval(-7 * 86_400)
        return best.values
            .map { var pb = $0; pb.isNew = pb.date >= newSince; return pb }
            .sorted { PersonalBestCategory.allCases.firstIndex(of: $0.category)! < PersonalBestCategory.allCases.firstIndex(of: $1.category)! }
    }

    /// Reads distance timelines with at most `width` concurrent queries and finds each run's best efforts.
    /// Runs whose timeline couldn't be read fall back to whole-run distance and are not persisted.
    @concurrent
    nonisolated private static func scanEfforts(_ runs: [Workout], source: any HealthDataSource, engine: any ScoreEngine, asOf: Date,
                                                width: Int = 4) async -> (found: [UUID: [PersonalBest]], failed: [UUID: [PersonalBest]]) {
        await withTaskGroup(of: (UUID, [PersonalBest], Bool).self) { group in
            var found: [UUID: [PersonalBest]] = [:], failed: [UUID: [PersonalBest]] = [:]
            var pending = runs[...]
            func addNext() {
                guard let run = pending.popFirst() else { return }
                group.addTask {
                    let timeline = try? await source.cumulativeDistance(for: run.id)
                    let efforts = engine.personalBests(runs: [RunEffortInput(workout: run, cumulativeDistance: timeline ?? [])], asOf: asOf)
                    return (run.id, efforts, timeline != nil)
                }
            }
            for _ in 0..<width { addNext() }
            while let (id, efforts, ok) = await group.next() {
                if ok { found[id] = efforts } else { failed[id] = efforts }
                addNext()
            }
            return (found, failed)
        }
    }

    /// Faster time wins for distance categories, longer distance for `longestRun`; ties go to the earlier run.
    private static func isBetter(_ candidate: PersonalBest, than current: PersonalBest?) -> Bool {
        guard let current else { return true }
        if let a = candidate.duration, let b = current.duration {
            return a < b || (a == b && candidate.date < current.date)
        }
        return candidate.distanceMeters > current.distanceMeters
            || (candidate.distanceMeters == current.distanceMeters && candidate.date < current.date)
    }

    /// Pace at similar heart rate, weekly, for Progress → Running.
    func aerobicEfficiency(endingOn day: LocalDay, weeks: Int) async throws -> AerobicEfficiencyTrend? {
        let start = day.adding(days: -(weeks * 7 - 1), calendar: calendar)
        let runs = try await dataSource.workouts(in: LocalDay.interval(from: start, through: day, calendar: calendar), kinds: [.run])
        return aerobicEfficiency(runs: runs, endingOn: day, weeks: weeks)
    }

    /// Same as `aerobicEfficiency(endingOn:weeks:)` from already-fetched runs (avoids a second year query).
    func aerobicEfficiency(runs: [Workout], endingOn day: LocalDay, weeks: Int) -> AerobicEfficiencyTrend? {
        let start = day.adding(days: -(weeks * 7 - 1), calendar: calendar)
        let interval = LocalDay.interval(from: start, through: day, calendar: calendar)
        return engine.aerobicEfficiency(runs: runs.filter { $0.kind == .run && interval.contains($0.start) }, endingOn: day, weeks: weeks)
    }

    /// Rule-based insights for `day`.
    func insights(for day: LocalDay) async throws -> [Insight] {
        let source = dataSource
        let start = day.adding(days: -27, calendar: calendar)
        let interval = LocalDay.interval(from: start, through: day, calendar: calendar)
        async let nights = source.sleepNights(in: interval)
        async let workouts = source.workouts(in: interval, kinds: nil)
        return engine.insights(InsightInput(day: day,
                                            nights: try await nights,
                                            workouts: WorkoutDeduplication.deduplicated(try await workouts),
                                            summaries: summaries.summaries(from: start, through: day)))
    }
}
