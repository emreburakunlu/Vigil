import Foundation

/// Everything computed for one day, cached in SwiftData (`DailySummaryRecord`) so screens and
/// the widget don't recompute 90 days on every launch. Any part may be missing.
struct DailySummary: Hashable, Codable, Sendable {
    /// Bump when the engine changes in a way that invalidates cached summaries.
    static let currentEngineVersion = 1

    var day: LocalDay
    var computedAt: Date
    var engineVersion: Int

    var baselines: PersonalBaselines?
    var vitals: DailyVitals?
    var activity: DailyActivity?
    /// Primary night ending on this day.
    var sleepNightID: String?
    var sleepDuration: TimeInterval?
    var sleepScore: SleepScore?
    var recovery: RecoveryScore?
    var strain: DailyStrain?

    init(day: LocalDay, computedAt: Date = .now, engineVersion: Int = DailySummary.currentEngineVersion,
         baselines: PersonalBaselines? = nil, vitals: DailyVitals? = nil, activity: DailyActivity? = nil,
         sleepNightID: String? = nil, sleepDuration: TimeInterval? = nil, sleepScore: SleepScore? = nil,
         recovery: RecoveryScore? = nil, strain: DailyStrain? = nil) {
        self.day = day
        self.computedAt = computedAt
        self.engineVersion = engineVersion
        self.baselines = baselines
        self.vitals = vitals
        self.activity = activity
        self.sleepNightID = sleepNightID
        self.sleepDuration = sleepDuration
        self.sleepScore = sleepScore
        self.recovery = recovery
        self.strain = strain
    }
}
