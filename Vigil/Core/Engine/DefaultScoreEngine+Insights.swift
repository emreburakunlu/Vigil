import Foundation

extension DefaultScoreEngine {
    /// Thresholds of the insight rules. An insight is only emitted when both groups of a comparison
    /// have enough samples and the effect clears its threshold.
    enum Insights {
        static let minimumGroupSize = 3
        /// Rest vs. training-day sleep: |difference| ≥ 15 min.
        static let sleepDurationDifference: TimeInterval = 15 * 60
        /// Bedtime variability week over week: ≥ 5 nights per week, |ΔSD| ≥ 10 min.
        static let minimumNightsPerWeek = 5
        static let bedtimeSpreadDifference = 10.0
        /// Deep sleep share before vs. after 23:00 in bed: |relative difference| ≥ 10 %.
        static let earlyBedtimeMinutes = 5 * 60.0 // 23:00 as minutes after 18:00
        static let deepShareRelativeDifference = 0.10
        /// Workouts ending ≤ 3 h before falling asleep: |sleep-score difference| ≥ 5.
        static let lateWorkoutWindow: TimeInterval = 3 * 3_600
        static let lateWorkoutScoreDifference = 5.0
        /// HRV trend: ≥ 10 of the last 14 days, |fitted change| ≥ 5 %.
        static let hrvTrendDays = 14
        static let hrvTrendMinimumDays = 10
        static let hrvTrendChange = 0.05
        /// Recovery after high-strain (≥ 67) days: lower by ≥ 8 points.
        static let heavyStrain = 67
        static let recoveryDrop = 8.0
        /// Sleep score ≥ 70 ("Good") streak of ≥ 4 nights.
        static let goodSleepScore = 70
        static let minimumSleepStreak = 4
        /// ≥ 2 run/strength sessions per 7-day block, ≥ 3 blocks in a row.
        static let sessionsPerWeek = 2
        static let minimumTrainingWeeks = 3
    }

    /// Rule-based insights, sorted by priority (desc) then id (asc), so ordering is deterministic.
    ///
    /// Rules (id — statement — condition):
    /// - `sleep.restDayDuration.strength` / `.run` — "You sleep 35 min more on rest days than after
    ///   lifting." Nights after a day with no workout vs. after a strength (or run) day; ≥ 3 nights
    ///   each, |Δ mean time asleep| ≥ 15 min.
    /// - `sleep.bedtimeSpread` — "Your bedtime varied by 48 min this week, up from 31 min last week."
    ///   SD of sleep-onset time, last 7 vs. previous 7 days; ≥ 5 nights each, |Δ| ≥ 10 min.
    /// - `sleep.earlyBedtimeDeep` — "Deep sleep is 18% higher on nights you're in bed before 23:00."
    ///   Mean deep share, in bed before vs. after 23:00; ≥ 3 nights each, |relative Δ| ≥ 10 %.
    /// - `sleep.lateWorkout` — "Your sleep score averages 7 points lower after workouts that end within
    ///   3 hours of bedtime." ≥ 3 nights each, |Δ| ≥ 5 points.
    /// - `recovery.hrvTrend` — "Your HRV has risen 8% over the last 14 days." Least-squares slope of
    ///   ln(HRV) over the last 14 days (≥ 10 values); |e^(13·slope) − 1| ≥ 5 %.
    /// - `recovery.afterHeavyDays` — "Recovery averages 14 points lower the day after high-strain days."
    ///   Days after strain ≥ 67 vs. other days; ≥ 3 each, drop ≥ 8 points.
    /// - `sleep.goodStreak` — "5 nights in a row with a sleep score of 70 or more." Ending on `day`, ≥ 4.
    /// - `training.weeklyStreak` — "You've trained at least twice a week for 4 weeks in a row."
    ///   7-day blocks ending on `day` with ≥ 2 run/strength sessions, ≥ 3 in a row.
    func insights(_ input: InsightInput) -> [Insight] {
        let day = input.day
        let nights = Dictionary(input.nights.filter { $0.isPrimary && $0.day <= day }.map { ($0.day, $0) },
                                uniquingKeysWith: { a, b in a.asleepDuration >= b.asleepDuration ? a : b })
            .values.sorted { $0.day < $1.day }
        let workouts = input.workouts.filter { LocalDay($0.start, calendar: calendar) <= day }
        let workoutsByDay = Dictionary(grouping: workouts) { LocalDay($0.start, calendar: calendar) }
        let summaries = Dictionary(input.summaries.filter { $0.day <= day }.map { ($0.day, $0) }, uniquingKeysWith: { _, b in b })

        var result: [Insight] = []
        result += restDaySleepInsights(nights: nights, workoutsByDay: workoutsByDay)
        if let insight = bedtimeSpreadInsight(nights: nights, day: day) { result.append(insight) }
        if let insight = earlyBedtimeDeepInsight(nights: nights) { result.append(insight) }
        if let insight = lateWorkoutInsight(nights: nights, workouts: workouts, summaries: summaries) { result.append(insight) }
        if let insight = hrvTrendInsight(summaries: summaries, day: day) { result.append(insight) }
        if let insight = heavyDayRecoveryInsight(summaries: summaries) { result.append(insight) }
        if let insight = sleepStreakInsight(summaries: summaries, day: day) { result.append(insight) }
        if let insight = trainingStreakInsight(workouts: workouts, day: day) { result.append(insight) }
        return result.sorted { ($0.priority, $1.id) > ($1.priority, $0.id) }
    }

    // MARK: Rules

    func restDaySleepInsights(nights: [SleepNight], workoutsByDay: [LocalDay: [Workout]]) -> [Insight] {
        var rest: [TimeInterval] = [], afterKind: [WorkoutKind: [TimeInterval]] = [:]
        for night in nights {
            let kinds = Set((workoutsByDay[night.day.adding(days: -1, calendar: calendar)] ?? []).map(\.kind))
            if kinds.isEmpty { rest.append(night.asleepDuration) }
            for kind in kinds where kind != .other { afterKind[kind, default: []].append(night.asleepDuration) }
        }
        guard rest.count >= Insights.minimumGroupSize, let restMean = EngineMath.mean(rest) else { return [] }
        return [(WorkoutKind.strength, "lifting", "strength"), (.run, "running", "run")].compactMap { kind, phrase, key in
            let values = afterKind[kind] ?? []
            guard values.count >= Insights.minimumGroupSize, let mean = EngineMath.mean(values) else { return nil }
            let diff = restMean - mean
            guard abs(diff) >= Insights.sleepDurationDifference else { return nil }
            let minutes = Int((abs(diff) / 60).rounded())
            let text = diff > 0
                ? "You sleep \(minutes) min more on rest days than after \(phrase)."
                : "You sleep \(minutes) min more after \(phrase) than on rest days."
            return Insight(id: "sleep.restDayDuration.\(key)", domain: .sleep, text: text,
                           priority: 60 + min(20, minutes / 3))
        }
    }

    func bedtimeSpreadInsight(nights: [SleepNight], day: LocalDay) -> Insight? {
        let thisWeekStart = day.adding(days: -6, calendar: calendar)
        let lastWeekStart = day.adding(days: -13, calendar: calendar)
        let onset: (SleepNight) -> Double = { self.minutesAfterSixPM($0.sleepStart) }
        let thisWeek = nights.filter { $0.day >= thisWeekStart }.map(onset)
        let lastWeek = nights.filter { $0.day >= lastWeekStart && $0.day < thisWeekStart }.map(onset)
        guard thisWeek.count >= Insights.minimumNightsPerWeek, lastWeek.count >= Insights.minimumNightsPerWeek,
              let now = EngineMath.standardDeviation(thisWeek), let before = EngineMath.standardDeviation(lastWeek),
              abs(now - before) >= Insights.bedtimeSpreadDifference else { return nil }
        let a = Int(now.rounded()), b = Int(before.rounded())
        return Insight(id: "sleep.bedtimeSpread", domain: .sleep,
                       text: "Your bedtime varied by \(a) min this week, \(now > before ? "up" : "down") from \(b) min last week.",
                       priority: 50 + min(20, abs(a - b) / 2))
    }

    func earlyBedtimeDeepInsight(nights: [SleepNight]) -> Insight? {
        let staged = nights.filter(\.hasStages)
        let early = staged.filter { minutesAfterSixPM($0.inBedStart) < Insights.earlyBedtimeMinutes }.map { $0.stageDurations.share(of: .deep) }
        let late = staged.filter { minutesAfterSixPM($0.inBedStart) >= Insights.earlyBedtimeMinutes }.map { $0.stageDurations.share(of: .deep) }
        guard early.count >= Insights.minimumGroupSize, late.count >= Insights.minimumGroupSize,
              let e = EngineMath.mean(early), let l = EngineMath.mean(late), l > 0 else { return nil }
        let relative = (e - l) / l
        guard abs(relative) >= Insights.deepShareRelativeDifference else { return nil }
        let percent = Int((abs(relative) * 100).rounded())
        return Insight(id: "sleep.earlyBedtimeDeep", domain: .sleep,
                       text: "Deep sleep is \(percent)% \(relative > 0 ? "higher" : "lower") on nights you're in bed before 23:00.",
                       priority: 45 + min(20, percent / 2))
    }

    func lateWorkoutInsight(nights: [SleepNight], workouts: [Workout], summaries: [LocalDay: DailySummary]) -> Insight? {
        var late: [Double] = [], other: [Double] = []
        for night in nights {
            guard let score = summaries[night.day]?.sleepScore?.value else { continue }
            let windowStart = night.sleepStart.addingTimeInterval(-Insights.lateWorkoutWindow)
            let isLate = workouts.contains { $0.end >= windowStart && $0.end <= night.sleepStart }
            if isLate { late.append(Double(score)) } else { other.append(Double(score)) }
        }
        guard late.count >= Insights.minimumGroupSize, other.count >= Insights.minimumGroupSize,
              let l = EngineMath.mean(late), let o = EngineMath.mean(other) else { return nil }
        let diff = l - o
        guard abs(diff) >= Insights.lateWorkoutScoreDifference else { return nil }
        let points = Int(abs(diff).rounded())
        return Insight(id: "sleep.lateWorkout", domain: .sleep,
                       text: "Your sleep score averages \(points) points \(diff < 0 ? "lower" : "higher") after workouts that end within 3 hours of bedtime.",
                       priority: 55 + min(20, points))
    }

    func hrvTrendInsight(summaries: [LocalDay: DailySummary], day: LocalDay) -> Insight? {
        var x: [Double] = [], y: [Double] = []
        for offset in 0..<Insights.hrvTrendDays {
            let d = day.adding(days: offset - (Insights.hrvTrendDays - 1), calendar: calendar)
            if let hrv = summaries[d]?.vitals?.heartRateVariability, hrv > 0 {
                x.append(Double(offset))
                y.append(log(hrv))
            }
        }
        guard x.count >= Insights.hrvTrendMinimumDays, let slope = EngineMath.slope(x: x, y: y) else { return nil }
        let change = exp(slope * Double(Insights.hrvTrendDays - 1)) - 1
        guard abs(change) >= Insights.hrvTrendChange else { return nil }
        let percent = Int((abs(change) * 100).rounded())
        return Insight(id: "recovery.hrvTrend", domain: .recovery,
                       text: "Your HRV has \(change > 0 ? "risen" : "fallen") \(percent)% over the last 14 days.",
                       priority: 65 + min(20, percent))
    }

    func heavyDayRecoveryInsight(summaries: [LocalDay: DailySummary]) -> Insight? {
        var heavy: [Double] = [], other: [Double] = []
        for (d, summary) in summaries {
            guard let recovery = summary.recovery?.value,
                  let previous = summaries[d.adding(days: -1, calendar: calendar)]?.strain?.value else { continue }
            if previous >= Insights.heavyStrain { heavy.append(Double(recovery)) } else { other.append(Double(recovery)) }
        }
        guard heavy.count >= Insights.minimumGroupSize, other.count >= Insights.minimumGroupSize,
              let h = EngineMath.mean(heavy), let o = EngineMath.mean(other), o - h >= Insights.recoveryDrop else { return nil }
        let points = Int((o - h).rounded())
        return Insight(id: "recovery.afterHeavyDays", domain: .recovery,
                       text: "Recovery averages \(points) points lower the day after high-strain days.",
                       priority: 58 + min(20, points / 2))
    }

    func sleepStreakInsight(summaries: [LocalDay: DailySummary], day: LocalDay) -> Insight? {
        var streak = 0
        var cursor = day
        while let score = summaries[cursor]?.sleepScore?.value, score >= Insights.goodSleepScore {
            streak += 1
            cursor = cursor.adding(days: -1, calendar: calendar)
        }
        guard streak >= Insights.minimumSleepStreak else { return nil }
        return Insight(id: "sleep.goodStreak", domain: .sleep,
                       text: "\(streak) nights in a row with a sleep score of \(Insights.goodSleepScore) or more.",
                       priority: 40 + min(15, streak))
    }

    func trainingStreakInsight(workouts: [Workout], day: LocalDay) -> Insight? {
        let sessions = workouts.filter { $0.kind != .other }.map { LocalDay($0.start, calendar: calendar) }
        var weeks = 0
        while true {
            let end = day.adding(days: -7 * weeks, calendar: calendar)
            let start = end.adding(days: -6, calendar: calendar)
            guard sessions.filter({ $0 >= start && $0 <= end }).count >= Insights.sessionsPerWeek else { break }
            weeks += 1
        }
        guard weeks >= Insights.minimumTrainingWeeks else { return nil }
        return Insight(id: "training.weeklyStreak", domain: .training,
                       text: "You've trained at least twice a week for \(weeks) weeks in a row.",
                       priority: 35 + min(15, weeks))
    }
}
