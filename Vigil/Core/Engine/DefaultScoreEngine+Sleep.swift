import Foundation

extension DefaultScoreEngine {
    /// Tunable constants of the sleep score.
    enum Sleep {
        /// Contributor weights before renormalisation (sum 1).
        static let weights: [SleepScoreContributorKind: Double] = [
            .duration: 0.35, .efficiency: 0.15, .deepSleep: 0.10, .remSleep: 0.10, .consistency: 0.15, .interruptions: 0.15,
        ]
        /// Healthy share of the night (asleep + awake) per stage — matches the "Typical" ranges on Sleep night.
        static let deepRange = 0.13...0.23
        static let remRange = 0.20...0.25
        /// Share of the previous 7 nights' shortfall added to tonight's need, capped.
        static let debtRepaymentShare = 0.25
        static let maximumDebtAdjustment: TimeInterval = 3_600
        /// Nights (including tonight) needed for the consistency contributor.
        static let minimumConsistencyNights = 3
    }

    /// Sleep score 0–100 for one night.
    ///
    /// **Need.** need = target + min(1 h, 25 % × Σ shortfall of the previous 7 recorded nights),
    /// i.e. part of recent sleep debt is added to tonight's need.
    ///
    /// **Contributors** (sub-score 0–100, weight):
    /// - Duration (35 %): 100 × clamp((r − 0.6) / 0.4) with r = asleep ÷ need (100 at ≥ need, 0 at ≤ 60 %).
    /// - Efficiency (15 %): asleep ÷ in bed, linear from 65 % (0) to 92 % (100).
    /// - Deep (10 %) and REM (10 %): share of the night vs. healthy ranges (deep 13–23 %, REM 20–25 %):
    ///   100 inside the range, linear to 0 at no deep/REM below it; above REM's range −4 per point
    ///   (min 60). Omitted when the night has no stage data.
    /// - Interruptions (15 %): 100 − 6 × (interruptions − 1)⁺ − 1 × (awake minutes − 10)⁺.
    /// - Consistency (15 %): mean of bedtime SD and wake-time SD over tonight + up to 6 previous
    ///   nights; 100 at ≤ 15 min, 0 at ≥ 90 min. Omitted with fewer than 3 nights.
    ///
    /// Omitted contributors' weights are redistributed proportionally, so returned weights always sum
    /// to 1 and **score = round(Σ weight × sub-score)**.
    func sleepScore(_ input: SleepScoreInput) -> SleepScore {
        let night = input.night
        let previous = input.recentNights
            .filter { $0.isPrimary && $0.day < night.day }
            .sorted { $0.day < $1.day }
            .suffix(7)
        let need = sleepNeed(target: input.target, previousNights: Array(previous))

        var raw: [(SleepScoreContributorKind, Double)] = []
        let ratio = night.asleepDuration / max(need, 1)
        raw.append((.duration, EngineMath.linearScore(ratio, zeroAt: 0.6, hundredAt: 1.0)))
        raw.append((.efficiency, EngineMath.linearScore(night.efficiency, zeroAt: 0.65, hundredAt: 0.92)))
        if night.hasStages {
            let deep = night.stageDurations.share(of: .deep)
            let rem = night.stageDurations.share(of: .rem)
            raw.append((.deepSleep, Self.stageScore(share: deep, range: Sleep.deepRange, penalizesExcess: false)))
            raw.append((.remSleep, Self.stageScore(share: rem, range: Sleep.remRange, penalizesExcess: true)))
        }
        if let consistency = consistencyScore(night: night, previous: Array(previous)) {
            raw.append((.consistency, consistency))
        }
        let awakeMinutes = night.stageDurations.awake / 60
        let interruptionPenalty = 6 * Double(max(0, night.interruptions - 1)) + max(0, awakeMinutes - 10)
        raw.append((.interruptions, EngineMath.clamp(100 - interruptionPenalty, 0...100)))

        let totalWeight = raw.reduce(0) { $0 + (Sleep.weights[$1.0] ?? 0) }
        // `raw` is already in `SleepScoreContributorKind.allCases` order.
        let contributors = raw.map { kind, score in
            SleepScoreContributor(kind: kind, score: Self.clampScore(score), weight: (Sleep.weights[kind] ?? 0) / totalWeight)
        }
        let value = Self.clampScore(contributors.reduce(0) { $0 + Double($1.score) * $1.weight })
        return SleepScore(value: value, band: SleepScoreBand(score: value), contributors: contributors,
                          targetDifference: night.asleepDuration - input.target)
    }

    /// target + min(1 h, 25 % of the shortfall vs. target over `previousNights`).
    func sleepNeed(target: TimeInterval, previousNights: [SleepNight]) -> TimeInterval {
        let debt = previousNights.reduce(0) { $0 + max(0, target - $1.asleepDuration) }
        return target + min(Sleep.maximumDebtAdjustment, Sleep.debtRepaymentShare * debt)
    }

    /// 100 inside `range`; linear from 0 (share 0) to 100 (lower bound) below it; above it either 100
    /// or −400 per unit share (−4 per percentage point) down to 60.
    static func stageScore(share: Double, range: ClosedRange<Double>, penalizesExcess: Bool) -> Double {
        if share < range.lowerBound { return EngineMath.linearScore(share, zeroAt: 0, hundredAt: range.lowerBound) }
        if share > range.upperBound, penalizesExcess { return max(60, 100 - (share - range.upperBound) * 400) }
        return 100
    }

    /// Bedtime/wake regularity score, nil with fewer than `Sleep.minimumConsistencyNights` nights.
    func consistencyScore(night: SleepNight, previous: [SleepNight]) -> Double? {
        let nights = previous.suffix(6) + [night]
        guard nights.count >= Sleep.minimumConsistencyNights,
              let bedSD = EngineMath.standardDeviation(nights.map { minutesAfterSixPM($0.sleepStart) }),
              let wakeSD = EngineMath.standardDeviation(nights.map { minutesAfterSixPM($0.sleepEnd) })
        else { return nil }
        return EngineMath.linearScore((bedSD + wakeSD) / 2, zeroAt: 90, hundredAt: 15)
    }

    // MARK: Sleep debt

    /// Shortfall vs. `target` over the 7 nights ending on `day` (primary nights only):
    /// Σ max(0, target − asleep). Nights without data count 0 and are reported via `nightsRecorded`.
    func sleepDebt(nights: [SleepNight], target: TimeInterval, endingOn day: LocalDay) -> SleepDebt {
        let primary = Dictionary(nights.filter(\.isPrimary).map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let entries = (0..<7).reversed().map { offset -> SleepDebtNight in
            let d = day.adding(days: -offset, calendar: calendar)
            let asleep = primary[d]?.asleepDuration
            return SleepDebtNight(day: d, asleep: asleep, shortfall: asleep.map { max(0, target - $0) } ?? 0)
        }
        return SleepDebt(endingOn: day, target: target, total: entries.reduce(0) { $0 + $1.shortfall },
                         nights: entries, nightsRecorded: entries.filter { $0.asleep != nil }.count)
    }
}
