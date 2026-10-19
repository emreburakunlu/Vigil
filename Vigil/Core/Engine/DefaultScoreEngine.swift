import Foundation

/// Default `ScoreEngine`. Owner: engine agent.
///
/// Every algorithm is pure, deterministic and documented next to its implementation so the
/// "How it's calculated" copy in the app can quote it:
///
/// | Output | File |
/// |---|---|
/// | Baselines | this file |
/// | Sleep score | `DefaultScoreEngine+Sleep.swift` |
/// | Recovery | `DefaultScoreEngine+Recovery.swift` |
/// | Zones, strain, training load | `DefaultScoreEngine+Strain.swift` |
/// | Personal bests, aerobic efficiency, splits | `DefaultScoreEngine+Running.swift`, `BestEffortFinder.swift`, `SplitCalculator.swift` |
/// | Insights | `DefaultScoreEngine+Insights.swift` |
///
/// Time only enters through inputs; "same day" is always decided with `LocalDay` in `calendar`.
struct DefaultScoreEngine: ScoreEngine {
    var calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    var version: Int { DailySummary.currentEngineVersion }

    // MARK: Baselines

    /// Rolling personal baselines as of `day`.
    ///
    /// - Window: the `Baseline.windowDays` (30) calendar days **before** `day`; `day` itself is excluded.
    /// - Resting HR, respiratory rate, wrist temperature, SpO₂, time asleep: robust mean ± SD — values
    ///   further than 4 × scaled MAD from the median are dropped as artefacts, then mean and sample SD
    ///   of the rest (`robustBaseline(of:)`).
    /// - HRV: HealthKit provides SDNN, which is right-skewed, so statistics are taken on ln(SDNN)
    ///   (`logNormalBaseline(of:)`). The reported `mean` is the geometric mean e^μ and
    ///   `standardDeviation` is e^μ · σ, so `standardDeviation / mean` is the log-domain SD σ used for
    ///   z-scores and `mean ± SD` stays a sensible "normal" band in ms.
    /// - Bedtime (minutes after 18:00 local) and daily strain: plain mean ± SD.
    /// - `sampleCount` is the number of days with a value; a baseline counts as established at
    ///   `Baseline.minimumSamples` (7) days — before that recovery reports a calibrating state.
    func baselines(on day: LocalDay, history: BaselineHistory) -> PersonalBaselines {
        let windowStart = day.adding(days: -Baseline.windowDays, calendar: calendar)
        let inWindow: (LocalDay) -> Bool = { $0 >= windowStart && $0 < day }
        var metrics: [HealthMetric: Baseline] = [:]
        let vitals = history.vitals.filter { inWindow($0.day) }
        for metric in HealthMetric.vitals {
            let values = vitals.compactMap { $0[metric] }.filter(\.isFinite)
            let baseline = metric == .heartRateVariability
                ? Self.logNormalBaseline(of: values.filter { $0 > 0 })
                : Self.robustBaseline(of: values)
            if let baseline { metrics[metric] = baseline }
        }
        let nights = history.nights.filter { $0.isPrimary && inWindow($0.day) }
        let strains = history.strains.filter { inWindow($0.day) }
        return PersonalBaselines(
            day: day,
            metrics: metrics,
            sleepDuration: Self.robustBaseline(of: nights.map(\.asleepDuration).filter { $0 > 0 }),
            bedtimeMinutes: Self.baseline(of: nights.map { minutesAfterSixPM($0.sleepStart) }),
            dailyStrain: Self.baseline(of: strains.map { Double($0.value) })
        )
    }

    /// Mean and sample standard deviation; nil for an empty list.
    static func baseline(of values: [Double]) -> Baseline? {
        guard let mean = EngineMath.mean(values), let sd = EngineMath.standardDeviation(values) else { return nil }
        return Baseline(mean: mean, standardDeviation: sd, sampleCount: values.count)
    }

    /// Mean ± SD after discarding outliers beyond median ± 4 × scaled MAD (only with ≥ 7 values and a
    /// non-zero MAD). `sampleCount` stays the number of input values.
    static func robustBaseline(of values: [Double]) -> Baseline? {
        guard !values.isEmpty else { return nil }
        var kept = values
        if values.count >= Baseline.minimumSamples, let median = EngineMath.median(values),
           let mad = EngineMath.scaledMAD(values), mad > 0 {
            kept = values.filter { abs($0 - median) <= 4 * mad }
        }
        guard var baseline = baseline(of: kept) else { return nil }
        baseline.sampleCount = values.count
        return baseline
    }

    /// Geometric mean e^μ and SD e^μ·σ of positive values, with μ, σ the (robust) mean/SD of ln(x).
    static func logNormalBaseline(of values: [Double]) -> Baseline? {
        guard let log = robustBaseline(of: values.filter { $0 > 0 }.map { Foundation.log($0) }) else { return nil }
        let mean = exp(log.mean)
        return Baseline(mean: mean, standardDeviation: mean * log.standardDeviation, sampleCount: log.sampleCount)
    }

    /// Minutes after 18:00 local (18:00 → 0, 23:00 → 300, 07:00 → 780). Keeps evening bedtimes and
    /// morning wake times on one continuous axis without midnight wrap-around.
    func minutesAfterSixPM(_ date: Date) -> Double {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        return minutes >= 18 * 60 ? minutes - 18 * 60 : minutes + 6 * 60
    }

    // MARK: Splits

    func splits(details: RunDetails, units: UnitSystem) -> [RunSplit] {
        SplitCalculator.splits(details: details, units: units)
    }

    // MARK: Helpers

    static func clampScore(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(100, max(0, value)).rounded())
    }
}
