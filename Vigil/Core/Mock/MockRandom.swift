import Foundation

/// SplitMix64 — tiny deterministic RNG for mock data.
struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func double(in range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &self) }
    mutating func int(in range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &self) }
}

/// Stateless, order-independent randomness: every value is a pure function of `(seed, key, salt, k)`,
/// so a given day always yields the same data no matter which calls happened before.
struct MockNoise: Sendable {
    var seed: UInt64

    static func mix(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    func hash(_ key: Int, _ salt: UInt64, _ k: Int = 0) -> UInt64 {
        var h = Self.mix(seed ^ 0xA5A5_5A5A_1234_8765)
        h = Self.mix(h &+ UInt64(bitPattern: Int64(key)))
        h = Self.mix(h &+ salt &* 0x9E37_79B9)
        return Self.mix(h &+ UInt64(bitPattern: Int64(k)))
    }

    /// Uniform in [0, 1).
    func unit(_ key: Int, _ salt: UInt64, _ k: Int = 0) -> Double {
        Double(hash(key, salt, k) >> 11) / 9_007_199_254_740_992.0
    }

    /// Uniform in [lo, hi).
    func value(_ key: Int, _ salt: UInt64, _ lo: Double, _ hi: Double, _ k: Int = 0) -> Double {
        lo + (hi - lo) * unit(key, salt, k)
    }

    /// Standard normal, clipped to ±2.5.
    func gauss(_ key: Int, _ salt: UInt64, _ k: Int = 0) -> Double {
        let u1 = max(unit(key, salt, k), 1e-12)
        let u2 = unit(key, salt, k &+ 10_007)
        return min(2.5, max(-2.5, (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)))
    }

    /// Smooth value noise in [-1, 1]; `x` is measured in noise "periods".
    func smooth(_ x: Double, key: Int, salt: UInt64) -> Double {
        let i = Int(x.rounded(.down))
        let f = x - Double(i)
        let s = f * f * (3 - 2 * f)
        let a = unit(key, salt, i) * 2 - 1
        let b = unit(key, salt, i + 1) * 2 - 1
        return a + (b - a) * s
    }
}

/// Day arithmetic without `Calendar` (fast, and independent of the time zone).
extension LocalDay {
    /// Days since 1970-01-01 (proleptic Gregorian civil date).
    var mockDayNumber: Int {
        let m = month
        let y = year - (m <= 2 ? 1 : 0)
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    init(mockDayNumber dn: Int) {
        let z = dn + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        self.init(year: yoe + era * 400 + (m <= 2 ? 1 : 0), month: m, day: d)
    }
}

/// 0 = Sunday … 6 = Saturday for a mock day number.
func mockWeekday(_ dn: Int) -> Int { ((dn % 7) + 7 + 4) % 7 }

func mockSmoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = min(1, max(0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
}

func mockClamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, x)) }
