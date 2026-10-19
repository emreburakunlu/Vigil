import Foundation

/// One timestamped value in a metric's canonical unit (see `HealthMetric.canonicalUnit`).
/// Used for raw HealthKit samples and for series such as HR during a workout.
struct MetricSample: Hashable, Codable, Sendable {
    var date: Date
    var value: Double
    /// Name of the app/device that recorded the sample ("Apple Watch Series 12"), if known.
    var sourceName: String?

    init(date: Date, value: Double, sourceName: String? = nil) {
        self.date = date
        self.value = value
        self.sourceName = sourceName
    }
}

/// An aggregated chart point (daily average, weekly total, …) covering `interval`.
struct TimeSeriesPoint: Hashable, Codable, Sendable, Identifiable {
    /// Bucket covered by this point.
    var interval: DateInterval
    var value: Double
    /// Optional min/max inside the bucket for range bars.
    var minimum: Double?
    var maximum: Double?

    var id: Date { interval.start }
    var date: Date { interval.start }

    init(interval: DateInterval, value: Double, minimum: Double? = nil, maximum: Double? = nil) {
        self.interval = interval
        self.value = value
        self.minimum = minimum
        self.maximum = maximum
    }
}

/// Range selector of the shared Metric detail screen: D / W / M / 6M / Y.
enum MetricRange: String, CaseIterable, Codable, Sendable, Identifiable {
    case day = "D"
    case week = "W"
    case month = "M"
    case sixMonths = "6M"
    case year = "Y"

    var id: String { rawValue }

    /// Bucket size used for chart points in this range.
    var bucket: Calendar.Component {
        switch self {
        case .day: .hour
        case .week, .month: .day
        case .sixMonths: .weekOfYear
        case .year: .month
        }
    }

    /// Interval ending at the end of `day` covered by the range.
    func interval(endingOn day: LocalDay, calendar: Calendar = .current) -> DateInterval {
        let end = day.interval(in: calendar).end
        let start: Date = switch self {
        case .day: day.startDate(in: calendar).addingTimeInterval(-6 * 3600) // evening before → morning
        case .week: day.adding(days: -6, calendar: calendar).startDate(in: calendar)
        case .month: day.adding(days: -29, calendar: calendar).startDate(in: calendar)
        case .sixMonths: calendar.date(byAdding: .month, value: -6, to: end) ?? end
        case .year: calendar.date(byAdding: .year, value: -1, to: end) ?? end
        }
        return DateInterval(start: start, end: end)
    }
}

/// Range selector of the Progress tab: 4W / 3M / 6M / 1Y.
enum ProgressRange: String, CaseIterable, Codable, Sendable, Identifiable {
    case fourWeeks = "4W"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1Y"

    var id: String { rawValue }

    /// Number of whole weeks shown.
    var weeks: Int {
        switch self {
        case .fourWeeks: 4
        case .threeMonths: 13
        case .sixMonths: 26
        case .oneYear: 52
        }
    }

    /// Interval of `weeks` weeks ending at the end of `day`.
    func interval(endingOn day: LocalDay, calendar: Calendar = .current) -> DateInterval {
        LocalDay.interval(from: day.adding(days: -(weeks * 7 - 1), calendar: calendar), through: day, calendar: calendar)
    }
}

/// Weekly vs. monthly aggregation toggle on Progress charts.
enum ProgressPeriod: String, CaseIterable, Codable, Sendable {
    case weekly
    case monthly
}
