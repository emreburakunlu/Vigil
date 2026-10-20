import Foundation

/// Raw Health data for a span of days, fetched once and reused for many summaries.
struct HealthDataBundle: Sendable {
    var nights: [SleepNight] = []
    var vitals: [DailyVitals] = []
    var activity: [DailyActivity] = []
    /// Deduplicated (`WorkoutDeduplication`) when produced by `fetch`.
    var workouts: [Workout] = []
    /// HR samples per workout id.
    var workoutHeartRate: [UUID: [MetricSample]] = [:]

    /// Fetches everything Vigil needs for `interval`. Sleep is fetched once and reused for the vitals.
    /// Heart rate is read only for workouts starting at or after `heartRateFrom` (the first day that will be
    /// built; earlier days only feed baselines, which don't use workout heart rate). nil reads all.
    static func fetch(from source: any HealthDataSource, interval: DateInterval,
                      heartRateFrom: Date? = nil) async throws -> HealthDataBundle {
        async let activity = source.dailyActivity(in: interval)
        async let workouts = source.workouts(in: interval, kinds: nil)
        let nights = try await source.sleepNights(in: interval)
        async let vitals = source.dailyVitals(in: interval, nights: nights)
        var bundle = try await HealthDataBundle(nights: nights, vitals: vitals, activity: activity,
                                                workouts: WorkoutDeduplication.deduplicated(workouts))
        let needsHeartRate = heartRateFrom.map { from in bundle.workouts.filter { $0.start >= from } } ?? bundle.workouts
        bundle.workoutHeartRate = try await heartRate(for: needsHeartRate, from: source)
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

// MARK: - Workout deduplication

/// The same strength session is often saved twice: once by a lifting app (Hevy) and once by the
/// Apple Watch Workout app. Counting both doubles strain, session counts and lists.
///
/// Two **strength** workouts from **different sources** that overlap by more than half of the shorter one
/// are one session. The kept one is the one with heart-rate data; on a tie, the longer one; on a tie,
/// the earlier one in the input. Everything else passes through unchanged, in input order.
/// The single helper used wherever workouts feed scores, counts or lists (repository + `SummaryBuilder`).
enum WorkoutDeduplication {
    /// Minimum share of the shorter workout that must overlap.
    static let overlapThreshold = 0.5

    static func deduplicated(_ workouts: [Workout]) -> [Workout] {
        let strength = workouts.indices.filter { workouts[$0].kind == .strength }
            .sorted { workouts[$0].start < workouts[$1].start }
        guard strength.count > 1 else { return workouts }
        var dropped = Set<Int>()
        for (position, i) in strength.enumerated() where !dropped.contains(i) {
            for j in strength[(position + 1)...] where !dropped.contains(j) {
                let a = workouts[i], b = workouts[j]
                if b.start >= a.end { break }
                guard a.source.bundleIdentifier != b.source.bundleIdentifier, overlaps(a, b) else { continue }
                if prefers(b, over: a, bIndex: j, aIndex: i) {
                    dropped.insert(i)
                    break
                } else {
                    dropped.insert(j)
                }
            }
        }
        guard !dropped.isEmpty else { return workouts }
        return workouts.indices.filter { !dropped.contains($0) }.map { workouts[$0] }
    }

    static func overlaps(_ a: Workout, _ b: Workout) -> Bool {
        let shorter = min(a.end.timeIntervalSince(a.start), b.end.timeIntervalSince(b.start))
        guard shorter > 0 else { return false }
        let overlap = min(a.end, b.end).timeIntervalSince(max(a.start, b.start))
        return overlap / shorter > overlapThreshold
    }

    private static func hasHeartRate(_ w: Workout) -> Bool { w.averageHeartRate != nil || w.maxHeartRate != nil }

    private static func prefers(_ b: Workout, over a: Workout, bIndex: Int, aIndex: Int) -> Bool {
        if hasHeartRate(a) != hasHeartRate(b) { return hasHeartRate(b) }
        let da = a.end.timeIntervalSince(a.start), db = b.end.timeIntervalSince(b.start)
        if da != db { return db > da }
        return bIndex < aIndex
    }
}

// MARK: - Builder

/// Turns a `HealthDataBundle` into `DailySummary` values with a `ScoreEngine`. Pure.
///
/// **Invariant:** a day's summary depends only on the bundle (which must cover `Baseline.windowDays`
/// before the first built day) and the strains of the `strainHistoryDays` days before it. Callers pass
/// cached strains for the days before the first built day (`previousStrains`), so a one-day build, a
/// refresh and the 90-day import produce identical summaries for the same day.
struct SummaryBuilder: Sendable {
    var engine: any ScoreEngine
    var calendar: Calendar

    /// Days of strain history before a built day that feed its baselines (30) and training load (86:
    /// the engine's 1 + 84 day load window as of the previous day, plus that day).
    static let strainHistoryDays = 86

    /// Builds summaries off the main actor. Same result as `summaries(for:...)`.
    @concurrent
    func build(for days: [LocalDay], data: HealthDataBundle, settings: VigilSettings, now: Date,
               previousStrains: [LocalDay: DailyStrain] = [:], zones: HeartRateZones? = nil,
               settingsFingerprint: String? = nil) async -> [DailySummary] {
        summaries(for: days, data: data, settings: settings, now: now, previousStrains: previousStrains,
                  zones: zones, settingsFingerprint: settingsFingerprint)
    }

    /// Builds summaries for `days` (ascending). Each day's baselines use only earlier days.
    /// - Parameters:
    ///   - previousStrains: strains of days before the first built day (from the cache).
    ///   - zones: heart-rate zones to use; nil derives them from the bundle's observed max HR (tests only —
    ///     the repository always passes `VigilRepository.heartRateZones` with its 365-day observed max).
    func summaries(for days: [LocalDay], data: HealthDataBundle, settings: VigilSettings, now: Date,
                   previousStrains: [LocalDay: DailyStrain] = [:], zones: HeartRateZones? = nil,
                   settingsFingerprint: String? = nil) -> [DailySummary] {
        let days = days.sorted()
        guard let firstDay = days.first else { return [] }
        let workouts = WorkoutDeduplication.deduplicated(data.workouts)
        let primaryNights = data.nights.filter(\.isPrimary).sorted { $0.sleepEnd < $1.sleepEnd }
        let nightsByDay = Dictionary(primaryNights.map { ($0.day, $0) }, uniquingKeysWith: { _, b in b })
        let vitalsByDay = Dictionary(data.vitals.map { ($0.day, $0) }, uniquingKeysWith: { _, b in b })
        let activityByDay = Dictionary(data.activity.map { ($0.day, $0) }, uniquingKeysWith: { _, b in b })
        let workoutsByDay = Dictionary(grouping: workouts) { LocalDay($0.start, calendar: calendar) }
        let zones = zones ?? engine.heartRateZones(profile: settings.profile, settings: settings.heartRateZones,
                                                   observedMaxHeartRate: workouts.compactMap(\.maxHeartRate).max(), on: now)

        // Strain history, ascending: cached days before the build, then each built day as it's computed.
        var history: [DailyStrain] = previousStrains.filter { $0.key < firstDay }.values.sorted { $0.day < $1.day }
        var strainsByDay = Dictionary(history.map { ($0.day, $0) }, uniquingKeysWith: { _, b in b })
        var windowStart = 0
        var result: [DailySummary] = []
        result.reserveCapacity(days.count)
        for day in days {
            let earliest = day.adding(days: -Self.strainHistoryDays, calendar: calendar)
            while windowStart < history.count, history[windowStart].day < earliest { windowStart += 1 }
            let window = history[windowStart...].filter { $0.day < day }

            let baselines = engine.baselines(on: day, history: BaselineHistory(vitals: data.vitals, nights: primaryNights,
                                                                                strains: Array(window)))
            let night = nightsByDay[day]
            let sleepScore = night.map { night in
                engine.sleepScore(SleepScoreInput(night: night, target: settings.goals.sleepTarget, baselines: baselines,
                                                  recentNights: Array(primaryNights.filter { $0.day < day }.suffix(7))))
            }
            let workoutStrains = (workoutsByDay[day] ?? []).map { workout in
                engine.workoutStrain(WorkoutStrainInput(workout: workout, heartRate: data.workoutHeartRate[workout.id] ?? [],
                                                        zones: zones, restingHeartRate: vitalsByDay[day]?.restingHeartRate,
                                                        sex: settings.profile.sex))
            }
            let strain = engine.dailyStrain(day: day, workouts: workoutStrains, activity: activityByDay[day])
            let yesterday = day.adding(days: -1, calendar: calendar)
            let loadBeforeToday = window.isEmpty ? nil : engine.trainingLoad(
                dailyLoads: Dictionary(window.map { ($0.day, $0.trainingLoad) }, uniquingKeysWith: { _, b in b }),
                asOf: yesterday, historyDays: 1)
            let vitals = vitalsByDay[day]
            let hasRecoverySignal = vitals.map { !$0.recordedMetrics.isEmpty } ?? false
            let recovery = (hasRecoverySignal || night != nil)
                ? engine.recovery(RecoveryInput(day: day, vitals: vitals, sleep: night, sleepScore: sleepScore, baselines: baselines,
                                                previousDayStrain: strainsByDay[yesterday], trainingLoad: loadBeforeToday))
                : nil
            history.append(strain)
            strainsByDay[day] = strain
            result.append(DailySummary(day: day, computedAt: now, engineVersion: engine.version,
                                       settingsFingerprint: settingsFingerprint, baselines: baselines,
                                       vitals: vitals, activity: activityByDay[day], sleepNightID: night?.id,
                                       sleepDuration: night?.asleepDuration, sleepScore: sleepScore, recovery: recovery,
                                       strain: strain))
        }
        return result
    }
}
