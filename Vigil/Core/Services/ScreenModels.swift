import Foundation

// View-facing aggregates returned by `VigilRepository`. Screens render these; they never call
// HealthKit or the engine directly. All are plain Sendable values, easy to build in previews.

/// How complete a day's data is (drives the partial-data state).
enum DataCompleteness: Hashable, Sendable {
    case complete
    /// Some recovery signals are missing.
    case partial(missing: [HealthMetric])
    /// Nothing recorded for the day.
    case none
}

/// A workout with its computed strain (Today "Today's workouts", Train lists).
struct WorkoutSummary: Hashable, Sendable, Identifiable {
    var workout: Workout
    var strain: WorkoutStrain?
    var id: UUID { workout.id }
}

/// Rolling 7-day progress (Today "Last 7 days", Train headers, weekly widget).
struct WeeklyProgress: Hashable, Sendable {
    /// First and last day of the window (inclusive).
    var startDay: LocalDay
    var endDay: LocalDay
    var runDistanceMeters: Double
    var runGoalMeters: Double
    var runCount: Int
    var runDuration: TimeInterval
    /// Running distance per day, oldest first (7 entries, 0 for rest days).
    var dailyRunDistanceMeters: [Double]
    var liftSessions: Int
    var liftGoal: Int
    var liftDuration: TimeInterval
    var liftEnergyKilocalories: Double
    /// Which days had which kind of training, oldest first (7 entries).
    var dailyTrainingKinds: [Set<WorkoutKind>]
    /// Average time asleep over recorded nights, nil if none.
    var averageSleep: TimeInterval?
    var sleepTarget: TimeInterval
}

/// Everything on the Today tab for one day.
struct DayOverview: Hashable, Sendable {
    var day: LocalDay
    var recovery: RecoveryScore?
    var sleepNight: SleepNight?
    var sleepScore: SleepScore?
    var strain: DailyStrain?
    var activity: DailyActivity?
    /// The five vitals vs. baseline, in `HealthMetric.vitals` order.
    var vitals: [VitalReading]
    var workouts: [WorkoutSummary]
    var weekly: WeeklyProgress
    var completeness: DataCompleteness
    /// When the underlying summary was computed ("Updated 07:04").
    var updatedAt: Date
}

/// Sleep tab / night detail for one night.
struct SleepNightDetail: Hashable, Sendable {
    var night: SleepNight
    var score: SleepScore
    /// Sleep vitals vs. baseline (HRV, resting HR, respiratory rate, wrist temp, SpO₂).
    var vitals: [VitalReading]
    /// Typical (baseline) share per stage for the "Typical …" hints, 0–1.
    var typicalStageShare: [SleepStage: ClosedRange<Double>]
}

/// One calendar cell / trend point of sleep history.
struct SleepNightSummary: Hashable, Sendable, Identifiable {
    var day: LocalDay
    var asleep: TimeInterval?
    var score: Int?
    var id: LocalDay { day }
}

/// Data for the shared Metric detail screen (D / W / M / 6M / Y).
struct MetricSeries: Hashable, Sendable {
    var metric: HealthMetric
    var range: MetricRange
    var interval: DateInterval
    /// Aggregated points (bucket = `range.bucket`), oldest first.
    var points: [TimeSeriesPoint]
    var average: Double?
    var minimum: Double?
    var maximum: Double?
    var baseline: Baseline?
    /// Latest raw sample in the interval.
    var latest: MetricSample?
    /// Device/app that recorded most samples ("Apple Watch Series 12").
    var sourceName: String?
}

/// Run detail screen.
struct RunDetail: Hashable, Sendable {
    var workout: Workout
    var details: RunDetails
    /// Splits in the user's current unit system.
    var splits: [RunSplit]
    var zones: HeartRateZones
    var zoneDurations: ZoneDurations
    var strain: WorkoutStrain
    /// Personal bests set by this run.
    var personalBests: [PersonalBest]
}

/// Lift detail screen.
struct LiftDetail: Hashable, Sendable {
    var workout: Workout
    var heartRate: [MetricSample]
    var zones: HeartRateZones
    var zoneDurations: ZoneDurations
    var strain: WorkoutStrain
}

/// Phases of the first-launch history import ("Reading your last 90 days").
enum ImportPhase: String, CaseIterable, Sendable {
    case sleep
    case vitals
    case workouts
    case baselines
    case scores
    case finished
}

/// Progress event emitted by `HistoryImportService.importHistory`.
struct ImportProgress: Hashable, Sendable {
    var phase: ImportPhase
    /// Overall progress 0–1.
    var fraction: Double
    var nightsImported: Int
    var workoutsImported: Int
    var workoutsTotal: Int
}
