import Foundation

/// Pure presentation decisions for the Train lists (date labels, grouping, week header, daily bars).
enum TrainFormatting {
    /// How a list row writes its date.
    enum RowStyle: Sendable {
        /// "Today, 07:12" · "Yesterday, 18:05" · "Thu, Oct 15"
        case run
        /// "Today · 18:30" · "Fri, Oct 16 · 19:05" (always carries the time)
        case lift
    }

    /// A date label that is relative for today / yesterday and absolute otherwise.
    static func rowDate(_ date: Date, style: RowStyle, now: Date, calendar: Calendar, formatter: VigilFormatter) -> String {
        let time = formatter.timeOfDay(date, calendar: calendar)
        let day = LocalDay(date, calendar: calendar)
        let today = LocalDay(now, calendar: calendar)
        let separator = style == .run ? ", " : " · "
        if day == today {
            return String(localized: "Today") + separator + time
        }
        if day == today.adding(days: -1, calendar: calendar) {
            return String(localized: "Yesterday") + separator + time
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        var format = Date.FormatStyle(calendar: calendar).weekday(.abbreviated).month(.abbreviated).day()
        if !sameYear { format = format.year() }
        let absolute = date.formatted(format)
        return style == .run ? absolute : absolute + separator + time
    }

    /// "Oct 13 – 19" for the 7-day window of a `WeeklyProgress`.
    static func weekRange(start: LocalDay, end: LocalDay, calendar: Calendar) -> String {
        let range = start.startDate(in: calendar)..<end.startDate(in: calendar)
        return range.formatted(Date.IntervalFormatStyle(calendar: calendar).month(.abbreviated).day())
    }

    /// Narrow weekday letters ("T", "W", …) for each day of the window, oldest first.
    static func weekdayInitials(start: LocalDay, count: Int, calendar: Calendar) -> [String] {
        (0..<count).map { offset in
            start.adding(days: offset, calendar: calendar).startDate(in: calendar)
                .formatted(Date.FormatStyle(calendar: calendar).weekday(.narrow))
        }
    }

    /// Spoken weekday names, oldest first (VoiceOver for the bar chart).
    static func weekdayNames(start: LocalDay, count: Int, calendar: Calendar) -> [String] {
        (0..<count).map { offset in
            start.adding(days: offset, calendar: calendar).startDate(in: calendar)
                .formatted(Date.FormatStyle(calendar: calendar).weekday(.wide))
        }
    }

    /// Bar heights 0...1 for the 7-day distance chart. Rest days are 0.
    static func barFractions(_ distances: [Double]) -> [Double] {
        guard let peak = distances.max(), peak > 0 else { return distances.map { _ in 0 } }
        return distances.map { $0 / peak }
    }

    /// Groups workouts (newest first) under month headings, preserving order.
    static func monthGroups(_ items: [WorkoutSummary], calendar: Calendar) -> [TrainMonthGroup] {
        var groups: [TrainMonthGroup] = []
        for item in items {
            let parts = calendar.dateComponents([.year, .month], from: item.workout.start)
            let key = (parts.year ?? 0) * 100 + (parts.month ?? 0)
            if let last = groups.last, last.key == key {
                groups[groups.count - 1].items.append(item)
            } else {
                groups.append(TrainMonthGroup(key: key, start: item.workout.start, items: [item]))
            }
        }
        return groups
    }

    /// "October" in the current year, "October 2025" otherwise.
    static func monthTitle(_ date: Date, now: Date, calendar: Calendar) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        var format = Date.FormatStyle(calendar: calendar).month(.wide)
        if !sameYear { format = format.year() }
        return date.formatted(format)
    }

    /// Share of the session spent in each zone (0...1), zero when there is no zone time.
    static func zoneFractions(_ durations: ZoneDurations) -> [Double] {
        let total = durations.total
        guard total > 0 else { return Array(repeating: 0, count: 5) }
        return durations.seconds.map { $0 / total }
    }

    /// Normalised bar length (0.25...1) for a split: faster splits draw longer.
    static func splitBarFraction(pace: Double, fastest: Double, slowest: Double) -> Double {
        guard slowest > fastest else { return 1 }
        return 0.25 + 0.75 * (slowest - pace) / (slowest - fastest)
    }
}

/// Workouts that share a calendar month (list section).
struct TrainMonthGroup: Identifiable, Hashable, Sendable {
    var key: Int
    var start: Date
    var items: [WorkoutSummary]
    var id: Int { key }
}
