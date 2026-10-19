import Foundation

// Pure series logic used by `LiveHealthDataSource` (unit-tested in `HealthKitSeriesTests`).

/// Reduces long series for charts while keeping their shape.
enum SeriesDownsampler {
    /// Default point budget for Run detail charts (HR, pace, power, form metrics, elevation).
    static let chartPointLimit = 600

    /// Time-bucket averaging: splits `[first, last]` into `maxPoints` equal buckets and replaces each
    /// non-empty bucket by the mean value at the mean timestamp. The first and last samples are kept as-is
    /// so the series still spans the full workout. Input must be sorted by date; returned unchanged when
    /// it already fits.
    static func downsample(_ samples: [MetricSample], maxPoints: Int = chartPointLimit) -> [MetricSample] {
        guard maxPoints >= 3, samples.count > maxPoints, let first = samples.first, let last = samples.last else { return samples }
        let span = last.date.timeIntervalSince(first.date)
        guard span > 0 else { return [first] }
        let inner = samples.dropFirst().dropLast()
        let bucketCount = maxPoints - 2
        var sums = [(time: Double, value: Double, count: Int)](repeating: (0, 0, 0), count: bucketCount)
        for sample in inner {
            let offset = sample.date.timeIntervalSince(first.date)
            let index = min(bucketCount - 1, max(0, Int(offset / span * Double(bucketCount))))
            sums[index].time += offset
            sums[index].value += sample.value
            sums[index].count += 1
        }
        var result = [first]
        for bucket in sums where bucket.count > 0 {
            let n = Double(bucket.count)
            result.append(MetricSample(date: first.date.addingTimeInterval(bucket.time / n), value: bucket.value / n,
                                       sourceName: first.sourceName))
        }
        result.append(last)
        return result
    }
}

/// A statistics bucket total (e.g. metres in 5 s, steps in 1 min).
struct QuantityBucket: Hashable, Sendable {
    var interval: DateInterval
    var value: Double
}

/// Run-detail series derivations.
enum RunSeriesMath {
    /// Speeds below this (≈ 33 min/km) are treated as standing still and produce no pace point.
    static let minimumRunningSpeed = 0.5

    /// Pace in s/km for a speed in m/s; nil when (almost) stationary.
    static func pace(speedMetersPerSecond speed: Double) -> Double? {
        speed >= minimumRunningSpeed ? 1_000 / speed : nil
    }

    /// Pace series (s/km) from running-speed samples (m/s).
    static func paceSeries(fromSpeed speed: [MetricSample]) -> [MetricSample] {
        speed.compactMap { s in pace(speedMetersPerSecond: s.value).map { MetricSample(date: s.date, value: $0, sourceName: s.sourceName) } }
    }

    /// Pace series (s/km) from a cumulative-distance series, using a trailing window of `window` seconds.
    /// Used when the watch recorded no running-speed samples.
    static func paceSeries(fromCumulativeDistance distance: [MetricSample], window: TimeInterval = 30) -> [MetricSample] {
        guard distance.count >= 2 else { return [] }
        var result: [MetricSample] = []
        var tail = 0
        for (index, point) in distance.enumerated() where index > 0 {
            while tail < index - 1, point.date.timeIntervalSince(distance[tail + 1].date) >= window { tail += 1 }
            let base = distance[tail]
            let elapsed = point.date.timeIntervalSince(base.date)
            guard elapsed > 0 else { continue }
            if let pace = pace(speedMetersPerSecond: (point.value - base.value) / elapsed) {
                result.append(MetricSample(date: point.date, value: pace))
            }
        }
        return result
    }

    /// Cumulative distance (m) from per-bucket distance totals; points are dated at bucket ends.
    /// Starts with a 0 m point at the first bucket start.
    static func cumulativeDistance(fromBuckets buckets: [QuantityBucket]) -> [MetricSample] {
        let sorted = buckets.sorted { $0.interval.start < $1.interval.start }
        guard let first = sorted.first else { return [] }
        var total = 0.0
        var result = [MetricSample(date: first.interval.start, value: 0)]
        for bucket in sorted where bucket.value > 0 {
            total += bucket.value
            result.append(MetricSample(date: bucket.interval.end, value: total))
        }
        return result.count >= 2 ? result : []
    }

    /// Cadence (steps/min) from per-bucket step totals. Buckets are clipped to `workout` (partial first/last
    /// minutes are scaled to a full minute); buckets without steps (pauses) are skipped.
    static func cadenceSeries(fromStepBuckets buckets: [QuantityBucket], within workout: DateInterval) -> [MetricSample] {
        buckets.sorted { $0.interval.start < $1.interval.start }.compactMap { bucket in
            guard bucket.value > 0, let clipped = bucket.interval.intersection(with: workout), clipped.duration >= 10 else { return nil }
            return MetricSample(date: clipped.start.addingTimeInterval(clipped.duration / 2), value: bucket.value / clipped.duration * 60)
        }
    }

    /// Mean of the values, nil when empty.
    static func mean(_ samples: [MetricSample]) -> Double? {
        samples.isEmpty ? nil : samples.reduce(0) { $0 + $1.value } / Double(samples.count)
    }

    /// Altitude series from a route (metres), skipping points without altitude.
    static func elevationSeries(from route: [RouteLocation]) -> [MetricSample] {
        route.compactMap { point in point.altitude.map { MetricSample(date: point.timestamp, value: $0) } }
    }

    /// Route points with acceptable horizontal accuracy (≤ `maximumAccuracy` m, unknown accuracy kept).
    static func filteredRoute(_ route: [RouteLocation], maximumAccuracy: Double = 50) -> [RouteLocation] {
        route.filter { point in
            guard let accuracy = point.horizontalAccuracy else { return true }
            return accuracy >= 0 && accuracy <= maximumAccuracy
        }.sorted { $0.timestamp < $1.timestamp }
    }
}

/// Builds `DailyVitals` from overnight samples. Pure.
struct VitalsAssembler: Sendable {
    var calendar: Calendar
    /// Fallback overnight window when no primary night exists: 20:00 the evening before → 10:00 on the wake day.
    var fallbackWindowStartHour = 20
    var fallbackWindowEndHour = 10

    /// The window whose HRV / respiratory rate / SpO₂ samples count for `day`: the primary night's in-bed
    /// window when there is one, else the fallback overnight window.
    func window(for day: LocalDay, night: SleepNight?) -> DateInterval {
        if let night, night.inBedEnd > night.inBedStart {
            return DateInterval(start: night.inBedStart, end: night.inBedEnd)
        }
        let dayStart = day.startDate(in: calendar)
        let previousStart = day.adding(days: -1, calendar: calendar).startDate(in: calendar)
        let start = calendar.date(bySettingHour: fallbackWindowStartHour, minute: 0, second: 0, of: previousStart) ?? dayStart
        let end = calendar.date(bySettingHour: fallbackWindowEndHour, minute: 0, second: 0, of: dayStart) ?? dayStart
        return DateInterval(start: start, end: max(start, end))
    }

    /// - Parameters:
    ///   - days: days to produce (days without any vital are omitted).
    ///   - nights: nights (primary ones are used for the sleep window).
    ///   - heartRateVariability / respiratoryRate / oxygenSaturation: raw samples (canonical units), dated by start.
    ///   - wristTemperature: samples dated by their **end** (wake) date; averaged per wake day.
    ///   - restingHeartRate: daily resting HR (HealthKit's one-per-day statistic).
    func dailyVitals(days: [LocalDay], nights: [SleepNight], heartRateVariability: [MetricSample],
                     respiratoryRate: [MetricSample], oxygenSaturation: [MetricSample],
                     wristTemperature: [MetricSample], restingHeartRate: [LocalDay: Double]) -> [DailyVitals] {
        let primary = Dictionary(nights.filter(\.isPrimary).map { ($0.day, $0) }, uniquingKeysWith: { a, b in
            a.asleepDuration >= b.asleepDuration ? a : b
        })
        let temperatureByDay = Dictionary(grouping: wristTemperature) { LocalDay($0.date, calendar: calendar) }
        return days.compactMap { day in
            let window = window(for: day, night: primary[day])
            func average(_ samples: [MetricSample]) -> Double? {
                RunSeriesMath.mean(samples.filter { $0.date >= window.start && $0.date <= window.end })
            }
            let vitals = DailyVitals(day: day,
                                     heartRateVariability: average(heartRateVariability),
                                     restingHeartRate: restingHeartRate[day],
                                     respiratoryRate: average(respiratoryRate),
                                     wristTemperature: temperatureByDay[day].flatMap(RunSeriesMath.mean),
                                     oxygenSaturation: average(oxygenSaturation))
            return vitals.recordedMetrics.isEmpty ? nil : vitals
        }
    }
}

extension LocalDay {
    /// Days overlapping `interval` (end exclusive), oldest first.
    static func days(overlapping interval: DateInterval, calendar: Calendar) -> [LocalDay] {
        guard interval.end > interval.start else { return [LocalDay(interval.start, calendar: calendar)] }
        return range(from: LocalDay(interval.start, calendar: calendar),
                     through: LocalDay(interval.end.addingTimeInterval(-0.001), calendar: calendar), calendar: calendar)
    }
}
