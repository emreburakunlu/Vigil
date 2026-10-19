import Foundation

// CONTRACT — the pure score engine API. Owner of the implementation: engine agent.
// Changing these signatures requires orchestrator approval (screen agents depend on them).
//
// Rules: deterministic and side-effect free. No HealthKit, no SwiftData, no `Date.now`
// (time comes in through inputs), no randomness. Everything is Sendable and nonisolated so
// it can run on any executor and in unit tests.

/// History used to build baselines (the `Baseline.windowDays` days before the target day).
struct BaselineHistory: Sendable {
    var vitals: [DailyVitals]
    /// Primary nights only.
    var nights: [SleepNight]
    var strains: [DailyStrain]

    init(vitals: [DailyVitals] = [], nights: [SleepNight] = [], strains: [DailyStrain] = []) {
        self.vitals = vitals
        self.nights = nights
        self.strains = strains
    }
}

/// Inputs for one night's sleep score.
struct SleepScoreInput: Sendable {
    var night: SleepNight
    /// Time-asleep target, seconds.
    var target: TimeInterval
    var baselines: PersonalBaselines?
    /// Previous primary nights (up to 7) for bedtime consistency.
    var recentNights: [SleepNight]
}

/// Inputs for a day's recovery.
struct RecoveryInput: Sendable {
    var day: LocalDay
    var vitals: DailyVitals?
    var sleep: SleepNight?
    var sleepScore: SleepScore?
    var baselines: PersonalBaselines
    /// Strain of the previous day (heavy days lower next-day recovery).
    var previousDayStrain: DailyStrain?
}

/// Inputs for a workout's strain.
struct WorkoutStrainInput: Sendable {
    var workout: Workout
    /// Heart-rate samples (bpm) during the workout.
    var heartRate: [MetricSample]
    var zones: HeartRateZones
    var restingHeartRate: Double?
}

/// Inputs for best-effort / personal-best detection.
struct RunEffortInput: Sendable {
    var workout: Workout
    /// Cumulative distance (m) over time; empty → only whole-run distance is considered.
    var cumulativeDistance: [MetricSample]
}

/// Inputs for rule-based insights.
struct InsightInput: Sendable {
    var day: LocalDay
    /// Recent primary nights (≥ 14 recommended), oldest first.
    var nights: [SleepNight]
    /// Recent workouts, oldest first.
    var workouts: [Workout]
    /// Recent cached summaries, oldest first.
    var summaries: [DailySummary]
}

/// The score engine. Inject via `AppContainer.engine`; use `DefaultScoreEngine` in tests.
protocol ScoreEngine: Sendable {
    /// Version stored with cached summaries; bump on algorithm changes.
    var version: Int { get }

    /// 30-day personal baselines as of `day` (excluding `day` itself).
    func baselines(on day: LocalDay, history: BaselineHistory) -> PersonalBaselines

    /// Sleep score 0–100 with contributors.
    func sleepScore(_ input: SleepScoreInput) -> SleepScore

    /// Recovery 0–100 %, band, factor contributions, readiness suggestion and message.
    /// Works with partial signals (`signalsUsed < signalsTotal`).
    func recovery(_ input: RecoveryInput) -> RecoveryScore

    /// Five zones from the profile (estimated or manual max HR) or custom boundaries.
    /// `observedMaxHeartRate` refines an estimated max upward.
    func heartRateZones(profile: UserProfile, settings: HeartRateZoneSettings, observedMaxHeartRate: Double?, on date: Date) -> HeartRateZones

    /// Time in each zone for HR samples inside `interval` (each sample holds until the next, capped at 60 s).
    func zoneDurations(heartRate: [MetricSample], zones: HeartRateZones, interval: DateInterval) -> ZoneDurations

    /// Strain 0–100 and training load of one workout.
    func workoutStrain(_ input: WorkoutStrainInput) -> WorkoutStrain

    /// Day strain from its workouts plus everyday movement.
    func dailyStrain(day: LocalDay, workouts: [WorkoutStrain], activity: DailyActivity?) -> DailyStrain

    /// Acute (7d) vs. chronic (28d) training load as of `day`, with `historyDays` of chart history.
    /// Missing days count as zero load.
    func trainingLoad(dailyLoads: [LocalDay: Double], asOf day: LocalDay, historyDays: Int) -> TrainingLoad

    /// Shortfall vs. `target` over the 7 nights ending on `day`.
    func sleepDebt(nights: [SleepNight], target: TimeInterval, endingOn day: LocalDay) -> SleepDebt

    /// Personal bests across `runs`; `isNew` when set within 7 days before `asOf`.
    func personalBests(runs: [RunEffortInput], asOf: Date) -> [PersonalBest]

    /// Per-km or per-mile splits for a run.
    func splits(details: RunDetails, units: UnitSystem) -> [RunSplit]

    /// Rule-based insights, highest priority first.
    func insights(_ input: InsightInput) -> [Insight]
}
