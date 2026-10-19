import Foundation

/// Why a set of custom zone bounds is rejected.
enum ProfileZoneBoundsError: Equatable, Sendable {
    case wrongCount
    case tooLow
    case notAscending
    case aboveMax
}

/// Pure settings logic for the Profile screen (unit-tested).
enum ProfileLogic {
    static let lowestZoneBound = 30
    static let sleepTargetRange: ClosedRange<TimeInterval> = (5 * 3600)...(11 * 3600)
    static let sleepTargetStep: TimeInterval = 15 * 60
    static let liftGoalRange = 0...7
    static let maxHeartRateRange = 100...230

    /// Validates the four upper bounds of Z1…Z4 (Z5 runs to max HR).
    static func validateZoneBounds(_ bounds: [Int], maxHeartRate: Int) -> ProfileZoneBoundsError? {
        guard bounds.count == 4 else { return .wrongCount }
        guard bounds[0] >= lowestZoneBound else { return .tooLow }
        guard zip(bounds, bounds.dropFirst()).allSatisfy({ $0 < $1 }) else { return .notAscending }
        guard bounds[3] < maxHeartRate else { return .aboveMax }
        return nil
    }

    /// Snaps a sleep target to the 15-minute grid inside 5–11 h.
    static func clampedSleepTarget(_ seconds: TimeInterval) -> TimeInterval {
        let snapped = (seconds / sleepTargetStep).rounded() * sleepTargetStep
        return min(max(snapped, sleepTargetRange.lowerBound), sleepTargetRange.upperBound)
    }

    /// Minutes after midnight for the hour/minute of `date`.
    static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Today at `minutes` after midnight (for a time-only `DatePicker`).
    static func date(fromMinutes minutes: Int, calendar: Calendar = .current, now: Date = .now) -> Date {
        let clamped = min(max(minutes, 0), 24 * 60 - 1)
        return calendar.date(bySettingHour: clamped / 60, minute: clamped % 60, second: 0, of: now) ?? now
    }

    /// Weight limits in kilograms accepted from manual entry.
    static func isPlausibleBodyMass(kilograms: Double) -> Bool { (20...400).contains(kilograms) }

    /// "Age 21" from a date of birth.
    static func age(from dateOfBirth: Date?, now: Date, calendar: Calendar) -> Int? {
        dateOfBirth.flatMap { calendar.dateComponents([.year], from: $0, to: now).year }
    }
}
