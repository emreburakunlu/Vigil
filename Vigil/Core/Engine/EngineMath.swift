import Foundation

/// Small, allocation-light statistics used by the score engine. All functions are pure and
/// return nil instead of trapping on empty or degenerate input.
enum EngineMath {
    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Sample standard deviation (n − 1); 0 for a single value, nil when empty.
    static func standardDeviation(_ values: [Double]) -> Double? {
        guard let mean = mean(values) else { return nil }
        guard values.count > 1 else { return 0 }
        let sum = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return (sum / Double(values.count - 1)).squareRoot()
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Median absolute deviation scaled by 1.4826 (≈ SD for normal data).
    static func scaledMAD(_ values: [Double]) -> Double? {
        guard let median = median(values) else { return nil }
        return self.median(values.map { abs($0 - median) }).map { $0 * 1.4826 }
    }

    /// Ordinary least-squares slope of `y` on `x`; nil for < 2 points or zero x-variance.
    static func slope(x: [Double], y: [Double]) -> Double? {
        guard x.count == y.count, x.count >= 2, let mx = mean(x), let my = mean(y) else { return nil }
        var sxy = 0.0, sxx = 0.0
        for (a, b) in zip(x, y) {
            sxy += (a - mx) * (b - my)
            sxx += (a - mx) * (a - mx)
        }
        return sxx > 0 ? sxy / sxx : nil
    }

    /// 1 / (1 + e^−x).
    static func logistic(_ x: Double) -> Double { 1 / (1 + exp(-x)) }

    static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }

    /// Linear map of `value` from `from` (score 0) to `to` (score 100), clamped to 0…100.
    /// Works for descending ranges too (`from > to`, e.g. "fewer minutes is better").
    static func linearScore(_ value: Double, zeroAt from: Double, hundredAt to: Double) -> Double {
        guard from != to else { return value >= to ? 100 : 0 }
        return clamp((value - from) / (to - from) * 100, 0...100)
    }

    /// Rounds `raw` values to integers whose sum equals `total`, using the largest-remainder
    /// method (ties broken by index, so the result is deterministic). Only indices in `eligible`
    /// receive the leftover units.
    static func apportion(_ raw: [Double], total: Int, eligible: [Bool]) -> [Int] {
        guard !raw.isEmpty else { return [] }
        var result = raw.map { Int($0.rounded(.down)) }
        var remaining = total - result.reduce(0, +)
        let candidates = raw.indices.filter { eligible[$0] }
        guard !candidates.isEmpty else { return result }
        if remaining > 0 {
            let order = candidates.sorted { (raw[$0] - raw[$0].rounded(.down), -$0) > (raw[$1] - raw[$1].rounded(.down), -$1) }
            var i = 0
            while remaining > 0 { result[order[i % order.count]] += 1; remaining -= 1; i += 1 }
        } else if remaining < 0 {
            let order = candidates.sorted { (raw[$0] - raw[$0].rounded(.down), $0) < (raw[$1] - raw[$1].rounded(.down), $1) }
            var i = 0
            while remaining < 0 { result[order[i % order.count]] -= 1; remaining += 1; i += 1 }
        }
        return result
    }
}
