import Foundation

/// One plotted point of a Train chart series. `id` is the index in the (downsampled) series.
struct TrainChartPoint: Hashable, Sendable, Identifiable {
    var id: Int
    var x: Double
    var y: Double
}

/// Pure maths for Train screens: downsampling, polyline simplification, lookups, ticks.
/// Everything is nonisolated so it can run off the main actor.
enum TrainSeries {
    /// Largest-Triangle-Three-Buckets downsampling: keeps the visual shape (and peaks) of a long series.
    static func downsample(_ points: [TrainChartPoint], to threshold: Int) -> [TrainChartPoint] {
        guard threshold >= 3, points.count > threshold else {
            return reindexed(points)
        }
        var sampled: [TrainChartPoint] = [points[0]]
        let every = Double(points.count - 2) / Double(threshold - 2)
        var anchor = 0
        for bucket in 0..<(threshold - 2) {
            let start = Int(Double(bucket) * every) + 1
            let end = min(Int(Double(bucket + 1) * every) + 1, points.count - 1)
            let nextStart = end
            let nextEnd = min(Int(Double(bucket + 2) * every) + 1, points.count)
            var avgX = 0.0, avgY = 0.0
            if nextStart < nextEnd {
                for index in nextStart..<nextEnd {
                    avgX += points[index].x
                    avgY += points[index].y
                }
                avgX /= Double(nextEnd - nextStart)
                avgY /= Double(nextEnd - nextStart)
            } else {
                avgX = points[points.count - 1].x
                avgY = points[points.count - 1].y
            }
            let a = points[anchor]
            var best = start
            var bestArea = -1.0
            if start < end {
                for index in start..<end {
                    let p = points[index]
                    let area = abs((a.x - avgX) * (p.y - a.y) - (a.x - p.x) * (avgY - a.y))
                    if area > bestArea {
                        bestArea = area
                        best = index
                    }
                }
            }
            sampled.append(points[best])
            anchor = best
        }
        sampled.append(points[points.count - 1])
        return reindexed(sampled)
    }

    private static func reindexed(_ points: [TrainChartPoint]) -> [TrainChartPoint] {
        points.enumerated().map { TrainChartPoint(id: $0.offset, x: $0.element.x, y: $0.element.y) }
    }

    /// Builds a downsampled series from timestamped samples. `x` maps a sample time to the plotted x value.
    static func series(from samples: [MetricSample], maxPoints: Int = 240, x: (Date) -> Double,
                       isValid: (Double) -> Bool = { $0.isFinite }) -> [TrainChartPoint] {
        var points: [TrainChartPoint] = []
        points.reserveCapacity(samples.count)
        for sample in samples where isValid(sample.value) {
            points.append(TrainChartPoint(id: points.count, x: x(sample.date), y: sample.value))
        }
        return downsample(points, to: maxPoints)
    }

    /// Value of the sample closest in time to `date` (samples sorted ascending). Nil when empty.
    static func nearestValue(in samples: [MetricSample], at date: Date) -> Double? {
        guard !samples.isEmpty else { return nil }
        var low = 0
        var high = samples.count - 1
        while low < high {
            let mid = (low + high) / 2
            if samples[mid].date < date { low = mid + 1 } else { high = mid }
        }
        if low > 0, abs(samples[low - 1].date.timeIntervalSince(date)) < abs(samples[low].date.timeIntervalSince(date)) {
            return samples[low - 1].value
        }
        return samples[low].value
    }

    /// Linear interpolation of a monotone series (cumulative distance) at `date`.
    static func interpolated(in samples: [MetricSample], at date: Date) -> Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        if date <= first.date { return first.value }
        if date >= last.date { return last.value }
        var low = 0
        var high = samples.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if samples[mid].date <= date { low = mid } else { high = mid }
        }
        let a = samples[low], b = samples[high]
        let span = b.date.timeIntervalSince(a.date)
        guard span > 0 else { return a.value }
        return a.value + (b.value - a.value) * date.timeIntervalSince(a.date) / span
    }

    /// Percentile (0...1) of an unsorted list using nearest-rank interpolation.
    static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let position = min(max(fraction, 0), 1) * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
    }

    // MARK: Polyline simplification

    /// Douglas-Peucker. Returns the sorted indices of the points to keep.
    static func simplify(x: [Double], y: [Double], epsilon: Double) -> [Int] {
        let count = min(x.count, y.count)
        guard count > 2 else { return Array(0..<count) }
        var keep = [Bool](repeating: false, count: count)
        keep[0] = true
        keep[count - 1] = true
        var stack: [(Int, Int)] = [(0, count - 1)]
        while let (start, end) = stack.popLast() {
            guard end > start + 1 else { continue }
            let ax = x[start], ay = y[start]
            let dx = x[end] - ax, dy = y[end] - ay
            let lengthSquared = dx * dx + dy * dy
            var maxDistance = 0.0
            var index = start
            for i in (start + 1)..<end {
                let px = x[i] - ax, py = y[i] - ay
                let distance: Double
                if lengthSquared == 0 {
                    distance = (px * px + py * py).squareRoot()
                } else {
                    let t = min(max((px * dx + py * dy) / lengthSquared, 0), 1)
                    let cx = px - t * dx, cy = py - t * dy
                    distance = (cx * cx + cy * cy).squareRoot()
                }
                if distance > maxDistance {
                    maxDistance = distance
                    index = i
                }
            }
            if maxDistance > epsilon {
                keep[index] = true
                stack.append((start, index))
                stack.append((index, end))
            }
        }
        return keep.indices.filter { keep[$0] }
    }

    /// Simplifies until at most `maxPoints` remain, growing the tolerance geometrically.
    static func simplify(x: [Double], y: [Double], maxPoints: Int) -> [Int] {
        guard x.count > maxPoints, let minX = x.min(), let maxX = x.max(), let minY = y.min(), let maxY = y.max() else {
            return Array(0..<min(x.count, y.count))
        }
        let diagonal = ((maxX - minX) * (maxX - minX) + (maxY - minY) * (maxY - minY)).squareRoot()
        var epsilon = max(diagonal * 0.0004, .leastNonzeroMagnitude)
        var kept = simplify(x: x, y: y, epsilon: epsilon)
        var attempts = 0
        while kept.count > maxPoints, attempts < 14 {
            epsilon *= 1.7
            kept = simplify(x: x, y: y, epsilon: epsilon)
            attempts += 1
        }
        return kept
    }

    // MARK: Axis ticks

    /// Nice x-axis tick positions in metres for a distance axis, stepping in whole display units (km or mi).
    static func distanceTicks(maxMeters: Double, formatter: VigilFormatter, maxCount: Int = 5) -> [Double] {
        let maxDisplay = formatter.displayDistance(meters: maxMeters)
        guard maxDisplay > 0 else { return [0] }
        let steps: [Double] = [0.5, 1, 2, 5, 10, 20, 50]
        let step = steps.first { maxDisplay / $0 <= Double(maxCount - 1) } ?? 100
        var ticks: [Double] = []
        var value = 0.0
        while value <= maxDisplay + 0.0001 {
            ticks.append(formatter.meters(fromDisplayDistance: value))
            value += step
        }
        return ticks
    }
}
