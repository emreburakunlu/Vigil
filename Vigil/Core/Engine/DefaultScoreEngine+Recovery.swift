import Foundation

extension DefaultScoreEngine {
    /// Tunable constants of the recovery score.
    enum Recovery {
        /// Weight of each signal's z-score in the composite.
        static let hrvWeight = 0.50
        static let restingHeartRateWeight = 0.25
        static let sleepWeight = 0.25
        static let respiratoryRateWeight = 0.15
        static let wristTemperatureWeight = 0.15
        /// z-scores are clamped to ± this value so one extreme reading can't dominate.
        static let zLimit = 3.0
        /// SD floors (avoid huge z-scores on very stable baselines).
        static let minimumLogHRVSD = 0.05
        static let minimumRestingHeartRateSD = 1.5
        static let minimumRespiratoryRateSD = 0.4
        static let minimumWristTemperatureSD = 0.15
        /// Respiratory rate and wrist temperature only count beyond this many SDs from baseline.
        static let deviationTolerance = 1.0
        /// Sleep score reference: z = (score − 75) / 12.
        static let sleepReference = 75.0
        static let sleepSpread = 12.0
        /// Logistic mapping: recovery = 100 / (1 + e^−(slope·S + offset)).
        static let slope = 1.2
        /// ln(58 / 42): a composite of 0 (everything at baseline) maps to 58 %.
        static let offset = log(58.0 / 42.0)
        static let neutral = 58
        /// Acute:chronic ratio above which "Push" is downgraded.
        static let highLoadRatio = 1.5
    }

    /// Recovery 0–100 %.
    ///
    /// 1. Each signal becomes a z-score against the personal 30-day baseline (clamped to ±3):
    ///    - HRV (weight 0.50): z = (ln HRV − ln baseline) / σ_ln, σ_ln = max(0.05, SD ÷ mean). Higher is better.
    ///    - Resting HR (0.25): z = −(RHR − mean) / max(1.5, SD). Lower is better.
    ///    - Sleep (0.25): z = (sleep score − 75) / 12.
    ///    - Respiratory rate (0.15) and wrist temperature (0.15): penalty only,
    ///      z = −max(0, |value − mean| / SD − 1) with SD floors 0.4 br/min and 0.15 °C.
    ///    Signals without a value or without an established baseline (< 7 days) contribute 0.
    /// 2. Composite S = Σ weight × z.
    /// 3. Recovery = 100 / (1 + e^−(1.2·S + ln(58/42))): 58 % when everything is at baseline,
    ///    ≈ 80 % at S = +0.8, ≈ 30 % at S = −1.
    /// 4. Factor points: each signal's share of (recovery − 58) in proportion to weight × z, rounded
    ///    with the largest-remainder method, so **recovery = 58 + Σ points** exactly.
    ///
    /// Band: green ≥ 67, yellow 34–66, red ≤ 33 (`RecoveryBand`). Suggestion: green → Push,
    /// yellow → Maintain, red → Take it easy; Push drops to Maintain (and the strain target by 10)
    /// after an all-out day (strain ≥ 90) or when the acute:chronic load ratio is > 1.5; Maintain
    /// drops to Take it easy below 50 % with a ratio > 1.5.
    /// Suggested strain: round(0.6·R + 8) … round(0.6·R + 28).
    func recovery(_ input: RecoveryInput) -> RecoveryScore {
        let baselines = input.baselines
        var signals: [RecoverySignal] = []

        let hrv = input.vitals?.heartRateVariability
        let hrvBaseline = baselines[.heartRateVariability]
        signals.append(RecoverySignal(kind: .heartRateVariability, value: hrv, baseline: hrvBaseline?.mean,
                                      weight: Recovery.hrvWeight, z: {
            guard let hrv, hrv > 0, let b = hrvBaseline, b.isEstablished, b.mean > 0 else { return nil }
            let sd = max(Recovery.minimumLogHRVSD, b.standardDeviation / b.mean)
            return (log(hrv) - log(b.mean)) / sd
        }()))

        let rhr = input.vitals?.restingHeartRate
        let rhrBaseline = baselines[.restingHeartRate]
        signals.append(RecoverySignal(kind: .restingHeartRate, value: rhr, baseline: rhrBaseline?.mean,
                                      weight: Recovery.restingHeartRateWeight, z: {
            guard let rhr, let b = rhrBaseline, b.isEstablished else { return nil }
            return -(rhr - b.mean) / max(Recovery.minimumRestingHeartRateSD, b.standardDeviation)
        }()))

        let sleep = input.sleepScore.map { Double($0.value) }
        signals.append(RecoverySignal(kind: .sleep, value: sleep, baseline: Recovery.sleepReference,
                                      weight: Recovery.sleepWeight,
                                      z: sleep.map { ($0 - Recovery.sleepReference) / Recovery.sleepSpread }))

        func penalty(_ metric: HealthMetric, _ kind: RecoveryFactorKind, weight: Double, floor: Double) -> RecoverySignal {
            let value = input.vitals?[metric]
            let b = baselines[metric]
            let z: Double? = {
                guard let value, let b, b.isEstablished else { return nil }
                return -max(0, abs(value - b.mean) / max(floor, b.standardDeviation) - Recovery.deviationTolerance)
            }()
            return RecoverySignal(kind: kind, value: value, baseline: b?.mean, weight: weight, z: z)
        }
        signals.append(penalty(.respiratoryRate, .respiratoryRate, weight: Recovery.respiratoryRateWeight,
                               floor: Recovery.minimumRespiratoryRateSD))
        signals.append(penalty(.wristTemperature, .wristTemperature, weight: Recovery.wristTemperatureWeight,
                               floor: Recovery.minimumWristTemperatureSD))

        let contributions = signals.map { s in s.z.map { s.weight * EngineMath.clamp($0, -Recovery.zLimit...Recovery.zLimit) } ?? 0 }
        let composite = contributions.reduce(0, +)
        let exact = 100 * EngineMath.logistic(Recovery.slope * composite + Recovery.offset)
        let value = Self.clampScore(exact)
        let points = Self.recoveryPoints(contributions: contributions, composite: composite, value: value)

        let factors = signals.enumerated().map { i, s in
            RecoveryFactor(kind: s.kind, value: s.value, baseline: s.baseline, points: points[i], isAvailable: s.z != nil)
        }

        let band = RecoveryBand(percent: value)
        var suggestion: ReadinessSuggestion = switch band {
        case .green: .push
        case .yellow: .maintain
        case .red: .takeItEasy
        }
        let ratio = input.trainingLoad?.ratio ?? 0
        let allOutYesterday = (input.previousDayStrain?.value ?? 0) >= 90
        var loadLimited = false
        if suggestion == .push, ratio > Recovery.highLoadRatio || allOutYesterday {
            suggestion = .maintain
            loadLimited = true
        } else if suggestion == .maintain, ratio > Recovery.highLoadRatio, value < 50 {
            suggestion = .takeItEasy
            loadLimited = true
        }

        let established = [hrvBaseline, rhrBaseline].compactMap { $0 }.map(\.sampleCount).max() ?? 0
        let calibrationDays = established >= Baseline.minimumSamples ? nil : Baseline.minimumSamples - established

        var low = Int((0.6 * Double(value) + 8).rounded()), high = Int((0.6 * Double(value) + 28).rounded())
        if loadLimited { low -= 10; high -= 10 }
        low = min(100, max(0, low)); high = min(100, max(low, high))

        return RecoveryScore(value: value, band: band, factors: factors, suggestion: suggestion,
                             message: recoveryMessage(factors: factors, suggestion: suggestion,
                                                      loadLimited: loadLimited, calibrationDays: calibrationDays),
                             suggestedStrain: low...high,
                             signalsUsed: factors.filter(\.isAvailable).count, signalsTotal: factors.count,
                             calibrationDaysRemaining: calibrationDays)
    }

    /// Splits `value − neutral` across signals in proportion to their weighted z (see `recovery(_:)`).
    static func recoveryPoints(contributions: [Double], composite: Double, value: Int) -> [Int] {
        let neutralExact = 100 * EngineMath.logistic(Recovery.offset)
        let exact = 100 * EngineMath.logistic(Recovery.slope * composite + Recovery.offset)
        // (exact − neutral) / S is always positive (monotonic curve); at S → 0 it is the curve's slope.
        let scale = abs(composite) > 1e-9
            ? (exact - neutralExact) / composite
            : 100 * Recovery.slope * EngineMath.logistic(Recovery.offset) * (1 - EngineMath.logistic(Recovery.offset))
        let raw = contributions.map { $0 * scale }
        return EngineMath.apportion(raw, total: value - Recovery.neutral, eligible: contributions.map { $0 != 0 })
    }

    /// "HRV 12% above your baseline. Good day for intervals."
    func recoveryMessage(factors: [RecoveryFactor], suggestion: ReadinessSuggestion,
                         loadLimited: Bool, calibrationDays: Int?) -> String {
        let advice: String = switch (suggestion, loadLimited) {
        case (.push, _): "Good day for intervals."
        case (.maintain, true): "Training load is high, so keep it steady today."
        case (.maintain, false): "Keep it steady today."
        case (.takeItEasy, true): "Training load is high, so keep it light today."
        case (.takeItEasy, false): "Keep it light today."
        }
        if let calibrationDays {
            let nights = calibrationDays == 1 ? "1 more night" : "\(calibrationDays) more nights"
            return "Still learning your baselines: \(nights) needed. \(advice)"
        }
        // Lead with the signal that moved the score most (ties: HRV, RHR, sleep, respiratory, temperature).
        guard let lead = factors.enumerated().filter({ $0.element.isAvailable && abs($0.element.points) >= 3 })
            .max(by: { (abs($0.element.points), -$0.offset) < (abs($1.element.points), -$1.offset) })
        else { return "Your signals are close to your baseline. \(advice)" }
        let factor = lead.element
        let up = factor.points > 0
        let headline: String
        switch factor.kind {
        case .heartRateVariability:
            if let v = factor.value, let b = factor.baseline, b > 0 {
                let percent = Int((abs(v - b) / b * 100).rounded())
                headline = "HRV \(percent)% \(v >= b ? "above" : "below") your baseline."
            } else {
                headline = up ? "HRV is above your baseline." : "HRV is below your baseline."
            }
        case .restingHeartRate:
            if let v = factor.value, let b = factor.baseline {
                let bpm = Int(abs(v - b).rounded())
                headline = bpm == 0 ? "Resting heart rate is at your baseline."
                    : "Resting heart rate \(bpm) bpm \(v > b ? "above" : "below") your baseline."
            } else {
                headline = up ? "Resting heart rate is below your baseline." : "Resting heart rate is above your baseline."
            }
        case .sleep:
            let score = Int(factor.value ?? 0)
            headline = up ? "Good sleep (score \(score)) is boosting recovery." : "A sleep score of \(score) is holding recovery back."
        case .respiratoryRate:
            headline = "Respiratory rate is off your baseline."
        case .wristTemperature:
            let above = (factor.value ?? 0) >= (factor.baseline ?? 0)
            headline = above ? "Wrist temperature is above your baseline." : "Wrist temperature is below your baseline."
        }
        return "\(headline) \(advice)"
    }

    /// One recovery signal before mapping.
    struct RecoverySignal {
        var kind: RecoveryFactorKind
        var value: Double?
        var baseline: Double?
        var weight: Double
        /// Signed z-score (positive = better recovery); nil when unavailable.
        var z: Double?
    }
}
