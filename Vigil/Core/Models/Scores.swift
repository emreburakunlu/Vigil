import Foundation

// Output types of the score engine (`ScoreEngine`). These are the CONTRACT between the engine
// agent and the screen agents: change only with orchestrator approval, add fields as optionals.

// MARK: - Baselines

/// Rolling personal baseline of one signal (default window 30 days).
struct Baseline: Hashable, Codable, Sendable {
    /// Minimum samples before a baseline is considered established.
    static let minimumSamples = 7
    /// Default rolling window, days.
    static let windowDays = 30

    var mean: Double
    var standardDeviation: Double
    var sampleCount: Int

    /// "Normal" band = mean ± 1 SD ("Your baseline · 55–67 ms").
    var normalRange: ClosedRange<Double> { (mean - standardDeviation)...(mean + standardDeviation) }
    var isEstablished: Bool { sampleCount >= Self.minimumSamples }

    /// Classifies a value against the normal band.
    func status(of value: Double?) -> BaselineStatus {
        guard let value else { return .missing }
        guard isEstablished else { return .noBaseline }
        if value > normalRange.upperBound { return .above }
        if value < normalRange.lowerBound { return .below }
        return .within
    }
}

/// All baselines as of `day` (computed from the `Baseline.windowDays` days *before* `day`).
struct PersonalBaselines: Hashable, Codable, Sendable {
    var day: LocalDay
    /// Baselines for `HealthMetric.vitals` (+ optionally others).
    var metrics: [HealthMetric: Baseline]
    /// Time asleep, seconds.
    var sleepDuration: Baseline?
    /// Sleep midpoint / bedtime regularity, minutes after 18:00 local.
    var bedtimeMinutes: Baseline?
    /// Daily strain.
    var dailyStrain: Baseline?

    init(day: LocalDay, metrics: [HealthMetric: Baseline] = [:], sleepDuration: Baseline? = nil,
         bedtimeMinutes: Baseline? = nil, dailyStrain: Baseline? = nil) {
        self.day = day
        self.metrics = metrics
        self.sleepDuration = sleepDuration
        self.bedtimeMinutes = bedtimeMinutes
        self.dailyStrain = dailyStrain
    }

    subscript(metric: HealthMetric) -> Baseline? { metrics[metric] }
}

// MARK: - Sleep score

/// A component of the sleep score.
enum SleepScoreContributorKind: String, CaseIterable, Codable, Sendable {
    case duration
    case efficiency
    case deepSleep
    case remSleep
    case consistency
    case interruptions
}

struct SleepScoreContributor: Hashable, Codable, Sendable, Identifiable {
    var kind: SleepScoreContributorKind
    /// Sub-score 0–100.
    var score: Int
    /// Weight 0–1 in the total.
    var weight: Double
    var id: SleepScoreContributorKind { kind }
}

/// Sleep score for one night (0–100).
struct SleepScore: Hashable, Codable, Sendable {
    var value: Int
    var band: SleepScoreBand
    var contributors: [SleepScoreContributor]
    /// Time asleep minus target, seconds (negative = short: "18 min short of your 8h target").
    var targetDifference: TimeInterval
}

// MARK: - Recovery

/// Signals that make up recovery.
enum RecoveryFactorKind: String, CaseIterable, Codable, Sendable {
    case heartRateVariability
    case restingHeartRate
    case sleep
    case respiratoryRate
    case wristTemperature
}

/// One signal's contribution ("HRV · 68 ms · baseline 61 · +14").
struct RecoveryFactor: Hashable, Codable, Sendable, Identifiable {
    var kind: RecoveryFactorKind
    /// Today's value in canonical units (sleep: sleep score).
    var value: Double?
    /// Baseline mean in the same unit.
    var baseline: Double?
    /// Signed points added to / taken from the neutral score.
    var points: Int
    /// False when the signal was not recorded (partial-data state).
    var isAvailable: Bool
    var id: RecoveryFactorKind { kind }
}

/// Recovery for one day (0–100 %).
struct RecoveryScore: Hashable, Codable, Sendable {
    var value: Int
    var band: RecoveryBand
    var factors: [RecoveryFactor]
    var suggestion: ReadinessSuggestion
    /// One-line explanation ("HRV 12% above your baseline. Good day for intervals.").
    var message: String
    /// Suggested strain target for the day ("Suggested for 78% recovery: 55–75").
    var suggestedStrain: ClosedRange<Int>
    /// Signals used vs. possible ("3 of 5 signals").
    var signalsUsed: Int
    var signalsTotal: Int

    var isPartial: Bool { signalsUsed < signalsTotal }
}

// MARK: - Heart-rate zones

/// How max HR / zones were determined.
enum HeartRateZoneSource: String, Codable, Sendable {
    /// Estimated from age (refined by observed peaks).
    case estimated
    /// User-entered max HR; zones derived from it.
    case manualMaxHeartRate
    /// User-entered zone boundaries.
    case custom
}

/// One of the five zones. Bounds are inclusive bpm.
struct HeartRateZone: Hashable, Codable, Sendable, Identifiable {
    /// 1...5.
    var number: Int
    /// "Warm-up", "Easy", "Aerobic", "Threshold", "Maximum".
    var name: String
    var lowerBound: Int
    var upperBound: Int
    var id: Int { number }

    static let names = ["Warm-up", "Easy", "Aerobic", "Threshold", "Maximum"]
}

/// The user's five zones.
struct HeartRateZones: Hashable, Codable, Sendable {
    var maxHeartRate: Int
    var source: HeartRateZoneSource
    /// Exactly five zones, ascending.
    var zones: [HeartRateZone]

    /// Zone number 1...5 for a heart rate, nil below zone 1.
    func zone(for bpm: Double) -> Int? {
        zones.last(where: { bpm >= Double($0.lowerBound) })?.number
    }
}

/// Seconds spent in each zone (index 0 = Z1).
struct ZoneDurations: Hashable, Codable, Sendable {
    var seconds: [TimeInterval]

    init(seconds: [TimeInterval] = Array(repeating: 0, count: 5)) {
        self.seconds = seconds.count == 5 ? seconds : Array((seconds + Array(repeating: 0, count: 5)).prefix(5))
    }

    /// Duration for zone 1...5.
    subscript(zone: Int) -> TimeInterval {
        (1...5).contains(zone) ? seconds[zone - 1] : 0
    }

    var total: TimeInterval { seconds.reduce(0, +) }

    static func + (lhs: ZoneDurations, rhs: ZoneDurations) -> ZoneDurations {
        ZoneDurations(seconds: zip(lhs.seconds, rhs.seconds).map(+))
    }
}

// MARK: - Strain & load

/// Strain of a single workout.
struct WorkoutStrain: Hashable, Codable, Sendable {
    var workoutID: UUID
    /// 0–100.
    var value: Int
    var level: StrainLevel
    /// Heart-rate based training load (TRIMP-like, unbounded; "Training load 118").
    var trainingLoad: Double
    var zoneDurations: ZoneDurations
}

/// Strain for a whole day.
struct DailyStrain: Hashable, Codable, Sendable {
    var day: LocalDay
    /// 0–100.
    var value: Int
    var level: StrainLevel
    var workouts: [WorkoutStrain]
    /// Strain from non-workout movement ("Everyday movement 12").
    var everydayMovement: Int
    /// Sum of workout zone durations.
    var zoneDurations: ZoneDurations
    /// Total training load of the day (input to acute/chronic load).
    var trainingLoad: Double
}

/// Risk band of the acute:chronic ratio.
enum TrainingLoadRisk: String, Codable, Sendable {
    /// < 0.8 — fitness may decline.
    case detraining
    /// 0.8–1.3 — "Productive".
    case productive
    /// 1.3–1.5 — building fast.
    case caution
    /// > 1.5 — "Too much, too fast".
    case high

    init(ratio: Double) {
        switch ratio {
        case ..<0.8: self = .detraining
        case ..<1.3: self = .productive
        case ...1.5: self = .caution
        default: self = .high
        }
    }
}

/// Acute (7-day) vs. chronic (28-day) load on one day.
struct TrainingLoadPoint: Hashable, Codable, Sendable, Identifiable {
    var day: LocalDay
    /// Mean daily load over the last 7 days.
    var acute: Double
    /// Mean daily load over the last 28 days.
    var chronic: Double
    var id: LocalDay { day }
}

/// Training load as of a day, with history for the chart.
struct TrainingLoad: Hashable, Codable, Sendable {
    var day: LocalDay
    var acute: Double
    var chronic: Double
    /// acute ÷ chronic; nil when chronic is 0.
    var ratio: Double?
    var risk: TrainingLoadRisk
    /// Oldest first.
    var history: [TrainingLoadPoint]
}

// MARK: - Sleep debt

struct SleepDebtNight: Hashable, Codable, Sendable, Identifiable {
    var day: LocalDay
    /// Time asleep, nil when no sleep was recorded.
    var asleep: TimeInterval?
    /// max(0, target − asleep); 0 when not recorded.
    var shortfall: TimeInterval
    var id: LocalDay { day }
}

/// Sleep debt over the last 7 nights ("4h 33m · shortfall vs. 8h").
struct SleepDebt: Hashable, Codable, Sendable {
    var endingOn: LocalDay
    var target: TimeInterval
    /// Total shortfall, seconds.
    var total: TimeInterval
    /// Oldest first, 7 entries.
    var nights: [SleepDebtNight]
    /// "6 of the last 7 nights recorded".
    var nightsRecorded: Int
}

// MARK: - Personal bests

enum PersonalBestCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case oneKilometer
    case fiveKilometers
    case tenKilometers
    case halfMarathon
    case marathon
    /// Longest single run (by distance).
    case longestRun

    var id: String { rawValue }

    /// Target distance in metres (nil for `longestRun`).
    var distanceMeters: Double? {
        switch self {
        case .oneKilometer: 1_000
        case .fiveKilometers: 5_000
        case .tenKilometers: 10_000
        case .halfMarathon: 21_097.5
        case .marathon: 42_195
        case .longestRun: nil
        }
    }

    var displayName: String {
        switch self {
        case .oneKilometer: "1K"
        case .fiveKilometers: "5K"
        case .tenKilometers: "10K"
        case .halfMarathon: "Half marathon"
        case .marathon: "Marathon"
        case .longestRun: "Longest run"
        }
    }
}

/// A personal best. Distance categories use the fastest effort *within* any run.
struct PersonalBest: Hashable, Codable, Sendable, Identifiable {
    var category: PersonalBestCategory
    /// Best time for distance categories, seconds; nil for `longestRun`.
    var duration: TimeInterval?
    /// Distance of the effort, metres (the run's distance for `longestRun`).
    var distanceMeters: Double
    var date: Date
    var workoutID: UUID
    /// Set within the last 7 days ("NEW").
    var isNew: Bool
    var id: PersonalBestCategory { category }
}

// MARK: - Insights

enum InsightDomain: String, Codable, Sendable {
    case sleep
    case recovery
    case training
    case body
}

/// A rule-based observation ("You sleep 35 min more on rest days than after lifting.").
struct Insight: Hashable, Codable, Sendable, Identifiable {
    /// Stable rule identifier, e.g. `"sleep.restDayDuration"`.
    var id: String
    var domain: InsightDomain
    var text: String
    /// Higher shows first.
    var priority: Int
}
