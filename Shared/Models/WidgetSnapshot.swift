import Foundation

/// The small, self-contained payload the app writes into the App Group and the widget reads.
///
/// Keep this type tiny and **backwards compatible**: add only optional fields, never rename.
/// Bump `schemaVersion` when semantics change; the widget treats unknown versions as missing.
struct WidgetSnapshot: Codable, Sendable, Hashable {
    static let currentSchemaVersion = 1

    /// Payload format version.
    var schemaVersion: Int
    /// When the app produced this snapshot ("Updated 07:04").
    var generatedAt: Date
    /// Calendar day the scores belong to (start of day, device time zone at generation).
    var day: Date
    /// Unit system for formatting distances in the weekly widget.
    var units: UnitSystem

    /// Recovery percentage 0–100, nil when it could not be computed.
    var recoveryPercent: Int?
    var recoveryBand: RecoveryBand?
    var readiness: ReadinessSuggestion?
    /// Sleep score 0–100 for last night.
    var sleepScore: Int?
    /// Time asleep last night, seconds.
    var sleepDuration: TimeInterval?
    /// Today's strain so far, 0–100.
    var strain: Int?
    var strainLevel: StrainLevel?

    /// Rolling 7-day running distance in metres and the weekly goal in metres.
    var weeklyRunDistanceMeters: Double
    var weeklyRunGoalMeters: Double
    /// Rolling 7-day strength sessions and the weekly goal.
    var weeklyLiftSessions: Int
    var weeklyLiftGoal: Int
    /// First and last day of the 7-day window ("Oct 13 – 19").
    var weekStart: Date
    var weekEnd: Date

    init(
        schemaVersion: Int = WidgetSnapshot.currentSchemaVersion,
        generatedAt: Date,
        day: Date,
        units: UnitSystem,
        recoveryPercent: Int?,
        recoveryBand: RecoveryBand?,
        readiness: ReadinessSuggestion?,
        sleepScore: Int?,
        sleepDuration: TimeInterval?,
        strain: Int?,
        strainLevel: StrainLevel?,
        weeklyRunDistanceMeters: Double,
        weeklyRunGoalMeters: Double,
        weeklyLiftSessions: Int,
        weeklyLiftGoal: Int,
        weekStart: Date,
        weekEnd: Date
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.day = day
        self.units = units
        self.recoveryPercent = recoveryPercent
        self.recoveryBand = recoveryBand
        self.readiness = readiness
        self.sleepScore = sleepScore
        self.sleepDuration = sleepDuration
        self.strain = strain
        self.strainLevel = strainLevel
        self.weeklyRunDistanceMeters = weeklyRunDistanceMeters
        self.weeklyRunGoalMeters = weeklyRunGoalMeters
        self.weeklyLiftSessions = weeklyLiftSessions
        self.weeklyLiftGoal = weeklyLiftGoal
        self.weekStart = weekStart
        self.weekEnd = weekEnd
    }

    /// Sample values matching the design's widget board; used for widget placeholders and previews.
    static func placeholder(now: Date = .now, calendar: Calendar = .current) -> WidgetSnapshot {
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        return WidgetSnapshot(
            generatedAt: now,
            day: today,
            units: .metric,
            recoveryPercent: 78,
            recoveryBand: .green,
            readiness: .push,
            sleepScore: 84,
            sleepDuration: 7 * 3600 + 42 * 60,
            strain: 62,
            strainLevel: .moderate,
            weeklyRunDistanceMeters: 18_400,
            weeklyRunGoalMeters: 25_000,
            weeklyLiftSessions: 2,
            weeklyLiftGoal: 3,
            weekStart: weekStart,
            weekEnd: today
        )
    }
}
