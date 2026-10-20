import Foundation

/// One bar of a Progress chart (a week, or a calendar month). `value` is in display units.
struct ProgressBar: Hashable, Sendable, Identifiable {
    var id: Int
    var start: Date
    var value: Double
}

/// One point of a Progress line chart. `value` is in display units.
struct ProgressPoint: Hashable, Sendable, Identifiable {
    var date: Date
    var value: Double
    var id: Date { date }
}

/// Which kinds of training happened on a heatmap day.
enum ProgressDayKind: Hashable, Sendable {
    case rest, run, lift, both
    /// After today (not yet lived).
    case future
}

/// A weeks × 7 consistency grid, one column per calendar week, oldest first.
struct ProgressHeatmap: Hashable, Sendable {
    struct Cell: Hashable, Sendable, Identifiable {
        var day: LocalDay
        var kind: ProgressDayKind
        var id: LocalDay { day }
    }
    /// `columns[week][row]`, row 0 = the calendar's first weekday.
    var columns: [[Cell]]
    /// Days with at least one run or lift.
    var trainingDays: Int
}

/// Pure aggregation used by the Progress screen models (unit-tested without a repository).
enum ProgressAggregation {
    /// First day of each of `weeks` consecutive 7-day buckets that end on `end`, oldest first.
    static func weekStarts(weeks: Int, endingOn end: LocalDay, calendar: Calendar) -> [LocalDay] {
        let first = end.adding(days: -(weeks * 7 - 1), calendar: calendar)
        return (0..<max(weeks, 0)).map { first.adding(days: $0 * 7, calendar: calendar) }
    }

    /// Index of the bucket (of `bucketDays` days, starting at `first`) containing `day`, nil when outside `count` buckets.
    static func bucketIndex(of day: LocalDay, first: LocalDay, bucketDays: Int = 7, count: Int, calendar: Calendar) -> Int? {
        let offset = first.days(to: day, calendar: calendar)
        guard offset >= 0 else { return nil }
        let index = offset / bucketDays
        return index < count ? index : nil
    }

    /// Sums `items` into `count` 7-day buckets.
    static func weeklySums(_ items: [(day: LocalDay, value: Double)], first: LocalDay, count: Int, calendar: Calendar) -> [Double] {
        var sums = Array(repeating: 0.0, count: count)
        for item in items {
            if let index = bucketIndex(of: item.day, first: first, count: count, calendar: calendar) { sums[index] += item.value }
        }
        return sums
    }

    /// Mean per bucket; nil for buckets without items.
    static func weeklyMeans(_ items: [(day: LocalDay, value: Double)], first: LocalDay, count: Int, calendar: Calendar) -> [Double?] {
        var sums = Array(repeating: 0.0, count: count)
        var counts = Array(repeating: 0, count: count)
        for item in items {
            if let index = bucketIndex(of: item.day, first: first, count: count, calendar: calendar) {
                sums[index] += item.value
                counts[index] += 1
            }
        }
        return zip(sums, counts).map { $1 > 0 ? $0 / Double($1) : nil }
    }

    /// First day of every calendar month from the month containing `first` through the month containing `today`, oldest first.
    static func monthStarts(from first: LocalDay, through today: LocalDay) -> [LocalDay] {
        let count = (today.year - first.year) * 12 + today.month - first.month + 1
        guard count > 0 else { return [] }
        return (0..<count).map { offset in
            let index = first.month - 1 + offset
            return LocalDay(year: first.year + index / 12, month: index % 12 + 1, day: 1)
        }
    }

    /// Sums `items` into the calendar months starting at `months` (as returned by `monthStarts`); items outside are ignored.
    static func monthlySums(_ items: [(day: LocalDay, value: Double)], months: [LocalDay]) -> [Double] {
        guard let first = months.first else { return [] }
        var sums = Array(repeating: 0.0, count: months.count)
        for item in items {
            let index = (item.day.year - first.year) * 12 + item.day.month - first.month
            if sums.indices.contains(index) { sums[index] += item.value }
        }
        return sums
    }

    /// Averages consecutive chunks so that at most `maxCount` points remain.
    static func downsample(_ points: [ProgressPoint], maxCount: Int = 300) -> [ProgressPoint] {
        guard maxCount > 0, points.count > maxCount else { return points }
        let chunk = Int((Double(points.count) / Double(maxCount)).rounded(.up))
        return stride(from: 0, to: points.count, by: chunk).map { start in
            let slice = points[start..<min(start + chunk, points.count)]
            let mean = slice.reduce(0) { $0 + $1.value } / Double(slice.count)
            let middle = slice[slice.startIndex + slice.count / 2]
            return ProgressPoint(date: middle.date, value: mean)
        }
    }

    /// Daily means of raw samples, oldest first.
    static func dailyMeans(_ samples: [MetricSample], calendar: Calendar) -> [ProgressPoint] {
        let grouped = Dictionary(grouping: samples) { LocalDay($0.date, calendar: calendar) }
        return grouped.keys.sorted().map { day in
            let values = grouped[day, default: []].map(\.value)
            return ProgressPoint(date: day.startDate(in: calendar), value: values.reduce(0, +) / Double(values.count))
        }
    }

    /// Change from the first to the last point; nil with fewer than two points.
    static func change(_ points: [ProgressPoint]) -> Double? {
        guard points.count >= 2, let first = points.first, let last = points.last else { return nil }
        return last.value - first.value
    }

    /// Three evenly spaced dates (first, middle, last) for the axis caption under a chart.
    static func tickDates(_ dates: [Date]) -> [Date] {
        guard let first = dates.first, let last = dates.last else { return [] }
        guard dates.count > 2 else { return dates.count == 1 ? [first] : [first, last] }
        return [first, dates[dates.count / 2], last]
    }

    /// Consistency grid ending with the calendar week that contains `today`.
    static func heatmap(workoutKinds: [LocalDay: Set<WorkoutKind>], weeks: Int, today: LocalDay, calendar: Calendar) -> ProgressHeatmap {
        let weekday = calendar.component(.weekday, from: today.startDate(in: calendar))
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let currentWeekStart = today.adding(days: -offset, calendar: calendar)
        let first = currentWeekStart.adding(days: -(max(weeks, 1) - 1) * 7, calendar: calendar)
        var trainingDays = 0
        let columns: [[ProgressHeatmap.Cell]] = (0..<max(weeks, 1)).map { week in
            (0..<7).map { row in
                let day = first.adding(days: week * 7 + row, calendar: calendar)
                let kind: ProgressDayKind
                if day > today {
                    kind = .future
                } else {
                    let kinds = workoutKinds[day] ?? []
                    switch (kinds.contains(.run), kinds.contains(.strength)) {
                    case (true, true): kind = .both
                    case (true, false): kind = .run
                    case (false, true): kind = .lift
                    case (false, false): kind = .rest
                    }
                    if kind != .rest { trainingDays += 1 }
                }
                return ProgressHeatmap.Cell(day: day, kind: kind)
            }
        }
        return ProgressHeatmap(columns: columns, trainingDays: trainingDays)
    }

    /// Acute ÷ chronic ratio per day, skipping days without chronic load.
    static func loadRatios(_ history: [TrainingLoadPoint], calendar: Calendar) -> [ProgressPoint] {
        history.compactMap { point in
            point.chronic > 0 ? ProgressPoint(date: point.day.startDate(in: calendar), value: point.acute / point.chronic) : nil
        }
    }
}
