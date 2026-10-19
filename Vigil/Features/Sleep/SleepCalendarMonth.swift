import Foundation

/// A month of nights laid out for the calendar grid, with its summary. Pure and testable.
struct SleepCalendarMonth: Equatable, Sendable {
    struct Cell: Equatable, Sendable, Identifiable {
        enum Kind: Equatable, Sendable {
            /// Padding before the 1st.
            case blank
            case scored(Int)
            /// A past day without a recorded night.
            case missing
            case future
        }
        var id: Int
        var day: LocalDay?
        var kind: Kind
        var isSelected: Bool
    }

    struct Summary: Equatable, Sendable {
        var averageScore: Int?
        var averageAsleep: TimeInterval?
        var nightsAtTarget: Int
        var recordedNights: Int
        var bestScore: Int?
        var bestDay: LocalDay?
    }

    var first: LocalDay
    var cells: [Cell]
    var summary: Summary

    /// First day of the month containing `day`.
    static func firstOfMonth(_ day: LocalDay) -> LocalDay { LocalDay(year: day.year, month: day.month, day: 1) }

    static func month(_ first: LocalDay, offset: Int, calendar: Calendar) -> LocalDay {
        let date = calendar.date(byAdding: .month, value: offset, to: first.startDate(in: calendar)) ?? first.startDate(in: calendar)
        return firstOfMonth(LocalDay(date, calendar: calendar))
    }

    static func lastOfMonth(_ first: LocalDay, calendar: Calendar) -> LocalDay {
        month(first, offset: 1, calendar: calendar).adding(days: -1, calendar: calendar)
    }

    init(first: LocalDay, history: [SleepNightSummary], target: TimeInterval, today: LocalDay, selected: LocalDay?, calendar: Calendar) {
        let first = Self.firstOfMonth(first)
        self.first = first
        let byDay = Dictionary(history.map { ($0.day, $0) }, uniquingKeysWith: { _, b in b })
        let last = Self.lastOfMonth(first, calendar: calendar)
        let weekday = calendar.component(.weekday, from: first.startDate(in: calendar))
        let padding = (weekday - calendar.firstWeekday + 7) % 7
        var cells = (0..<padding).map { Cell(id: -($0 + 1), day: nil, kind: .blank, isSelected: false) }
        var scored: [(LocalDay, SleepNightSummary)] = []
        for day in LocalDay.range(from: first, through: last, calendar: calendar) {
            let kind: Cell.Kind
            if day > today {
                kind = .future
            } else if let entry = byDay[day], let score = entry.score, entry.asleep != nil {
                kind = .scored(score)
                scored.append((day, entry))
            } else {
                kind = .missing
            }
            cells.append(Cell(id: day.key, day: day, kind: kind, isSelected: day == selected))
        }
        self.cells = cells

        let scores = scored.compactMap { $0.1.score }
        let asleep = scored.compactMap { $0.1.asleep }
        let best = scored.max { ($0.1.score ?? 0) < ($1.1.score ?? 0) }
        summary = Summary(
            averageScore: scores.isEmpty ? nil : Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded()),
            averageAsleep: asleep.isEmpty ? nil : asleep.reduce(0, +) / Double(asleep.count),
            nightsAtTarget: asleep.filter { $0 >= target }.count,
            recordedNights: scored.count,
            bestScore: best?.1.score,
            bestDay: best?.0)
    }
}
