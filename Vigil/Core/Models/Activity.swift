import Foundation

/// Apple activity ring goals for a day.
struct ActivityGoals: Hashable, Codable, Sendable {
    /// Move goal, active kcal.
    var moveKilocalories: Double
    /// Exercise goal, minutes.
    var exerciseMinutes: Double
    /// Stand goal, hours.
    var standHours: Int
}

/// Daily activity totals (Today "Activity" card, everyday-movement strain).
struct DailyActivity: Hashable, Codable, Sendable {
    var day: LocalDay
    var steps: Int
    /// Active energy, kcal.
    var activeEnergyKilocalories: Double
    /// Basal (resting) energy, kcal, if available.
    var basalEnergyKilocalories: Double?
    /// Apple exercise minutes.
    var exerciseMinutes: Double
    /// Stand hours.
    var standHours: Int
    /// Ring goals, if the user has an Activity summary for that day.
    var goals: ActivityGoals?

    /// Progress 0–∞ (1 = goal met) for each ring; nil without goals.
    var moveProgress: Double? { goals.map { $0.moveKilocalories > 0 ? activeEnergyKilocalories / $0.moveKilocalories : 0 } }
    var exerciseProgress: Double? { goals.map { $0.exerciseMinutes > 0 ? exerciseMinutes / $0.exerciseMinutes : 0 } }
    var standProgress: Double? { goals.map { $0.standHours > 0 ? Double(standHours) / Double($0.standHours) : 0 } }
}
