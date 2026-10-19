import Foundation

/// The seven days shown in the Today day strip and the rules for moving through days.
///
/// The strip normally ends on today. Stepping or picking a day outside the visible window slides
/// the window so the selection sits at its edge.
struct TodayDayWindow: Hashable, Sendable {
    static let length = 7

    /// The last day of the strip.
    var end: LocalDay
    var calendar: Calendar = .current

    /// Oldest first.
    var days: [LocalDay] {
        (0..<Self.length).map { end.adding(days: $0 - (Self.length - 1), calendar: calendar) }
    }

    /// Window that shows `selection`, as close to ending on `today` as possible.
    static func containing(_ selection: LocalDay, today: LocalDay, calendar: Calendar = .current) -> TodayDayWindow {
        let latestStart = today.adding(days: -(length - 1), calendar: calendar)
        if selection >= latestStart { return TodayDayWindow(end: today, calendar: calendar) }
        return TodayDayWindow(end: min(selection.adding(days: length - 1, calendar: calendar), today), calendar: calendar)
    }

    /// The day `delta` days from `day`, never later than `today`.
    static func step(_ day: LocalDay, by delta: Int, today: LocalDay, calendar: Calendar = .current) -> LocalDay {
        min(day.adding(days: delta, calendar: calendar), today)
    }
}
