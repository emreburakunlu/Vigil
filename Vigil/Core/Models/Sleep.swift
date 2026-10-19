import Foundation

/// A sleep analysis stage. Mirrors `HKCategoryValueSleepAnalysis`.
enum SleepStage: String, CaseIterable, Codable, Sendable {
    case inBed
    case awake
    case rem
    case core
    /// Asleep without stage information (older devices / third-party apps). Counted as asleep.
    case asleepUnspecified
    case deep

    /// Whether the stage counts toward time asleep.
    var isAsleep: Bool {
        switch self {
        case .rem, .core, .deep, .asleepUnspecified: true
        case .inBed, .awake: false
        }
    }

    /// The four stages drawn in the hypnogram, top to bottom.
    static let hypnogramStages: [SleepStage] = [.awake, .rem, .core, .deep]
}

/// A contiguous interval in one stage.
struct SleepSegment: Hashable, Codable, Sendable {
    var stage: SleepStage
    var start: Date
    var end: Date
    var source: DataSourceInfo?

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Time spent in each stage over a night (seconds).
struct SleepStageDurations: Hashable, Codable, Sendable {
    var awake: TimeInterval = 0
    var rem: TimeInterval = 0
    var core: TimeInterval = 0
    var deep: TimeInterval = 0
    /// Asleep time without stage data.
    var unspecified: TimeInterval = 0

    /// Total time asleep (REM + core + deep + unspecified).
    var asleep: TimeInterval { rem + core + deep + unspecified }

    subscript(stage: SleepStage) -> TimeInterval {
        switch stage {
        case .awake: awake
        case .rem: rem
        case .core: core
        case .deep: deep
        case .asleepUnspecified: unspecified
        case .inBed: 0
        }
    }

    /// Fraction 0–1 of (asleep + awake) spent in `stage`, as shown in the stage breakdown.
    func share(of stage: SleepStage) -> Double {
        let total = asleep + awake
        return total > 0 ? self[stage] / total : 0
    }
}

/// One night of sleep, attributed to the day the user woke up.
///
/// The live source merges overlapping samples from multiple sources (Watch preferred) and
/// groups segments into a "primary" sleep; naps are separate nights with `isPrimary == false`.
struct SleepNight: Identifiable, Hashable, Codable, Sendable {
    /// Stable id derived from the wake day + start (`"2026-10-19-primary"`); unique per night.
    var id: String
    /// Wake-up day. "Sun 18 → Mon 19" belongs to Mon 19.
    var day: LocalDay
    /// Whether this is the main overnight sleep (vs. a nap).
    var isPrimary: Bool
    /// In-bed window; falls back to first/last asleep segment when no in-bed samples exist.
    var inBedStart: Date
    var inBedEnd: Date
    /// First asleep moment ("Bedtime 22:58") and final wake ("Woke up 07:04").
    var sleepStart: Date
    var sleepEnd: Date
    /// Stage segments ordered by start, without `.inBed` segments.
    var segments: [SleepSegment]
    /// Pre-computed stage totals.
    var stageDurations: SleepStageDurations
    /// Number of awake periods between `sleepStart` and `sleepEnd` ("Interruptions 3").
    var interruptions: Int
    /// Distinct sources that contributed.
    var sources: [DataSourceInfo]

    /// Time asleep.
    var asleepDuration: TimeInterval { stageDurations.asleep }
    /// Time in bed.
    var inBedDuration: TimeInterval { inBedEnd.timeIntervalSince(inBedStart) }
    /// Asleep ÷ in bed, 0–1 ("Efficiency 95%").
    var efficiency: Double { inBedDuration > 0 ? min(1, asleepDuration / inBedDuration) : 0 }
    /// Whether stage data (REM/core/deep) is present.
    var hasStages: Bool { stageDurations.rem + stageDurations.core + stageDurations.deep > 0 }
}
