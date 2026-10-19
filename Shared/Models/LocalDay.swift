import Foundation

/// A calendar day independent of time of day, used as the key for everything "daily"
/// (scores, summaries, activity, the Today day strip).
///
/// A day is interpreted in a `Calendar` (time zone) supplied by the caller; default `.current`.
/// Sleep nights belong to the day the user **woke up** (Sun 18 → Mon 19 is `LocalDay` Mon 19).
struct LocalDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    var year: Int
    var month: Int
    var day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day containing `date` in `calendar`.
    init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// Parses `yyyy-MM-dd`.
    init?(isoString: String) {
        let parts = isoString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    /// Today in `calendar`.
    static func today(calendar: Calendar = .current, now: Date = .now) -> LocalDay {
        LocalDay(now, calendar: calendar)
    }

    /// Compact sortable integer `yyyymmdd` (used as the SwiftData unique key).
    var key: Int { year * 10_000 + month * 100 + day }

    /// `yyyy-MM-dd`.
    var isoString: String { String(format: "%04d-%02d-%02d", year, month, day) }

    var description: String { isoString }

    /// Midnight at the start of the day.
    func startDate(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    /// `[start of day, start of next day)`; handles DST-length days.
    func interval(in calendar: Calendar = .current) -> DateInterval {
        let start = startDate(in: calendar)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    /// The day `days` later (negative for earlier).
    func adding(days: Int, calendar: Calendar = .current) -> LocalDay {
        let shifted = calendar.date(byAdding: .day, value: days, to: startDate(in: calendar)) ?? startDate(in: calendar)
        return LocalDay(shifted, calendar: calendar)
    }

    /// Whole days from `self` to `other` (positive when `other` is later).
    func days(to other: LocalDay, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: startDate(in: calendar), to: other.startDate(in: calendar)).day ?? 0
    }

    /// Inclusive list of days `from...to`.
    static func range(from start: LocalDay, through end: LocalDay, calendar: Calendar = .current) -> [LocalDay] {
        guard start <= end else { return [] }
        var days: [LocalDay] = []
        var cursor = start
        while cursor <= end {
            days.append(cursor)
            cursor = cursor.adding(days: 1, calendar: calendar)
        }
        return days
    }

    /// Interval spanning whole days `start...end`.
    static func interval(from start: LocalDay, through end: LocalDay, calendar: Calendar = .current) -> DateInterval {
        DateInterval(start: start.startDate(in: calendar), end: end.interval(in: calendar).end)
    }

    static func < (lhs: LocalDay, rhs: LocalDay) -> Bool { lhs.key < rhs.key }
}
