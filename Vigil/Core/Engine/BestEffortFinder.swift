import Foundation

/// Finds the fastest contiguous segment of a given distance inside a run's distance timeline.
/// Pure, O(n) per target distance. Owner: engine agent.
enum BestEffortFinder {
    /// Distance increments implying a faster speed than this are treated as GPS spikes and capped (m/s).
    static let maximumSpeed = 10.0

    /// A cleaned timeline: strictly ordered times, non-decreasing cumulative distance.
    struct Timeline: Sendable {
        var times: [TimeInterval]
        var distances: [Double]

        var totalDistance: Double { distances.last ?? 0 }
    }

    /// Sorts by date, makes distance non-decreasing, caps implausible jumps at `maximumSpeed`, and
    /// rebases distance and time to start at 0.
    static func timeline(from samples: [MetricSample]) -> Timeline {
        let sorted = samples.filter { $0.value.isFinite }.sorted { $0.date < $1.date }
        guard let first = sorted.first else { return Timeline(times: [], distances: []) }
        var times: [TimeInterval] = [0]
        var distances: [Double] = [0]
        times.reserveCapacity(sorted.count)
        distances.reserveCapacity(sorted.count)
        var previousRaw = first.value
        for sample in sorted.dropFirst() {
            let t = sample.date.timeIntervalSince(first.date)
            let dt = t - times[times.count - 1]
            let gain = min(max(0, sample.value - previousRaw), maximumSpeed * max(0, dt))
            previousRaw = max(previousRaw, sample.value)
            if dt <= 0 {
                distances[distances.count - 1] += gain
            } else {
                times.append(t)
                distances.append(distances[distances.count - 1] + gain)
            }
        }
        return Timeline(times: times, distances: distances)
    }

    /// Fastest time (seconds) to cover `target` metres anywhere in `timeline`, nil if it is shorter.
    ///
    /// With linear interpolation between samples the optimum always has its start or its end on a
    /// sample, so two linear two-pointer passes are exact:
    /// 1. end at sample j, start at the interpolated point where distance = d[j] − target;
    /// 2. start at sample i, end at the interpolated point where distance = d[i] + target.
    static func fastest(_ target: Double, in timeline: Timeline) -> TimeInterval? {
        let t = timeline.times, d = timeline.distances
        let n = d.count
        guard target > 0, n >= 2, timeline.totalDistance >= target else { return nil }
        var best = Double.infinity

        // Pass 1: i = last index with d[i] ≤ d[j] − target (latest such sample, i.e. after any pause).
        var i = 0
        for j in 0..<n where d[j] >= target {
            let startDistance = d[j] - target
            while i + 1 < n, d[i + 1] <= startDistance { i += 1 }
            let startTime = interpolateTime(at: startDistance, from: i, t, d)
            best = min(best, t[j] - startTime)
        }

        // Pass 2: e = first index with d[e] ≥ d[s] + target.
        var e = 0
        for s in 0..<n {
            let endDistance = d[s] + target
            if endDistance > d[n - 1] { break }
            while e < n - 1, d[e] < endDistance { e += 1 }
            let endTime: TimeInterval
            if e > 0, d[e] > d[e - 1], d[e - 1] < endDistance {
                endTime = t[e - 1] + (t[e] - t[e - 1]) * (endDistance - d[e - 1]) / (d[e] - d[e - 1])
            } else {
                endTime = t[e]
            }
            best = min(best, endTime - t[s])
        }
        return best.isFinite && best > 0 ? best : nil
    }

    /// Time at `distance` on the segment starting at sample `i` (d[i] ≤ distance).
    private static func interpolateTime(at distance: Double, from i: Int, _ t: [TimeInterval], _ d: [Double]) -> TimeInterval {
        guard i + 1 < d.count, d[i + 1] > d[i], distance > d[i] else { return t[i] }
        return t[i] + (t[i + 1] - t[i]) * (distance - d[i]) / (d[i + 1] - d[i])
    }
}
