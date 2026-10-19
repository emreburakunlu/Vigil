import Foundation

// Output of `ScoreEngine.aerobicEfficiency(runs:endingOn:weeks:)` — "pace at similar heart rate"
// on Progress → Running. Additive contract type (engine agent, Phase 1).

/// Average heart-rate-normalised pace of the runs in one 7-day bucket.
struct AerobicEfficiencyPoint: Hashable, Codable, Sendable, Identifiable {
    /// First day of the 7-day bucket (buckets end on the trend's `endingOn` day).
    var weekStart: LocalDay
    /// Mean pace normalised to `AerobicEfficiencyTrend.referenceHeartRate`, seconds per km.
    var paceSecondsPerKilometer: Double
    /// Runs that contributed to this bucket.
    var runCount: Int
    var id: LocalDay { weekStart }
}

/// Trend of running pace at a common heart rate (aerobic efficiency).
struct AerobicEfficiencyTrend: Hashable, Codable, Sendable {
    /// Heart rate every run's pace is normalised to (median of the runs' average HR), bpm.
    var referenceHeartRate: Double
    /// Oldest first; weeks without qualifying runs are omitted.
    var points: [AerobicEfficiencyPoint]
    /// Least-squares fitted change in normalised pace from the first to the last qualifying run,
    /// seconds per km (negative = faster, "12 s/km faster at 150 bpm"). Nil when the runs span < 14 days.
    var paceChangeSecondsPerKilometer: Double?
    /// Runs used (average HR within ± `DefaultScoreEngine.Running.similarHeartRateWindow` of the reference).
    var runsUsed: Int
}
