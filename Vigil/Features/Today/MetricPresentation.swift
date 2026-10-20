import Foundation

/// Pure display logic of the shared Metric detail screen. Works for every `HealthMetric`.
///
/// Display values: wrist temperature is shown as the deviation from the baseline mean (°C or °F delta),
/// body mass in the user's weight unit; everything else in its formatter unit.
enum MetricPresentation {
    struct Stat: Hashable, Sendable {
        var value: String
        var unit: String
    }

    struct Display: Hashable, Sendable {
        var points: [TodayChartPoint]
        var band: ClosedRange<Double>?
        var yDomain: ClosedRange<Double>?
        var average: Stat?
        var minimum: Stat?
        var maximum: Stat?
        var baselineText: String?
        var unit: String
        var isEmpty: Bool { points.isEmpty }
    }

    /// Reference for deviation metrics: baseline mean, else the series average.
    static func reference(_ series: MetricSeries) -> Double {
        series.baseline?.mean ?? series.average ?? 0
    }

    /// Converts a canonical value to the number drawn on the chart.
    static func chartValue(_ value: Double, metric: HealthMetric, reference: Double, formatter: VigilFormatter) -> Double {
        switch metric {
        case .wristTemperature: formatter.units == .metric ? value - reference : (value - reference) * 9 / 5
        case .bodyMass: formatter.displayWeight(kilograms: value)
        default: value
        }
    }

    /// Formats a *canonical* value for text.
    static func stat(_ value: Double, metric: HealthMetric, reference: Double, formatter: VigilFormatter) -> Stat {
        let formatted = metric == .wristTemperature
            ? formatter.temperatureDelta(celsius: value - reference)
            : formatter.format(metric, value)
        return Stat(value: formatted.value, unit: formatted.unit)
    }

    static func display(_ series: MetricSeries, formatter: VigilFormatter) -> Display {
        let metric = series.metric
        let ref = reference(series)
        func convert(_ v: Double) -> Double { chartValue(v, metric: metric, reference: ref, formatter: formatter) }
        let points = series.points.map { TodayChartPoint(date: $0.date, value: convert($0.value)) }
        let band: ClosedRange<Double>? = series.baseline.flatMap { baseline in
            guard baseline.isEstablished else { return nil }
            let range = baseline.normalRange
            let lo = convert(range.lowerBound), hi = convert(range.upperBound)
            return min(lo, hi)...max(lo, hi)
        }
        let baselineText: String? = series.baseline.flatMap { baseline -> String? in
            guard baseline.isEstablished else { return nil }
            if metric == .wristTemperature {
                let lo = formatter.temperatureDelta(celsius: baseline.normalRange.lowerBound - ref)
                let hi = formatter.temperatureDelta(celsius: baseline.normalRange.upperBound - ref)
                return String(localized: "Your baseline · \(lo.value) to \(hi.value) \(hi.unit) (30-day)")
            }
            let lo = formatter.format(metric, baseline.normalRange.lowerBound)
            let hi = formatter.format(metric, baseline.normalRange.upperBound)
            return String(localized: "Your baseline · \(lo.value)–\(hi.value) \(hi.unit) (30-day)")
        }
        let unit = stat(ref, metric: metric, reference: ref, formatter: formatter).unit
        return Display(
            points: points, band: band,
            yDomain: TodayChartScale.domain(values: points.map(\.value), band: band),
            average: series.average.map { stat($0, metric: metric, reference: ref, formatter: formatter) },
            minimum: series.minimum.map { stat($0, metric: metric, reference: ref, formatter: formatter) },
            maximum: series.maximum.map { stat($0, metric: metric, reference: ref, formatter: formatter) },
            baselineText: baselineText, unit: unit)
    }

    /// The latest raw reading as a vital reading, so the same delta rules apply.
    static func latestReading(_ series: MetricSeries) -> VitalReading? {
        guard let latest = series.latest else { return nil }
        let baseline = series.baseline
        let delta = baseline.map { latest.value - $0.mean }
        let percent = delta.flatMap { d in baseline.flatMap { $0.mean != 0 ? d / $0.mean * 100 : nil } }
        return VitalReading(metric: series.metric, value: latest.value, baseline: baseline, delta: delta, deltaPercent: percent,
                            status: baseline?.status(of: latest.value) ?? .noBaseline, trend: [])
    }

    /// The series average against the baseline, for the delta shown beside the big "Average" value.
    static func averageReading(_ series: MetricSeries) -> VitalReading? {
        guard let average = series.average, let baseline = series.baseline, baseline.isEstablished else { return nil }
        let delta = average - baseline.mean
        let percent = baseline.mean != 0 ? delta / baseline.mean * 100 : nil
        return VitalReading(metric: series.metric, value: average, baseline: baseline, delta: delta, deltaPercent: percent,
                            status: baseline.status(of: average), trend: [])
    }

    static func latestTitle(_ metric: HealthMetric) -> String {
        HealthMetric.vitals.contains(metric) ? String(localized: "Last night (sleep average)") : String(localized: "Latest reading")
    }

    static func subtitle(_ metric: HealthMetric) -> String {
        switch metric {
        case .heartRateVariability: String(localized: "HRV · SDNN")
        case .restingHeartRate: String(localized: "Beats per minute at rest")
        case .respiratoryRate: String(localized: "Breaths per minute asleep")
        case .wristTemperature: String(localized: "Change from your baseline")
        case .oxygenSaturation: String(localized: "SpO₂")
        case .heartRate: String(localized: "Beats per minute")
        case .vo2Max: String(localized: "Cardio fitness")
        case .bodyMass: String(localized: "Weight")
        }
    }

    static func explanation(_ metric: HealthMetric) -> String {
        switch metric {
        case .heartRateVariability:
            String(localized: "HRV is the variation in time between heartbeats, measured by your watch while you sleep. Higher than your own baseline usually means you're well recovered. Compare it with yourself, not with others.")
        case .restingHeartRate:
            String(localized: "Resting heart rate is how fast your heart beats when you are calm. A rate below your baseline is a good sign; a rate well above it can mean stress, illness or poor recovery.")
        case .respiratoryRate:
            String(localized: "Respiratory rate is how many breaths you take per minute while asleep. It is usually very stable, so a clear rise from your baseline is worth noticing.")
        case .wristTemperature:
            String(localized: "Your watch measures skin temperature at the wrist while you sleep. Vigil shows how far it is from your own baseline. A sustained rise can be an early sign of illness.")
        case .oxygenSaturation:
            String(localized: "Blood oxygen is the share of your blood carrying oxygen. Healthy levels are usually 95% or higher. This is not a medical measurement.")
        case .heartRate:
            String(localized: "Heart rate is how fast your heart is beating. It rises with effort and falls at rest.")
        case .vo2Max:
            String(localized: "VO₂ max estimates how much oxygen your body can use during hard exercise. It is a common measure of cardio fitness and changes slowly.")
        case .bodyMass:
            String(localized: "Body weight naturally moves by a little each day. Look at the trend over weeks rather than single readings.")
        }
    }

    static func rangeLabel(_ interval: DateInterval, range: MetricRange, calendar: Calendar = .current) -> String {
        if range == .day {
            return interval.end.addingTimeInterval(-1).formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
        var style = Date.IntervalFormatStyle().month(.abbreviated).day().year()
        style.calendar = calendar
        return (interval.start..<interval.end.addingTimeInterval(-60)).formatted(style)
    }

    static func xFormat(_ range: MetricRange) -> Date.FormatStyle {
        switch range {
        case .day: .dateTime.hour()
        case .week: .dateTime.weekday(.abbreviated)
        case .month: .dateTime.month(.abbreviated).day()
        case .sixMonths: .dateTime.month(.abbreviated)
        case .year: .dateTime.month(.abbreviated)
        }
    }

    /// Decimal places used for a single value of the metric.
    static func fractionDigits(_ metric: HealthMetric) -> Int {
        switch metric {
        case .respiratoryRate, .bodyMass, .vo2Max: 1
        case .wristTemperature: 2
        default: 0
        }
    }

    /// Short chip title in the metric switcher.
    static func chipTitle(_ metric: HealthMetric) -> String {
        metric == .wristTemperature ? String(localized: "Temperature") : metric.shortName
    }
}
