import Foundation

/// Computes per-km / per-mile splits from a run's cumulative distance (preferred) or GPS route.
/// Pure and deterministic. Owner: engine agent.
enum SplitCalculator {
    /// Final partial splits shorter than this are dropped (metres).
    static let minimumPartialSplitMeters = 10.0

    /// A point along the run.
    struct TrackPoint: Sendable {
        var time: Date
        var distance: Double
        var altitude: Double?
    }

    static func splits(details: RunDetails, units: UnitSystem) -> [RunSplit] {
        let splitLength = units == .metric ? UnitConversion.metersPerKilometer : UnitConversion.metersPerMile
        let track = trackPoints(details: details)
        guard track.count >= 2 else { return [] }
        let altitudeSeries = details.elevation.isEmpty
            ? track.compactMap { p in p.altitude.map { MetricSample(date: p.time, value: $0) } }
            : details.elevation

        var boundaries: [(time: Date, distance: Double)] = [(track[0].time, track[0].distance)]
        var nextMark = track[0].distance + splitLength
        for (previous, current) in zip(track, track.dropFirst()) where current.distance > previous.distance {
            while current.distance >= nextMark {
                let fraction = (nextMark - previous.distance) / (current.distance - previous.distance)
                let time = previous.time.addingTimeInterval(current.time.timeIntervalSince(previous.time) * fraction)
                boundaries.append((time, nextMark))
                nextMark += splitLength
            }
        }
        if let last = track.last, let lastBoundary = boundaries.last,
           last.distance - lastBoundary.distance >= minimumPartialSplitMeters {
            boundaries.append((last.time, last.distance))
        }

        return zip(boundaries, boundaries.dropFirst()).enumerated().map { index, pair in
            let (start, end) = pair
            let distance = end.distance - start.distance
            let window = DateInterval(start: start.time, end: max(start.time, end.time))
            let hr = details.heartRate.filter { window.contains($0.date) }.map(\.value)
            let elevationChange: Double? = {
                guard let a = value(in: altitudeSeries, at: start.time), let b = value(in: altitudeSeries, at: end.time) else { return nil }
                return b - a
            }()
            return RunSplit(index: index + 1, distanceMeters: distance, duration: window.duration,
                            averageHeartRate: hr.isEmpty ? nil : hr.reduce(0, +) / Double(hr.count),
                            elevationChangeMeters: elevationChange,
                            isPartial: distance < splitLength - 0.5)
        }
    }

    /// Cumulative-distance track from `details.cumulativeDistance`, else from the route (haversine).
    static func trackPoints(details: RunDetails) -> [TrackPoint] {
        if details.cumulativeDistance.count >= 2 {
            return details.cumulativeDistance.sorted { $0.date < $1.date }.map {
                TrackPoint(time: $0.date, distance: $0.value, altitude: nil)
            }
        }
        let route = details.route.sorted { $0.timestamp < $1.timestamp }
        guard let first = route.first else { return [] }
        var points = [TrackPoint(time: first.timestamp, distance: 0, altitude: first.altitude)]
        var total = 0.0
        for (a, b) in zip(route, route.dropFirst()) {
            total += haversineMeters(a.latitude, a.longitude, b.latitude, b.longitude)
            points.append(TrackPoint(time: b.timestamp, distance: total, altitude: b.altitude))
        }
        return points
    }

    /// Great-circle distance in metres.
    static func haversineMeters(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6_371_008.8
        let dLat = (lat2 - lat1) * .pi / 180, dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(a.squareRoot(), (1 - a).squareRoot())
    }

    /// Linear interpolation of a sorted series at `date` (clamped to the ends).
    static func value(in series: [MetricSample], at date: Date) -> Double? {
        guard let first = series.first, let last = series.last else { return nil }
        if date <= first.date { return first.value }
        if date >= last.date { return last.value }
        guard let upper = series.firstIndex(where: { $0.date >= date }), upper > 0 else { return last.value }
        let a = series[upper - 1], b = series[upper]
        let span = b.date.timeIntervalSince(a.date)
        guard span > 0 else { return b.value }
        return a.value + (b.value - a.value) * date.timeIntervalSince(a.date) / span
    }
}
