import Foundation

enum SleepTrendRange: Hashable, CaseIterable, Sendable {
    case sevenDays, thirtyDays, ninetyDays

    var days: Int {
        switch self {
        case .sevenDays: 7
        case .thirtyDays: 30
        case .ninetyDays: 90
        }
    }

    var title: String {
        switch self {
        case .sevenDays: String(localized: "7D")
        case .thirtyDays: String(localized: "30D")
        case .ninetyDays: String(localized: "90D")
        }
    }
}

enum SleepTrendMetric: Hashable, CaseIterable, Sendable {
    case duration, score, consistency

    var title: String {
        switch self {
        case .duration: String(localized: "Duration")
        case .score: String(localized: "Score")
        case .consistency: String(localized: "Consistency")
        }
    }
}

/// One day of the trend series (a day without a recorded night has all-nil values).
struct SleepTrendPoint: Equatable, Sendable {
    var day: LocalDay
    var asleep: TimeInterval?
    var score: Int?
    /// Minutes after 18:00 at which sleep started / ended.
    var bedtimeMinutes: Double?
    var wakeMinutes: Double?
}

enum SleepBarTone: Equatable, Sendable {
    case metTarget, shortOfTarget
    case scoreBand(SleepScoreBand)
    case window
}

struct SleepTrendBar: Equatable, Sendable {
    /// Top edge and height as fractions of the plot height (0 at the top).
    var top: Double
    var height: Double
    var tone: SleepBarTone
}

/// Precomputed trend chart for one range + metric.
struct SleepTrendChart: Equatable, Sendable {
    /// One slot per day; nil where nothing was recorded.
    var bars: [SleepTrendBar?]
    var headline: String
    var subtitle: String
    var ticks: [String]
    var accessibility: String

    static func make(points: [SleepTrendPoint], range: SleepTrendRange, metric: SleepTrendMetric,
                     target: TimeInterval, calendar: Calendar, formatter: VigilFormatter) -> SleepTrendChart {
        let slice = Array(points.suffix(range.days))
        let ticks: [String] = {
            guard let first = slice.first, let last = slice.last else { return [] }
            let mid = slice[(slice.count - 1) / 2]
            return [first, mid, last].map { SleepFormat.shortDate($0.day, calendar: calendar) }
        }()
        var chart: SleepTrendChart
        switch metric {
        case .duration: chart = duration(slice, target: target, formatter: formatter)
        case .score: chart = score(slice)
        case .consistency: chart = consistency(slice, calendar: calendar, formatter: formatter)
        }
        chart.ticks = ticks
        chart.accessibility = "\(metric.title), \(chart.headline) \(chart.subtitle)"
        return chart
    }

    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }

    private static func duration(_ points: [SleepTrendPoint], target: TimeInterval, formatter: VigilFormatter) -> SleepTrendChart {
        let floor = target / 60 - 180
        let values = points.compactMap(\.asleep)
        let ceiling = max(target / 60 + 60, (values.max() ?? 0) / 60)
        let bars: [SleepTrendBar?] = points.map { point in
            guard let asleep = point.asleep else { return nil }
            let height = max(0.02, clamp((asleep / 60 - floor) / (ceiling - floor)))
            return SleepTrendBar(top: 1 - height, height: height, tone: asleep >= target ? .metTarget : .shortOfTarget)
        }
        let average = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        return SleepTrendChart(bars: bars, headline: average.map { formatter.duration($0) } ?? "–",
                               subtitle: average == nil ? String(localized: "no nights recorded") : String(localized: "average asleep"),
                               ticks: [], accessibility: "")
    }

    private static func score(_ points: [SleepTrendPoint]) -> SleepTrendChart {
        let bars: [SleepTrendBar?] = points.map { point in
            guard let score = point.score else { return nil }
            let height = max(0.02, clamp(Double(score) / 100))
            return SleepTrendBar(top: 1 - height, height: height, tone: .scoreBand(SleepScoreBand(score: score)))
        }
        let scores = points.compactMap(\.score)
        let average = scores.isEmpty ? nil : Double(scores.reduce(0, +)) / Double(scores.count)
        return SleepTrendChart(bars: bars, headline: average.map { "\(Int($0.rounded()))" } ?? "–",
                               subtitle: average == nil ? String(localized: "no nights recorded") : String(localized: "average score"),
                               ticks: [], accessibility: "")
    }

    private static func consistency(_ points: [SleepTrendPoint], calendar: Calendar, formatter: VigilFormatter) -> SleepTrendChart {
        let windows = points.compactMap { p -> (Double, Double)? in
            guard let bed = p.bedtimeMinutes, let wake = p.wakeMinutes, wake > bed else { return nil }
            return (bed, wake)
        }
        guard let minBed = windows.map(\.0).min(), let maxWake = windows.map(\.1).max() else {
            return SleepTrendChart(bars: points.map { _ in nil }, headline: "–",
                                   subtitle: String(localized: "no nights recorded"), ticks: [], accessibility: "")
        }
        let low = (minBed / 60).rounded(.down) * 60
        let high = max((maxWake / 60).rounded(.up) * 60, low + 360)
        let bars: [SleepTrendBar?] = points.map { point in
            guard let bed = point.bedtimeMinutes, let wake = point.wakeMinutes, wake > bed else { return nil }
            return SleepTrendBar(top: clamp((bed - low) / (high - low)), height: max(0.02, clamp((wake - bed) / (high - low))), tone: .window)
        }
        let beds = windows.map(\.0)
        var headline = "–"
        var subtitle = String(localized: "not enough nights")
        if beds.count >= 2 {
            let mean = beds.reduce(0, +) / Double(beds.count)
            let variance = beds.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(beds.count)
            headline = "± " + formatter.duration(variance.squareRoot() * 60, style: .minutes)
            let reference = points.last?.day.startDate(in: calendar) ?? .now
            let lowText = clockText(minutesAfterSix: low, on: reference, calendar: calendar, formatter: formatter)
            let highText = clockText(minutesAfterSix: high, on: reference, calendar: calendar, formatter: formatter)
            subtitle = String(localized: "bedtime variation · \(lowText) → \(highText)")
        }
        return SleepTrendChart(bars: bars, headline: headline, subtitle: subtitle, ticks: [], accessibility: "")
    }

    private static func clockText(minutesAfterSix: Double, on reference: Date, calendar: Calendar, formatter: VigilFormatter) -> String {
        let total = Int(minutesAfterSix) + 18 * 60
        let date = calendar.date(bySettingHour: (total / 60) % 24, minute: total % 60, second: 0, of: reference) ?? reference
        return formatter.timeOfDay(date, calendar: calendar)
    }

    /// Joins the history summaries with the night times into trend points, oldest first.
    static func points(history: [SleepNightSummary], nights: [SleepNight], calendar: Calendar) -> [SleepTrendPoint] {
        let byDay = Dictionary(nights.map { ($0.day, $0) }, uniquingKeysWith: { _, b in b })
        return history.map { summary in
            let night = byDay[summary.day]
            let bed = night.map { SleepFormat.minutesAfterSix($0.sleepStart, calendar: calendar) }
            let wake = night.map { bed! + $0.sleepEnd.timeIntervalSince($0.sleepStart) / 60 }
            return SleepTrendPoint(day: summary.day, asleep: summary.asleep, score: summary.score,
                                   bedtimeMinutes: bed, wakeMinutes: wake)
        }
    }
}
